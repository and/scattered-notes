using System.Globalization;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Threading;
using FluentIcons.Common;
using ScatteredNotes.Core.Agenda;
using ScatteredNotes.Core.Models;
using ScatteredNotes.Core.Search;
using ScatteredNotes.Core.Text;

namespace ScatteredNotes.App.Views;

internal enum EditorMode
{
    Edit,
    Split,
    Preview,
}

/// <summary>
/// Title, toolbar, text, Markdown preview, agenda column and status bar for one note. Edits save 0.4 s after
/// typing stops, and pending edits are written straight away when the note changes or the app quits.
/// </summary>
internal sealed class EditorView : UserControl
{
    private static bool s_showAgenda = true;
    private static bool s_showLinks = true;

    private readonly AppState _state;
    private readonly TextBox _title;
    private readonly TextBox _text;
    private readonly MarkdownView _preview;
    private readonly Grid _body;
    private readonly Border _agendaPane;
    private readonly Border _linksPane;
    private readonly Border _rightPane;
    private readonly StackPanel _agendaList;
    private readonly StackPanel _linksList;
    private readonly ToggleButton _linksToggle;
    private readonly DropDownButton _destination;
    private readonly ToggleButton _agendaToggle;
    private readonly Button _pin;
    private readonly StackPanel _status;
    private readonly ToggleButton[] _modeButtons;
    private readonly DispatcherTimer _saveTimer;
    private EditorMode _mode = EditorMode.Edit;
    private Note _note;
    private bool _loading;

    public Guid NoteId => _note.Id;

    public EditorView(AppState state, Note note)
    {
        _state = state;
        _note = note;
        _saveTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(400) };
        _saveTimer.Tick += (_, _) => FlushPendingSave();

        _title = new TextBox
        {
            FontSize = 20,
            FontWeight = FontWeight.SemiBold,
            PlaceholderText = "Note Title",
            BorderThickness = new Thickness(0),
            Background = Brushes.Transparent,
            VerticalContentAlignment = VerticalAlignment.Center,
        };
        Avalonia.Automation.AutomationProperties.SetName(_title, "Note title");
        _title.TextChanged += (_, _) => ScheduleSave();
        _title.KeyDown += (_, e) =>
        {
            if (e.Key != Key.Enter && e.Key != Key.Down) return;
            FocusText(int.MaxValue);
            e.Handled = true;
        };

        var destinationMenu = new MenuFlyout();
        _destination = new DropDownButton { Padding = new Thickness(10, 4), Flyout = destinationMenu };
        destinationMenu.Opening += (_, _) =>
        {
            var flyout = destinationMenu;
            flyout.Items.Clear();
            foreach (var item in NoteMenus.MoveItems(_state, _note)) flyout.Items.Add(item);
        };
        ToolTip.SetTip(_destination, "Move to Inbox or a project");

        _modeButtons = [ModeButton(EditorMode.Edit, Symbol.Edit, "Edit"), ModeButton(EditorMode.Split, Symbol.SplitVertical, "Split"), ModeButton(EditorMode.Preview, Symbol.Eye, "Preview")];
        var modes = Ui.Row(0, _modeButtons);

        _agendaToggle = new ToggleButton { Classes = { "icon" }, Content = Ui.Icon(Symbol.PanelRight, 16), IsChecked = s_showAgenda, Background = Brushes.Transparent, BorderThickness = new Thickness(0) };
        ToolTip.SetTip(_agendaToggle, "Show or hide the agenda column");
        Avalonia.Automation.AutomationProperties.SetName(_agendaToggle, "Agenda column");
        _agendaToggle.IsCheckedChanged += (_, _) =>
        {
            s_showAgenda = _agendaToggle.IsChecked == true;
            RefreshAgenda();
        };

        _linksToggle = new ToggleButton { Classes = { "icon" }, Content = Ui.Icon(Symbol.Link, 16), IsChecked = s_showLinks, Background = Brushes.Transparent, BorderThickness = new Thickness(0) };
        ToolTip.SetTip(_linksToggle, "Show or hide the links column");
        Avalonia.Automation.AutomationProperties.SetName(_linksToggle, "Links column");
        _linksToggle.IsCheckedChanged += (_, _) =>
        {
            s_showLinks = _linksToggle.IsChecked == true;
            RefreshLinks();
        };

