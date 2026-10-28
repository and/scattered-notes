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

    private readonly AppState _state;
    private readonly TextBox _title;
    private readonly TextBox _text;
    private readonly MarkdownView _preview;
    private readonly Grid _body;
    private readonly Border _agendaPane;
    private readonly StackPanel _agendaList;
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

        _pin = Ui.IconButton(Symbol.Pin, "Pin Note", () => _state.Store.TogglePin(CurrentNote()));
        var reveal = Ui.IconButton(Symbol.FolderOpen, OperatingSystem.IsWindows() ? "Show in File Explorer" : "Reveal in Finder", () =>
        {
            if (_note.FilePath is { } path) NoteMenus.RevealFile(path);
        });
        var delete = Ui.IconButton(Symbol.Delete, "Delete Note", () => _ = NoteMenus.ConfirmDeleteAsync(_state, _note, TopLevel.GetTopLevel(this) as Window));

        var toolbar = Ui.Row(4, _destination, new Border { Width = 6 }, modes, _agendaToggle, _pin, reveal, delete);
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
        _agendaPane = new Border
        {
            Width = 250,
            BorderThickness = new Thickness(1, 0, 0, 0),
            Child = new ScrollViewer { Content = _agendaList },
        }.Themed(Border.BorderBrushProperty, "CardBorder").Themed(Border.BackgroundProperty, "PaneBackground");

        _status = Ui.Row(16);
        var statusBar = new Border { Padding = new Thickness(16, 5), BorderThickness = new Thickness(0, 1, 0, 0), Child = _status }
            .Themed(Border.BorderBrushProperty, "CardBorder");

        var columns = new DockPanel();
        DockPanel.SetDock(_agendaPane, Dock.Right);
        columns.Children.Add(_agendaPane);
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
            var caret = _text.CaretIndex;
            LoadNote(current);
            _text.CaretIndex = Math.Min(caret, _text.Text?.Length ?? 0);
        }
        else
        {
            _note = current;
            RefreshChrome();
            RefreshAgenda();
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
