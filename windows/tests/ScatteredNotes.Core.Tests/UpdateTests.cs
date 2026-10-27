using System.Text.Json;
using ScatteredNotes.Core.Updates;

namespace ScatteredNotes.Core.Tests;

public class UpdateTests
{
    private static AppVersion V(string text) => AppVersion.Parse(text)!;

    private static Release R(string tag, string[]? assets = null, bool draft = false, bool prerelease = false, string body = "Notes") =>
        Release.FromJson(JsonSerializer.Serialize(new
        {
            tag_name = tag,
            body,
            html_url = $"https://github.com/and/scattered-notes/releases/tag/{tag}",
            draft,
            prerelease,
            assets = (assets ?? ["ScatteredNotes-1.1.1-mac.zip", "ScatteredNotes-1.1.1-windows.exe"])
                .Select(name => new { name, size = 10, browser_download_url = $"https://example.invalid/{name}" }),
        }))!;

    [Fact]
    public void VersionsCompareNumberByNumber()
    {
        Assert.True(V("1.1.1") > V("1.1.0"));
        Assert.True(V("1.10.0") > V("v1.9.0"));
        Assert.Equal(V("1.1"), V("1.1.0"));
        Assert.Null(AppVersion.Parse("1.2.0-beta"));
        Assert.Null(AppVersion.Parse("latest"));
        Assert.Null(AppVersion.Parse(""));
    }

    [Fact]
    public void OnlyNewerPublishedReleasesWithAWindowsDownloadAreOffered()
    {
        var installed = V("1.1.0");
        Assert.True(R("v1.1.1").IsUpdate(installed, null));
        Assert.False(R("v1.1.0").IsUpdate(installed, null));
        Assert.False(R("v1.0.9").IsUpdate(installed, null));
        Assert.False(R("v1.1.1", draft: true).IsUpdate(installed, null));
        Assert.False(R("v1.1.1", prerelease: true).IsUpdate(installed, null));
        Assert.False(R("v1.1.1", ["ScatteredNotes-1.1.1-mac.zip"]).IsUpdate(installed, null));
        Assert.Equal("ScatteredNotes-1.1.1-windows.exe", R("v1.1.1").WindowsAsset?.Name);
    }

    [Fact]
    public void SkippedVersionIsNotOfferedButALaterOneIs()
    {
        Assert.False(R("v1.1.1").IsUpdate(V("1.1.0"), "v1.1.1"));
        Assert.True(R("v1.2.0").IsUpdate(V("1.1.0"), "v1.1.1"));
    }

    [Fact]
    public void NotesDropTheDownloadTable()
    {
        Assert.Equal("Intro\n\n\n### Fixed\n- Sync", R("v1.1.1", body: "Intro\r\n\r\n| A | B |\r\n|---|---|\r\n\r\n### Fixed\r\n- Sync").Notes);
    }

    [Fact]
    public void BadJsonIsNotARelease()
    {
        Assert.Null(Release.FromJson("{ nope"));
    }
}
