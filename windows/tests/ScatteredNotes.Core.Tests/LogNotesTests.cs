using ScatteredNotes.Core.Agenda;
using ScatteredNotes.Core.Models;

namespace ScatteredNotes.Core.Tests;

public class LogNotesTests
{
    private static readonly DateTimeOffset Now = new(2026, 11, 19, 12, 40, 5, TimeSpan.FromHours(5.5));

    [Theory]
    [InlineData("Log - reading", true)]
    [InlineData("log — workouts", true)]
    [InlineData("Orders Log", true)]
    [InlineData("# Orders Log", true)]
    [InlineData("Workout log", true)]
    [InlineData("Log", true)]
    [InlineData("Backlog", false)]
    [InlineData("Changelog", false)]
    [InlineData("Logging ideas", false)]
    [InlineData("Log in to the bank", false)]
    [InlineData("Journal", false)]
    public void TellsALogByItsName(string title, bool isLog) => Assert.Equal(isLog, LogNotes.IsLogName(title));

    [Theory]
    [InlineData("2026-11-19", true)]
    [InlineData("2026/11/19", true)]
    [InlineData("19-11-2026", true)]
    [InlineData("2026-11-19 09:30", true)]
    [InlineData("2026-11-19 standup", false)]
    [InlineData("Plans for 2026-11-19", false)]
    [InlineData("2026", false)]
    public void ATitleThatIsOnlyADateMakesALog(string title, bool isLog) => Assert.Equal(isLog, LogNotes.IsLog(title, "some text"));

    [Fact]
    public void TheFirstLineCanMakeALogToo()
    {
        Assert.True(LogNotes.IsLog("Untitled", "\n# Orders Log\n\n- an entry"));
        Assert.False(LogNotes.IsLog("Plans", "# Plans\nLog - not first"));
    }

    [Fact]
    public void ANewLineCopiesTheStyleOfTheLastTimedLine()
    {
        var orders = "# Orders Log\n\nEvery order.\n\n- 2026-11-19 11:46 — PROPOSED BUY 1 TECHM\n- 2026-11-19 12:11 — PLACED BUY 1 TECHM\n";
        Assert.Equal("- 2026-11-19 12:40 — ", LogNotes.NewLinePrefix(orders, orders.Length, Now));

        var app = "Log - reading\n2026-11-05T13:32:00+05:30 started";
        Assert.Equal("2026-11-19T12:40:05+05:30 ", LogNotes.NewLinePrefix(app, app.Length, Now));

        var plain = "Workout log\n2026-11-18 07:10 ran 5k";
        Assert.Equal("2026-11-19 12:40 ", LogNotes.NewLinePrefix(plain, plain.Length, Now));
    }

    [Fact]
    public void WithoutATimedLineANewLineUsesTheAppsStyle()
    {
        Assert.Equal("2026-11-19T12:40:05+05:30 ", LogNotes.NewLinePrefix("Log - new", 9, Now));
    }

    [Fact]
    public void OnlyLinesBeforeTheCaretSetTheStyle()
    {
        var text = "Log - mixed\n2026-11-18T07:10:00+05:30 first\n- 2026-11-18 08:00 — second";
        var afterFirst = text.IndexOf("\n- ", StringComparison.Ordinal);
        Assert.Equal("2026-11-19T12:40:05+05:30 ", LogNotes.NewLinePrefix(text, afterFirst, Now));
    }

    [Fact]
    public void TheTimeIsTakenOffKeepingTheBullet()
    {
        Assert.Equal("- PLACED BUY 1 TECHM", LogNotes.WithoutStamp("- 2026-11-19 12:11 — PLACED BUY 1 TECHM"));
        Assert.Equal("ran 5k", LogNotes.WithoutStamp("2026-11-05T11:34:07+05:30 ran 5k"));
        Assert.Equal("call the bank 2026-11-20", LogNotes.WithoutStamp("call the bank 2026-11-20"));
    }

    [Fact]
    public void TheDashboardDoesNotReadLogTimesAsPlans()
    {
        var log = new Note
        {
            Title = "Orders Log",
            Content = "# Orders Log\n\n- 2026-11-19 11:46 — PROPOSED BUY 1 TECHM\n- 2026-11-19 12:00 — renew token tomorrow\n",
            UpdatedAt = Now,
        };
        var items = AgendaExtractor.Items(log, TempStore.Kolkata);
        // The order line has no date of its own once its time is taken off; a relative word still counts
        Assert.DoesNotContain(items, i => i.Text.Contains("TECHM"));
        Assert.Contains(items, i => i.Text.Contains("renew token") && i.Date == new DateOnly(2026, 11, 20));

        // The same lines in a note that isn't a log are dated as before
        var plain = log with { Title = "Orders", Content = log.Content.Replace("# Orders Log", "# Orders") };
        Assert.Contains(AgendaExtractor.Items(plain, TempStore.Kolkata), i => i.Text.Contains("TECHM") && i.Date == new DateOnly(2026, 11, 19));
    }

    [Fact]
    public void AnEntryThatReadsLikeAPlanIsNotATodoInALog()
    {
        var log = new Note
        {
            Title = "Orders Log",
            Content = "# Orders Log\n\n- 2026-11-19 11:46 — check the fills\n- 2026-11-19 12:00 — [ ] renew token\n- 2026-11-19 12:10 — send report tomorrow\n",
            UpdatedAt = Now,
        };
        var items = AgendaExtractor.Items(log, TempStore.Kolkata);
        Assert.DoesNotContain(items, i => i.Text.Contains("check the fills"));
        Assert.Contains(items, i => i.Text.Contains("send report") && i.Date == new DateOnly(2026, 11, 20));

        // In a note that isn't a log a plain "check the fills" is an open to-do
        var plain = log with { Title = "Orders", Content = "# Orders\n\n- check the fills\n" };
        Assert.Contains(AgendaExtractor.Items(plain, TempStore.Kolkata), i => i.Text.Contains("check the fills") && i.IsTodo);
    }

    [Fact]
    public void ADailyNoteDoesNotListItsOwnDateOrTimedEntries()
    {
        var daily = new Note
        {
            Title = "2026-11-19",
            Content = "2026-11-19\n\n- 2026-11-19 09:30 — standup\n- 2026-11-19 10:00 - Created the doc\n09:45 started work\nStatic IP registered\n",
            UpdatedAt = Now,
        };
        Assert.Empty(AgendaExtractor.Items(daily, TempStore.Kolkata));
    }
}
