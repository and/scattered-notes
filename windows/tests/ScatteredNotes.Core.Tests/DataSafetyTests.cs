using System.Text;
using ScatteredNotes.Core.Agenda;
using ScatteredNotes.Core.Models;
using ScatteredNotes.Core.Storage;

namespace ScatteredNotes.Core.Tests;

/// <summary>
/// Guards against losing or corrupting notes: lossless round trips, crash leftovers, Windows file quirks,
/// and the rule that merely opening the app never rewrites a note file. Ported from the Mac DataSafetyTests.
/// </summary>
public class DataSafetyTests
{
    private static readonly string[] NastyPieces =
    [
        "---", "--- ", "----", "\n", "\n\n", "\r\n", "title: x", "id: nope", "type: project", "\"", "\\", "\\\"",
        "'", ":", "#tag", "- [ ] todo", "- [x] done", "---\ntitle: fake\n---", "emoji 🍅🚀", "日本語", "é", "\t",
        "   ", "[]", "tags: [\"a\"]", "<!-- c -->", "```", "a---b", "%", "{{}}", "\0", "\u2028", "\r", "\uFEFF",
    ];

    private static string RandomText(Random rng, int maxPieces = 14) =>
        string.Join(rng.Next(2) == 0 ? "" : " ",
            Enumerable.Range(0, rng.Next(maxPieces + 1)).Select(_ => NastyPieces[rng.Next(NastyPieces.Length)]));

    [Fact]
    public void RoundTripPreservesContentAndTitleExactly()
    {
        var rng = new Random(42);
        CategoryType[] categories = [CategoryType.Inbox, CategoryType.Project, CategoryType.Area];
        for (var i = 0; i < 3000; i++)
        {
            var note = new Note
            {
                Title = RandomText(rng, 5).Replace("\0", ""),
                Content = RandomText(rng),
                CategoryType = categories[rng.Next(3)],
                TargetName = rng.Next(2) == 0 ? $"Proj {i}" : null,
                IsPinned = rng.Next(2) == 0,
            };
            var parsed = NoteFormat.Parse(NoteFormat.Serialize(note));
            Assert.True(note.Content == parsed.Content, $"content changed in iteration {i}");
            Assert.Equal(note.Id, parsed.Id);
            Assert.Equal(note.CategoryType, parsed.CategoryType);
            Assert.Equal(note.IsPinned, parsed.IsPinned);
            // Blank titles are replaced by the first line of the body on load, by design
            if (note.Title.Trim().Length > 0) Assert.True(note.Title == parsed.Title, $"title changed in iteration {i}");
        }
    }

    [Fact]
    public void RepeatedSaveLoadCyclesAreStable()
    {
        var note = new Note { Title = "He said \"hi\" \\ --- ok", Content = "---\nbody\n\n\n" };
        var first = NoteFormat.Serialize(note);
        for (var i = 0; i < 50; i++) note = NoteFormat.Parse(NoteFormat.Serialize(note));
        Assert.Equal(first, NoteFormat.Serialize(note));
    }

    [Fact]
    public void TitleContainingDelimiterDoesNotLeakIntoBody()
    {
        var parsed = NoteFormat.Parse(NoteFormat.Serialize(new Note { Title = "Plan --- phase 2", Content = "real body" }));
        Assert.Equal("Plan --- phase 2", parsed.Title);
        Assert.Equal("real body", parsed.Content);
    }

    [Fact]
    public void BodyKeepsLeadingAndTrailingBlankLines()
    {
        var note = new Note { Title = "t", Content = "\n\nstart\nend\n\n" };
        Assert.Equal("\n\nstart\nend\n\n", NoteFormat.Parse(NoteFormat.Serialize(note)).Content);
    }

    [Fact]
    public void MacFilesParse()
    {
        const string mac = """
        ---
        id: 02EFF95A-FF15-4719-990A-0A091ABE49F6
        title: "Old \"quoted\" title"
        type: project
        target: "dsa"
        created_at: 2026-10-26T10:00:00.000Z
        updated_at: 2026-10-26T11:00:00.000Z
        pinned: true
        tags: ["a", "b"]
        ---

        Body line 1
        --- not frontmatter
        Body line 3
        """;
        // Git may check this file out with Windows line endings; the Mac writes "\n"
        var note = NoteFormat.Parse(mac.ReplaceLineEndings("\n"));
        Assert.Equal(Guid.Parse("02EFF95A-FF15-4719-990A-0A091ABE49F6"), note.Id);
        Assert.Equal("02EFF95A-FF15-4719-990A-0A091ABE49F6", note.IdString);
        Assert.Equal("Old \"quoted\" title", note.Title);
        Assert.Equal("dsa", note.TargetName);
        Assert.True(note.IsPinned);
        Assert.Equal(["a", "b"], note.Tags);
        Assert.Equal(new DateTimeOffset(2026, 10, 26, 10, 0, 0, TimeSpan.Zero), note.CreatedAt);
        Assert.Equal("Body line 1\n--- not frontmatter\nBody line 3", note.Content);
    }

