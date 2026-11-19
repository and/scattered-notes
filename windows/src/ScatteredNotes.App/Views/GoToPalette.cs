using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Templates;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using FluentIcons.Common;
using ScatteredNotes.Core.Models;
using ScatteredNotes.Core.Search;

namespace ScatteredNotes.App.Views;

/// <summary>
/// Go to a project, person or tag (Ctrl+O), as on the Mac: type part of a name, <c>#</c> for tags only or
/// <c>@</c> for people only, and Return opens that place with the keyboard in its notes.
/// </summary>
internal sealed class GoToPalette : Window
{
    private sealed record Target(SidebarSelection Selection, int? Count);

    private static GoToPalette? s_open;

    private readonly AppState _state;
    private readonly TextBox _query;
    private readonly ListBox _results;
    private readonly List<Target> _targets;
    private bool _chosen;

    public static void Show(AppState state, Window owner)
    {
        if (s_open is not null)
        {
            s_open.Activate();
            s_open._query.Focus();
            return;
        }
        s_open = new GoToPalette(state);
        s_open.Closed += (_, _) => s_open = null;
        s_open.Show(owner);
        s_open.Activate();
    }

    private GoToPalette(AppState state)
    {
        _state = state;
        _targets = AllTargets(state);
        Title = "Go to Project, Person or Tag";
        Width = 480;
        Height = 420;
        CanResize = false;
        ShowInTaskbar = false;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        this.Themed(BackgroundProperty, "CardBackground");

        _query = new TextBox
        {
            PlaceholderText = "Go to a project, @person or #tag",
            FontSize = 17,
            BorderThickness = new Thickness(0),
            Background = Brushes.Transparent,
            InnerLeftContent = Ui.Icon(Symbol.ArrowRight, 18, "WcagSecondaryText"),
            Padding = new Thickness(10, 12),
        };
        Avalonia.Automation.AutomationProperties.SetName(_query, "Go to");
        _query.TextChanged += (_, _) => Update();

        _results = new ListBox
        {
            Classes = { "wcag" },
            Background = Brushes.Transparent,
            ItemTemplate = new FuncDataTemplate<Target>((target, _) => target is null ? new TextBlock() : Row(target)),
        };
        _results.DoubleTapped += (_, _) => GoToSelected();

        var root = new DockPanel();
        var top = new Border { Child = _query, BorderThickness = new Thickness(0, 0, 0, 1), Padding = new Thickness(8, 4) }.Themed(Border.BorderBrushProperty, "CardBorder");
        DockPanel.SetDock(top, Dock.Top);
        root.Children.Add(top);
        root.Children.Add(_results);
        Content = root;

        // The main window gets the keyboard back as this one closes, so moving it into the list waits until then
        Closed += (_, _) =>
        {
            if (_chosen) _state.RequestFocus(FocusTarget.Content);
        };

        // Tunnel so arrows and Return reach the list while typing in the box
        AddHandler(KeyDownEvent, OnKeyDown, Avalonia.Interactivity.RoutingStrategies.Tunnel);
        Opened += (_, _) => _query.Focus();
        Deactivated += (_, _) => Close();
        Update();
    }

    /// <summary>Every place in the sidebar's order: Dashboard, All Notes, Inbox, projects, people, then tags.</summary>
    private static List<Target> AllTargets(AppState state)
    {
        var notes = state.Store.Notes;
        var targets = new List<Target>
        {
            new(SidebarSelection.Dashboard, null),
            new(SidebarSelection.All, notes.Count),
            new(SidebarSelection.Inbox, notes.Count(SidebarSelection.Inbox.Includes)),
        };
        foreach (var project in state.Store.Projects)
        {
            var selection = new SidebarSelection(SidebarKind.Project, project.Name);
            targets.Add(new Target(selection, notes.Count(selection.Includes)));
        }
        targets.AddRange(Named(notes.Select(state.Store.PeopleIn), SidebarKind.Person, notes));
        targets.AddRange(Named(notes.Select(n => n.Tags), SidebarKind.Tag, notes));
        return targets;
    }

    /// <summary>Names used across the notes, differing only in case counting once, spelled as first seen.</summary>
    private static IEnumerable<Target> Named(IEnumerable<IReadOnlyList<string>> lists, SidebarKind kind, IReadOnlyList<Note> notes)
    {
        var spelling = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var names in lists)
            foreach (var name in names)
                spelling.TryAdd(name, name);
        return spelling.Values
            .OrderBy(n => n, StringComparer.CurrentCultureIgnoreCase)
            .Select(name => new SidebarSelection(kind, name))
            .Select(selection => new Target(selection, notes.Count(selection.Includes)));
    }

    private void Update()
    {
        var matches = GoToMatching.Matching(_query.Text ?? "", _targets, t => t.Selection.Name ?? t.Selection.Title, t => t.Selection.Kind switch
        {
            SidebarKind.Person => GoToKind.Person,
            SidebarKind.Tag => GoToKind.Tag,
            _ => GoToKind.Place,
        });
        _results.ItemsSource = matches;
        if (matches.Count > 0) _results.SelectedIndex = 0;
    }

    private void OnKeyDown(object? sender, KeyEventArgs e)
    {
        switch (e.Key)
        {
            case Key.Escape:
                Close();
                e.Handled = true;
                break;
            case Key.Down or Key.Up when _results.ItemCount > 0:
                var step = e.Key == Key.Down ? 1 : -1;
                _results.SelectedIndex = Math.Clamp(_results.SelectedIndex + step, 0, _results.ItemCount - 1);
                if (_results.SelectedItem is { } item) _results.ScrollIntoView(item);
                e.Handled = true;
                break;
            case Key.Enter:
                GoToSelected();
                e.Handled = true;
                break;
        }
    }

    private void GoToSelected()
    {
        if (_results.SelectedItem is not Target target) return;
        _chosen = true;
        _state.ShowMainWindow?.Invoke();
        _state.SelectNote(null);
        _state.Selection = target.Selection;
        Close();
    }

    private static Control Row(Target target)
    {
        var selection = target.Selection;
        var (symbol, brush) = selection.Kind switch
        {
            SidebarKind.Dashboard => (Symbol.Board, "WcagBlue"),
            SidebarKind.All => (Symbol.Notebook, "WcagBlue"),
            SidebarKind.Inbox => (Symbol.MailInbox, "WcagOrange"),
            SidebarKind.Project => (Symbol.Folder, "WcagPurple"),
            SidebarKind.Person => (Symbol.Person, "WcagBlue"),
            _ => (Symbol.NumberSymbol, "WcagGreen"),
        };
        var row = new DockPanel { Margin = new Thickness(12, 7) };
        if (target.Count is { } count)
        {
            var countText = Ui.Text(count.ToString(System.Globalization.CultureInfo.CurrentCulture), 12, classes: "secondary");
            DockPanel.SetDock(countText, Dock.Right);
            row.Children.Add(countText);
        }
        var icon = Ui.Icon(symbol, 16, brush);
        icon.Margin = new Thickness(0, 0, 10, 0);
        DockPanel.SetDock(icon, Dock.Left);
        row.Children.Add(icon);
        row.Children.Add(new TextBlock { Text = selection.Title, FontSize = 14, VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis });
        Avalonia.Automation.AutomationProperties.SetName(row, selection.Title);
        return row;
    }
}
