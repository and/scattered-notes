using ScatteredNotes.Core.Agenda;
using ScatteredNotes.Core.Models;

namespace ScatteredNotes.Core.Tests;

/// <summary>Ported from the Mac AgendaTests; the reference day is Monday 26 Oct 2026 in Kolkata.</summary>
public class AgendaTests
{
    private static readonly TimeZoneInfo Zone = TempStore.Kolkata;
    private static readonly DateTimeOffset Monday = new(2026, 10, 26, 9, 0, 0, TimeSpan.FromHours(5.5));

    private static DateOnly Day(int month, int day, int year = 2026) => new(year, month, day);

    private static DateOnly? Parse(string line) => AgendaExtractor.ParseDate(line, Day(10, 26));

    [Fact]
    public void ParsesSupportedDateFormats()
    {
        Assert.Equal(Day(11, 2), Parse("Send invoice @2026-11-02"));
        Assert.Equal(Day(10, 27), Parse("Call the bank tomorrow"));
        Assert.Equal(Day(10, 26), Parse("Finish draft today"));
        Assert.Equal(Day(10, 30), Parse("Team dinner on Friday"));
        Assert.Equal(Day(11, 6), Parse("Review next friday"));
        Assert.Equal(Day(10, 26), Parse("Gym on monday"));
        Assert.Equal(Day(11, 2), Parse("Next week, plan to buy spare parts"));
        Assert.Equal(Day(10, 30), Parse("Dentist Oct 30th at 4pm"));
        Assert.Equal(Day(11, 3), Parse("Flight on 3 November"));
        Assert.Equal(Day(1, 15, 2027), Parse("Taxes due jan 15"));
    }

    [Fact]
    public void IgnoresLinesWithoutDates()
    {
        Assert.Null(Parse("Buy milk"));
        Assert.Null(Parse("Read chapter 30"));
        Assert.Null(Parse("Sunny weather"));
        Assert.Null(Parse("Feb 30 is not a day"));
        Assert.Null(Parse("Build 0000-00-00 and 2026-13-45"));
    }

    [Fact]
    public void ExtractsTodosAndDatedLines()
    {
        var note = new Note
        {
            Title = "Week",
            Content = "# Plans for tomorrow\n- [ ] Renew passport\n- [x] Pay rent\nLunch with Sam tomorrow\nJust a thought\n- [ ] Send invoice @2026-11-02",
            CreatedAt = Monday,
        };
        var items = AgendaExtractor.Items(note, timeZone: Zone);

        Assert.Equal(["Renew passport", "Pay rent", "Lunch with Sam tomorrow", "Send invoice"], items.Select(i => i.Text));
        Assert.Equal([1, 2, 3, 5], items.Select(i => i.LineIndex));
        Assert.Equal([true, true, false, true], items.Select(i => i.IsTodo));
        Assert.Equal([false, true, false, false], items.Select(i => i.IsDone));
        Assert.Equal([null, null, Day(10, 27), Day(11, 2)], items.Select(i => i.Date));
    }

    [Theory]
    [InlineData("fix the right side of the mac screen getting unresponsive.")]
    [InlineData("- Call the bank")]
    [InlineData("Need to renew passport")]
    [InlineData("I have to pay rent")]
    [InlineData("I’ll email Sam the slides")]
    [InlineData("we're going to repaint the hall")]
    [InlineData("Don't forget the charger")]
    [InlineData("TODO: back up photos")]
    public void PlainLinesThatReadAsPlansAreTodos(string line) =>
        Assert.True(AgendaExtractor.IsPlannedAction(AgendaExtractor.DisplayText(line)));

    [Theory]
    [InlineData("Just a thought")]
    [InlineData("Lunch with Sam")]
    [InlineData("Fixed the login bug")]
    [InlineData("Should we move?")]
    [InlineData("Read later:")]
    [InlineData("Fixes")]
    public void OtherPlainLinesAreNotTodos(string line) => Assert.False(AgendaExtractor.IsPlannedAction(line));

