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
    private AgendaLog _agendaLog = new();
    private List<Note> _notes = [];

    /// <summary>Notes, pinned first, then most recently updated.</summary>
    public IReadOnlyList<Note> Notes => _notes;
    public IReadOnlyList<ProjectArea> Projects { get; private set; } = [];
    public IReadOnlyList<ProjectArea> Areas { get; private set; } = [];

    /// <summary>Raised after notes, projects or areas change.</summary>
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
    public string AreasPath => Path.Combine(RootPath, "Areas");
    public string AgendaLogPath => Path.Combine(RootPath, AgendaLog.FileName);

    public void SetupDirectories()
    {
        foreach (var dir in new[] { InboxPath, ProjectsPath, AreasPath }) Directory.CreateDirectory(dir);
    }

    // MARK: Loading

    public void LoadAll()
    {
        SetupDirectories();
        Projects = DiscoverFolders(ProjectsPath, CategoryType.Project);
        Areas = DiscoverFolders(AreasPath, CategoryType.Area);

        var loaded = new List<Note>();
        loaded.AddRange(LoadNotes(InboxPath, CategoryType.Inbox, null));
        foreach (var project in Projects)
            loaded.AddRange(LoadNotes(Path.Combine(ProjectsPath, project.Name), CategoryType.Project, project.Name));
        foreach (var area in Areas)
            loaded.AddRange(LoadNotes(Path.Combine(AreasPath, area.Name), CategoryType.Area, area.Name));

        // A crash while moving a note can leave its file in two folders. Show the newest copy and leave
        // the other file on disk untouched
        var newest = new Dictionary<Guid, Note>();
        foreach (var note in loaded)
        {
            if (!newest.TryGetValue(note.Id, out var seen) || seen.UpdatedAt <= note.UpdatedAt) newest[note.Id] = note;
        }
        loaded = loaded.Where(n => newest[n.Id].FilePath == n.FilePath).ToList();

        // Pick up lines written outside the app, anchoring them to when the file last changed
        LoadAgendaLog();
        var logChanged = false;
        foreach (var note in loaded)
        {
            var fallback = _agendaLog.Notes.ContainsKey(note.IdString) ? note.UpdatedAt : note.CreatedAt;
            logChanged |= RecordAgenda(note, fallback);
        }
        var liveIds = loaded.Select(n => n.IdString).ToHashSet();
        foreach (var id in _agendaLog.Notes.Keys.Where(id => !liveIds.Contains(id)).ToList())
        {
            _agendaLog.Notes.Remove(id);
            logChanged = true;
        }
        if (logChanged) WriteAgendaLog();

        _notes = loaded;
        SortNotes();
        Changed?.Invoke(this, EventArgs.Empty);
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

    private static List<Note> LoadNotes(string directory, CategoryType category, string? targetName)
    {
        if (!Directory.Exists(directory)) return [];
        var result = new List<Note>();
        foreach (var file in Directory.EnumerateFiles(directory))
        {
            if (!file.EndsWith(".md", StringComparison.OrdinalIgnoreCase) || IsHidden(file)) continue;
            string? raw;
            try
            {
                raw = AtomicFile.ReadUtf8(file);
            }
            catch (IOException)
            {
                continue;
            }
            if (raw is null) continue;
            var note = NoteFormat.Parse(raw, file);
            // Frontmatter without a destination takes it from the folder
            if (note.CategoryType == CategoryType.Inbox && category != CategoryType.Inbox)
                note = note with { CategoryType = category, TargetName = targetName };
            result.Add(note);
        }
        return result;
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
        if (RecordAgenda(updated, DateTimeOffset.UtcNow)) WriteAgendaLog();
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
        if (_agendaLog.Remove(note.Id)) WriteAgendaLog();
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

    /// <summary>Checklist items and dated lines of one note, dated from when each line was first written.</summary>
    public List<AgendaItem> AgendaItemsFor(Note note) =>
        AgendaExtractor.Items(note, _agendaLog.Anchors(note.Id), _timeZone);

    private void LoadAgendaLog()
    {
        _agendaLog = ReadLog(AgendaLogPath) ?? new AgendaLog();
        // Sync clients save clashing versions next to the original, e.g. ".agenda-log 2.json"
        foreach (var copy in Directory.EnumerateFiles(RootPath, ".agenda-log*.json"))
        {
            if (SamePath(copy, AgendaLogPath)) continue;
            if (ReadLog(copy) is { } other) _agendaLog.Merge(other);
        }
    }

    private static AgendaLog? ReadLog(string path)
    {
        try
        {
            return File.Exists(path) ? AgendaLog.Decode(File.ReadAllBytes(path)) : null;
        }
        catch (IOException)
        {
            return null;
        }
    }

    private void WriteAgendaLog()
    {
        IgnoreOwnEvents();
        try
        {
            AtomicFile.WriteAllBytes(AgendaLogPath, _agendaLog.Encode());
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            // Derived data: it is rebuilt on the next save
        }
    }

    /// <summary>Adds log entries for new lines and drops entries for removed ones. Returns whether anything changed.</summary>
    private bool RecordAgenda(Note note, DateTimeOffset seenAt)
    {
        var lines = AgendaExtractor.Items(note, timeZone: _timeZone).Select(i => (AgendaExtractor.LogKey(i.Text), i.Text));
        return _agendaLog.Update(note.Id, lines, seenAt);
    }

    // MARK: Projects and areas

    /// <summary>Creates a project folder and returns the name it got, which may differ to be valid on Windows.</summary>
    public string? CreateProject(string name, string? icon = null) => CreateFolder(ProjectsPath, name, icon);

    public void DeleteProject(string name) => DeleteFolder(Path.Combine(ProjectsPath, name));

    public string? CreateArea(string name, string? icon = null) => CreateFolder(AreasPath, name, icon);

    public void DeleteArea(string name) => DeleteFolder(Path.Combine(AreasPath, name));

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
        var log = ReadLog(Path.Combine(destination, AgendaLog.FileName)) ?? new AgendaLog();
        foreach (var source in sources)
        {
            foreach (var folder in new[] { "Inbox", "Projects", "Areas" })
                moved += MoveContents(Path.Combine(source, folder), Path.Combine(destination, folder));
            // Keep when each line was written, so relative dates do not move
            if (ReadLog(Path.Combine(source, AgendaLog.FileName)) is { } sourceLog) log.Merge(sourceLog);
        }
        Directory.CreateDirectory(destination);
        AtomicFile.WriteAllBytes(Path.Combine(destination, AgendaLog.FileName), log.Encode());

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
        // Temporary files from atomic writes and the agenda log are the app's own
        if (name.EndsWith(".tmp", StringComparison.OrdinalIgnoreCase) || name.StartsWith(".agenda-log", StringComparison.Ordinal)) return;
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

    private static string UniqueFilePath(Note note, string directory)
    {
        var candidate = Path.Combine(directory, FileNames.NoteFileName(note));
        if (!File.Exists(candidate) || SamePath(candidate, note.FilePath)) return candidate;
        return Path.Combine(directory, FileNames.NoteFileName(note, withIdSuffix: true));
    }

    private void SortNotes() =>
        _notes = _notes.OrderByDescending(n => n.IsPinned).ThenByDescending(n => n.UpdatedAt).ToList();
}
