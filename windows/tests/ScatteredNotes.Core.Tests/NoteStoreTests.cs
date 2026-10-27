using ScatteredNotes.Core.Models;
using ScatteredNotes.Core.Storage;

namespace ScatteredNotes.Core.Tests;

/// <summary>Ported from the Mac NoteStorageTests and EndToEndFeatureTests.</summary>
public class NoteStoreTests
{
    [Fact]
    public void SerializationAndParsing()
    {
        var original = new Note
        {
            Title = "Test Note Title",
            Content = "This is test content.\n- [ ] Task 1\n- [x] Task 2",
            CategoryType = CategoryType.Project,
            TargetName = "ScatteredApp",
            Tags = ["swift", "test"],
            IsPinned = true,
        };
        var markdown = NoteFormat.Serialize(original);
        Assert.Contains("title: \"Test Note Title\"", markdown);
        Assert.Contains("type: project", markdown);
        Assert.Contains("target: \"ScatteredApp\"", markdown);
        Assert.Contains("pinned: true", markdown);
        Assert.Contains("tags: [\"swift\", \"test\"]", markdown);

        var parsed = NoteFormat.Parse(markdown);
        Assert.Equal(original.Id, parsed.Id);
        Assert.Equal("Test Note Title", parsed.Title);
        Assert.Equal(CategoryType.Project, parsed.CategoryType);
        Assert.Equal("ScatteredApp", parsed.TargetName);
        Assert.True(parsed.IsPinned);
        Assert.Equal(["swift", "test"], parsed.Tags);
        Assert.Equal(original.Content, parsed.Content);
    }

    [Fact]
    public void ChecklistStats()
    {
        var note = new Note { Content = "My tasks:\n- [ ] Todo item\n- [x] Done item\n* [ ] Another todo\n* [X] Another done" };
        Assert.Equal((2, 4), note.ChecklistStats);
        Assert.Null(new Note { Content = "no tasks" }.ChecklistStats);
    }

    [Fact]
    public void FallbackDisplayTitle()
    {
        Assert.Equal("Meeting with Team", new Note { Content = "# Meeting with Team\nDiscuss roadmap items" }.DisplayTitle);
        Assert.Equal("Quick thought on architecture", new Note { Content = "Quick thought on architecture" }.DisplayTitle);
        Assert.Equal("Untitled Note", new Note { Content = "\n  \n" }.DisplayTitle);
    }

    [Fact]
    public void ProjectAndAreaDirectoryScaffolding()
    {
        using var temp = new TempStore();
        var store = temp.Store;
        Assert.True(Directory.Exists(store.InboxPath));
        Assert.True(Directory.Exists(store.ProjectsPath));
        Assert.True(Directory.Exists(store.AreasPath));

        store.CreateProject("New Project");
        Assert.True(Directory.Exists(Path.Combine(store.ProjectsPath, "New Project")));
        Assert.Equal(["New Project"], store.Projects.Select(p => p.Name));

        var note = store.CreateNote("Roadmap", "Sprint 1 deliverables", CategoryType.Project, "New Project");
        Assert.Single(store.Notes);
        Assert.True(File.Exists(note.FilePath));

        store.Move(note, CategoryType.Inbox, null);
        Assert.Equal(CategoryType.Inbox, store.Notes[0].CategoryType);
        Assert.Equal(store.InboxPath, Path.GetDirectoryName(store.Notes[0].FilePath));

        store.CreateProject("App Project", "rocket.fill");
        Assert.Equal("rocket.fill", store.Projects.Single(p => p.Name == "App Project").IconName);
    }

    [Theory]
    [InlineData("Buy groceries @groceries", "groceries", "Buy groceries")]
    [InlineData("Buy groceries @groceries.", "groceries", "Buy groceries.")]
    [InlineData("@groceries Buy groceries", "groceries", "Buy groceries")]
    [InlineData("Buy @groceries for dinner", "groceries", "Buy for dinner")]
    [InlineData("@groceries: buy milk, eggs", "groceries", "buy milk, eggs")]
    [InlineData("- [ ] Call dentist @health", "health", "- [ ] Call dentist")]
    [InlineData("Contact user@groceries.com for info", "groceries", "Contact user@groceries.com for info")]
    [InlineData("Review PR @MobileApp", "Mobile App", "Review PR")]
    [InlineData("Fix crash +MobileApp #bug", "MobileApp", "Fix crash #bug")]
    [InlineData("Daily jog [[Health]]", "Health", "Daily jog")]
    public void RemoveProjectTagFromContent(string text, string target, string expected)
    {
        Assert.Equal(expected, ProjectTags.Remove(text, target));
    }

    [Fact]
    public void QuickCaptureToInbox()
    {
        using var temp = new TempStore();
        var note = temp.Store.CreateNote("", "Remember to buy coffee beans #groceries", tags: ["groceries"]);

        Assert.Equal(CategoryType.Inbox, note.CategoryType);
        Assert.Equal("Remember to buy coffee beans #groceries", note.DisplayTitle);
        Assert.Equal(temp.Store.InboxPath, Path.GetDirectoryName(note.FilePath));
        var raw = File.ReadAllText(note.FilePath!);
        Assert.Contains("type: inbox", raw);
        Assert.Contains("tags: [\"groceries\"]", raw);
        Assert.Contains("Remember to buy coffee beans #groceries", raw);
    }

