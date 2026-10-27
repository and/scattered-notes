using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Templates;
using Avalonia.Layout;
using Avalonia.Media;
using FluentIcons.Common;
using ScatteredNotes.Core.Models;

namespace ScatteredNotes.App.Views;

/// <summary>Dashboard, All Notes, Inbox, then the projects and areas, like the Mac sidebar.</summary>
internal sealed class SidebarView : UserControl
{
    private readonly AppState _state;
    private readonly ListBox _main;
    private readonly ListBox _projects;
    private readonly ListBox _areas;
    private bool _syncing;

    public SidebarView(AppState state)
    {
        _state = state;
        _main = MakeList();
        _projects = MakeList();
        _areas = MakeList();

        var panel = new StackPanel { Spacing = 2, Margin = new Thickness(0, 8) };
        panel.Children.Add(_main);
        panel.Children.Add(Header("Projects", () => AddFolderAsync(CategoryType.Project)));
        panel.Children.Add(_projects);
        panel.Children.Add(Header("Areas", () => AddFolderAsync(CategoryType.Area)));
        panel.Children.Add(_areas);

        var settings = new Button
        {
            Content = Ui.Row(8, Ui.Icon(Symbol.Settings, 16), Ui.Text("Settings", 13)),
            Classes = { "icon" },
            Margin = new Thickness(8),
            HorizontalAlignment = HorizontalAlignment.Stretch,
        };
        settings.Click += (_, _) => SettingsWindow.Show(_state, TopLevel.GetTopLevel(this) as Window);

        var root = new DockPanel();
        DockPanel.SetDock(settings, Dock.Bottom);
        root.Children.Add(settings);
        root.Children.Add(new ScrollViewer { Content = panel });
        Content = root;
        this.Themed(BackgroundProperty, "PaneBackground");

        _state.Store.Changed += (_, _) => Refresh();
        _state.SelectionChanged += SyncSelection;
        Refresh();
    }

    private ListBox MakeList()
    {
        var list = new ListBox
        {
            Classes = { "wcag" },
            Background = Brushes.Transparent,
            ItemTemplate = new FuncDataTemplate<SidebarSelection>((item, _) => ItemView(item)),
        };
        list.SelectionChanged += (_, _) =>
        {
            if (_syncing || list.SelectedItem is not SidebarSelection selection) return;
            _state.Selection = selection;
        };
        list.ContextRequested += (_, e) =>
        {
            if (list == _main || (e.Source as Control)?.DataContext is not SidebarSelection item) return;
            var delete = new MenuItem { Header = $"Delete {item.Name}…", Icon = Ui.Icon(Symbol.Delete) };
            delete.Click += async (_, _) => await DeleteFolderAsync(item);
            new ContextMenu { Items = { delete } }.Open(e.Source as Control);
            e.Handled = true;
        };
        return list;
    }

    private Control ItemView(SidebarSelection? item)
    {
        if (item is null) return new TextBlock();
        var (symbol, brush) = item.Kind switch
        {
            SidebarKind.Dashboard => (Symbol.Board, "WcagBlue"),
            SidebarKind.All => (Symbol.Notebook, "WcagBlue"),
            SidebarKind.Inbox => (Symbol.MailInbox, "WcagOrange"),
            SidebarKind.Project => (Ui.SymbolFor(FolderIcon(_state.Store.Projects, item.Name)), "WcagPurple"),
            _ => (Ui.SymbolFor(FolderIcon(_state.Store.Areas, item.Name)), "WcagGreen"),
        };
        var count = item.Kind == SidebarKind.Dashboard ? "" : _state.Store.Notes.Count(item.Includes).ToString();
        var row = new DockPanel { Margin = new Thickness(10, 7) };
        var countText = Ui.Text(count, 12, classes: "secondary");
        DockPanel.SetDock(countText, Dock.Right);
        row.Children.Add(countText);
        var icon = Ui.Icon(symbol, 16, brush);
        icon.Margin = new Thickness(0, 0, 10, 0);
        DockPanel.SetDock(icon, Dock.Left);
        countText.Margin = new Thickness(8, 0, 0, 0);
        row.Children.Add(icon);
        row.Children.Add(Ui.Text(item.Title, 13));
        Avalonia.Automation.AutomationProperties.SetName(row, item.Title);
        return row;
    }

    private static string FolderIcon(IReadOnlyList<ProjectArea> folders, string? name) =>
        folders.FirstOrDefault(f => f.Name == name)?.IconName ?? "folder.fill";

    private static Control Header(string title, Func<Task> onAdd)
    {
        var add = Ui.IconButton(Symbol.Add, $"New {title.TrimEnd('s')}", () => _ = onAdd());
        var header = new DockPanel { Margin = new Thickness(16, 14, 8, 2) };
        DockPanel.SetDock(add, Dock.Right);
        header.Children.Add(add);
        header.Children.Add(new TextBlock { Text = title.ToUpperInvariant(), FontSize = 11, FontWeight = FontWeight.SemiBold, VerticalAlignment = VerticalAlignment.Center, Classes = { "secondary" } });
        return header;
    }

    private void Refresh()
    {
        _syncing = true;
        _main.ItemsSource = new[] { SidebarSelection.Dashboard, SidebarSelection.All, SidebarSelection.Inbox };
        _projects.ItemsSource = _state.Store.Projects.Select(p => new SidebarSelection(SidebarKind.Project, p.Name)).ToList();
        _areas.ItemsSource = _state.Store.Areas.Select(a => new SidebarSelection(SidebarKind.Area, a.Name)).ToList();
        _syncing = false;
        // A project that was deleted elsewhere can no longer be selected
        var current = _state.Selection;
        if (current.Kind == SidebarKind.Project && !_state.Store.Projects.Any(p => p.Name == current.Name) ||
            current.Kind == SidebarKind.Area && !_state.Store.Areas.Any(a => a.Name == current.Name))
        {
            _state.Selection = SidebarSelection.All;
        }
        SyncSelection();
    }

    private void SyncSelection()
    {
        _syncing = true;
        var selection = _state.Selection;
        foreach (var list in new[] { _main, _projects, _areas })
            list.SelectedItem = list.ItemsSource?.Cast<SidebarSelection>().FirstOrDefault(i => i == selection);
        _syncing = false;
    }

    private async Task AddFolderAsync(CategoryType type)
    {
        if (TopLevel.GetTopLevel(this) is not Window window) return;
        var kind = type == CategoryType.Project ? "Project" : "Area";
        if (await Dialogs.NewFolderAsync(window, kind) is not { } result) return;
        var name = type == CategoryType.Project
            ? _state.Store.CreateProject(result.Name, result.Icon)
            : _state.Store.CreateArea(result.Name, result.Icon);
        if (name is not null) _state.Selection = new SidebarSelection(type == CategoryType.Project ? SidebarKind.Project : SidebarKind.Area, name);
    }

    private async Task DeleteFolderAsync(SidebarSelection item)
    {
        if (TopLevel.GetTopLevel(this) is not Window window || item.Name is null) return;
        var kind = item.Kind == SidebarKind.Project ? "Project" : "Area";
        var notes = _state.Store.Notes.Count(item.Includes);
        var message = notes == 0
            ? $"\"{item.Name}\" will be removed."
            : $"\"{item.Name}\" and its {notes} note{(notes == 1 ? "" : "s")} will be deleted from disk.";
        if (!await Dialogs.ConfirmAsync(window, $"Delete {kind}?", message, "Delete")) return;
        if (item.Kind == SidebarKind.Project) _state.Store.DeleteProject(item.Name);
        else _state.Store.DeleteArea(item.Name);
    }
}
