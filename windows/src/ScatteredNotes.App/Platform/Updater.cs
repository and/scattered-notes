using System.Diagnostics;
using System.Net.Http.Headers;
using ScatteredNotes.Core.Storage;
using ScatteredNotes.Core.Updates;

namespace ScatteredNotes.App.Platform;

/// <summary>
/// Looks for a newer release on GitHub and, when the user agrees, replaces this exe with the new one and
/// restarts. Windows lets a running exe be renamed, so the old file is moved aside to <c>.old</c>, the
/// download takes its place, and the old file is deleted at the next start.
/// </summary>
internal sealed class Updater
{
    public const string ReleasesApi = "https://api.github.com/repos/and/scattered-notes/releases/latest";
    public const string ReleasesPage = "https://github.com/and/scattered-notes/releases/latest";

    /// <summary>Passed to the new exe so it waits for this copy to quit before taking over.</summary>
    public const string WaitForArgument = "--wait-for";

    private static readonly HttpClient Http = CreateClient();
    private readonly AppSettings _settings;

    public Updater(AppSettings settings) => _settings = settings;

    public static AppVersion CurrentVersion =>
        AppVersion.Parse(typeof(Updater).Assembly.GetName().Version?.ToString(3)) ?? AppVersion.Parse("0")!;

    /// <summary>Whether this copy can replace itself; otherwise the download page is opened.</summary>
    public static bool CanInstallInPlace =>
        OperatingSystem.IsWindows() && Environment.ProcessPath is { } exe &&
        exe.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) && IsWritable(Path.GetDirectoryName(exe)!);

    private static HttpClient CreateClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromMinutes(5) };
        // GitHub rejects API requests without a User-Agent
        client.DefaultRequestHeaders.UserAgent.Add(new ProductInfoHeaderValue("ScatteredNotes", CurrentVersion.ToString()));
        client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
        return client;
    }

    /// <summary>Whether an automatic check is due: the setting is on and a day has passed.</summary>
    public bool IsCheckDue =>
        _settings.CheckForUpdates &&
        (_settings.LastUpdateCheck is not { } last || DateTimeOffset.UtcNow - last > TimeSpan.FromHours(20));

    /// <summary>The newer release to offer, or null. A user-initiated check ignores a skipped version. Throws when GitHub can't be reached.</summary>
    public async Task<Release?> CheckAsync(bool userInitiated)
    {
        var json = await Http.GetStringAsync(ReleasesApi);
        _settings.LastUpdateCheck = DateTimeOffset.UtcNow;
        var release = Release.FromJson(json);
        var skipped = userInitiated ? null : _settings.SkippedVersion;
        return release is not null && release.IsUpdate(CurrentVersion, skipped) ? release : null;
    }

    public void Skip(Release release) => _settings.SkippedVersion = release.TagName;

    /// <summary>
    /// Downloads the new exe next to this one, swaps them, and starts the new one. The caller then quits.
    /// Returns false when this copy can't replace itself and the download page was opened instead.
    /// </summary>
    public static async Task<bool> InstallAsync(Release release, IProgress<double>? progress = null)
    {
        if (!CanInstallInPlace || release.WindowsAsset is not { } asset)
        {
            OpenInBrowser(release.HtmlUrl.Length > 0 ? release.HtmlUrl : ReleasesPage);
            return false;
        }
        var exe = Environment.ProcessPath!;
        var download = exe + ".download";
        var old = exe + ".old";

        using (var response = await Http.GetAsync(asset.DownloadUrl, HttpCompletionOption.ResponseHeadersRead))
        {
            response.EnsureSuccessStatusCode();
            await using var source = await response.Content.ReadAsStreamAsync();
            await using var target = new FileStream(download, FileMode.Create, FileAccess.Write, FileShare.None, 1 << 16, FileOptions.WriteThrough);
            var buffer = new byte[1 << 16];
            long written = 0;
            int read;
            while ((read = await source.ReadAsync(buffer)) > 0)
            {
                await target.WriteAsync(buffer.AsMemory(0, read));
                written += read;
                progress?.Report(asset.Size > 0 ? (double)written / asset.Size : 0);
            }
            await target.FlushAsync();
        }
        if (new FileInfo(download).Length != asset.Size)
        {
            File.Delete(download);
            throw new IOException("The download was incomplete. Try again.");
        }

        if (File.Exists(old)) File.Delete(old);
        File.Move(exe, old);
        try
        {
            File.Move(download, exe);
        }
        catch
        {
            // Put the working copy back rather than leave no app at all
            File.Move(old, exe);
            throw;
        }
        Process.Start(new ProcessStartInfo(exe, $"{WaitForArgument} {Environment.ProcessId}") { UseShellExecute = false });
        return true;
    }

    /// <summary>Removes the previous exe left by an update. Called at startup.</summary>
    public static void CleanUpAfterUpdate()
    {
        if (Environment.ProcessPath is not { } exe) return;
        try
        {
            if (File.Exists(exe + ".old")) File.Delete(exe + ".old");
            if (File.Exists(exe + ".download")) File.Delete(exe + ".download");
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            // Still in use; tried again next start
        }
    }

    public static void OpenInBrowser(string url) => Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });

    private static bool IsWritable(string directory)
    {
        try
        {
            var probe = Path.Combine(directory, $".write-test-{Guid.NewGuid():N}");
            File.WriteAllBytes(probe, []);
            File.Delete(probe);
            return true;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }
}