    [Fact]
    public void NoteInProjectFolderHasProjectFrontmatter()
    {
        using var temp = new TempStore();
        temp.Store.CreateProject("MobileApp", "iphone");
        var note = temp.Store.CreateNote("Fix navigation freeze", "Investigate crash +MobileApp #bug", CategoryType.Project, "MobileApp", ["bug"]);

        Assert.Equal(Path.Combine(temp.Store.ProjectsPath, "MobileApp"), Path.GetDirectoryName(note.FilePath));
        var raw = File.ReadAllText(note.FilePath!);
        Assert.Contains("type: project", raw);
        Assert.Contains("target: \"MobileApp\"", raw);
    }

    [Fact]
    public void ProjectCustomIconPersists()
    {
        using var temp = new TempStore();
        temp.Store.CreateProject("Stargazer", "rocket.fill");
        Assert.True(File.Exists(Path.Combine(temp.Store.ProjectsPath, "Stargazer", NoteStore.MetadataFileName)));
        Assert.Equal("rocket.fill", temp.Open().Projects.Single(p => p.Name == "Stargazer").IconName);
    }

    [Fact]
    public void PinnedNotesComeFirst()
    {
        using var temp = new TempStore();
        var older = temp.Store.CreateNote("Note 1 (Older)", "Content 1");
        var newer = temp.Store.CreateNote("Note 2 (Newer)", "Content 2");
        Assert.Equal(newer.Id, temp.Store.Notes[0].Id);

        temp.Store.TogglePin(older);

        Assert.Equal(older.Id, temp.Store.Notes[0].Id);
        Assert.True(temp.Store.Notes[0].IsPinned);
    }

    [Fact]
    public void DeletionCleansUpDisk()
    {
        using var temp = new TempStore();
        var note = temp.Store.CreateNote("Temporary Note", "To be deleted");
        Assert.True(File.Exists(note.FilePath));

        temp.Store.Delete(note);

        Assert.Empty(temp.Store.Notes);
        Assert.False(File.Exists(note.FilePath));
    }

    [Fact]
    public void RelocateStorageMovesNotesFromCurrentAndDefaultFolders()
    {
        using var temp = new TempStore();
        var store = temp.Store;
        store.CreateProject("Website", "globe");
        var inboxNote = store.CreateNote("Inbox idea", "Call back tomorrow");
        store.CreateNote("Landing page", "Hero copy", CategoryType.Project, "Website");
        var dayBefore = store.AgendaItemsFor(inboxNote)[0].Date;

        var scratch = Path.Combine(Path.GetTempPath(), "sn-relocate-" + Guid.NewGuid().ToString("N"));
        try
        {
            var defaultInbox = Path.Combine(scratch, "Default", "Inbox");
            Directory.CreateDirectory(defaultInbox);
            File.WriteAllText(Path.Combine(defaultInbox, "2026-01-01_Old-note.md"), NoteFormat.Serialize(new Note { Title = "Old note", Content = "From before" }));
            var newRoot = Path.Combine(scratch, "Chosen");

            var moved = store.RelocateStorage(newRoot, Path.Combine(scratch, "Default"));

            Assert.Equal(3, moved);
            Assert.Equal(Path.GetFullPath(newRoot), temp.Settings.NotesDirectory);
            Assert.Equal(3, store.Notes.Count);
            Assert.Equal("globe", store.Projects.Single().CustomIcon);
            Assert.All(store.Notes, n => Assert.StartsWith(Path.GetFullPath(newRoot), n.FilePath));
            Assert.False(File.Exists(inboxNote.FilePath));
            Assert.False(Directory.Exists(defaultInbox));
            Assert.Equal(dayBefore, store.AgendaItemsFor(store.Notes.Single(n => n.Id == inboxNote.Id))[0].Date);
        }
        finally
        {
            if (Directory.Exists(scratch)) Directory.Delete(scratch, recursive: true);
        }
    }

    [Fact]
    public void RelocateStorageRejectsFolderInsideCurrentFolder()
    {
        using var temp = new TempStore();
        temp.Store.CreateNote("Keep me", "Safe");

        Assert.Throws<NoteStore.RelocationException>(() =>
            temp.Store.RelocateStorage(Path.Combine(temp.Store.InboxPath, "Nested"), Path.Combine(temp.Root, "Default")));
        Assert.Equal(temp.Root, temp.Settings.NotesDirectory);
        Assert.Single(temp.Store.Notes);
    }

    [Fact]
    public void SettingsPersistAcrossLaunches()
    {
        var path = Path.Combine(Path.GetTempPath(), "sn-settings-" + Guid.NewGuid().ToString("N"), "settings.json");
        try
        {
            var settings = new AppSettings(path);
            Assert.Equal(HotKeyShortcut.QuickCaptureDefault, settings.QuickCaptureShortcut);
            Assert.Equal("Ctrl+Alt+N", settings.QuickCaptureShortcut.DisplayString);
            settings.EditorFontSize = 17;
            settings.SearchShortcut = new HotKeyShortcut(HotKeyModifiers.Windows | HotKeyModifiers.Shift, 0x4B, "K");

            var reloaded = new AppSettings(path);
            Assert.Equal(17, reloaded.EditorFontSize);
            Assert.Equal("Win+Shift+K", reloaded.SearchShortcut.DisplayString);

            File.WriteAllText(path, "{ broken");
            Assert.Equal(14, new AppSettings(path).EditorFontSize);
        }
        finally
        {
            Directory.Delete(Path.GetDirectoryName(path)!, recursive: true);
        }
    }
}
