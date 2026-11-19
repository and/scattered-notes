using ScatteredNotes.Core.Models;

namespace ScatteredNotes.Core.Tests;

/// <summary>
/// A notes folder laid out like an Obsidian vault: notes at the top level and in folders of their own, beside
/// the app's Inbox/ and Projects/. Top-level notes show in the Inbox, folders with notes show as projects, and
/// the files stay where they are.
/// </summary>
public class LooseNotesTests
{
    private static string Write(string root, string relative, string text)
    {
        var path = Path.Combine(root, relative);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, text);
        return path;
    }

    private static TempStore Vault(out string root)
    {
        var temp = new TempStore();
        root = temp.Root;
        Write(root, "Journal.md", "# Trading Journal\n\n- Deposited money\n");
        Write(root, "Day Trading/2026-11-19.md", "# Day trading\n\n- 12:20 Agent started\n");
        Write(root, "Day Trading/chart.png", "not a note");
        Write(root, ".obsidian/workspace.md", "hidden");
        Write(root, "attachments/image.png", "no notes in here");
        Write(root, ".hidden.md", "hidden");
        return temp;
    }

    [Fact]
    public void TopLevelNotesShowInTheInboxAndFoldersAsProjects()
    {
        using var temp = Vault(out var root);
        var store = temp.Open();

        Assert.Equal(2, store.Notes.Count);
        var journal = Assert.Single(store.Notes, n => n.DisplayTitle == "Journal");
        Assert.Equal(CategoryType.Inbox, journal.CategoryType);
        var day = Assert.Single(store.Notes, n => n.DisplayTitle == "2026-11-19");
        Assert.Equal(CategoryType.Project, day.CategoryType);
        Assert.Equal("Day Trading", day.TargetName);

        // Hidden folders, folders without notes and the app's own folders are not projects
        Assert.Equal(["Day Trading"], store.Projects.Select(p => p.Name));
    }

    [Fact]
    public void ANoteWithoutATitleIsNamedByItsFileAsInObsidian()
    {
        using var temp = Vault(out var root);
        Write(root, "Titled.md", "---\ntitle: \"Chosen title\"\n---\n\n# First line\n");
        var store = temp.Open();

        // The first line says "# Trading Journal", but Obsidian calls the note by its file name
        Assert.Contains(store.Notes, n => n.Title == "Journal" && n.FilePath == Path.Combine(root, "Journal.md"));
        Assert.Contains(store.Notes, n => n.Title == "Chosen title");
        Assert.False(Directory.Exists(Path.Combine(root, "Inbox")));
    }

    [Fact]
    public void LoadingWritesNothing()
    {
        using var temp = Vault(out var root);
        var before = Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories).ToDictionary(f => f, File.ReadAllText);
        _ = temp.Open();
        foreach (var (path, text) in before) Assert.Equal(text, File.ReadAllText(path));
    }

    [Fact]
    public void EditingKeepsTheFileWhereItIs()
    {
        using var temp = Vault(out var root);
        var store = temp.Open();
        var journal = store.Notes.Single(n => n.DisplayTitle == "Journal");
        var day = store.Notes.Single(n => n.DisplayTitle == "2026-11-19");

        Assert.True(store.Save(journal with { Content = journal.Content + "- Bought shares\n" }));
        Assert.True(store.Save(day with { Content = day.Content + "- 12:40 Agent stopped\n" }));

        Assert.Contains("Bought shares", File.ReadAllText(Path.Combine(root, "Journal.md")));
        Assert.Contains("Agent stopped", File.ReadAllText(Path.Combine(root, "Day Trading", "2026-11-19.md")));
        // Nothing was moved into the app's own folders, which aren't even made
        Assert.False(Directory.Exists(Path.Combine(root, "Inbox")));
        Assert.False(Directory.Exists(Path.Combine(root, "Projects")));

        // Still found in the same places after a relaunch, and not duplicated
        var reopened = temp.Open();
        Assert.Equal(2, reopened.Notes.Count);
        Assert.Equal("Day Trading", reopened.Notes.Single(n => n.DisplayTitle == "2026-11-19").TargetName);
    }

    [Fact]
    public void NewNotesStillGoToTheInboxFolder()
    {
        using var temp = Vault(out var root);
        var store = temp.Open();
        var note = store.CreateNote(content: "A new thought");
        Assert.Equal(Path.Combine(root, "Inbox"), Path.GetDirectoryName(note.FilePath));
    }

    [Fact]
    public void MovingANoteIntoALooseFolderProjectPutsItInThatFolder()
    {
        using var temp = Vault(out var root);
        var store = temp.Open();
        var journal = store.Notes.Single(n => n.DisplayTitle == "Journal");

        Assert.True(store.Move(journal, CategoryType.Project, "Day Trading"));

        var moved = store.Notes.Single(n => n.Id == journal.Id);
        Assert.Equal(Path.Combine(root, "Day Trading"), Path.GetDirectoryName(moved.FilePath));
        Assert.False(File.Exists(Path.Combine(root, "Journal.md")));
    }

    [Fact]
    public void ALooseFolderNamedLikeAProjectShowsOnce()
    {
        using var temp = Vault(out var root);
        Write(root, "Projects/Day Trading/plan.md", "# The plan\n");
        var store = temp.Open();

        Assert.Equal(["Day Trading"], store.Projects.Select(p => p.Name));
        Assert.Equal(2, store.Notes.Count(n => n.TargetName == "Day Trading"));
    }

    [Fact]
    public void DeletingALooseFolderProjectKeepsFilesThatAreNotNotes()
    {
        using var temp = Vault(out var root);
        var store = temp.Open();

        store.DeleteProject("Day Trading");

        Assert.False(File.Exists(Path.Combine(root, "Day Trading", "2026-11-19.md")));
        Assert.True(File.Exists(Path.Combine(root, "Day Trading", "chart.png")));
        Assert.DoesNotContain(store.Projects, p => p.Name == "Day Trading");
        Assert.Single(store.Notes);
    }
}
