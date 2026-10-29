using System.ComponentModel;
using System.Text.Json;
using ScatteredNotes.Core.Agenda;
using ScatteredNotes.Core.Models;

namespace ScatteredNotes.Core.Storage;

/// <summary>
/// Reads and writes the notes folder. Call it from one thread (the UI thread); file watcher callbacks only
/// raise <see cref="FilesChangedExternally"/>, and the app reloads on its own thread.
///
/// Data safety rules: writes are atomic; a moved note's new file is written before the old one is removed;
/// loading never writes a note file; files that cannot be read are left alone.
/// </summary>
public sealed class NoteStore : IDisposable
{
    public const string MetadataFileName = ".metadata.json";

    private readonly AppSettings _settings;
    private readonly bool _enableFileWatcher;
    private readonly TimeZoneInfo _timeZone;
    private FileSystemWatcher? _watcher;
    private Timer? _debounce;
    private long _ignoreEventsUntil;

    /// <summary>
    /// Parsed notes by file path, reused by <see cref="LoadAll"/> while a file's modification time and size are
    /// unchanged, so a reload only reads the files that changed.
    /// </summary>
    private readonly Dictionary<string, CachedFile> _fileCache = new(StringComparer.OrdinalIgnoreCase);
    private sealed record CachedFile(DateTime Modified, long Size, Note Note);

    /// <summary>Agenda items per note, valid while the note's text and update time are unchanged, because the update time decides what relative words without a <c>📅</c> marker resolve to.</summary>
    private readonly Dictionary<Guid, CachedAgenda> _agendaCache = [];
    /// <summary>The <c>@people</c> of each note, valid while its text is unchanged, so the sidebar does not rescan every note on each save.</summary>
    private readonly Dictionary<Guid, (string Content, IReadOnlyList<string> Names)> _peopleCache = [];

    private sealed record CachedAgenda(string Content, DateTimeOffset UpdatedAt, List<AgendaItem> Items);

    private List<Note> _notes = [];

    /// <summary>Notes, pinned first, then most recently updated.</summary>
    public IReadOnlyList<Note> Notes => _notes;
    public IReadOnlyList<ProjectArea> Projects { get; private set; } = [];

    /// <summary>Raised after notes or projects change.</summary>
    public event EventHandler? Changed;

    /// <summary>Raised on a background thread when files change outside the app; reload with <see cref="LoadAll"/>.</summary>
    public event EventHandler? FilesChangedExternally;

    /// <summary>Raised when a note could not be written. The edit is still in the editor and is retried on the next save.</summary>
    public event EventHandler<Exception>? SaveFailed;

    public NoteStore(AppSettings settings, bool enableFileWatcher = true, TimeZoneInfo? timeZone = null)
    {
        _settings = settings;
        _enableFileWatcher = enableFileWatcher;
        _timeZone = timeZone ?? TimeZoneInfo.Local;
        LoadAll();
        if (enableFileWatcher) StartWatching();
        _settings.PropertyChanged += OnSettingsChanged;
    }

    public void Dispose()
    {
        _settings.PropertyChanged -= OnSettingsChanged;
        StopWatching();
    }

