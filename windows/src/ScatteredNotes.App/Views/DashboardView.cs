using System.Globalization;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Threading;
using FluentIcons.Common;
using ScatteredNotes.Core.Agenda;
using ScatteredNotes.Core.Models;

namespace ScatteredNotes.App.Views;

/// <summary>Every to-do and dated line from all notes: overdue, today, the next 14 days, and open to-dos.</summary>
internal sealed class DashboardView : UserControl
{
    private readonly AppState _state;
    private readonly StackPanel _panel = new() { Spacing = 24, Margin = new Thickness(32, 28), MaxWidth = 760 };
    private readonly DispatcherTimer _midnight = new() { Interval = TimeSpan.FromMinutes(1) };
    private DateOnly _renderedDay;
    /// <summary>The list of everything ticked earlier starts folded away.</summary>
    private bool _completedExpanded;

    public DashboardView(AppState state)
    {
        _state = state;
        Content = new ScrollViewer { Content = _panel };
        _state.Store.Changed += OnChanged;
        // Roll "today" over at midnight while the window stays open
        _midnight.Tick += (_, _) =>
        {
            if (DateOnly.FromDateTime(DateTime.Now) != _renderedDay) Render();
        };
        AttachedToVisualTree += (_, _) => _midnight.Start();
        DetachedFromVisualTree += (_, _) =>
        {
            _midnight.Stop();
            _state.Store.Changed -= OnChanged;
        };
        Render();
    }

    private void OnChanged(object? sender, EventArgs e) => Render();

    private void Render()
    {
        var today = DateOnly.FromDateTime(DateTime.Now);
        _renderedDay = today;
        var notes = _state.Store.Notes;
        var byId = notes.ToDictionary(n => n.Id);
        var dashboard = Dashboard.Build(notes, _state.Store.AgendaItems(), today);
        _panel.Children.Clear();
        _panel.Children.Add(Header(dashboard));

        if (dashboard.IsEmpty) return;

        if (dashboard.Overdue.Count > 0)
            _panel.Children.Add(Section("Overdue", Symbol.ErrorCircle, "WcagOrange",
                dashboard.Overdue.Select(i => Row(i, byId, Dashboard.DayLabel(i.Date!.Value, today)))));

        var todayRows = dashboard.DueToday.Count == 0
            ? [new TextBlock { Text = "Nothing planned for today.", Margin = new Thickness(10, 8), Classes = { "WcagSecondaryText" } }]
            : dashboard.DueToday.Select(i => Row(i, byId, null));
        _panel.Children.Add(Section("Today", Symbol.WeatherSunny, "WcagBlue", todayRows));

        if (dashboard.Upcoming.Count > 0)
        {
            var rows = new List<Control>();
            foreach (var (day, items) in dashboard.Upcoming)
            {
                rows.Add(GroupLabel(Dashboard.DayLabel(day, today)));
                rows.AddRange(items.Select(i => Row(i, byId, null)));
            }
            _panel.Children.Add(Section($"Next {Dashboard.UpcomingDays} Days", Symbol.Calendar, "WcagPurple", rows));
        }

        if (dashboard.UndatedTodos.Count > 0)
        {
            var rows = new List<Control>();
            foreach (var (note, items) in dashboard.UndatedTodos)
            {
                var open = new Button { Classes = { "link" }, Margin = new Thickness(8, 10, 0, 2), Content = Ui.Row(6, Ui.Icon(Ui.SymbolFor(note.CategoryType.IconName()), 12, "WcagSecondaryText"), Ui.Text(note.DisplayTitle, 12, FontWeight.SemiBold, "WcagSecondaryText")) };
                ToolTip.SetTip(open, "Open note");
                open.Click += (_, _) => _state.OpenNote(note);
                rows.Add(open);
                rows.AddRange(items.Select(i => Row(i, byId, null, showNote: false)));
            }
            _panel.Children.Add(Section("To-do", Symbol.CheckboxChecked, "WcagGreen", rows));
        }

        if (dashboard.Completed.Count > 0) _panel.Children.Add(CompletedSection(dashboard, byId, today));
    }