    [Fact]
    public void WritesTheMacFormat()
    {
        var note = new Note
        {
            Id = Guid.Parse("02eff95a-ff15-4719-990a-0a091abe49f6"),
            Title = "Plan",
            CategoryType = CategoryType.Project,
            TargetName = "Web",
            CreatedAt = new DateTimeOffset(2026, 10, 26, 10, 0, 0, 5, TimeSpan.Zero),
            UpdatedAt = new DateTimeOffset(2026, 10, 26, 16, 0, 0, TimeSpan.FromHours(5.5)),
            Tags = ["a"],
            Content = "body",
        };
        Assert.Equal(
            "---\nid: 02EFF95A-FF15-4719-990A-0A091ABE49F6\ntitle: \"Plan\"\ntype: project\ntarget: \"Web\"\n" +
            "created_at: 2026-10-26T10:00:00.005Z\nupdated_at: 2026-10-26T10:30:00.000Z\ntags: [\"a\"]\n---\n\nbody",
            NoteFormat.Serialize(note));
    }

    [Fact]
    public void WindowsLineEndingFrontmatterParsesAndBodyIsKept()
    {
        var note = NoteFormat.Parse("---\r\nid: 02EFF95A-FF15-4719-990A-0A091ABE49F6\r\ntitle: \"crlf\"\r\n---\r\n\r\nbody\r\nline 2\r\n");
        Assert.Equal("crlf", note.Title);
        Assert.Equal("02EFF95A-FF15-4719-990A-0A091ABE49F6", note.IdString);
        Assert.Equal("body\r\nline 2\r\n", note.Content);
    }

    [Fact]
    public void TextWithoutFrontmatterIsKeptWhole()
    {
        foreach (var raw in new[] { "plain text", "--- \nhr only\nno closing", "---\nunterminated: yes", "", "---", "----\ntext\n----\nmore" })
            Assert.Equal(raw, NoteFormat.Parse(raw).Content);
    }

    [Fact]
    public void ManySavesAllSurviveAFreshLoad()
    {
        using var temp = new TempStore();
        var rng = new Random(7);
        var notes = Enumerable.Range(0, 25).Select(i => temp.Store.CreateNote($"Note {i}", $"seed {i}")).ToList();
        for (var round = 0; round < 200; round++)
        {
            var index = rng.Next(notes.Count);
            temp.Store.Save(notes[index] with { Content = RandomText(rng) + $" round {round}" });
            notes[index] = temp.Store.Notes.First(n => n.Id == notes[index].Id);
        }
        var expected = notes.ToDictionary(n => n.Id, n => n.Content);

        var reloaded = temp.Open();
        Assert.Equal(25, reloaded.Notes.Count);
        Assert.Equal(25, temp.MarkdownFiles().Count());
        foreach (var note in reloaded.Notes) Assert.Equal(expected[note.Id], note.Content);
    }

    [Fact]
    public void NotesLeftInAreasMoveToTheInboxAsTags()
    {
        using var temp = new TempStore();
        var home = Path.Combine(temp.Root, "Areas", "Home Office");
        var empty = Path.Combine(temp.Root, "Areas", "ideas");
        var kept = Path.Combine(temp.Root, "Areas", "Scans");
        foreach (var dir in new[] { home, empty, kept }) Directory.CreateDirectory(dir);
        File.WriteAllText(Path.Combine(empty, NoteStore.MetadataFileName), "{\"icon\":\"heart.fill\"}");
        File.WriteAllText(Path.Combine(kept, "scan.pdf"), "not a note");
        var desk = new Note { Title = "Desk", Content = "Buy a lamp\n", CategoryType = CategoryType.Area, TargetName = "Home Office" };
        File.WriteAllText(Path.Combine(home, "desk.md"), NoteFormat.Serialize(desk));

        var store = temp.Open();

        var moved = store.Notes.Single();
        Assert.Equal(desk.Id, moved.Id);
        Assert.Equal(CategoryType.Inbox, moved.CategoryType);
        Assert.Equal("Buy a lamp\n\n#home-office", moved.Content);
        Assert.Equal(["home-office"], moved.Tags);
        Assert.Single(temp.MarkdownFiles());
        Assert.False(Directory.Exists(home));
        Assert.False(Directory.Exists(empty));
        Assert.True(File.Exists(Path.Combine(kept, "scan.pdf")), "other files are never removed");
    }