    [Fact]
    public void ExtractsPlannedLinesAsTodos()
    {
        var note = new Note { Title = "Mixed", Content = "Sunny today\nfix the screen bug\nWill was here", CreatedAt = Monday };
        var items = AgendaExtractor.Items(note, timeZone: Zone);

        Assert.Equal(["Sunny today", "fix the screen bug"], items.Select(i => i.Text));
        Assert.Equal([false, true], items.Select(i => i.IsTodo));
    }

    [Fact]
    public void CrlfLinesKeepTheSameIndexes()
    {
        var note = new Note { Content = "intro\r\n- [ ] one\r\n\r\ntwo tomorrow", CreatedAt = Monday };
        var items = AgendaExtractor.Items(note, timeZone: Zone);
        Assert.Equal([1, 3], items.Select(i => i.LineIndex));
    }

    [Fact]
    public void ToggleChecklistItemUpdatesNoteOnDisk()
    {
        using var temp = new TempStore();
        var note = temp.Store.CreateNote("Errands", "Intro\n- [ ] Buy stamps\n- [ ] Post letter");

        temp.Store.ToggleChecklistItem(note.Id, 2);

        var saved = File.ReadAllText(temp.Store.Notes[0].FilePath!);
        Assert.EndsWith("Intro\n- [ ] Buy stamps\n- [x] Post letter", saved);
        Assert.Equal(["Post letter"], temp.Store.AgendaItems().Where(i => i.IsDone).Select(i => i.Text));
    }

    [Fact]
    public void ParsesDayAfterAndIntervals()
    {
        Assert.Equal(Day(10, 28), Parse("Party the day after tomorrow"));
        Assert.Equal(Day(10, 27), Parse("Laundry the day after"));
        Assert.Equal(Day(10, 29), Parse("Renew in 3 days"));
        Assert.Equal(Day(11, 9), Parse("Review in 2 weeks"));

        var note = new Note { Content = "buy tomatoes today\n\nalso do laundry the day after.", CreatedAt = Monday };
        Assert.Equal([Day(10, 26), Day(10, 27)], AgendaExtractor.Items(note, timeZone: Zone).Select(i => i.Date));
    }

    [Fact]
    public void RelativeWordsResolveFromLineAnchorNotCreationDate()
    {
        var note = new Note { Content = "Old plan tomorrow\nCall bank tomorrow", CreatedAt = Monday };
        var friday = new DateTimeOffset(2026, 10, 30, 9, 0, 0, TimeSpan.FromHours(5.5));
        var anchors = new Dictionary<string, DateTimeOffset> { [AgendaExtractor.LogKey("Call bank tomorrow")] = friday };

        var items = AgendaExtractor.Items(note, anchors, Zone);

        Assert.Equal([Day(10, 27), Day(10, 31)], items.Select(i => i.Date));
        Assert.Equal([Day(10, 26), Day(10, 30)], items.Select(i => i.WrittenOn));
    }

    [Fact]
    public void AgendaLogKeepsFirstSeenAndDropsRemovedLines()
    {
        var log = new AgendaLog();
        var id = Guid.NewGuid();
        var later = Monday.AddDays(4);

        Assert.True(log.Update(id, [("a tomorrow", "A tomorrow")], Monday));
        Assert.False(log.Update(id, [("a tomorrow", "A tomorrow")], later));
        Assert.True(log.Update(id, [("a tomorrow", "A tomorrow"), ("b today", "B today")], later));
        Assert.Equal(new Dictionary<string, DateTimeOffset> { ["a tomorrow"] = Monday, ["b today"] = later }, log.Anchors(id));
        Assert.True(log.Update(id, [("b today", "B today")], later));
        Assert.Equal(["b today"], log.Anchors(id).Keys);
    }

