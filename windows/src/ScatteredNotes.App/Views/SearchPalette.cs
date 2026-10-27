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
/// Search over all notes (Ctrl+K, or the global shortcut from any app). Every word must match somewhere
/// in a note; Enter opens the note with the cursor just after the first word found.
/// </summary>
internal sealed class SearchPalette : Window
{
    private static SearchPalette? s_open;

    private readonly AppState _state;
    private readonly TextBox _query;
    private readonly ListBox _results;
    private readonly TextBlock _hint;

    /// <param name="owner">The main window; when it is hidden (global shortcut from another app) the palette opens on its own.</param>
    public static void Show(AppState state, Window? owner)
    {
        if (s_open is not null)
        {
            s_open.Activate();
            s_open._query.Focus();
            return;
        }
        s_open = new SearchPalette(state);
        s_open.Closed += (_, _) => s_open = null;
        if (owner is { IsVisible: true })
        {
            s_open.Show(owner);
        }
        else
        {
            s_open.WindowStartupLocation = WindowStartupLocation.CenterScreen;
            s_open.Topmost = true;
            s_open.Show();
        }
        s_open.Activate();
    }

    private SearchPalette(AppState state)
    {
        _state = state;
        Title = "Search All Notes";
        Width = 640;
        Height = 460;
        CanResize = false;
        ShowInTaskbar = false;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        this.Themed(BackgroundProperty, "CardBackground");

        _query = new TextBox
        {
            PlaceholderText = "Search all notes",
            FontSize = 18,
            BorderThickness = new Thickness(0),
            Background = Brushes.Transparent,
            InnerLeftContent = Ui.Icon(Symbol.Search, 18, "WcagSecondaryText"),
            Padding = new Thickness(10, 12),
        };
        Avalonia.Automation.AutomationProperties.SetName(_query, "Search all notes");
        _query.TextChanged += (_, _) => Update();

        _results = new ListBox
        {
            Classes = { "wcag" },
            Background = Brushes.Transparent,
            ItemTemplate = new FuncDataTemplate<SearchResult>((result, _) => result is null ? new TextBlock() : ResultRow(result)),
        };
        _results.DoubleTapped += (_, _) => OpenSelected();

        _hint = new TextBlock { Margin = new Thickness(16), TextWrapping = TextWrapping.Wrap, Classes = { "WcagSecondaryText" } };

        var root = new DockPanel();
        var top = new Border { Child = _query, BorderThickness = new Thickness(0, 0, 0, 1), Padding = new Thickness(8, 4) }.Themed(Border.BorderBrushProperty, "CardBorder");
        DockPanel.SetDock(top, Dock.Top);
        root.Children.Add(top);
        var body = new Panel();
        body.Children.Add(_results);
        body.Children.Add(_hint);
        root.Children.Add(body);
        Content = root;

        // Tunnel so arrows and Enter reach the list while typing in the box
        AddHandler(KeyDownEvent, OnKeyDown, Avalonia.Interactivity.RoutingStrategies.Tunnel);
        Opened += (_, _) => _query.Focus();
        Deactivated += (_, _) => Close();
        Update();
    }

    private void Update()
    {
        var query = _query.Text ?? "";
        var results = NoteSearch.Search(query, _state.Store.Notes);
        _results.ItemsSource = results;
        if (results.Count > 0) _results.SelectedIndex = 0;
        _hint.IsVisible = results.Count == 0;
        _hint.Text = NoteSearch.Terms(query).Count == 0
            ? "Type words to find in titles, text, tags and projects. Start a word with # to match tags only."
            : "No notes match all of those words.";
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
                OpenSelected();
                e.Handled = true;
                break;
        }
    }

    private void OpenSelected()
    {
        if (_results.SelectedItem is not SearchResult result) return;
        var terms = NoteSearch.Terms(_query.Text ?? "");
        Close();
        _state.ShowMainWindow?.Invoke();
        _state.OpenNote(result.Note, terms);
    }

    private Control ResultRow(SearchResult result)
    {
        var terms = NoteSearch.Terms(_query.Text ?? "");
        var note = result.Note;
        var title = new TextBlock { FontSize = 14, FontWeight = FontWeight.SemiBold, TextTrimming = TextTrimming.CharacterEllipsis };
        Ui.AddHighlighted(title.Inlines!, note.DisplayTitle, terms);

        var header = new DockPanel();
        var destination = Ui.Text(note.DestinationDisplay, 11, FontWeight.SemiBold, Ui.DestinationBrush(note.CategoryType));
        DockPanel.SetDock(destination, Dock.Right);
        header.Children.Add(destination);
        header.Children.Add(title);

        var stack = new StackPanel { Spacing = 3, Margin = new Thickness(12, 8) };
        stack.Children.Add(header);
        if (result.Snippet is { } snippet)
        {
            var text = new TextBlock { FontSize = 12, TextTrimming = TextTrimming.CharacterEllipsis, Classes = { "WcagSecondaryText" } };
            Ui.AddHighlighted(text.Inlines!, snippet, terms);
            stack.Children.Add(text);
        }
        if (note.Tags.Count > 0) stack.Children.Add(Ui.Text(string.Join("  ", note.Tags.Select(t => "#" + t)), 11, brushKey: "WcagBlue"));
        Avalonia.Automation.AutomationProperties.SetName(stack, note.DisplayTitle);
        return stack;
    }
}