    [Fact]
    public void MovingNotesBetweenFoldersNeverLosesOrDuplicatesThem()
    {
        using var temp = new TempStore();
        var store = temp.Store;
        store.CreateProject("Alpha");
        store.CreateProject("Beta");
        var note = store.CreateNote("Traveller", "keep me --- safe\n- [ ] item");
        var rng = new Random(99);

        for (var i = 0; i < 40; i++)
        {
            switch (rng.Next(3))
            {
                case 0: store.Move(note, CategoryType.Inbox, null); break;
                case 1: store.Move(note, CategoryType.Project, "Alpha"); break;
                default: store.Move(note, CategoryType.Project, "Beta"); break;
            }
            note = store.Notes.Single(n => n.Id == note.Id);
            Assert.Single(temp.MarkdownFiles());
            Assert.True(File.Exists(note.FilePath));
        }

        var reloaded = temp.Open();
        Assert.Single(reloaded.Notes);
        Assert.Equal("keep me --- safe\n- [ ] item", reloaded.Notes[0].Content);
        Assert.Equal(note.CategoryType, reloaded.Notes[0].CategoryType);
    }

    [Fact]
    public void LoadingNeverRewritesExistingFiles()
    {
        using var temp = new TempStore();
        var inbox = temp.Store.InboxPath;
        var samples = new Dictionary<string, byte[]>
        {
            ["no-frontmatter.md"] = Encoding.UTF8.GetBytes("just text\n--- \nmore"),
            ["broken-frontmatter.md"] = Encoding.UTF8.GetBytes("---\ntitle: \"oops\nid: not-a-uuid\n"),
            ["crlf.md"] = Encoding.UTF8.GetBytes("---\r\ntitle: \"crlf\"\r\n---\r\n\r\nbody\r\n"),
            ["bom.md"] = [0xEF, 0xBB, 0xBF, .. Encoding.UTF8.GetBytes("---\ntitle: \"bom\"\n---\n\nbody")],
            ["empty.md"] = [],
            ["invalid-utf8.md"] = [0xFF, 0xFE, 0x00, 0x41, 0xC3, 0x28],
            ["legacy.md"] = Encoding.UTF8.GetBytes("---\nid: 02EFF95A-FF15-4719-990A-0A091ABE49F6\ntitle: \"Legacy\"\n---\n\nhello\n\n\n"),
        };
        foreach (var (name, data) in samples) File.WriteAllBytes(Path.Combine(inbox, name), data);

        var store = temp.Open();
        store.LoadAll();
        store.LoadAll();

        foreach (var (name, data) in samples) Assert.Equal(data, File.ReadAllBytes(Path.Combine(inbox, name)));
        Assert.Equal(samples.Count, temp.MarkdownFiles().Count());
        Assert.Contains(store.Notes, n => n.Title == "bom" && n.Content == "body");
    }

    [Fact]
    public void UnreadableFileSurvivesOtherNotesBeingSaved()
    {
        using var temp = new TempStore();
        var garbled = Path.Combine(temp.Store.InboxPath, "2026-01-01_garbled.md");
        byte[] garbage = [0xFF, 0xFE, 0xFD, 0xC3, 0x28];
        File.WriteAllBytes(garbled, garbage);

        for (var i = 0; i < 10; i++) temp.Store.CreateNote($"n{i}", $"c{i}");

        Assert.Equal(garbage, File.ReadAllBytes(garbled));
    }

    [Fact]
    public void CrashLeftoversDoNotBreakOrDuplicateNotes()
    {
        using var temp = new TempStore();
        var note = temp.Store.CreateNote("Survivor", "important");
        var file = note.FilePath!;
        var dir = Path.GetDirectoryName(file)!;

        // Leftovers a crash can leave: temp files from an atomic write, and a copy made halfway through a move
        File.WriteAllText(Path.Combine(dir, $".{Path.GetFileName(file)}.0123456789abcdef.tmp"), "partial");
        File.WriteAllText(Path.Combine(dir, "tmp.md.partial"), "partial");
        temp.Store.CreateProject("Alpha");
        var copy = Path.Combine(temp.Store.ProjectsPath, "Alpha", Path.GetFileName(file));
        File.Copy(file, copy);

        var reloaded = temp.Open();
        Assert.Single(reloaded.Notes);
        Assert.Equal("important", reloaded.Notes[0].Content);
        Assert.True(File.Exists(file));
        Assert.True(File.Exists(copy)); // the loader must not delete the extra copy
    }

    [Fact]
    public void OpeningANoteWithoutMarkersNeverRewritesIt()
    {
        using var temp = new TempStore();
        var note = temp.Store.CreateNote("Plans", "x");
        var written = $"---\nid: {note.IdString}\ntitle: Plans\n---\n\nbuy tomatoes today\n- [x] call bank tomorrow\n";
        File.WriteAllText(note.FilePath!, written);

        var reloaded = temp.Open();

        Assert.Equal(2, reloaded.AgendaItemsFor(reloaded.Notes[0]).Count);
        Assert.Equal(written, File.ReadAllText(note.FilePath!)); // opening a note must not rewrite its file
    }

