using ScatteredNotes.Core.Agenda;
using ScatteredNotes.Core.Models;

namespace ScatteredNotes.Core.Tests;

public class QuickCaptureAndDashboardTests
{
    private static readonly ProjectArea[] Projects = [new("Mobile App", CategoryType.Project), new("Website", CategoryType.Project)];
    private static readonly ProjectArea[] Areas = [new("Health", CategoryType.Area)];

    [Fact]
    public void DetectsDestinationFromInlineTags()
    {
        Assert.Equal(new Destination(CategoryType.Project, "Mobile App"), QuickCapture.DetectDestination("fix crash +MobileApp", Projects, Areas));
        Assert.Equal(new Destination(CategoryType.Area, "Health"), QuickCapture.DetectDestination("jog #health", Projects, Areas));
        Assert.Equal(new Destination(CategoryType.Area, "Health"), QuickCapture.DetectDestination("jog [[health]]", Projects, Areas));
        Assert.Equal(new Destination(CategoryType.Project, "BrandRedesign"), QuickCapture.DetectDestination("logos @brandRedesign", Projects, Areas));
        Assert.Equal(new Destination(CategoryType.Project, "New thing"), QuickCapture.DetectDestination("see [[New thing]]", Projects, Areas));
        Assert.Null(QuickCapture.DetectDestination("just #groceries", Projects, Areas));
        Assert.Null(QuickCapture.DetectDestination("mail a@b.c about it", Projects, Areas));
    }

    [Fact]
    public void ContentDropsTheDestinationTagAndKeepsOtherTags()
    {
        var destination = new Destination(CategoryType.Project, "Website");
        const string text = "  Hero copy +Website #urgent #website  ";
        Assert.Equal("Hero copy #urgent #website", QuickCapture.Content(text, destination));
        Assert.Equal(["urgent"], QuickCapture.Tags(text, destination.Name));
        Assert.Equal("Website", QuickCapture.Content("+Website", destination));
    }

    [Fact]
    public void DashboardGroupsItemsLikeTheMacApp()
    {
        var today = new DateOnly(2026, 10, 27);
        var id = Guid.NewGuid();
        AgendaItem Item(int line, DateOnly? date, bool todo = true, bool done = false) => new(id, line, $"line {line}", todo, done, date, today);
        var note = new Note { Id = id, Title = "n" };
        var items = new[]
        {
            Item(0, today.AddDays(-2)),
            Item(1, today.AddDays(-1), done: true),
            Item(2, today, done: true),
            Item(3, today, todo: false),
            Item(4, today.AddDays(1)),
            Item(5, today.AddDays(1), todo: false),
            Item(6, today.AddDays(14)),
            Item(7, today.AddDays(15)),
            Item(8, null),
            Item(9, null, done: true),
        };

        var dashboard = Dashboard.Build([note], items, today);

        Assert.Equal([0], dashboard.Overdue.Select(i => i.LineIndex));
        Assert.Equal([3, 2], dashboard.DueToday.Select(i => i.LineIndex));
        Assert.Equal(1, dashboard.DueTodayOpenCount);
        Assert.Equal([today.AddDays(1), today.AddDays(14)], dashboard.Upcoming.Select(g => g.Day));
        Assert.Equal(3, dashboard.UpcomingCount);
        Assert.Equal([8], dashboard.UndatedTodos.Single().Items.Select(i => i.LineIndex));
        Assert.Equal(5, dashboard.OpenTodoCount);
    }

    [Fact]
    public void DayLabels()
    {
        var today = new DateOnly(2026, 10, 27);
        var culture = System.Globalization.CultureInfo.GetCultureInfo("en-GB");
        Assert.Equal("Tomorrow", Dashboard.DayLabel(today.AddDays(1), today, culture));
        Assert.Equal("Yesterday", Dashboard.DayLabel(today.AddDays(-1), today, culture));
        Assert.Equal("Friday", Dashboard.DayLabel(new DateOnly(2026, 10, 30), today, culture));
        Assert.Equal("Monday", Dashboard.DayLabel(new DateOnly(2026, 11, 2), today, culture));
        Assert.Equal("Tue, 3 Nov", Dashboard.DayLabel(new DateOnly(2026, 11, 3), today, culture));
    }
}