    /// <summary>Everything ticked that the sections above do not show, folded away until asked for.</summary>
    private Control CompletedSection(Dashboard dashboard, Dictionary<Guid, Note> byId, DateOnly today)
    {
        var header = new Button
        {
            Classes = { "link" },
            HorizontalAlignment = HorizontalAlignment.Left,
            Content = Ui.Row(8,
                Ui.Icon(_completedExpanded ? Symbol.ChevronDown : Symbol.ChevronRight, 12, "WcagSecondaryText"),
                Ui.Icon(Symbol.CheckmarkCircle, 18, "WcagGreen", IconVariant.Filled),
                Ui.Text("Completed", 18, FontWeight.SemiBold),
                Ui.Text(dashboard.Completed.Count.ToString(CultureInfo.CurrentCulture), 13, brushKey: "WcagSecondaryText")),
        };
        ToolTip.SetTip(header, _completedExpanded ? "Hide completed items" : "Show completed items");
        Avalonia.Automation.AutomationProperties.SetName(header, $"Completed, {dashboard.Completed.Count}, {(_completedExpanded ? "expanded" : "collapsed")}");
        header.Click += (_, _) =>
        {
            _completedExpanded = !_completedExpanded;
            Render();
        };

        var section = new StackPanel { Spacing = 8 };
        section.Children.Add(header);
        if (_completedExpanded)
        {
            var rows = new List<Control>();
            string? label = null;
            foreach (var item in dashboard.Completed)
            {
                var group = item.DoneOn is { } day ? Dashboard.DayLabel(day, today) : "Earlier";
                if (group != label) rows.Add(GroupLabel(label = group));
                rows.Add(Row(item, byId, null));
            }
            section.Children.Add(Card(rows));
        }
        return section;
    }

    private Control Header(Dashboard dashboard)
    {
        var now = DateTime.Now;
        var stack = new StackPanel { Spacing = 12 };
        var dates = new StackPanel { Spacing = 0 };
        dates.Children.Add(Ui.Text(now.ToString("dddd", CultureInfo.CurrentCulture), 18, FontWeight.Medium, "WcagSecondaryText"));
        // Month and day in the order the user's region writes them, then the year
        dates.Children.Add(Ui.Text($"{now.ToString("M", CultureInfo.CurrentCulture)} {now.Year}", 32, FontWeight.Bold));
        stack.Children.Add(dates);

        // With nothing to show there is nothing to count
        if (dashboard.IsEmpty) return stack;

        var chips = new WrapPanel { ItemSpacing = 8, LineSpacing = 8 };
        chips.Children.Add(Chip(dashboard.Overdue.Count, "overdue", "WcagOrange"));
        chips.Children.Add(Chip(dashboard.DueTodayOpenCount, "today", "WcagBlue"));
        chips.Children.Add(Chip(dashboard.UpcomingCount, "upcoming", "WcagPurple"));
        chips.Children.Add(Chip(dashboard.OpenTodoCount, "open to-dos", "WcagGreen"));
        stack.Children.Add(chips);
        return stack;
    }

    private static Control Chip(int value, string label, string brush) =>
        new Border
        {
            Classes = { "badge" },
            CornerRadius = new CornerRadius(14),
            Padding = new Thickness(12, 5),
            Child = Ui.Row(5, Ui.Text(value.ToString(CultureInfo.CurrentCulture), 13, FontWeight.SemiBold, value > 0 ? brush : "WcagSecondaryText"), Ui.Text(label, 13, brushKey: "WcagSecondaryText")),
        };

    private static Border Card(IEnumerable<Control> rows)
    {
        var list = new StackPanel { Spacing = 0 };
        list.Children.AddRange(rows);
        return new Border
        {
            CornerRadius = new CornerRadius(12),
            BorderThickness = new Thickness(1),
            Padding = new Thickness(6),
            Child = list,
        }.Themed(Border.BackgroundProperty, "CardBackground").Themed(Border.BorderBrushProperty, "CardBorder");
    }

    private static Control Section(string title, Symbol symbol, string brush, IEnumerable<Control> rows)
    {
        var card = Card(rows);
        var section = new StackPanel { Spacing = 8 };
        section.Children.Add(Ui.Row(8, Ui.Icon(symbol, 18, brush, IconVariant.Filled), Ui.Text(title, 18, FontWeight.SemiBold)));
        section.Children.Add(card);
        return section;
    }

    private static Control GroupLabel(string text) =>
        new TextBlock { Text = text, FontSize = 12, FontWeight = FontWeight.SemiBold, Margin = new Thickness(10, 10, 0, 2), Classes = { "WcagSecondaryText" } };

    private Control Row(AgendaItem item, Dictionary<Guid, Note> notes, string? dateLabel, bool showNote = true) =>
        AgendaRow.Build(item,
            () => _state.Store.ToggleChecklistItem(item.NoteId, item.LineIndex),
            dateLabel,
            showNote ? notes.GetValueOrDefault(item.NoteId) : null,
            note => _state.OpenNote(note));
}
