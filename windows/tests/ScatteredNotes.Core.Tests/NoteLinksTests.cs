using ScatteredNotes.Core.Models;

namespace ScatteredNotes.Core.Tests;

/// <summary>The same cases as the Mac app's NoteLinksTests.</summary>
public class NoteLinksTests
{
    private static readonly DateTimeOffset Base = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000);

    private static Note N(string title, string content = "", int minutes = 0) =>
        new() { Title = title, Content = content, UpdatedAt = Base.AddMinutes(minutes) };

    private static List<Guid?> Targets(NoteLinkIndex index, Note from) => index.LinksFrom(from.Id).Select(l => l.Target).ToList();

    [Fact]
    public void FindsAnotherNotesTitleInTheText()
    {
        var budget = N("Budget");
        var plan = N("Plan", "Check the budget before Friday");
        var links = new NoteLinkIndex([budget, plan]).LinksFrom(plan.Id);
        var link = Assert.Single(links);
        Assert.Equal(budget.Id, link.Target);
        Assert.Equal("budget", link.Text);
        Assert.False(link.IsExplicit);
        Assert.Equal("budget", plan.Content.Substring(link.Start, link.Length));
    }

    [Fact]
    public void MatchesWholeWordsOnly()
    {
        var plan = N("Plan");
        var other = N("Other", "planning the planets, a plant");
        Assert.Empty(new NoteLinkIndex([plan, other]).LinksFrom(other.Id));
    }

    [Fact]
    public void IgnoresCaseAndAccents()
    {
        var cafe = N("Café Notes");
        var other = N("Other", "met at the CAFE NOTES place");
        Assert.Equal([cafe.Id], Targets(new NoteLinkIndex([cafe, other]), other));
    }

    [Fact]
    public void PunctuationBetweenWordsDoesNotMatter()
    {
        var title = N("Plan: Q4");
        var other = N("Other", "the plan Q4 review, and plan - Q4 again");
        Assert.Equal([title.Id, title.Id], Targets(new NoteLinkIndex([title, other]), other));
    }

    [Fact]
    public void TheLongestTitleWinsAndUsesUpTheText()
    {
        var shortTitle = N("Garden");
        var longTitle = N("Garden Party");
        var other = N("Other", "the garden party is on Friday, the garden is wet");
        var links = new NoteLinkIndex([shortTitle, longTitle, other]).LinksFrom(other.Id);
        Assert.Equal([longTitle.Id, shortTitle.Id], links.Select(l => l.Target));
        Assert.Equal(["garden party", "garden"], links.Select(l => l.Text));
    }

    [Fact]
    public void TitlesSharingTheFirstWordAreToldApart()
    {
        var one = N("Trip to Goa");
        var two = N("Trip to Pune");
        var bare = N("Trip");
        var other = N("Other", "trip to pune, trip to goa, a trip to Delhi");
        var links = new NoteLinkIndex([one, two, bare, other]).LinksFrom(other.Id);
        Assert.Equal([two.Id, one.Id, bare.Id], links.Select(l => l.Target));
    }

    [Fact]
    public void TitlesShorterThanThreeCharactersAreNotLookedFor()
    {
        var tiny = N("Go");
        var other = N("Other", "go to the shop");
        Assert.Empty(new NoteLinkIndex([tiny, other]).LinksFrom(other.Id));
    }

    [Fact]
    public void ANoteDoesNotLinkToItself()
    {
        var budget = N("Budget", "The budget is tight");
        Assert.Empty(new NoteLinkIndex([budget]).LinksFrom(budget.Id));
    }

    [Fact]
    public void TwoNotesWithTheSameTitleBothGetTheLink()
    {
        var first = N("Ideas");
        var second = N("Ideas");
        var other = N("Other", "More ideas for the site");
        Assert.Equal(new HashSet<Guid?> { first.Id, second.Id }, Targets(new NoteLinkIndex([first, second, other]), other).ToHashSet());
    }

    [Fact]
    public void AnUntitledNoteIsNotFoundByItsPlaceholder()
    {
        var blank = N("");
        var other = N("Other", "an untitled note is here");
        Assert.Empty(new NoteLinkIndex([blank, other]).LinksFrom(other.Id));
    }

    [Fact]
    public void TheTitleOfANoteWithoutOneIsItsFirstLine()
    {
        var untitled = N("", "Holiday packing\n- socks");
        var other = N("Other", "see holiday packing");
        Assert.Equal([untitled.Id], Targets(new NoteLinkIndex([untitled, other]), other));
    }

    [Fact]
    public void LinksComeInTheOrderOfTheText()
    {
        var a = N("Alpha");
        var b = N("Bravo");
        var other = N("Other", "bravo first, then alpha");
        Assert.Equal([b.Id, a.Id], Targets(new NoteLinkIndex([a, b, other]), other));
    }

    [Fact]
    public void RangesCountUtf16SoEmojiBeforeATitleDoNotShiftThem()
    {
        var budget = N("Budget");
        var other = N("Other", "🙂🙂 budget");
        var link = new NoteLinkIndex([budget, other]).LinksFrom(other.Id)[0];
        Assert.Equal("budget", other.Content.Substring(link.Start, link.Length));
    }

    [Fact]
    public void ExplicitLinkFindsTheNote()
    {
        var budget = N("Budget");
        var other = N("Other", "see [[Budget]] now");
        var link = Assert.Single(new NoteLinkIndex([budget, other]).LinksFrom(other.Id));
        Assert.Equal(budget.Id, link.Target);
        Assert.True(link.IsExplicit);
        Assert.Equal("[[Budget]]", other.Content.Substring(link.Start, link.Length));
    }

    [Fact]
    public void ExplicitLinkIsNotAlsoCountedAsAPlainMention()
    {
        var budget = N("Budget");
        var other = N("Other", "[[Budget]] and the budget");
        Assert.Equal([true, false], new NoteLinkIndex([budget, other]).LinksFrom(other.Id).Select(l => l.IsExplicit));
    }

    [Fact]
    public void ExplicitLinkToAMissingNoteHasNoTarget()
    {
        var other = N("Other", "see [[Nowhere]]");
        var link = Assert.Single(new NoteLinkIndex([other]).LinksFrom(other.Id));
        Assert.Null(link.Target);
        Assert.Equal("Nowhere", link.Text);
    }

    [Fact]
    public void ExplicitLinkWorksForShortTitlesAndIgnoresCase()
    {
        var go = N("Go");
        var other = N("Other", "[[go]]");
        Assert.Equal([go.Id], Targets(new NoteLinkIndex([go, other]), other));
    }

    [Fact]
    public void AnExplicitLinkToYourselfIsDropped()
    {
        var me = N("Me", "[[Me]]");
        Assert.Empty(new NoteLinkIndex([me]).LinksFrom(me.Id));
    }

    [Fact]
    public void BracketsAcrossLinesAreNotALink()
    {
        var budget = N("Budget");
        var other = N("Other", "[[Bud\nget]]");
        Assert.Empty(new NoteLinkIndex([budget, other]).LinksFrom(other.Id));
    }

    [Fact]
    public void AMentionBecomesAnExplicitLinkToTheSameNote()
    {
        var budget = N("Budget");
        var other = N("Other", "🙂 check the budget first, then the budget again");
        var link = new NoteLinkIndex([budget, other]).LinksFrom(other.Id).First();
        var changed = NoteLinkIndex.MakingExplicit(link, "Budget", other.Content);
        Assert.Equal("🙂 check the [[Budget]] first, then the budget again", changed);

        var after = new NoteLinkIndex([budget, other with { Content = changed! }]).LinksFrom(other.Id);
        Assert.Equal([true, false], after.Select(l => l.IsExplicit));
        Assert.Equal([budget.Id, budget.Id], after.Select(l => l.Target));
    }

    [Fact]
    public void TitlesThatCannotBeWrittenAsALinkAreRefused()
    {
        Assert.Null(NoteLinkIndex.ExplicitText("Plan [draft]"));
        Assert.Null(NoteLinkIndex.ExplicitText("Two\nlines"));
        Assert.Null(NoteLinkIndex.ExplicitText(""));
        Assert.Equal("[[Plan: Q4]]", NoteLinkIndex.ExplicitText("Plan: Q4"));
    }

    [Fact]
    public void AnExplicitLinkOrAStaleRangeIsNotRewritten()
    {
        var budget = N("Budget");
        var other = N("Other", "[[Budget]]");
        var link = new NoteLinkIndex([budget, other]).LinksFrom(other.Id).First();
        Assert.Null(NoteLinkIndex.MakingExplicit(link, "Budget", other.Content));

        var plain = N("Plain", "the budget");
        var mention = new NoteLinkIndex([budget, plain]).LinksFrom(plain.Id).First();
        Assert.Null(NoteLinkIndex.MakingExplicit(mention, "Budget", "tiny"));
    }

    [Fact]
    public void BacklinksListEachLinkingNoteOnceNewestFirst()
    {
        var budget = N("Budget", minutes: 0);
        var older = N("Older", "budget, budget and [[Budget]]", minutes: 1);
        var newer = N("Newer", "the budget", minutes: 5);
        var unrelated = N("Unrelated", "nothing here", minutes: 9);
        var index = new NoteLinkIndex([budget, older, newer, unrelated]);
        Assert.Equal([newer.Id, older.Id], index.BacklinksTo(budget.Id));
        Assert.Empty(index.BacklinksTo(unrelated.Id));
    }

    [Fact]
    public void LinkedNotesListsEachTargetOnceInOrder()
    {
        var a = N("Alpha");
        var b = N("Bravo");
        var other = N("Other", "alpha, bravo, alpha again");
        Assert.Equal([a.Id, b.Id], new NoteLinkIndex([a, b, other]).LinkedNotesFrom(other.Id));
    }

    [Fact]
    public void RenamingANoteMovesItsBacklinks()
    {
        var budget = N("Budget");
        var other = N("Other", "the budget");
        Assert.Equal([other.Id], new NoteLinkIndex([budget, other]).BacklinksTo(budget.Id));
        Assert.Empty(new NoteLinkIndex([budget with { Title = "Money" }, other]).BacklinksTo(budget.Id));
    }

    [Fact]
    public void NoNotesAndEmptyTextGiveNothing()
    {
        Assert.Empty(new NoteLinkIndex([]).LinksFrom(Guid.NewGuid()));
        var empty = N("Empty");
        Assert.Empty(new NoteLinkIndex([empty]).LinksFrom(empty.Id));
    }
}