        _pin = Ui.IconButton(Symbol.Pin, "Pin Note", () => _state.Store.TogglePin(CurrentNote()));
        var reveal = Ui.IconButton(Symbol.FolderOpen, OperatingSystem.IsWindows() ? "Show in File Explorer" : "Reveal in Finder", () =>
        {
            if (_note.FilePath is { } path) NoteMenus.RevealFile(path);
        });
        var delete = Ui.IconButton(Symbol.Delete, "Delete Note", () => _ = NoteMenus.ConfirmDeleteAsync(_state, _note, TopLevel.GetTopLevel(this) as Window));

        var toolbar = Ui.Row(4, _destination, new Border { Width = 6 }, modes, _agendaToggle, _linksToggle, _pin, reveal, delete);
        var header = new DockPanel { Margin = new Thickness(16, 8, 12, 8) };
        DockPanel.SetDock(toolbar, Dock.Right);
        header.Children.Add(toolbar);
        header.Children.Add(_title);

        _text = new TextBox
        {
            AcceptsReturn = true,
            AcceptsTab = true,
            TextWrapping = TextWrapping.Wrap,
            BorderThickness = new Thickness(0),
            Background = Brushes.Transparent,
            Padding = new Thickness(20, 12),
            FontSize = state.Settings.EditorFontSize,
            LineHeight = state.Settings.EditorFontSize * 1.5,
            VerticalAlignment = VerticalAlignment.Stretch,
            VerticalContentAlignment = VerticalAlignment.Top,
        };
        _text.Resources["TextControlBackgroundFocused"] = Brushes.Transparent;
        _text.Resources["TextControlBackgroundPointerOver"] = Brushes.Transparent;
        _text.Resources["TextControlBorderThemeThicknessFocused"] = new Thickness(0);
        Avalonia.Automation.AutomationProperties.SetName(_text, "Note text");
        _text.TextChanged += (_, _) =>
        {
            ScheduleSave();
            RefreshStatus();
        };

        _preview = new MarkdownView(lineIndex =>
        {
            _text.Text = Checklist.ToggleLine(lineIndex, _text.Text ?? "");
            FlushPendingSave();
        });

        _body = new Grid();
        _agendaList = new StackPanel { Spacing = 2, Margin = new Thickness(12) };
        _agendaPane = new Border { MaxHeight = 280, Child = new ScrollViewer { Content = _agendaList } };
        _linksList = new StackPanel { Spacing = 2, Margin = new Thickness(12) };
        _linksPane = new Border { BorderThickness = new Thickness(0, 1, 0, 0), Child = new ScrollViewer { Content = _linksList } }
            .Themed(Border.BorderBrushProperty, "CardBorder");
        Grid.SetRow(_agendaPane, 0);
        Grid.SetRow(_linksPane, 1);
        _rightPane = new Border
        {
            Width = 250,
            BorderThickness = new Thickness(1, 0, 0, 0),
            Child = new Grid { RowDefinitions = new RowDefinitions("Auto,*"), Children = { _agendaPane, _linksPane } },
        }.Themed(Border.BorderBrushProperty, "CardBorder").Themed(Border.BackgroundProperty, "PaneBackground");

        _status = Ui.Row(16);
        var statusBar = new Border { Padding = new Thickness(16, 5), BorderThickness = new Thickness(0, 1, 0, 0), Child = _status }
            .Themed(Border.BorderBrushProperty, "CardBorder");

        var columns = new DockPanel();
        DockPanel.SetDock(_rightPane, Dock.Right);
        columns.Children.Add(_rightPane);
        columns.Children.Add(_body);

        var root = new DockPanel();
        var headerBorder = new Border { Child = header, BorderThickness = new Thickness(0, 0, 0, 1) }.Themed(Border.BorderBrushProperty, "CardBorder");
        DockPanel.SetDock(headerBorder, Dock.Top);
        DockPanel.SetDock(statusBar, Dock.Bottom);
        root.Children.Add(headerBorder);
        root.Children.Add(statusBar);
        root.Children.Add(columns);
        Content = root;

