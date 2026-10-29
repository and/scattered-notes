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
            CreatedAt = Monday, UpdatedAt = Monday,
        };
        var items = AgendaExtractor.Items(note, Zone);

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
        var note = new Note { Title = "Mixed", Content = "Sunny today\nfix the screen bug\nWill was here", CreatedAt = Monday, UpdatedAt = Monday };
        var items = AgendaExtractor.Items(note, Zone);

        Assert.Equal(["Sunny today", "fix the screen bug"], items.Select(i => i.Text));
        Assert.Equal([false, true], items.Select(i => i.IsTodo));
    }

    [Fact]
    public void CrlfLinesKeepTheSameIndexes()
    {
        var note = new Note { Content = "intro\r\n- [ ] one\r\n\r\ntwo tomorrow", CreatedAt = Monday, UpdatedAt = Monday };
        var items = AgendaExtractor.Items(note, Zone);
        Assert.Equal([1, 3], items.Select(i => i.LineIndex));
    }

    [Fact]
    public void ToggleChecklistItemUpdatesNoteOnDisk()
    {
        using var temp = new TempStore();
        var note = temp.Store.CreateNote("Errands", "Intro\n- [ ] Buy stamps\n- [ ] Post letter");

        temp.Store.ToggleChecklistItem(note.Id, 2);

        var saved = File.ReadAllText(temp.Store.Notes[0].FilePath!);
        Assert.Contains("Intro\n- [ ] Buy stamps\n- [x] Post letter ✅ ", saved);
        Assert.Equal(["Post letter"], temp.Store.AgendaItems().Where(i => i.IsDone).Select(i => i.Text));
    }

    [Fact]
    public void ParsesDaysOfTheMonth()
    {
        Assert.Equal(Day(11, 22), Parse("there is a driving class on 22nd of the next month"));
        Assert.Equal(Day(11, 1), Parse("Rent due 1 of next month"));
        Assert.Equal(Day(10, 28), Parse("Report on the 28th of this month"));
        Assert.Equal(Day(10, 31), Parse("Pay it by the end of the month"));
        Assert.Equal(Day(11, 30), Parse("Plan ready end of next month"));
        Assert.Equal(Day(10, 28), Parse("Class on the 28th"));
        Assert.Equal(Day(11, 22), Parse("Class on the 22nd")); // already past this month
        Assert.Equal(Day(10, 26), Parse("Class on the 26th")); // today counts
        Assert.Null(Parse("Class on 31st of next month")); // November has no 31st
        Assert.Null(Parse("Buy the 3 apples"));
    }

    [Fact]
    public void ParsesDayAfterAndIntervals()
    {
        Assert.Equal(Day(10, 28), Parse("Party the day after tomorrow"));
        Assert.Equal(Day(10, 27), Parse("Laundry the day after"));
        Assert.Equal(Day(10, 29), Parse("Renew in 3 days"));
        Assert.Equal(Day(11, 9), Parse("Review in 2 weeks"));

        var note = new Note { Content = "buy tomatoes today\n\nalso do laundry the day after.", CreatedAt = Monday, UpdatedAt = Monday };
        Assert.Equal([Day(10, 26), Day(10, 27)], AgendaExtractor.Items(note, Zone).Select(i => i.Date));
    }

    [Fact]
    public void MarkersFixAWordsDayAndShowTheTickDay()
    {
        var note = new Note
        {
            Content = "Call bank tomorrow 📅 2026-10-30\n- [x] Pay rent ✅ 2026-10-25\n- [x] Send form friday 📅 2026-11-06 ✅ 2026-10-28",
            CreatedAt = Monday,
            UpdatedAt = Monday,
        };
        var items = AgendaExtractor.Items(note, Zone);

        Assert.Equal(["Call bank tomorrow", "Pay rent", "Send form friday"], items.Select(i => i.Text));
        Assert.Equal([Day(10, 30), (DateOnly?)null, Day(11, 6)], items.Select(i => i.Date));
        Assert.Equal([(DateOnly?)null, Day(10, 25), Day(10, 28)], items.Select(i => i.DoneOn));
    }

    private static string Resolve(string content, string? previous = null, DateTimeOffset? previousUpdatedAt = null, DateTimeOffset? now = null) =>
        AgendaExtractor.ResolvingDates(content, previous, previousUpdatedAt, now ?? Monday, Zone);

    [Fact]
    public void ResolvingWritesTheDayOfRelativeWordsOnly()
    {
        const string content = "Call bank tomorrow\nlunch on 2026-11-02\nbuy milk oct 28\n# Heading today\nplain line";
        var once = Resolve(content);
        Assert.Equal("Call bank tomorrow 📅 2026-10-27\nlunch on 2026-11-02\nbuy milk oct 28\n# Heading today\nplain line", once);
        Assert.Equal(once, Resolve(once, once, Monday, Monday.AddDays(5))); // a marked line never moves
    }

    [Fact]
    public void ResolvingKeepsTheMarkerWhenTheEditorsCopyLacksIt()
    {
        const string saved = "Call bank tomorrow 📅 2026-10-27";
        var later = Monday.AddDays(4);
        Assert.Equal(saved, Resolve("Call bank tomorrow", saved, Monday, later));
        Assert.Equal("intro\n" + saved, Resolve("intro\nCall bank tomorrow", saved, Monday, later)); // moving a line keeps its day
        Assert.Equal("Call bank tomorrow 📅 2026-11-02", Resolve("Call bank tomorrow 📅 2026-11-02", saved, Monday, later)); // an edited marker wins
    }

    [Fact]
    public void DuplicateLinesKeepTheirOwnDays()
    {
        const string saved = "call bank tomorrow 📅 2026-10-27\ncall bank tomorrow 📅 2026-10-31";
        Assert.Equal(saved, Resolve("call bank tomorrow\ncall bank tomorrow", saved, Monday, Monday.AddDays(9)));
    }

    [Fact]
    public void ResolvingDatesNewLinesFromNowAndOldUnmarkedLinesFromTheirNote()
    {
        var result = Resolve("old plan tomorrow\nnew plan tomorrow", "old plan tomorrow", Monday, Monday.AddDays(3));
        Assert.Equal("old plan tomorrow 📅 2026-10-27\nnew plan tomorrow 📅 2026-10-30", result);
    }

    [Fact]
    public void ResolvingChainsTheDayAfterFromTheLineAbove()
    {
        Assert.Equal("buy tomatoes today 📅 2026-10-26\nbake the day after 📅 2026-10-27", Resolve("buy tomatoes today\nbake the day after"));
    }

    [Fact]
    public void ResolvingWritesAndRemovesTheTickDay()
    {
        var ticked = Resolve("- [x] call bank");
        Assert.Equal("- [x] call bank ✅ 2026-10-26", ticked);
        var later = Monday.AddDays(1);
        Assert.Equal(ticked, Resolve(ticked, ticked, Monday, later)); // the tick day is kept
        Assert.Equal(ticked, Resolve("- [x] call bank", ticked, Monday, later)); // so is it when the editor's copy lacks the marker
        Assert.Equal("- [ ] call bank", Resolve("- [ ] call bank ✅ 2026-10-26", ticked, Monday, later));
        Assert.Equal("- [x] send form friday 📅 2026-10-30 ✅ 2026-10-26", Resolve("- [x] send form friday"));
    }

    [Fact]
    public void ResolvingKeepsWindowsLineEndings()
    {
        Assert.Equal("a\r\ncall bank tomorrow 📅 2026-10-27\r\nb", Resolve("a\r\ncall bank tomorrow\r\nb"));
    }

    [Fact]
    public void MarkersAreInvisibleToTheLineText()
    {
        Assert.Equal("call bank tomorrow", AgendaExtractor.DisplayText("- [x] call bank tomorrow 📅 2026-10-27 ✅ 2026-10-28"));
        Assert.True(AgendaExtractor.IsPlannedAction(AgendaExtractor.DisplayText("call bank 📅 2026-10-27")));
    }

    [Fact]
    public void SavingWritesDaysIntoTheNotesOwnFile()
    {
        using var temp = new TempStore();
        var note = temp.Store.CreateNote("Errands", "Buy tomatoes today");
        var firstDay = temp.Store.AgendaItemsFor(note)[0].Date;

        temp.Store.Save(note with { Content = note.Content + "\nCall bank tomorrow" });

        var stored = temp.Store.Notes[0];
        var items = temp.Store.AgendaItemsFor(stored);
        Assert.Equal(2, items.Count);
        Assert.Equal(firstDay, items[0].Date);
        Assert.Equal(firstDay!.Value.AddDays(1), items[1].Date);
        var file = File.ReadAllText(stored.FilePath!);
        Assert.Contains("Call bank tomorrow 📅 ", file);
        Assert.DoesNotContain("seen:", file);
        Assert.False(File.Exists(Path.Combine(temp.Root, ".agenda-log.json")));
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

        var saved = File.ReadAllText(temp.Store.Notes[0].FilePath!);
        Assert.Contains("- [x] buy tomatoes today 📅 ", saved);
        Assert.Contains(" ✅ ", saved);
        var after = temp.Store.AgendaItemsFor(temp.Store.Notes[0]);
        Assert.Equal([true, false], after.Select(i => i.IsDone));
        Assert.Equal(before.Select(i => i.Date), after.Select(i => i.Date)); // completing must not move the date
    }

    [Fact]
    public void FrontmatterFromOtherAppsSurvivesASave()
    {
        const string raw = "---\nid: 7C1F3A52-1111-4B5B-9C8E-1234567890AB\ntitle: \"Trip\"\naliases:\n  - Holiday\n  - \"Trip 2026\"\ncssclasses: wide\ntags:\n  - travel\n  - \"#plans\"\nrating: 4\n---\n\nbody";
        var note = NoteFormat.Parse(raw);
        Assert.Equal(["travel", "plans"], note.Tags);
        Assert.Equal("aliases:\n  - Holiday\n  - \"Trip 2026\"\ncssclasses: wide\nrating: 4", note.ExtraFrontmatter);

        var saved = NoteFormat.Serialize(note);
        Assert.Contains("\naliases:\n  - Holiday\n  - \"Trip 2026\"\ncssclasses: wide\nrating: 4\n---\n\nbody", saved);
        Assert.Equal(2, saved.Split("\ntags:").Length);
        var again = NoteFormat.Parse(saved);
        Assert.Equal(note.ExtraFrontmatter, again.ExtraFrontmatter);
        Assert.Equal(note.Tags, again.Tags);
        Assert.Equal(saved, NoteFormat.Serialize(again));
    }

    [Fact]
    public void CaretStaysInTheSameWordsWhenMarkersAreWritten()
    {
        const string old = "do this tomorrow\nand the day after tomorrow do";
        const string updated = "do this tomorrow 📅 2026-10-30\nand the day after tomorrow do 📅 2026-10-31";
        Assert.Equal(updated.Length - " 📅 2026-10-31".Length, AgendaExtractor.MappedOffset(old.Length, old, updated)); // typing at a line end stays before its marker
        Assert.Equal(3, AgendaExtractor.MappedOffset(3, old, updated));
        const string firstEnd = "do this tomorrow";
        Assert.Equal(firstEnd.Length + " 📅 2026-10-30".Length + 1, AgendaExtractor.MappedOffset(firstEnd.Length + 1, old, updated));
        const string marked = "a tomorrow 📅 2026-10-30 b";
        Assert.Equal("a tomorrow 📅 2026-10-30".Length, AgendaExtractor.MappedOffset("a tomorrow 📅 2026-10-30".Length, marked, marked + "!")); // right after a marker stays after it
        Assert.True(AgendaExtractor.SameIgnoringMarkers(old, updated));
    }
}
