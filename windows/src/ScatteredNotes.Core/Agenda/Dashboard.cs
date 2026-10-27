using System.Globalization;
using ScatteredNotes.Core.Models;

namespace ScatteredNotes.Core.Agenda;

/// <summary>What the dashboard shows, worked out from every note's agenda items. Same rules as the Mac app.</summary>
public sealed class Dashboard
{
    public const int UpcomingDays = 14;

    public required DateOnly Today { get; init; }
    /// <summary>Open to-dos dated before today, oldest first.</summary>
    public required List<AgendaItem> Overdue { get; init; }
    /// <summary>Everything dated today, open items first.</summary>
    public required List<AgendaItem> DueToday { get; init; }
    /// <summary>Open items in the next <see cref="UpcomingDays"/> days, grouped by day.</summary>
    public required List<(DateOnly Day, List<AgendaItem> Items)> Upcoming { get; init; }
    /// <summary>Open to-dos without a date, grouped by note, most recently updated note first.</summary>
    public required List<(Note Note, List<AgendaItem> Items)> UndatedTodos { get; init; }
    public required int OpenTodoCount { get; init; }

    public int DueTodayOpenCount => DueToday.Count(i => !i.IsDone);
    public int UpcomingCount => Upcoming.Sum(g => g.Items.Count);
    public bool IsEmpty => Overdue.Count == 0 && DueToday.Count == 0 && Upcoming.Count == 0 && UndatedTodos.Count == 0;

    public static Dashboard Build(IReadOnlyList<Note> notes, IReadOnlyList<AgendaItem> items, DateOnly today)
    {
        var notesById = notes.ToDictionary(n => n.Id);
        var end = today.AddDays(UpcomingDays + 1);
        return new Dashboard
        {
            Today = today,
            Overdue = items.Where(i => i.IsTodo && !i.IsDone && i.Date < today).OrderBy(i => i.Date).ToList(),
            DueToday = items.Where(i => i.Date == today).OrderBy(i => i.IsDone).ToList(),
            Upcoming = items
                .Where(i => i.Date is { } d && d > today && d < end && !i.IsDone)
                .GroupBy(i => i.Date!.Value)
                .OrderBy(g => g.Key)
                .Select(g => (g.Key, g.ToList()))
                .ToList(),
            UndatedTodos = items
                .Where(i => i.IsTodo && !i.IsDone && i.Date is null)
                .GroupBy(i => i.NoteId)
                .Where(g => notesById.ContainsKey(g.Key))
                .Select(g => (notesById[g.Key], g.OrderBy(i => i.LineIndex).ToList()))
                .OrderByDescending(g => g.Item1.UpdatedAt)
                .ToList(),
            OpenTodoCount = items.Count(i => i.IsTodo && !i.IsDone),
        };
    }

    /// <summary>"Tomorrow", "Yesterday", a weekday within the week, otherwise e.g. "Mon, 2 Nov".</summary>
    public static string DayLabel(DateOnly day, DateOnly today, CultureInfo? culture = null)
    {
        culture ??= CultureInfo.CurrentCulture;
        var days = day.DayNumber - today.DayNumber;
        return days switch
        {
            1 => "Tomorrow",
            -1 => "Yesterday",
            >= 2 and <= 6 => day.ToString("dddd", culture),
            _ => day.ToString("ddd, d MMM", culture),
        };
    }
}