        LoadNote(note);
        ApplyMode();

        _state.Store.Changed += OnStoreChanged;
        _state.FocusEditorRequested += OnFocusRequested;
        _state.Settings.PropertyChanged += OnSettingsChanged;
        DetachedFromVisualTree += (_, _) =>
        {
            // Write pending edits instead of dropping them, e.g. when switching to the dashboard
            FlushPendingSave();
            _state.Store.Changed -= OnStoreChanged;
            _state.FocusEditorRequested -= OnFocusRequested;
            _state.Settings.PropertyChanged -= OnSettingsChanged;
        };
    }

    private ToggleButton ModeButton(EditorMode mode, Symbol symbol, string label)
    {
        var button = new ToggleButton { Content = Ui.Icon(symbol, 15), Padding = new Thickness(10, 5), CornerRadius = new CornerRadius(0) };
        ToolTip.SetTip(button, label);
        Avalonia.Automation.AutomationProperties.SetName(button, label);
        button.Click += (_, _) =>
        {
            _mode = mode;
            ApplyMode();
        };
        return button;
    }

    private void ApplyMode()
    {
        for (var i = 0; i < _modeButtons.Length; i++) _modeButtons[i].IsChecked = (int)_mode == i;
        _modeButtons[0].CornerRadius = new CornerRadius(6, 0, 0, 6);
        _modeButtons[2].CornerRadius = new CornerRadius(0, 6, 6, 0);

        _body.Children.Clear();
        _body.ColumnDefinitions.Clear();
        switch (_mode)
        {
            case EditorMode.Edit:
                _body.Children.Add(_text);
                break;
            case EditorMode.Preview:
                _preview.Render(_text.Text ?? "");
                _body.Children.Add(_preview);
                break;
            default:
                _body.ColumnDefinitions = new ColumnDefinitions("*,1,*");
                var divider = new Border().Themed(Border.BackgroundProperty, "CardBorder");
                Grid.SetColumn(divider, 1);
                Grid.SetColumn(_preview, 2);
                _preview.Render(_text.Text ?? "");
                _body.Children.Add(_text);
                _body.Children.Add(divider);
                _body.Children.Add(_preview);
                break;
        }
    }

    /// <summary>The note as saved, which may be newer than the one this editor was opened with.</summary>
    private Note CurrentNote() => _state.Store.Notes.FirstOrDefault(n => n.Id == _note.Id) ?? _note;

    private void LoadNote(Note note)
    {
        _loading = true;
        _note = note;
        _title.Text = note.Title;
        // Keep the note's own line endings: Enter in a Windows TextBox would otherwise insert "\r\n"
        _text.NewLine = LineText.DominantBreak(note.Content);
        _text.Text = note.Content;
        _loading = false;
        RefreshChrome();
        RefreshAgenda();
        RefreshLinks();
        RefreshStatus();
    }

    private void OnStoreChanged(object? sender, EventArgs e)
    {
        var current = _state.Store.Notes.FirstOrDefault(n => n.Id == _note.Id);
        if (current is null) return;
        var changedOnDisk = current.Content != _note.Content || current.Title != _note.Title;
        // Take changes made elsewhere (another app, sync) only when there are no unsaved edits here
        if (changedOnDisk && !_saveTimer.IsEnabled && (current.Content != _text.Text || current.Title != _title.Text))
        {
            // The app may have written date markers into the text being typed; the caret stays in the same words
            var caret = _text.CaretIndex;
            var before = _text.Text ?? "";
            LoadNote(current);
            _text.CaretIndex = Math.Min(AgendaExtractor.MappedOffset(caret, before, _text.Text ?? ""), _text.Text?.Length ?? 0);
        }
        else
        {
            _note = current;
            RefreshChrome();
            RefreshAgenda();
            RefreshLinks();
            RefreshStatus();
        }
        if (_mode != EditorMode.Edit) _preview.Render(_text.Text ?? "");
    }

    private void OnSettingsChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(Core.Storage.AppSettings.EditorFontSize)) return;
        _text.FontSize = _state.Settings.EditorFontSize;
        _text.LineHeight = _state.Settings.EditorFontSize * 1.5;
    }

    private void RefreshChrome()
    {
        var note = _note;
        var brush = Ui.DestinationBrush(note.CategoryType);
        var icon = note.CategoryType switch
        {
            CategoryType.Project => _state.Store.Projects.FirstOrDefault(p => p.Name == note.TargetName)?.IconName ?? "folder.fill",
            CategoryType.Area => "tray.fill",
            _ => "tray.fill",
        };
        _destination.Content = Ui.Row(6, Ui.Icon(Ui.SymbolFor(icon), 14, brush), Ui.Text(note.DestinationDisplay, 12, FontWeight.SemiBold, brush));
        Avalonia.Automation.AutomationProperties.SetName(_destination, $"Destination: {note.DestinationDisplay}");
        _pin.Content = Ui.Icon(note.IsPinned ? Symbol.Pin : Symbol.Pin, 16, note.IsPinned ? "WcagOrange" : "WcagSecondaryText", note.IsPinned ? IconVariant.Filled : IconVariant.Regular);
        ToolTip.SetTip(_pin, note.IsPinned ? "Unpin Note" : "Pin Note");
    }

    private void RefreshAgenda()
    {
        var items = _state.Store.AgendaItemsFor(CurrentNote());
        _agendaToggle.IsVisible = items.Count > 0;
        _agendaPane.IsVisible = items.Count > 0 && s_showAgenda;
        _rightPane.IsVisible = _agendaPane.IsVisible || s_showLinks;
        _agendaList.Children.Clear();
        _agendaList.Children.Add(new TextBlock { Text = "Agenda", FontSize = 15, FontWeight = FontWeight.SemiBold, Margin = new Thickness(4, 0, 0, 6) });
        var today = DateOnly.FromDateTime(DateTime.Now);
        foreach (var item in items)
        {
            var details = new List<string>();
            if (DueLabel(item.Date, today) is { } due) details.Add(due);
            details.Add($"Written {item.WrittenOn.ToString("d MMM", CultureInfo.CurrentCulture)}");
            _agendaList.Children.Add(AgendaRow.Build(item, () =>
            {
                // Edit the live text so the toggle is not overwritten by the next autosave
                _text.Text = Checklist.ToggleLine(item.LineIndex, _text.Text ?? "");
                FlushPendingSave();
            }, details: details));
        }
    }


    /// <summary>The links column: the notes this note mentions, the notes that mention it, and notes related to it.
    /// Reads the saved text, so a new mention shows up a moment after typing stops.</summary>
    private void RefreshLinks()
    {
        if (!s_showLinks)
        {
            _linksPane.IsVisible = false;
            _rightPane.IsVisible = _agendaPane.IsVisible;
            return;
        }

        var note = CurrentNote();
        var notes = _state.Store.Notes;
        var byId = new Dictionary<Guid, Note>();
        foreach (var n in notes) byId[n.Id] = n;
        var index = new NoteLinkIndex(notes);
        var linked = index.LinkedNotesFrom(note.Id);
        var backlinks = index.BacklinksTo(note.Id);
        var links = index.LinksFrom(note.Id);
        var explicitTargets = links.Where(l => l.IsExplicit && l.Target is not null).Select(l => l.Target!.Value).ToHashSet();
        // Notes mentioned only in plain text, never as [[Title]]: the ones that can be made a link
        var makeLink = links.Where(l => !l.IsExplicit && l.Target is { } t && !explicitTargets.Contains(t)
                                        && byId.TryGetValue(t, out var target) && NoteLinkIndex.ExplicitText(target.DisplayTitle) is not null)
            .GroupBy(l => l.Target!.Value).ToDictionary(g => g.Key, g => g.First());

        var unresolved = links.Where(l => l.Target is null).GroupBy(l => l.Text.ToLowerInvariant()).Select(g => g.First()).ToList();
        var similar = new RelatedIndex(notes).RelatedTo(note.Id, excluding: linked.Concat(backlinks).ToHashSet());
        // Nothing to list: hide the whole column
        var hasContent = linked.Count > 0 || backlinks.Count > 0 || unresolved.Count > 0 || similar.Count > 0;
        _linksPane.IsVisible = hasContent;
        _rightPane.IsVisible = _agendaPane.IsVisible || hasContent;
        if (!hasContent) return;

        _linksList.Children.Clear();
        _linksList.Children.Add(new TextBlock { Text = "Links", FontSize = 15, FontWeight = FontWeight.SemiBold, Margin = new Thickness(4, 0, 0, 6) });

        LinkSection("Links to", linked, byId, makeLink);
        if (unresolved.Count > 0)
        {
            _linksList.Children.Add(SectionTitle("No note with this title"));
            foreach (var link in unresolved)
                _linksList.Children.Add(new TextBlock { Text = $"[[{link.Text}]]", FontSize = 13, Margin = new Thickness(4, 2) }.Themed(TextBlock.ForegroundProperty, "WcagOrange"));
        }
        LinkSection("Linked from", backlinks, byId, null);

        // Notes already listed above are not repeated here
        if (similar.Count > 0)
        {
            _linksList.Children.Add(SectionTitle("Related"));
            foreach (var item in similar)
            {
                if (!byId.TryGetValue(item.Id, out var other)) continue;
                var why = item.SharedMarks.Count > 0 ? "Shares " + string.Join(", ", item.SharedMarks) : "Also about " + string.Join(", ", item.SharedWords);
                _linksList.Children.Add(LinkRow(other, why, null));
            }
        }
    }

    private static TextBlock SectionTitle(string title) =>
        Ui.Text(title, 12, FontWeight.SemiBold, "WcagSecondaryText").With(t => t.Margin = new Thickness(4, 12, 0, 2));

    private void LinkSection(string title, IReadOnlyList<Guid> ids, Dictionary<Guid, Note> byId, Dictionary<Guid, NoteLink>? makeLink)
    {
        if (ids.Count == 0) return;
        _linksList.Children.Add(SectionTitle(title));
        foreach (var id in ids)
        {
            if (!byId.TryGetValue(id, out var other)) continue;
            NoteLink? link = makeLink is not null && makeLink.TryGetValue(id, out var found) ? found : null;
            _linksList.Children.Add(LinkRow(other, null, link));
        }
    }

    private Control LinkRow(Note other, string? why, NoteLink? makeLink)
    {
        var text = new StackPanel { Spacing = 1, VerticalAlignment = VerticalAlignment.Center };
        text.Children.Add(Ui.Text(other.DisplayTitle, 13).With(t => t.TextTrimming = TextTrimming.CharacterEllipsis));
        if (other.CategoryType == CategoryType.Project && !string.IsNullOrEmpty(other.TargetName))
            text.Children.Add(Ui.Text(other.TargetName, 11, FontWeight.Medium, "WcagPurple").With(t => t.TextTrimming = TextTrimming.CharacterEllipsis));
        else if (other.CategoryType == CategoryType.Inbox)
            text.Children.Add(Ui.Text("Inbox", 11, FontWeight.Medium, "WcagOrange"));
        if (why is not null) text.Children.Add(Ui.Text(why, 11, brushKey: "WcagSecondaryText").With(t => t.TextTrimming = TextTrimming.CharacterEllipsis));
        var open = new Button
        {
            Classes = { "icon" },
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Left,
            Padding = new Thickness(4, 4),
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            Content = Ui.Row(6, Ui.Icon(Symbol.Document, 14, "WcagSecondaryText"), text),
        };
        ToolTip.SetTip(open, $"Open {other.DisplayTitle}");
        Avalonia.Automation.AutomationProperties.SetName(open, $"Open {other.DisplayTitle}");
        open.Click += (_, _) =>
        {
            FlushPendingSave();
            _state.OpenNote(other);
        };
        if (makeLink is null) return open;

        var make = Ui.IconButton(Symbol.LinkAdd, $"Make this a link: writes [[{other.DisplayTitle}]] in the note where it is mentioned", () => MakeLink(other, makeLink), "WcagBlue");
        Avalonia.Automation.AutomationProperties.SetName(make, "Make this a link");
        var row = new DockPanel();
        DockPanel.SetDock(make, Dock.Right);
        row.Children.Add(make);
        row.Children.Add(open);
        return row;
    }

    /// <summary>Writes <c>[[Title]]</c> over the mention, in the text as it is now.</summary>
    private void MakeLink(Note target, NoteLink link)
    {
        FlushPendingSave();
        var current = CurrentNote();
        // The saved text is what the link was found in, so its place in the text is right
        if (NoteLinkIndex.MakingExplicit(link, target.DisplayTitle, current.Content) is not { } changed) return;
        _text.Text = changed;
        FlushPendingSave();
    }

    private static string? DueLabel(DateOnly? date, DateOnly today)
    {
        if (date is not { } day) return null;
        var label = day.ToString("ddd, d MMM", CultureInfo.CurrentCulture);
        return (day.DayNumber - today.DayNumber) switch
        {
            0 => $"Today · {label}",
            1 => $"Tomorrow · {label}",
            < 0 => $"Overdue · {label}",
            _ => label,
        };
    }

    private void RefreshStatus()
    {
        _status.Children.Clear();
        if (Checklist.Stats(_text.Text ?? "") is { } stats)
        {
            var done = stats.Completed == stats.Total;
            _status.Children.Add(Ui.Row(4, Ui.Icon(Symbol.CheckboxChecked, 12, done ? "WcagGreen" : "WcagSecondaryText"),
                Ui.Text($"{stats.Completed}/{stats.Total} tasks", 12, brushKey: done ? "WcagGreen" : "WcagSecondaryText")));
        }
        _status.Children.Add(Ui.Text($"Last modified {_note.UpdatedAt.ToLocalTime():g}", 12, brushKey: "WcagSecondaryText"));
        foreach (var tag in _note.Tags)
            _status.Children.Add(new Border { Classes = { "badge" }, CornerRadius = new CornerRadius(4), Padding = new Thickness(6, 1), Child = Ui.Text("#" + tag, 11, brushKey: "WcagBlue") });
        var words = (_text.Text ?? "").Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length;
        _status.Children.Add(Ui.Text($"{words} words", 12, brushKey: "WcagSecondaryText"));
    }

    private void ScheduleSave()
    {
        if (_loading) return;
        _saveTimer.Stop();
        _saveTimer.Start();
        if (_mode != EditorMode.Edit) _preview.Render(_text.Text ?? "");
    }

    public void FlushPendingSave()
    {
        _saveTimer.Stop();
        var current = CurrentNote();
        var title = _title.Text ?? "";
        var content = _text.Text ?? "";
        if (title == current.Title && content == current.Content) return;

        var updated = current with { Title = title, Content = content, Tags = Mentions.Names(Mentions.Kind.Tag, content) };
        if (_state.Store.Save(updated)) _note = CurrentNote();
    }

    private void OnFocusRequested(EditorFocusRequest request)
    {
        if (request.NoteId != _note.Id) return;
        if (_mode == EditorMode.Preview)
        {
            _mode = EditorMode.Edit;
            ApplyMode();
        }
        var text = _text.Text ?? "";
        FocusText(CursorOffset(text, request.Terms));
    }

    /// <summary>Just after the first search term found in the text, else the end of the text.</summary>
    public static int CursorOffset(string text, IReadOnlyList<string> terms)
    {
        foreach (var term in terms.Where(t => t.Length > 0))
        {
            if (NoteSearch.Find(text, term) is { } hit) return hit.Index + hit.Length;
        }
        return text.Length;
    }

    private void FocusText(int offset)
    {
        // The text box may not be laid out yet when the note was just opened
        Dispatcher.UIThread.Post(() =>
        {
            _text.Focus();
            _text.CaretIndex = Math.Min(offset, _text.Text?.Length ?? 0);
            _text.ClearSelection();
        }, DispatcherPriority.Input);
    }
}
