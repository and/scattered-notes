using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace ScatteredNotes.Core.Storage;

/// <summary>
/// User preferences, saved as JSON in <c>%APPDATA%\ScatteredNotes\settings.json</c> (the Mac app keeps
/// the same values in UserDefaults). Every change is saved straight away.
/// </summary>
public sealed class AppSettings : INotifyPropertyChanged
{
    public static string DefaultNotesDirectory =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "ScatteredNotes");

    public static string DefaultSettingsPath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "ScatteredNotes", "settings.json");

    private sealed class Stored
    {
        [JsonPropertyName("notesDirectory")] public string? NotesDirectory { get; set; }
        [JsonPropertyName("editorFontSize")] public double EditorFontSize { get; set; }
        [JsonPropertyName("quickCaptureShortcut")] public HotKeyShortcut? QuickCaptureShortcut { get; set; }
        [JsonPropertyName("searchShortcut")] public HotKeyShortcut? SearchShortcut { get; set; }
        [JsonPropertyName("startAtLogin")] public bool StartAtLogin { get; set; }
    }

    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    private readonly string? _path;
    private string _notesDirectory;
    private double _editorFontSize;
    private HotKeyShortcut _quickCaptureShortcut;
    private HotKeyShortcut _searchShortcut;
    private bool _startAtLogin;

    public event PropertyChangedEventHandler? PropertyChanged;

    /// <param name="path">Where settings are kept; null keeps them in memory only, for tests.</param>
    /// <param name="notesDirectory">Overrides the saved notes folder.</param>
    public AppSettings(string? path = null, string? notesDirectory = null)
    {
        _path = path;
        Stored? stored = null;
        if (path is not null && File.Exists(path))
        {
            try
            {
                stored = JsonSerializer.Deserialize<Stored>(File.ReadAllBytes(path), JsonOptions);
            }
            catch (Exception)
            {
                // Unreadable settings fall back to the defaults
            }
        }
        _notesDirectory = notesDirectory
            ?? (string.IsNullOrEmpty(stored?.NotesDirectory) ? DefaultNotesDirectory : stored.NotesDirectory);
        _editorFontSize = stored?.EditorFontSize > 0 ? stored.EditorFontSize : 14;
        _quickCaptureShortcut = stored?.QuickCaptureShortcut ?? HotKeyShortcut.QuickCaptureDefault;
        _searchShortcut = stored?.SearchShortcut ?? HotKeyShortcut.SearchDefault;
        _startAtLogin = stored?.StartAtLogin ?? false;
    }

    public string NotesDirectory
    {
        get => _notesDirectory;
        set => Set(ref _notesDirectory, value);
    }

    public double EditorFontSize
    {
        get => _editorFontSize;
        set => Set(ref _editorFontSize, value);
    }

    /// <summary>Global shortcut that opens Quick Capture from any app.</summary>
    public HotKeyShortcut QuickCaptureShortcut
    {
        get => _quickCaptureShortcut;
        set => Set(ref _quickCaptureShortcut, value);
    }

    /// <summary>Global shortcut that opens search over all notes from any app.</summary>
    public HotKeyShortcut SearchShortcut
    {
        get => _searchShortcut;
        set => Set(ref _searchShortcut, value);
    }

    public bool StartAtLogin
    {
        get => _startAtLogin;
        set => Set(ref _startAtLogin, value);
    }

    public void ResetToDefault()
    {
        NotesDirectory = DefaultNotesDirectory;
        EditorFontSize = 14;
    }

    private void Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return;
        field = value;
        Save();
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }

    private void Save()
    {
        if (_path is null) return;
        var stored = new Stored
        {
            NotesDirectory = _notesDirectory,
            EditorFontSize = _editorFontSize,
            QuickCaptureShortcut = _quickCaptureShortcut,
            SearchShortcut = _searchShortcut,
            StartAtLogin = _startAtLogin,
        };
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
        AtomicFile.WriteAllBytes(_path, JsonSerializer.SerializeToUtf8Bytes(stored, JsonOptions));
    }
}
