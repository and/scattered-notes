using ScatteredNotes.Core.Models;

namespace ScatteredNotes.Core.Tests;

/// <summary>The same cases as the Mac app's MentionsTests.</summary>
public class MentionsTests
{
    [Fact]
    public void FindsPeopleTagsAndProjectsAtTheStartOfWords()
    {
        const string text = "Call @Ana about +Website (#idea), then #idea again and @ana.";
        Assert.Equal(["Ana"], Mentions.Names(Mentions.Kind.Person, text));
        Assert.Equal(["idea"], Mentions.Names(Mentions.Kind.Tag, text));
        Assert.Equal(["Website"], Mentions.Names(Mentions.Kind.Project, text));
    }

    [Fact]
    public void IgnoresSymbolsThatAreNotMarks() =>
        Assert.Empty(Mentions.Marks("Mail ana@example.com about C# and +91 98450 for #1 ~5 min, x+y"));

    [Fact]
    public void NamesKeepDashesDotsAndDigitsButNotATrailingDot() =>
        Assert.Equal(["home-office", "v2.1", "done"], Mentions.Names(Mentions.Kind.Tag, "#home-office #v2.1 #done."));

    [Fact]
    public void NoteTagsAndPeopleComeFromItsText()
    {
        var note = NoteFormat.Parse("---\ntags: [\"old\"]\n---\n\nPing @sam #new");
        Assert.Equal(["old", "new"], note.Tags);
        Assert.Equal(["sam"], note.People);
    }

    [Fact]
    public void AreaNamesBecomeTagNames()
    {
        Assert.Equal("home-office", Mentions.TagNameForArea("Home Office"));
        Assert.Equal("area-2026-goals", Mentions.TagNameForArea("2026 Goals"));
    }
}
