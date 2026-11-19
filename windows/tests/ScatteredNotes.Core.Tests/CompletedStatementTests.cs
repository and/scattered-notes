using ScatteredNotes.Core.Agenda;
using ScatteredNotes.Core.Models;

namespace ScatteredNotes.Core.Tests;

/// <summary>Lines that say something was done on a day, such as "Created: 2026-11-19", show as completed.</summary>
public class CompletedStatementTests
{
    private static readonly DateOnly Day = new(2026, 11, 19);

    [Theory]
    [InlineData("Created: 2026-11-19", true)]
    [InlineData("Created 2026-11-19", true)]
    [InlineData("Deposited ₹10,000 into Dhan account today", true)]
    [InlineData("Paid rent today", true)]
    [InlineData("Built order tool on friday", true)]
    [InlineData("Fixed. Moving on", true)]
    [InlineData("Need to renew passport", false)]
    [InlineData("Speed up the build", false)]
    [InlineData("Red flags in the report", false)]
    [InlineData("Hundred things to do", false)]
    [InlineData("Created the doc?", false)]
    [InlineData("Create the doc", false)]
    [InlineData("Team dinner on friday", false)]
    [InlineData("2026-11-19: v1 built, backtested, and started in paper mode.", true)]
    [InlineData("Static IP registered with Dhan: 223.181.117.129. Locked until 2026-11-25.", true)]
    [InlineData("Report was sent to Sam on friday", true)]
    [InlineData("Car serviced on monday", true)]
    [InlineData("Meeting with shared team friday", false)]
    [InlineData("Needs to be signed by friday", false)]
    [InlineData("Paper trade every day from monday", false)]
    [InlineData("2026-11-25: dentist", false)]
    public void TellsAStatementOfSomethingDone(string text, bool done) =>
        Assert.Equal(done, AgendaExtractor.IsCompletedStatement(text));

    [Fact]
    public void ADatedStatementIsACompletedTask()
    {
        var note = new Note
        {
            Title = "Day Trading Plan",
            Content = "# Day Trading Plan\n\nCreated: 2026-11-19. Code: `tools/daytrader.py`.\n- Review fills 2026-11-19\nBuilt the dashboard\n",
            UpdatedAt = new DateTimeOffset(2026, 11, 19, 12, 0, 0, TimeSpan.FromHours(5.5)),
        };
        var items = AgendaExtractor.Items(note, TempStore.Kolkata);

        var created = Assert.Single(items, i => i.Text.StartsWith("Created", StringComparison.Ordinal));
        Assert.True(created.IsTodo);
        Assert.True(created.IsDone);
        Assert.Equal(Day, created.Date);
        Assert.Equal(Day, created.DoneOn);

        // A plan on the same day stays open, and a statement without a day stays off the dashboard
        Assert.False(Assert.Single(items, i => i.Text.StartsWith("Review", StringComparison.Ordinal)).IsDone);
        Assert.DoesNotContain(items, i => i.Text.StartsWith("Built", StringComparison.Ordinal));

        var dashboard = Dashboard.Build([note], items, Day);
        Assert.Equal(1, dashboard.DueTodayOpenCount);
        Assert.Equal(1, dashboard.OpenTodoCount);
    }

    [Fact]
    public void UntickingAStatementMakesItAnOpenTodo()
    {
        Assert.Equal("- [ ] Created: 2026-11-19", Checklist.ToggleLine(0, "Created: 2026-11-19"));
        Assert.Equal("- [ ] Created: 2026-11-19", Checklist.ToggleLine(0, "- Created: 2026-11-19"));
        // Then it toggles like any checklist line, and a plan is still ticked as before
        Assert.Equal("- [x] Created: 2026-11-19", Checklist.ToggleLine(0, "- [ ] Created: 2026-11-19"));
        Assert.Equal("- [x] call the bank tomorrow", Checklist.ToggleLine(0, "call the bank tomorrow"));
    }
}
