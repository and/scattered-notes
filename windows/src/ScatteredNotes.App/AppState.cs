using Avalonia.Threading;
using ScatteredNotes.Core.Models;
using ScatteredNotes.Core.Storage;

namespace ScatteredNotes.App;

public enum SidebarKind
{
    Dashboard,
    All,
    Inbox,
    Project,
    Area,
}

/// <summary>What the sidebar has selected.</summary>
public sealed record SidebarSelection(SidebarKind Kind, string? Name = null)
{
    public static readonly SidebarSelection Dashboard = new(SidebarKind.Dashboard);
    public static readonly SidebarSelection All = new(SidebarKind.All);
    public static readonly SidebarSelection Inbox = new(SidebarKind.Inbox);

    public string Title => Kind switch
    {
        SidebarKind.Dashboard => "Dashboard",
        SidebarKind.All => "All Notes",
        SidebarKind.Inbox => "Inbox",
        _ => Name ?? "",
    };

    public bool Includes(Note note) => Kind switch
    {
        SidebarKind.Inbox => note.CategoryType == CategoryType.Inbox,
        SidebarKind.Project => note.CategoryType == CategoryType.Project && note.TargetName == Name,
        SidebarKind.Area => note.CategoryType == CategoryType.Area && note.TargetName == Name,
        _ => true,
    };
}

/// <summary>A request to put the cursor in a note's text: after the searched word, or at the end.</summary>
public sealed record EditorFocusRequest(Guid NoteId, IReadOnlyList<string> Terms);

/// <summary>State shared by every window: the store, settings, and what is selected.</summary>
public sealed class AppState
{
    public AppSettings Settings { get; }
    public NoteStore Store { get; }

    private SidebarSelection _selection = SidebarSelection.Dashboard;
    private Guid? _selectedNoteId;

    /// <summary>Brings the main window forward; set by the app.</summary>
    public Action? ShowMainWindow { get; set; }

    public event Action? SelectionChanged;
    public event Action? SelectedNoteChanged;
    public event Action<EditorFocusRequest>? FocusEditorRequested;

    public AppState(AppSettings settings, NoteStore store)
    {
        Settings = settings;
        Store = store;
        // Changes made by other apps (or the Mac app over sync) arrive on a watcher thread
        Store.FilesChangedExternally += (_, _) => Dispatcher.UIThread.Post(Store.LoadAll);
    }

    public SidebarSelection Selection
    {
        get => _selection;
        set
        {
            if (_selection == value) return;
            _selection = value;
            SelectionChanged?.Invoke();
        }
    }

    public Note? SelectedNote => _selectedNoteId is { } id ? Store.Notes.FirstOrDefault(n => n.Id == id) : null;

    public void SelectNote(Note? note)
    {
        if (_selectedNoteId == note?.Id) return;
        _selectedNoteId = note?.Id;
        // The dashboard has no editor, so opening a note leaves it
        if (note is not null && Selection.Kind == SidebarKind.Dashboard) Selection = SidebarSelection.All;
        SelectedNoteChanged?.Invoke();
    }

    /// <summary>Shows the note in the editor and puts the cursor in it.</summary>
    public void OpenNote(Note note, IReadOnlyList<string>? terms = null)
    {
        if (Selection.Kind == SidebarKind.Dashboard || !Selection.Includes(note)) Selection = SidebarSelection.All;
        SelectNote(note);
        FocusEditorRequested?.Invoke(new EditorFocusRequest(note.Id, terms ?? []));
    }

    public Note CreateNoteInCurrentSelection()
    {
        var (category, target) = Selection.Kind switch
        {
            SidebarKind.Project => (CategoryType.Project, Selection.Name),
            SidebarKind.Area => (CategoryType.Area, Selection.Name),
            _ => (CategoryType.Inbox, (string?)null),
        };
        var note = Store.CreateNote("Untitled Note", "", category, target);
        OpenNote(note);
        return note;
    }
}
