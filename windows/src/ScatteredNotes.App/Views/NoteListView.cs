using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Templates;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.VisualTree;
using FluentIcons.Common;
using ScatteredNotes.Core.Models;
using ScatteredNotes.Core.Search;

namespace ScatteredNotes.App.Views;

internal enum NoteSort
{
    DateModified,
    DateCreated,
    Title,
}

/// <summary>The notes of the selected sidebar item, with a filter box, sort menu and new note button.</summary>
internal sealed class NoteListView : UserControl
{
    private readonly AppState _state;
    private readonly TextBox _search;
    private readonly ListBox _list;
    private readonly Control _empty;
    private NoteSort _sort = NoteSort.DateModified;
    private bool _syncing;

    public NoteListView(AppState state)
    {
        _state = state;

        _search = new TextBox { PlaceholderText = "Search notes or #tags…", InnerLeftContent = Ui.Icon(Symbol.Search, 14, "WcagSecondaryText"), Padding = new Thickness(6, 5) };
        _search.TextChanged += (_, _) => Refresh();
        _search.KeyDown += (_, e) =>
        {
            if (e.Key == Key.Down && _list!.ItemCount > 0)
            {
                // Back into the list
                _list.Focus();
                if (_list.SelectedItem is null) _list.SelectedIndex = 0;
                e.Handled = true;
                return;
            }
            if (e.Key != Key.Enter) return;
            OpenFirstMatch();
            e.Handled = true;
        };

        var sortButton = Ui.IconButton(Symbol.ArrowSort, "Sort by", () => { });
        sortButton.Flyout = SortMenu();
        var newButton = Ui.IconButton(Symbol.Compose, "New Note (Ctrl+N)", () => _state.CreateNoteInCurrentSelection(), "WcagBlue");

        var header = new DockPanel { Margin = new Thickness(12, 10, 8, 8) };
        var buttons = Ui.Row(2, sortButton, newButton);
        DockPanel.SetDock(buttons, Dock.Right);
        header.Children.Add(buttons);
        header.Children.Add(_search);

        _list = new ListBox
        {
            Classes = { "wcag" },
            Background = Brushes.Transparent,
            ItemTemplate = new FuncDataTemplate<Note>((note, _) => note is null ? new TextBlock() : NoteRow(note)),
        };
        _list.SelectionChanged += (_, _) =>
        {
            if (!_syncing && _list.SelectedItem is Note note) _state.SelectNote(note);
        };
        // Tunnelling, so left and right reach this before the list uses them for its own navigation
        _list.AddHandler(KeyDownEvent, (_, e) =>
        {
            if (e.KeyModifiers != KeyModifiers.None) return;
            if (e.Key == Key.Up && _list.SelectedIndex <= 0)
            {
                // Up from the first note goes to the search box
                _search.Focus();
                e.Handled = true;
                return;
            }
            if (e.Key == Key.Left)
            {
                MoveToSidebar();
                e.Handled = true;
                return;
            }
            // Return and the right arrow both go on into the note's text
            if (e.Key is not (Key.Enter or Key.Right) || _state.SelectedNote is not { } note) return;
            _state.OpenNote(note, NoteSearch.Terms(_search.Text ?? ""));
            e.Handled = true;
        }, Avalonia.Interactivity.RoutingStrategies.Tunnel);
        _list.ContextRequested += (_, e) =>
        {
            if ((e.Source as Control)?.FindAncestorOfType<ListBoxItem>(true)?.DataContext is not Note note) return;
            NoteMenus.ContextMenu(_state, note, TopLevel.GetTopLevel(this) as Window).Open(e.Source as Control);
            e.Handled = true;
        };

        var create = new Button { Content = "Create Note", Classes = { "accent" }, HorizontalAlignment = HorizontalAlignment.Center };
        create.Click += (_, _) => _state.CreateNoteInCurrentSelection();
        var emptyPanel = new StackPanel { Spacing = 12, VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center };
        emptyPanel.Children.Add(Ui.Icon(Symbol.Note, 36, "WcagSecondaryText"));
        emptyPanel.Children.Add(Ui.Text("No notes yet", 15, FontWeight.SemiBold, "WcagSecondaryText"));
        emptyPanel.Children.Add(create);
        _empty = emptyPanel;

        var root = new DockPanel();
        DockPanel.SetDock(header, Dock.Top);
        root.Children.Add(header);
        var separator = new Border { Height = 1 }.Themed(Border.BackgroundProperty, "CardBorder");
        DockPanel.SetDock(separator, Dock.Top);
        root.Children.Add(separator);
        var body = new Panel();
        body.Children.Add(_list);
        body.Children.Add(_empty);
        root.Children.Add(body);
        Content = root;

        _state.Store.Changed += (_, _) => Refresh();
        _state.SelectionChanged += Refresh;
        _state.SelectedNoteChanged += SyncSelection;
        Refresh();
    }

    /// <summary>
    /// Left from the list goes to the sidebar. From All Notes it lands on the open note's project, as on the Mac,
    /// so the arrows move on among that project's neighbours.
    /// </summary>
    private void MoveToSidebar()
    {
        if (_state.Selection.Kind == SidebarKind.All && _state.SelectedNote is { CategoryType: CategoryType.Project, TargetName: { } project })
            _state.Selection = new SidebarSelection(SidebarKind.Project, project);
        _state.RequestFocus(FocusTarget.Sidebar);
    }

    /// <summary>Puts the keyboard in the list, on the open note, or on the first note when none of this list is open.</summary>
    public void FocusList()
    {
        if (_list.ItemCount == 0)
        {
            _search.Focus();
            return;
        }
        if (_list.SelectedIndex < 0) _list.SelectedIndex = 0;
        _list.ScrollIntoView(_list.SelectedIndex);
        if (_list.ContainerFromIndex(_list.SelectedIndex) is { } row) row.Focus(NavigationMethod.Directional);
        else _list.Focus(NavigationMethod.Directional);
    }

