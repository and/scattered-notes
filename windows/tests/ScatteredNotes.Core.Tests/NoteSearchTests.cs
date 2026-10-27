using ScatteredNotes.Core.Models;
using ScatteredNotes.Core.Search;

namespace ScatteredNotes.Core.Tests;

public class NoteSearchTests
{
    private static Note N(string title, string content, string[]? tags = null, CategoryType category = CategoryType.Inbox, string? target = null, int updated = 0) =>
        new()
        {
            Title = title,
            Content = content,
            CategoryType = category,
            TargetName = target,
            UpdatedAt = DateTimeOffset.FromUnixTimeSeconds(updated),
            Tags = tags ?? [],
        };

    [Fact]
    public void AllTermsMustMatchAnywhereInNote()
    {
        Note[] notes = [N("Groceries", "buy tomatoes and basil"), N("Garage", "tomatoes are not here")];
        Assert.Equal(["Groceries"], NoteSearch.Search("tomatoes basil", notes).Select(r => r.Note.Title));
        Assert.Empty(NoteSearch.Search("tomatoes zebra", notes));
    }

    [Fact]
    public void IgnoresCaseAndAccents()
    {
        Note[] notes = [N("Café plans", "Meet at the CAFÉ")];
        Assert.Single(NoteSearch.Search("cafe", notes));
        Assert.Single(NoteSearch.Search("MEET", notes));
    }

    [Fact]
    public void TitleMatchesRankAboveBodyMatches()
    {
        Note[] notes = [N("Misc", "motor bike parts", updated: 100), N("Motor bike", "service due", updated: 1)];
        Assert.Equal(["Motor bike", "Misc"], NoteSearch.Search("motor", notes).Select(r => r.Note.Title));
    }

    [Fact]
    public void HashTermsMatchTagsOnly()
    {
        Note[] notes = [N("Tagged", "nothing", ["work"]), N("Mentions", "talk about work")];
        Assert.Equal(["Tagged"], NoteSearch.Search("#work", notes).Select(r => r.Note.Title));
    }

    [Fact]
    public void ProjectNameIsSearchable()
    {
        Assert.Single(NoteSearch.Search("sandtimer", [N("Plan", "outline", category: CategoryType.Project, target: "Sandtimer")]));
    }

    [Fact]
    public void BlankQueryReturnsNothing()
    {
        Assert.Empty(NoteSearch.Search("   ", [N("a", "b")]));
        Assert.Empty(NoteSearch.Search("#", [N("a", "b")]));
    }

    [Fact]
    public void SnippetStaysOnMatchLineAndIsTrimmed()
    {
        var longText = new string('x', 200);
        var result = NoteSearch.Search("needle", [N("t", $"first line\n{longText} needle {longText}\nlast")]).Single();
        var snippet = result.Snippet!;
        Assert.Contains("needle", snippet);
        Assert.StartsWith("…", snippet);
        Assert.EndsWith("…", snippet);
        Assert.DoesNotContain("first line", snippet);
        Assert.DoesNotContain("last", snippet);
        Assert.True(snippet.Length < 110);
    }

    [Fact]
    public void SnippetOfShortLineHasNoEllipses()
    {
        var result = NoteSearch.Search("milk", [N("t", "eggs\r\nbuy milk\r\nbread")]).Single();
        Assert.Equal("buy milk", result.Snippet);
    }

    [Fact]
    public void TitleOnlyMatchHasNoSnippet()
    {
        Assert.Null(NoteSearch.Search("groceries", [N("Groceries", "milk")]).Single().Snippet);
    }
}
