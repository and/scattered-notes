using System.Text.Json;
using System.Text.Json.Serialization;

namespace ScatteredNotes.Core.Updates;

/// <summary>A version such as "1.1.1", compared number by number. Tags may start with "v".</summary>
public sealed class AppVersion : IComparable<AppVersion>, IEquatable<AppVersion>
{
    public IReadOnlyList<int> Parts { get; }

    private AppVersion(IReadOnlyList<int> parts) => Parts = parts;

    /// <summary>null for text that is not a plain version, including pre-releases such as "1.2.0-beta".</summary>
    public static AppVersion? Parse(string? text)
    {
        var trimmed = (text ?? "").Trim();
        if (trimmed.StartsWith('v') || trimmed.StartsWith('V')) trimmed = trimmed[1..];
        if (trimmed.Length == 0 || trimmed.Contains('-')) return null;
        var parts = new List<int>();
        foreach (var part in trimmed.Split('.'))
        {
            if (!int.TryParse(part, System.Globalization.NumberStyles.None, System.Globalization.CultureInfo.InvariantCulture, out var n)) return null;
            parts.Add(n);
        }
        return new AppVersion(parts);
    }

    public int CompareTo(AppVersion? other)
    {
        if (other is null) return 1;
        for (var i = 0; i < Math.Max(Parts.Count, other.Parts.Count); i++)
        {
            var left = i < Parts.Count ? Parts[i] : 0;
            var right = i < other.Parts.Count ? other.Parts[i] : 0;
            if (left != right) return left.CompareTo(right);
        }
        return 0;
    }

    public bool Equals(AppVersion? other) => CompareTo(other) == 0;
    public override bool Equals(object? obj) => obj is AppVersion other && Equals(other);
    public override int GetHashCode() => string.Join(".", Parts.Reverse().SkipWhile(p => p == 0).Reverse()).GetHashCode();
    public override string ToString() => string.Join(".", Parts);

    public static bool operator >(AppVersion a, AppVersion b) => a.CompareTo(b) > 0;
    public static bool operator <(AppVersion a, AppVersion b) => a.CompareTo(b) < 0;
}

/// <summary>A published GitHub release, as returned by the releases API.</summary>
public sealed class Release
{
    public sealed class Asset
    {
        [JsonPropertyName("name")] public string Name { get; set; } = "";
        [JsonPropertyName("size")] public long Size { get; set; }
        [JsonPropertyName("browser_download_url")] public string DownloadUrl { get; set; } = "";
    }

    [JsonPropertyName("tag_name")] public string TagName { get; set; } = "";
    [JsonPropertyName("name")] public string? Name { get; set; }
    [JsonPropertyName("body")] public string? Body { get; set; }
    [JsonPropertyName("html_url")] public string HtmlUrl { get; set; } = "";
    [JsonPropertyName("draft")] public bool Draft { get; set; }
    [JsonPropertyName("prerelease")] public bool Prerelease { get; set; }
    [JsonPropertyName("assets")] public List<Asset> Assets { get; set; } = [];

    public static Release? FromJson(string json)
    {
        try
        {
            return JsonSerializer.Deserialize<Release>(json);
        }
        catch (JsonException)
        {
            return null;
        }
    }

    public AppVersion? Version => AppVersion.Parse(TagName);

    /// <summary>The Windows download, named <c>ScatteredNotes-&lt;version&gt;-windows.exe</c>.</summary>
    public Asset? WindowsAsset => Assets.FirstOrDefault(a => a.Name.EndsWith("-windows.exe", StringComparison.OrdinalIgnoreCase));

    /// <summary>The release notes without the download table, which only matters on the website.</summary>
    public string Notes => string.Join("\n", (Body ?? "").ReplaceLineEndings("\n").Split('\n')
        .Where(l => !l.TrimStart().StartsWith('|'))).Trim();

    /// <summary>Whether to offer this release to an app running <paramref name="installed"/>, unless the user skipped it.</summary>
    public bool IsUpdate(AppVersion installed, string? skipped)
    {
        if (Draft || Prerelease || Version is not { } version || !(version > installed) || WindowsAsset is null) return false;
        return AppVersion.Parse(skipped) is not { } skip || !skip.Equals(version);
    }
}