    [Fact]
    public void AgendaLogFileMatchesMacFormat()
    {
        var log = new AgendaLog();
        var id = Guid.Parse("02eff95a-ff15-4719-990a-0a091abe49f6");
        log.Update(id, [("call bank tomorrow", "Call bank tomorrow")], new DateTimeOffset(2026, 10, 27, 6, 55, 0, 123, TimeSpan.Zero));
        var json = System.Text.Encoding.UTF8.GetString(log.Encode());

        Assert.Contains("\"02EFF95A-FF15-4719-990A-0A091ABE49F6\"", json);
        Assert.Contains("\"firstSeen\": \"2026-10-27T06:55:00Z\"", json);

        // As the Mac app writes it, with Swift's pretty printing
        const string mac = """
        {
          "notes" : {
            "02EFF95A-FF15-4719-990A-0A091ABE49F6" : {
              "call bank tomorrow" : {
                "firstSeen" : "2026-10-27T06:55:00Z",
                "line" : "Call bank tomorrow"
              }
            }
          }
        }
        """;
        var decoded = AgendaLog.Decode(System.Text.Encoding.UTF8.GetBytes(mac));
        Assert.NotNull(decoded);
        Assert.Equal(new DateTimeOffset(2026, 10, 27, 6, 55, 0, TimeSpan.Zero), decoded.Anchors(id)["call bank tomorrow"]);
    }

    [Fact]
    public void MergeKeepsEarliestFirstSeen()
    {
        var id = Guid.NewGuid();
        var mine = new AgendaLog();
        mine.Update(id, [("a", "A"), ("b", "B")], Monday.AddDays(2));
        var conflict = new AgendaLog();
        conflict.Update(id, [("a", "A")], Monday);

        mine.Merge(conflict);

        Assert.Equal(Monday, mine.Anchors(id)["a"]);
        Assert.Equal(Monday.AddDays(2), mine.Anchors(id)["b"]);
    }

    [Fact]
    public void EditingNoteLaterDoesNotMoveEarlierRelativeLines()
    {
        using var temp = new TempStore();
        var note = temp.Store.CreateNote("Errands", "Buy tomatoes today");
        var firstDay = temp.Store.AgendaItemsFor(note)[0].Date;

        temp.Store.Save(note with { Content = note.Content + "\nCall bank tomorrow" });

        var items = temp.Store.AgendaItemsFor(temp.Store.Notes[0]);
        Assert.Equal(2, items.Count);
        Assert.Equal(firstDay, items[0].Date);
        Assert.True(File.Exists(temp.Store.AgendaLogPath));
    }

    [Fact]
    public void TogglingPlainLineMakesItACheckedItemAndBack()
    {
        const string content = "Intro\n  call bank tomorrow\n* buy milk\n# Heading\n\nlast";
        var first = Checklist.ToggleLine(1, content);
        Assert.Equal("Intro\n  - [x] call bank tomorrow\n* buy milk\n# Heading\n\nlast", first);
        Assert.Equal("Intro\n  - [ ] call bank tomorrow\n* buy milk\n# Heading\n\nlast", Checklist.ToggleLine(1, first));
        Assert.Equal("Intro\n  call bank tomorrow\n- [x] buy milk\n# Heading\n\nlast", Checklist.ToggleLine(2, content));
        Assert.Equal(content, Checklist.ToggleLine(3, content)); // headings are not completable
        Assert.Equal(content, Checklist.ToggleLine(4, content)); // blank lines are not completable
    }

    [Fact]
    public void TogglingKeepsWindowsLineEndings()
    {
        Assert.Equal("a\r\n- [x] b\r\nc", Checklist.ToggleLine(1, "a\r\n- [ ] b\r\nc"));
    }

    [Fact]
    public void CompletingPlainDatedLineFromDashboardKeepsItsDate()
    {
        using var temp = new TempStore();
        var note = temp.Store.CreateNote("Plans", "buy tomatoes today\nhiking next week");
        var before = temp.Store.AgendaItemsFor(note);
        Assert.Equal([false, false], before.Select(i => i.IsDone));

        temp.Store.ToggleChecklistItem(note.Id, 0);

        Assert.EndsWith("- [x] buy tomatoes today\nhiking next week", File.ReadAllText(temp.Store.Notes[0].FilePath!));
        var after = temp.Store.AgendaItemsFor(temp.Store.Notes[0]);
        Assert.Equal([true, false], after.Select(i => i.IsDone));
        Assert.Equal(before.Select(i => i.Date), after.Select(i => i.Date)); // completing must not move the date
    }
}