    [Fact]
    public void ReloadingReadsOnlyTheFilesThatChanged()
    {
        using var temp = new TempStore();
        var first = temp.Store.CreateNote("One", "first");
        temp.Store.CreateNote("Two", "second");
        temp.Store.LoadAll();
        var before = temp.Store.Notes.ToDictionary(n => n.Id);

        File.AppendAllText(first.FilePath!, " edited outside");
        temp.Store.LoadAll();

        var after = temp.Store.Notes.ToDictionary(n => n.Id);
        Assert.Equal("first edited outside", after[first.Id].Content.Trim());
        foreach (var (id, note) in before.Where(p => p.Key != first.Id)) Assert.Same(note, after[id]);
    }

    [Fact]
    public void DeletingOneNoteLeavesAllOthersIntact()
    {
        using var temp = new TempStore();
        var keep = Enumerable.Range(0, 5).Select(i => temp.Store.CreateNote("same title", $"body {i}")).ToList();
        var doomed = temp.Store.CreateNote("same title", "delete me");

        temp.Store.Delete(doomed);

        Assert.Equal(keep.Select(n => n.Content).ToHashSet(), temp.Open().Notes.Select(n => n.Content).ToHashSet());
    }

    [Fact]
    public void SameTitleNotesGetSeparateFiles()
    {
        using var temp = new TempStore();
        for (var i = 0; i < 30; i++) temp.Store.CreateNote("Untitled Note", $"n{i}");

        Assert.Equal(30, temp.MarkdownFiles().Count());
        Assert.Equal(30, temp.Open().Notes.Select(n => n.Content).Distinct().Count());
    }

    [Fact]
    public void ClashingIdPrefixNeverOverwritesAnotherNote()
    {
        using var temp = new TempStore();
        var first = temp.Store.CreateNote("Same", "first");
        // A second note whose short-ID file name is already taken by an unrelated file
        var id = Guid.NewGuid();
        var taken = Path.Combine(temp.Store.InboxPath, FileNames.NoteFileName(new Note { Id = id, Title = "Same" }, 6));
        File.WriteAllText(taken, "someone else's file");

        temp.Store.Save(new Note { Id = id, Title = "Same", Content = "second" });

        Assert.Equal("someone else's file", File.ReadAllText(taken));
        Assert.Equal(["first", "second"], temp.Open().Notes.Select(n => n.Content).Where(c => c != "someone else's file").Order());
        Assert.Equal("first", File.ReadAllText(first.FilePath!)[^5..]);
    }

    [Fact]
    public void LockedFileIsRetriedNotLost()
    {
        using var temp = new TempStore();
        var note = temp.Store.CreateNote("Locked", "v1");
        AtomicFile.RetryDelays = [TimeSpan.FromMilliseconds(100), TimeSpan.FromMilliseconds(300), TimeSpan.FromMilliseconds(600)];

        // A sync client holding the file open briefly, without sharing it
        var holder = new FileStream(note.FilePath!, FileMode.Open, FileAccess.Read, FileShare.None);
        _ = Task.Delay(200).ContinueWith(_ => holder.Dispose());

        Assert.True(temp.Store.Save(note with { Content = "v2" }));
        Assert.Equal("v2", temp.Open().Notes[0].Content);
    }

    [Fact]
    public void ProjectNamesBecomeValidWindowsFolders()
    {
        Assert.Equal("Work- 2026", FileNames.SanitizeFolderName("Work: 2026"));
        Assert.Equal("con_", FileNames.SanitizeFolderName("con"));
        Assert.Equal("LPT1.txt_", FileNames.SanitizeFolderName("LPT1.txt"));
        Assert.Equal("Notes", FileNames.SanitizeFolderName(" Notes. "));
        Assert.Equal("", FileNames.SanitizeFolderName(" ... "));

        using var temp = new TempStore();
        Assert.Equal("Q1-Q2", temp.Store.CreateProject("Q1/Q2"));
        var note = temp.Store.CreateNote("Plan", "x", CategoryType.Project, "Q1/Q2");
        Assert.Equal("Q1-Q2", note.TargetName);
        Assert.Equal(Path.Combine(temp.Store.ProjectsPath, "Q1-Q2"), Path.GetDirectoryName(note.FilePath));
    }

    [Fact]
    public void NoteFileNamesAreValidOnWindows()
    {
        var name = FileNames.NoteFileName(new Note { Title = "a<b>c:d\"e/f\\g|h?i*j\u0001k con" });
        Assert.DoesNotContain(name, ch => "<>:\"/\\|?*".Contains(ch) || ch < 32);
    }
}