    private void OnSettingsChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(AppSettings.NotesDirectory)) return;
        LoadAll();
        if (_enableFileWatcher) StartWatching();
    }

    // MARK: Folders

    public string RootPath => _settings.NotesDirectory;
    public string InboxPath => Path.Combine(RootPath, "Inbox");
    public string ProjectsPath => Path.Combine(RootPath, "Projects");
    /// <summary>Where areas were kept before tags replaced them; see <see cref="MoveAreaNotesToInbox"/>.</summary>
    public string AreasPath => Path.Combine(RootPath, "Areas");

    public void SetupDirectories()
    {
        foreach (var dir in new[] { InboxPath, ProjectsPath }) Directory.CreateDirectory(dir);
    }

    // MARK: Loading

    public void LoadAll()
    {
        SetupDirectories();
        Projects = DiscoverFolders(ProjectsPath, CategoryType.Project);
        var areas = DiscoverFolders(AreasPath, CategoryType.Area);

        var loaded = new List<Note>();
        loaded.AddRange(LoadNotes(InboxPath, CategoryType.Inbox, null));
        foreach (var project in Projects)
            loaded.AddRange(LoadNotes(Path.Combine(ProjectsPath, project.Name), CategoryType.Project, project.Name));
        foreach (var area in areas)
            loaded.AddRange(LoadNotes(Path.Combine(AreasPath, area.Name), CategoryType.Area, area.Name));

        // A crash while moving a note can leave its file in two folders. Show the newest copy and leave
        // the other file on disk untouched
        var newest = new Dictionary<Guid, Note>();
        foreach (var note in loaded)
        {
            if (!newest.TryGetValue(note.Id, out var seen) || seen.UpdatedAt <= note.UpdatedAt) newest[note.Id] = note;
        }
        loaded = loaded.Where(n => newest[n.Id].FilePath == n.FilePath).ToList();

        // Forget files that are gone, so the caches never outgrow the folder
        var loadedPaths = loaded.Select(n => n.FilePath!).ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var path in _fileCache.Keys.Where(p => !loadedPaths.Contains(p)).ToList()) _fileCache.Remove(path);
        var liveIds = loaded.Select(n => n.Id).ToHashSet();
        foreach (var id in _agendaCache.Keys.Where(id => !liveIds.Contains(id)).ToList()) _agendaCache.Remove(id);
        foreach (var id in _peopleCache.Keys.Where(id => !liveIds.Contains(id)).ToList()) _peopleCache.Remove(id);

        _notes = loaded;
        SortNotes();
        if (Directory.Exists(AreasPath) || _notes.Any(n => n.CategoryType == CategoryType.Area)) MoveAreaNotesToInbox();
        Changed?.Invoke(this, EventArgs.Empty);
    }

    /// <summary>
    /// Areas were replaced by tags, as in the Mac app. Moves each note still in an area (written by an older
    /// version, perhaps on another device) to the Inbox tagged with the area's name, then removes area folders
    /// left with nothing but their icon file. A note is written to the Inbox before its old file is removed.
    /// </summary>
    private void MoveAreaNotesToInbox()
    {
        foreach (var note in _notes.Where(n => n.CategoryType == CategoryType.Area).ToList())
        {
            var tag = Mentions.TagNameForArea(note.TargetName ?? "");
            var content = note.Content;
            if (!Mentions.Names(Mentions.Kind.Tag, content).Contains(tag, StringComparer.OrdinalIgnoreCase))
            {
                var body = content.Trim('\n', '\r');
                content = body.Length == 0 ? "#" + tag : body + "\n\n#" + tag;
            }
            Save(note with { Content = content, CategoryType = CategoryType.Inbox, TargetName = null, Tags = Mentions.Names(Mentions.Kind.Tag, content) });
        }

        if (!Directory.Exists(AreasPath)) return;
        IgnoreOwnEvents();
        foreach (var dir in Directory.EnumerateDirectories(AreasPath))
        {
            var files = Directory.EnumerateFileSystemEntries(dir).Select(Path.GetFileName).ToList();
            if (files.All(f => f is MetadataFileName or ".DS_Store" or "desktop.ini")) Directory.Delete(dir, recursive: true);
        }
        if (Directory.EnumerateFileSystemEntries(AreasPath).Select(Path.GetFileName).All(f => f is ".DS_Store" or "desktop.ini"))
            Directory.Delete(AreasPath, recursive: true);
    }

    private static bool IsHidden(string path) =>
        Path.GetFileName(path).StartsWith('.') ||
        (OperatingSystem.IsWindows() && File.GetAttributes(path).HasFlag(FileAttributes.Hidden));

    private static List<ProjectArea> DiscoverFolders(string parent, CategoryType type)
    {
        if (!Directory.Exists(parent)) return [];
        return Directory.EnumerateDirectories(parent)
            .Where(dir => !IsHidden(dir))
            .Select(dir => new ProjectArea(Path.GetFileName(dir), type, ReadIcon(dir)))
            .OrderBy(p => p.Name, StringComparer.CurrentCultureIgnoreCase)
            .ToList();
    }

    private static string? ReadIcon(string dir)
    {
        var path = Path.Combine(dir, MetadataFileName);
        if (!File.Exists(path)) return null;
        try
        {
            return JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllBytes(path))?.GetValueOrDefault("icon");
        }
        catch (Exception)
        {
            return null;
        }
    }

    private List<Note> LoadNotes(string directory, CategoryType category, string? targetName)
    {
        if (!Directory.Exists(directory)) return [];
        var result = new List<Note>();
        foreach (var file in Directory.EnumerateFiles(directory))
        {
            if (!file.EndsWith(".md", StringComparison.OrdinalIgnoreCase) || IsHidden(file)) continue;
            var note = CachedOrParsedNote(file);
            if (note is null) continue;
            // Frontmatter without a destination takes it from the folder
            if (note.CategoryType == CategoryType.Inbox && category != CategoryType.Inbox)
                note = note with { CategoryType = category, TargetName = targetName };
            result.Add(note);
        }
        return result;
    }

    /// <summary>The parsed note at <paramref name="file"/>, read from disk only when the file changed since it was last parsed.</summary>
    private Note? CachedOrParsedNote(string file)
    {
        FileInfo info;
        try
        {
            info = new FileInfo(file);
            if (_fileCache.TryGetValue(file, out var cached) && cached.Modified == info.LastWriteTimeUtc && cached.Size == info.Length)
                return cached.Note;
        }
        catch (IOException)
        {
            return null;
        }

        string? raw;
        try
        {
            raw = AtomicFile.ReadUtf8(file);
        }
        catch (IOException)
        {
            _fileCache.Remove(file);
            return null;
        }
        if (raw is null) return null;
        var note = NoteFormat.Parse(raw, file);
        _fileCache[file] = new CachedFile(info.LastWriteTimeUtc, info.Length, note);
        return note;
    }

    // MARK: Notes

    public Note CreateNote(
        string title = "",
        string content = "",
        CategoryType category = CategoryType.Inbox,
        string? targetName = null,
        IReadOnlyList<string>? tags = null)
    {
        var now = DateTimeOffset.UtcNow;
        var note = new Note
        {
            Title = title,
            Content = content,
            CategoryType = category,
            TargetName = targetName,
            CreatedAt = now,
            UpdatedAt = now,
            Tags = tags ?? [],
        };
        Save(note);
        return _notes.FirstOrDefault(n => n.Id == note.Id) ?? note;
    }

    /// <summary>Writes the note to disk and updates <see cref="Notes"/>. Returns false when the file could not be written.</summary>
    public bool Save(Note note)
    {
        var existing = _notes.FirstOrDefault(n => n.Id == note.Id);
        if (existing is not null && existing.HasSameContent(note) && note.FilePath is not null) return true;

        var updated = note with { UpdatedAt = DateTimeOffset.UtcNow, TargetName = NormalizedTarget(note) };
        updated = updated with
        {
            Content = AgendaExtractor.ResolvingDates(updated.Content, existing?.Content, existing?.UpdatedAt, updated.UpdatedAt, _timeZone),
        };
        var destination = TargetDirectory(updated.CategoryType, updated.TargetName);

        string? stale = null;
        string filePath;
        if (updated.FilePath is { } current && SamePath(Path.GetDirectoryName(current), destination))
        {
            filePath = current;
        }
        else
        {
            // Moved to another folder, or new. The old file goes only after the new one is safely on disk,
            // so a crash in between leaves a duplicate, never a lost note
            if (updated.FilePath is { } old && File.Exists(old)) stale = old;
            filePath = UniqueFilePath(updated, destination);
            updated = updated with { FilePath = filePath };
        }

        IgnoreOwnEvents();
        try
        {
            Directory.CreateDirectory(destination);
            AtomicFile.WriteAllText(filePath, NoteFormat.Serialize(updated));
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            SaveFailed?.Invoke(this, e);
            return false;
        }

        if (stale is not null && !SamePath(stale, filePath))
        {
            try
            {
                AtomicFile.WithRetry(() => File.Delete(stale));
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                // The note is safe at its new path; the leftover copy is hidden as a duplicate on load
            }
        }

        var index = _notes.FindIndex(n => n.Id == updated.Id);
        if (index >= 0) _notes[index] = updated;
        else _notes.Insert(0, updated);
        SortNotes();
        Changed?.Invoke(this, EventArgs.Empty);
        return true;
    }

    public void Delete(Note note)
    {
        IgnoreOwnEvents();
        if (note.FilePath is { } path && File.Exists(path))
        {
            try
            {
                AtomicFile.WithRetry(() => File.Delete(path));
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                SaveFailed?.Invoke(this, e);
                return;
            }
        }
        _notes.RemoveAll(n => n.Id == note.Id);
        _agendaCache.Remove(note.Id);
        _peopleCache.Remove(note.Id);
        Changed?.Invoke(this, EventArgs.Empty);
    }

    public bool Move(Note note, CategoryType category, string? targetName) =>
        Save(note with { CategoryType = category, TargetName = targetName });

    public bool TogglePin(Note note) => Save(note with { IsPinned = !note.IsPinned });

    public void ToggleChecklistItem(Guid noteId, int lineIndex)
    {
        if (_notes.FirstOrDefault(n => n.Id == noteId) is not { } note) return;
        Save(note with { Content = Checklist.ToggleLine(lineIndex, note.Content) });
    }

    // MARK: Agenda

    /// <summary>Checklist items and dated lines from every note, for the dashboard.</summary>
    public List<AgendaItem> AgendaItems() => _notes.SelectMany(AgendaItemsFor).ToList();

    /// <summary>Checklist items and dated lines of one note, dated from when each line was written.</summary>
    public List<AgendaItem> AgendaItemsFor(Note note)
    {
        if (_agendaCache.TryGetValue(note.Id, out var cached) && cached.UpdatedAt == note.UpdatedAt &&
            cached.Content == note.Content)
            return cached.Items;
        var items = AgendaExtractor.Items(note, _timeZone);
        _agendaCache[note.Id] = new CachedAgenda(note.Content, note.UpdatedAt, items);
        return items;
    }

    /// <summary>The people mentioned in a note as <c>@name</c>, in the order they first appear.</summary>
    public IReadOnlyList<string> PeopleIn(Note note)
    {
        if (_peopleCache.TryGetValue(note.Id, out var cached) && cached.Content == note.Content) return cached.Names;
        var names = note.People;
        _peopleCache[note.Id] = (note.Content, names);
        return names;
    }

    // MARK: Projects

    /// <summary>Creates a project folder and returns the name it got, which may differ to be valid on Windows.</summary>
    public string? CreateProject(string name, string? icon = null) => CreateFolder(ProjectsPath, name, icon);

    public void DeleteProject(string name) => DeleteFolder(Path.Combine(ProjectsPath, name));

    private string? CreateFolder(string parent, string name, string? icon)
    {
        var folder = FileNames.SanitizeFolderName(name);
        if (folder.Length == 0) return null;
        var dir = Path.Combine(parent, folder);
        Directory.CreateDirectory(dir);
        if (!string.IsNullOrEmpty(icon))
            AtomicFile.WriteAllBytes(Path.Combine(dir, MetadataFileName), JsonSerializer.SerializeToUtf8Bytes(new Dictionary<string, string> { ["icon"] = icon }));
        LoadAll();
        return folder;
    }

    private void DeleteFolder(string dir)
    {
        IgnoreOwnEvents();
        if (Directory.Exists(dir)) Directory.Delete(dir, recursive: true);
        LoadAll();
    }

    // MARK: Moving the notes folder

    public sealed class RelocationException(string message) : Exception(message);

    /// <summary>
    /// Points the app at <paramref name="newRoot"/> and moves every note, project and area folder and their
    /// metadata from the current folder and the default folder into it. Returns the number of notes moved.
    /// </summary>
    public int RelocateStorage(string newRoot, string? defaultRoot = null)
    {
        var destination = Path.GetFullPath(newRoot);
        var sources = new List<string> { Path.GetFullPath(RootPath) };
        var fallback = Path.GetFullPath(defaultRoot ?? AppSettings.DefaultNotesDirectory);
        if (!sources.Any(s => SamePath(s, fallback))) sources.Add(fallback);
        sources.RemoveAll(s => SamePath(s, destination));

        if (sources.Any(s => IsInside(destination, s)))
            throw new RelocationException("The new folder can't be inside a folder that currently holds your notes.");

        StopWatching();
        IgnoreOwnEvents();
        var moved = 0;
        foreach (var source in sources)
        {
            foreach (var folder in new[] { "Inbox", "Projects", "Areas" })
                moved += MoveContents(Path.Combine(source, folder), Path.Combine(destination, folder));
        }
        Directory.CreateDirectory(destination);

        if (!SamePath(_settings.NotesDirectory, destination))
        {
            // The settings handler reloads and restarts the watcher
            _settings.NotesDirectory = destination;
        }
        else
        {
            LoadAll();
            if (_enableFileWatcher) StartWatching();
        }
        return moved;
    }

    private static bool IsInside(string child, string parent)
    {
        var prefix = parent.EndsWith(Path.DirectorySeparatorChar) ? parent : parent + Path.DirectorySeparatorChar;
        return child.StartsWith(prefix, PathComparison);
    }

    /// <summary>Moves notes and metadata recursively, keeping the layout. Clashing notes get a numeric suffix; metadata already at the destination wins.</summary>
    private static int MoveContents(string sourceDir, string destDir)
    {
        if (!Directory.Exists(sourceDir)) return 0;
        Directory.CreateDirectory(destDir);
        var moved = 0;
        foreach (var dir in Directory.EnumerateDirectories(sourceDir).ToList())
            moved += MoveContents(dir, Path.Combine(destDir, Path.GetFileName(dir)));
        foreach (var file in Directory.EnumerateFiles(sourceDir).ToList())
        {
            var name = Path.GetFileName(file);
            if (name == MetadataFileName)
            {
                var target = Path.Combine(destDir, name);
                if (!File.Exists(target)) File.Move(file, target);
            }
            else if (name.EndsWith(".md", StringComparison.OrdinalIgnoreCase))
            {
                File.Move(file, UniqueDestination(name, destDir));
                moved++;
            }
        }
        // Remove the source folder if only system clutter is left
        string[] clutter = [".DS_Store", "desktop.ini", "Thumbs.db"];
        if (Directory.EnumerateFileSystemEntries(sourceDir).All(e => clutter.Contains(Path.GetFileName(e))))
            Directory.Delete(sourceDir, recursive: true);
        return moved;
    }

    private static string UniqueDestination(string fileName, string directory)
    {
        var candidate = Path.Combine(directory, fileName);
        if (!File.Exists(candidate)) return candidate;
        var stem = Path.GetFileNameWithoutExtension(fileName);
        var ext = Path.GetExtension(fileName);
        for (var index = 2; ; index++)
        {
            var next = Path.Combine(directory, $"{stem}_{index}{ext}");
            if (!File.Exists(next)) return next;
        }
    }

    // MARK: File watching

    private void StartWatching()
    {
        StopWatching();
        _watcher = new FileSystemWatcher(RootPath)
        {
            IncludeSubdirectories = true,
            NotifyFilter = NotifyFilters.FileName | NotifyFilters.DirectoryName | NotifyFilters.LastWrite,
        };
        _watcher.Changed += OnFileEvent;
        _watcher.Created += OnFileEvent;
        _watcher.Deleted += OnFileEvent;
        _watcher.Renamed += OnFileEvent;
        _debounce = new Timer(_ => FilesChangedExternally?.Invoke(this, EventArgs.Empty));
        _watcher.EnableRaisingEvents = true;
    }

    private void StopWatching()
    {
        _watcher?.Dispose();
        _watcher = null;
        _debounce?.Dispose();
        _debounce = null;
    }

    private void OnFileEvent(object sender, FileSystemEventArgs e)
    {
        if (Environment.TickCount64 < Interlocked.Read(ref _ignoreEventsUntil)) return;
        var name = Path.GetFileName(e.FullPath);
        // Temporary files from atomic writes are the app's own
        if (name.EndsWith(".tmp", StringComparison.OrdinalIgnoreCase)) return;
        _debounce?.Change(TimeSpan.FromMilliseconds(400), Timeout.InfiniteTimeSpan);
    }

    private void IgnoreOwnEvents() => Interlocked.Exchange(ref _ignoreEventsUntil, Environment.TickCount64 + 800);

    // MARK: Helpers

    private static StringComparison PathComparison =>
        OperatingSystem.IsLinux() ? StringComparison.Ordinal : StringComparison.OrdinalIgnoreCase;

    private static bool SamePath(string? a, string? b) =>
        a is not null && b is not null &&
        string.Equals(Path.GetFullPath(a).TrimEnd(Path.DirectorySeparatorChar), Path.GetFullPath(b).TrimEnd(Path.DirectorySeparatorChar), PathComparison);

    /// <summary>Project and area names become folder names, so they follow the folder name rules.</summary>
    private static string? NormalizedTarget(Note note)
    {
        if (note.CategoryType == CategoryType.Inbox || string.IsNullOrWhiteSpace(note.TargetName)) return note.TargetName;
        var folder = FileNames.SanitizeFolderName(note.TargetName);
        return folder.Length == 0 ? null : folder;
    }

    private string TargetDirectory(CategoryType category, string? targetName)
    {
        var name = string.IsNullOrWhiteSpace(targetName) ? "General" : targetName.Trim();
        return category switch
        {
            CategoryType.Project => Path.Combine(ProjectsPath, name),
            CategoryType.Area => Path.Combine(AreasPath, name),
            _ => InboxPath,
        };
    }

    /// <summary>
    /// A file name no other note uses. Clashing titles get the first 6 characters of the ID, as on the Mac;
    /// if even that is taken, the whole ID, so a new note can never overwrite another note's file.
    /// </summary>
    private static string UniqueFilePath(Note note, string directory)
    {
        foreach (var suffix in new[] { 0, 6, 36 })
        {
            var candidate = Path.Combine(directory, FileNames.NoteFileName(note, suffix));
            if (!File.Exists(candidate) || SamePath(candidate, note.FilePath)) return candidate;
        }
        throw new IOException($"A file named after note {note.IdString} already exists in {directory}.");
    }

    private void SortNotes() =>
        _notes = _notes.OrderByDescending(n => n.IsPinned).ThenByDescending(n => n.UpdatedAt).ToList();
}