    public void FocusSearch() => _search.Focus();

    private MenuFlyout SortMenu()
    {
        var menu = new MenuFlyout();
        foreach (var (sort, label) in new[] { (NoteSort.DateModified, "Date Modified"), (NoteSort.DateCreated, "Date Created"), (NoteSort.Title, "Title") })
        {
            var item = new MenuItem { Header = label, ToggleType = MenuItemToggleType.Radio, IsChecked = sort == _sort, GroupName = "sort" };
            item.Click += (_, _) =>
            {
                _sort = sort;
                Refresh();
            };
            menu.Items.Add(item);
        }
        return menu;
    }

    private List<Note> FilteredNotes()
    {
        var notes = _state.Store.Notes.Where(_state.Selection.Includes);
        var query = (_search.Text ?? "").Trim();
        if (query.Length > 0)
        {
            notes = notes.Where(n =>
                NoteSearch.Find(n.Title, query) is not null ||
                NoteSearch.Find(n.Content, query) is not null ||
                n.Tags.Any(t => NoteSearch.Find(t, query.TrimStart('#')) is not null) ||
                (n.TargetName is { } target && NoteSearch.Find(target, query) is not null));
        }
        var pinnedFirst = notes.OrderByDescending(n => n.IsPinned);
        return (_sort switch
        {
            NoteSort.DateCreated => pinnedFirst.ThenByDescending(n => n.CreatedAt),
            NoteSort.Title => pinnedFirst.ThenBy(n => n.DisplayTitle, StringComparer.CurrentCultureIgnoreCase),
            _ => pinnedFirst.ThenByDescending(n => n.UpdatedAt),
        }).ToList();
    }

    private void Refresh()
    {
        var notes = FilteredNotes();
        _syncing = true;
        _list.ItemsSource = notes;
        _syncing = false;
        _list.IsVisible = notes.Count > 0;
        _empty.IsVisible = notes.Count == 0;
        SyncSelection();
    }

    private void SyncSelection()
    {
        _syncing = true;
        var id = _state.SelectedNote?.Id;
        _list.SelectedItem = _list.ItemsSource?.Cast<Note>().FirstOrDefault(n => n.Id == id);
        if (_list.SelectedItem is { } selected) _list.ScrollIntoView(selected);
        _syncing = false;
    }

    private void OpenFirstMatch()
    {
        var matches = _list.ItemsSource?.Cast<Note>().ToList() ?? [];
        var note = matches.FirstOrDefault(n => n.Id == _state.SelectedNote?.Id) ?? matches.FirstOrDefault();
        if (note is not null) _state.OpenNote(note, NoteSearch.Terms(_search.Text ?? ""));
    }

    private Control NoteRow(Note note)
    {
        var top = new DockPanel();
        var date = Ui.Text(note.UpdatedAt.ToLocalTime().ToString("d"), 11, classes: "secondary");
        DockPanel.SetDock(date, Dock.Right);
        top.Children.Add(date);
        // A DockPanel, not a StackPanel, so a long title is cut with an ellipsis before the date
        date.Margin = new Thickness(8, 0, 0, 0);
        if (note.IsPinned)
        {
            var pin = Ui.Icon(Symbol.Pin, 11, "WcagOrange", IconVariant.Filled);
            pin.Margin = new Thickness(0, 0, 6, 0);
            DockPanel.SetDock(pin, Dock.Left);
            top.Children.Add(pin);
        }
        top.Children.Add(Ui.Text(note.DisplayTitle, 13, FontWeight.SemiBold));

        var stack = new StackPanel { Spacing = 4, Margin = new Thickness(10, 8) };
        stack.Children.Add(top);
        if (note.PreviewExcerpt.Length > 0)
        {
            var excerpt = Ui.Text(note.PreviewExcerpt, 12, classes: "secondary");
            excerpt.TextWrapping = TextWrapping.Wrap;
            excerpt.MaxLines = 2;
            stack.Children.Add(excerpt);
        }

        var meta = new DockPanel { Margin = new Thickness(0, 2, 0, 0) };
        if (note.Tags.Count > 0)
        {
            var tag = Ui.Text("#" + note.Tags[0], 10, classes: "secondary");
            DockPanel.SetDock(tag, Dock.Right);
            meta.Children.Add(tag);
        }
        var badges = Ui.Row(6);
        // Under a project every note is in it, so naming it on each row only adds noise
        if (_state.Selection.Kind == SidebarKind.All ||
            (_state.Selection.Kind != SidebarKind.Project && note.CategoryType != CategoryType.Inbox))
        {
            var brush = Ui.DestinationBrush(note.CategoryType);
            var badge = new Border
            {
                Classes = { "badge" },
                CornerRadius = new CornerRadius(4),
                Padding = new Thickness(5, 2),
                Child = Ui.Text(note.DestinationDisplay, 10, FontWeight.SemiBold, brush),
            };
            badges.Children.Add(badge);
        }
        if (note.ChecklistStats is { } stats)
        {
            var done = stats.Completed == stats.Total;
            badges.Children.Add(Ui.Row(2, Ui.Icon(Symbol.CheckmarkCircle, 11, done ? "WcagGreen" : "WcagSecondaryText"),
                Ui.Text($"{stats.Completed}/{stats.Total}", 10, brushKey: done ? "WcagGreen" : "WcagSecondaryText")));
        }
        meta.Children.Add(badges);
        stack.Children.Add(meta);
        Avalonia.Automation.AutomationProperties.SetName(stack, note.DisplayTitle);
        return stack;
    }
}
