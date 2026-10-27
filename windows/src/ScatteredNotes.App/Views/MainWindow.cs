using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using FluentIcons.Common;

namespace ScatteredNotes.App.Views;

/// <summary>
/// Sidebar, note list and editor; on the Dashboard the list is hidden. Closing the window hides it, and the
/// app keeps running in the notification area so the global shortcuts still work.
/// </summary>
internal sealed class MainWindow : Window
{
    private readonly AppState _state;
    private readonly Grid _grid;
    private readonly NoteListView _list;
    private readonly ContentControl _detail = new();
    private readonly GridSplitter _listSplitter;

    public bool AllowClose { get; set; }

    public MainWindow(AppState state)
    {
        _state = state;
        Title = "Scattered Notes";
        Width = 1200;
        Height = 760;
        MinWidth = 720;
        MinHeight = 420;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Icon = new WindowIcon(Avalonia.Platform.AssetLoader.Open(new Uri("avares://ScatteredNotes/Assets/AppIcon.ico")));
        // Mica on Windows 11, plain background elsewhere
        TransparencyLevelHint = [WindowTransparencyLevel.Mica, WindowTransparencyLevel.None];

        var sidebar = new SidebarView(state);
        _list = new NoteListView(state);
        _grid = new Grid { ColumnDefinitions = new ColumnDefinitions("230,1,300,1,*") };
        Grid.SetColumn(sidebar, 0);
        Grid.SetColumn(_list, 2);
        Grid.SetColumn(_detail, 4);
        var sidebarSplitter = new GridSplitter { ResizeDirection = GridResizeDirection.Columns }.Themed(GridSplitter.BackgroundProperty, "CardBorder");
        Grid.SetColumn(sidebarSplitter, 1);
        _listSplitter = new GridSplitter { ResizeDirection = GridResizeDirection.Columns }.Themed(GridSplitter.BackgroundProperty, "CardBorder");
        Grid.SetColumn(_listSplitter, 3);
        _grid.Children.Add(sidebar);
        _grid.Children.Add(sidebarSplitter);
        _grid.Children.Add(_list);
        _grid.Children.Add(_listSplitter);
        _grid.Children.Add(_detail);
        Content = _grid;
        this.Themed(BackgroundProperty, "CardBackground");

        _state.SelectionChanged += ApplySelectionLayout;
        _state.SelectedNoteChanged += UpdateDetail;
        _state.Store.Changed += (_, _) => UpdateDetail();
        _state.Store.SaveFailed += async (_, error) =>
            await Dialogs.ShowMessageAsync(this, "Couldn't save the note",
                $"Your text is still in the editor and will be saved again with your next change.\n\n{error.Message}");

        KeyDown += OnKeyDown;
        Closing += (_, e) =>
        {
            if (AllowClose) return;
            // Hide rather than close so the window comes back as it was
            e.Cancel = true;
            FlushEditor();
            Hide();
        };
        ApplySelectionLayout();
    }

    /// <summary>Writes the open note's unsaved text, e.g. before quitting.</summary>
    public void FlushEditor() => (_detail.Content as EditorView)?.FlushPendingSave();

    public void ShowAndActivate()
    {
        Show();
        if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
        Activate();
    }

    private void ApplySelectionLayout()
    {
        var onDashboard = _state.Selection.Kind == SidebarKind.Dashboard;
        _list.IsVisible = !onDashboard;
        _listSplitter.IsVisible = !onDashboard;
        _grid.ColumnDefinitions[2].Width = onDashboard ? new GridLength(0) : new GridLength(300);
        _grid.ColumnDefinitions[3].Width = onDashboard ? new GridLength(0) : new GridLength(1);
        Title = WindowTitle();
        UpdateDetail();
    }

    private void UpdateDetail()
    {
        Title = WindowTitle();
        if (_state.Selection.Kind == SidebarKind.Dashboard)
        {
            if (_detail.Content is not DashboardView) _detail.Content = new DashboardView(_state);
            return;
        }
        if (_state.SelectedNote is { } note)
        {
            if (_detail.Content is not EditorView editor || editor.NoteId != note.Id) _detail.Content = new EditorView(_state, note);
            return;
        }
        if (_detail.Content is EditorView or DashboardView or null) _detail.Content = Placeholder();
    }

    private string WindowTitle() =>
        _state.Selection.Kind != SidebarKind.Dashboard && _state.SelectedNote is { } note
            ? $"{note.DisplayTitle} — {_state.Selection.Title}"
            : _state.Selection.Title;

    private Control Placeholder()
    {
        var stack = new StackPanel { Spacing = 12, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        stack.Children.Add(Ui.Icon(Symbol.Compose, 44, "WcagSecondaryText"));
        stack.Children.Add(Ui.Text("Select a note to view or edit", 18, brushKey: "WcagSecondaryText"));
        stack.Children.Add(Ui.Text($"Press {_state.Settings.QuickCaptureShortcut.DisplayString} anywhere to capture a quick note", 13, brushKey: "WcagSecondaryText"));
        foreach (var child in stack.Children) child.HorizontalAlignment = HorizontalAlignment.Center;
        return stack;
    }

    private void OnKeyDown(object? sender, KeyEventArgs e)
    {
        var ctrl = e.KeyModifiers.HasFlag(OperatingSystem.IsMacOS() ? KeyModifiers.Meta : KeyModifiers.Control);
        switch (e.Key)
        {
            case Key.Escape:
                // Esc goes back to the dashboard; on the dashboard it hides the window
                if (_state.Selection.Kind != SidebarKind.Dashboard)
                {
                    FlushEditor();
                    _state.Selection = SidebarSelection.Dashboard;
                }
                else
                {
                    Hide();
                }
                e.Handled = true;
                break;
            case Key.N when ctrl:
                _state.CreateNoteInCurrentSelection();
                e.Handled = true;
                break;
            case Key.K when ctrl:
                SearchPalette.Show(_state, this);
                e.Handled = true;
                break;
            case Key.F when ctrl && _state.Selection.Kind != SidebarKind.Dashboard:
                _list.FocusSearch();
                e.Handled = true;
                break;
            case Key.OemComma when ctrl:
                SettingsWindow.Show(_state, this);
                e.Handled = true;
                break;
        }
    }
}
