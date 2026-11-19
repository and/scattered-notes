using ScatteredNotes.Core.Search;

namespace ScatteredNotes.Core.Tests;

/// <summary>Ported from the Mac GoToTargets tests' rules.</summary>
public class GoToMatchingTests
{
    private static readonly (string Title, GoToKind Kind)[] Places =
    [
        ("Dashboard", GoToKind.Place),
        ("All Notes", GoToKind.Place),
        ("Inbox", GoToKind.Place),
        ("Day Trading", GoToKind.Place),
        ("Trading Journal", GoToKind.Place),
        ("Strategy", GoToKind.Place),
        ("sam", GoToKind.Person),
        ("trades", GoToKind.Tag),
        ("café", GoToKind.Tag),
    ];

    private static List<string> Match(string query) =>
        GoToMatching.Matching(query, Places, p => p.Title, p => p.Kind).Select(p => p.Title).ToList();

    [Fact]
    public void NothingTypedListsEverythingInOrder() => Assert.Equal(Places.Select(p => p.Title), Match(""));

    [Fact]
    public void StartOfNameBeatsStartOfWordBeatsInside()
    {
        // "Trading Journal" starts with it, "Day Trading" has a word that does, "trades" only via its start
        Assert.Equal(["Trading Journal", "trades", "Day Trading"], Match("trad"));
        Assert.Equal(["Trading Journal"], Match("journ"));
        // Only inside a word: kept in the given order
        Assert.Equal(["Day Trading", "Trading Journal"], Match("ading"));
    }

    [Fact]
    public void HashAndAtNarrowToTagsAndPeople()
    {
        Assert.Equal(["trades", "café"], Match("#"));
        Assert.Equal(["trades"], Match("#tr"));
        Assert.Equal(["sam"], Match("@"));
        Assert.Empty(Match("@trad"));
    }

    [Fact]
    public void CaseAndAccentsAreIgnored()
    {
        Assert.Equal(["Inbox"], Match("INB"));
        Assert.Equal(["café"], Match("cafe"));
    }
}
