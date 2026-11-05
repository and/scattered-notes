using ScatteredNotes.Core.Models;

namespace ScatteredNotes.Core.Tests;

/// <summary>The same cases as the Mac app's RelatedNotesTests.</summary>
public class RelatedNotesTests
{
    private static readonly DateTimeOffset Base = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000);

    private static Note N(string title, string content = "", string[]? tags = null, string? project = null, int minutes = 0) => new()
    {
        Title = title,
        Content = content,
        CategoryType = project is null ? CategoryType.Inbox : CategoryType.Project,
        TargetName = project,
        UpdatedAt = Base.AddMinutes(minutes),
        Tags = tags ?? [],
    };

    /// <summary>Some filler notes so a word shared by two of them is rare among all.</summary>
    private static List<Note> Filler() =>
        Enumerable.Range(0, 8).Select(i => N($"Filler {i}", $"nothing special about number{i} here at all")).ToList();

    private static List<Note> With(params Note[] notes) => [.. notes, .. Filler()];

    [Fact]
    public void NotesWithTheSameTagAreRelated()
    {
        var a = N("Garden", "water the beds", ["home"]);
        var b = N("Paint", "buy brushes", ["home"]);
        var c = N("Work", "send the invoice", ["office"]);
        var result = new RelatedIndex(With(a, b, c)).RelatedTo(a.Id);
        Assert.Equal([b.Id], result.Select(r => r.Id));
        Assert.Equal(["#home"], result[0].SharedMarks);
    }

    [Fact]
    public void NotesMentioningTheSamePersonAreRelated()
    {
        var a = N("Call", "ask @neil about the deck");
        var b = N("Lunch", "lunch with @Neil on friday");
        var result = new RelatedIndex(With(a, b)).RelatedTo(a.Id);
        Assert.Equal([b.Id], result.Select(r => r.Id));
        Assert.Equal(["@neil"], result[0].SharedMarks);
    }

    [Fact]
    public void NotesUsingTheSameUncommonWordsAreRelated()
    {
        var a = N("Trip", "booking flights and a hotel in lisbon, lisbon trams, lisbon food");
        var b = N("Packing", "things to take to lisbon: a coat, lisbon is windy");
        var c = N("Taxes", "form for the accountant");
        var result = new RelatedIndex(With(a, b, c)).RelatedTo(a.Id);
        Assert.Equal([b.Id], result.Select(r => r.Id));
        Assert.Contains("lisbon", result[0].SharedWords);
    }

    [Fact]
    public void CommonWordsAndShortWordsDoNotRelateNotes()
    {
        var a = N("One", "this would have been about that with your things");
        var b = N("Two", "this would have been about that with your stuff");
        Assert.Empty(new RelatedIndex(With(a, b)).RelatedTo(a.Id));
    }

    [Fact]
    public void NumbersDoNotRelateNotes()
    {
        var a = N("One", "123456 now");
        var b = N("Two", "123456 later");
        Assert.Empty(new RelatedIndex(With(a, b)).RelatedTo(a.Id));
    }

    [Fact]
    public void SharingOnlyAProjectIsNotEnough()
    {
        var a = N("Alpha", "apples", project: "Home");
        var b = N("Bravo", "bicycles", project: "Home");
        Assert.Empty(new RelatedIndex(With(a, b)).RelatedTo(a.Id));
    }

    [Fact]
    public void TheSameProjectBreaksATie()
    {
        var me = N("Me", "x", ["t"], "Home");
        var near = N("Near", "y", ["t"], "Home", 0);
        var far = N("Far", "z", ["t"], "Work", 5);
        Assert.Equal([near.Id, far.Id], new RelatedIndex(With(me, near, far)).RelatedTo(me.Id).Select(r => r.Id));
    }

    [Fact]
    public void MoreSharedMarksRankHigher()
    {
        var me = N("Me", "", ["a", "b"]);
        var one = N("One", "", ["a"]);
        var two = N("Two", "", ["a", "b"]);
        Assert.Equal([two.Id, one.Id], new RelatedIndex(With(me, one, two)).RelatedTo(me.Id).Select(r => r.Id));
    }

    [Fact]
    public void ANoteIsNotRelatedToItselfAndExcludedNotesAreLeftOut()
    {
        var a = N("A", "", ["x"]);
        var b = N("B", "", ["x"]);
        var index = new RelatedIndex(With(a, b));
        Assert.DoesNotContain(index.RelatedTo(a.Id), r => r.Id == a.Id);
        Assert.Empty(index.RelatedTo(a.Id, excluding: new HashSet<Guid> { b.Id }));
    }

    [Fact]
    public void LimitAndOrderAreStable()
    {
        var notes = Enumerable.Range(0, 9).Select(i => N($"N{i}", "", ["same"], minutes: i)).ToList();
        var first = new RelatedIndex([.. notes, .. Filler()]).RelatedTo(notes[0].Id, limit: 3);
        Assert.Equal([notes[8].Id, notes[7].Id, notes[6].Id], first.Select(r => r.Id));
    }

    [Fact]
    public void UnknownNoteAndNoNotesGiveNothing()
    {
        Assert.Empty(new RelatedIndex([]).RelatedTo(Guid.NewGuid()));
        Assert.Empty(new RelatedIndex(Filler()).RelatedTo(Guid.NewGuid()));
    }
}
