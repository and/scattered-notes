using ScatteredNotes.Core.Storage;

namespace ScatteredNotes.Core.Tests;

/// <summary>A notes folder in the temp directory, deleted when the test ends.</summary>
public sealed class TempStore : IDisposable
{
    public static readonly TimeZoneInfo Kolkata = TimeZoneInfo.FindSystemTimeZoneById("Asia/Kolkata");

    public string Root { get; } = Path.Combine(Path.GetTempPath(), "sn-tests-" + Guid.NewGuid().ToString("N"));

    public AppSettings Settings { get; }

    public NoteStore Store { get; private set; }

    public TempStore()
    {
        Settings = new AppSettings(notesDirectory: Root);
        Store = new NoteStore(Settings, enableFileWatcher: false, timeZone: Kolkata);
    }

    /// <summary>A brand new store reading only what is on disk, as after a crash and relaunch.</summary>
    public NoteStore Open() => new(new AppSettings(notesDirectory: Settings.NotesDirectory), enableFileWatcher: false, timeZone: Kolkata);

    public IEnumerable<string> MarkdownFiles() =>
        Directory.Exists(Root) ? Directory.EnumerateFiles(Root, "*.md", SearchOption.AllDirectories) : [];

    public void Dispose()
    {
        if (Directory.Exists(Root)) Directory.Delete(Root, recursive: true);
    }
}
