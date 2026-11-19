using System.Diagnostics;
using ScatteredNotes.Core.Storage;

namespace ScatteredNotes.App.Platform;

/// <summary>
/// Global shortcuts on Linux. Wayland doesn't let an app grab keys for itself, so the shortcut is added to
/// GNOME as a custom keyboard shortcut (Settings → Keyboard → Custom Shortcuts) that runs this app with
/// <c>--quick-capture</c> or <c>--search</c>. That launch hands the command to the running copy through
/// <see cref="SingleInstance"/>, or starts the app when it isn't running.
/// </summary>
internal static class GnomeShortcuts
{
    private const string ListSchema = "org.gnome.settings-daemon.plugins.media-keys";
    private const string ListKey = "custom-keybindings";
    private const string EntrySchema = "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding";
    private const string PathPrefix = "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/";

    private static readonly Lazy<bool> s_available = new(() => Gsettings("get", ListSchema, ListKey) is not null);

    /// <summary>Whether GNOME's custom shortcuts can be set (gsettings and the schema are present).</summary>
    public static bool IsAvailable => s_available.Value;

    private static string EntryPath(HotKeyAction action) =>
        PathPrefix + (action == HotKeyAction.QuickCapture ? "scattered-notes-capture/" : "scattered-notes-search/");

    /// <summary>Adds or updates the shortcut. False when GNOME isn't available or another custom shortcut already uses the keys.</summary>
    public static bool Register(HotKeyAction action, HotKeyShortcut shortcut)
    {
        if (!IsAvailable || !shortcut.IsValidGlobal || Environment.ProcessPath is not { } exe) return false;
        if (Accelerator(shortcut) is not { } accelerator) return false;

        var path = EntryPath(action);
        var paths = ReadPaths();
        foreach (var other in paths.Where(p => p != path && !p.StartsWith(PathPrefix + "scattered-notes-", StringComparison.Ordinal)))
        {
            if (string.Equals(ParseString(Gsettings("get", $"{EntrySchema}:{other}", "binding")), accelerator, StringComparison.OrdinalIgnoreCase))
                return false;
        }

        var argument = action == HotKeyAction.QuickCapture ? SingleInstance.QuickCaptureArgument : SingleInstance.SearchArgument;
        var name = action == HotKeyAction.QuickCapture ? "Scattered Notes: Quick Capture" : "Scattered Notes: Search";
        // GNOME splits the command like a shell would, so the path is quoted
        var command = $"\"{exe.Replace("\\", "\\\\").Replace("\"", "\\\"")}\" {argument}";
        Gsettings("set", $"{EntrySchema}:{path}", "name", Quote(name));
        Gsettings("set", $"{EntrySchema}:{path}", "command", Quote(command));
        Gsettings("set", $"{EntrySchema}:{path}", "binding", Quote(accelerator));
        if (!paths.Contains(path))
        {
            paths.Add(path);
            Gsettings("set", ListSchema, ListKey, "[" + string.Join(", ", paths.Select(Quote)) + "]");
        }
        return ParseString(Gsettings("get", $"{EntrySchema}:{path}", "binding")) == accelerator;
    }

    public static void Unregister(HotKeyAction action)
    {
        if (!IsAvailable) return;
        var path = EntryPath(action);
        var paths = ReadPaths();
        if (paths.Remove(path))
            Gsettings("set", ListSchema, ListKey, paths.Count == 0 ? "@as []" : "[" + string.Join(", ", paths.Select(Quote)) + "]");
        Gsettings("reset-recursively", $"{EntrySchema}:{path}");
    }

    /// <summary>GTK accelerator text, e.g. "&lt;Control&gt;&lt;Alt&gt;n".</summary>
    internal static string? Accelerator(HotKeyShortcut shortcut)
    {
        var key = shortcut.KeyName switch
        {
            { Length: 1 } k when char.IsAsciiLetter(k[0]) => k.ToLowerInvariant(),
            { Length: 1 } k when char.IsAsciiDigit(k[0]) => k,
            { } k when k.Length is 2 or 3 && k[0] == 'F' && int.TryParse(k[1..], out var n) && n is >= 1 and <= 12 => k,
            "Space" => "space",
            "Enter" => "Return",
            "," => "comma",
            "." => "period",
            "/" => "slash",
            ";" => "semicolon",
            "[" => "bracketleft",
            "]" => "bracketright",
            _ => null,
        };
        if (key is null) return null;
        var text = "";
        if (shortcut.Modifiers.HasFlag(HotKeyModifiers.Windows)) text += "<Super>";
        if (shortcut.Modifiers.HasFlag(HotKeyModifiers.Control)) text += "<Control>";
        if (shortcut.Modifiers.HasFlag(HotKeyModifiers.Alt)) text += "<Alt>";
        if (shortcut.Modifiers.HasFlag(HotKeyModifiers.Shift)) text += "<Shift>";
        return text + key;
    }

    private static List<string> ReadPaths()
    {
        var value = Gsettings("get", ListSchema, ListKey)?.Trim() ?? "";
        if (value.StartsWith("@as", StringComparison.Ordinal)) value = value[3..].Trim();
        return value.Trim('[', ']').Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(ParseString).OfType<string>().ToList();
    }

    /// <summary>A GVariant string literal.</summary>
    private static string Quote(string value) => "'" + value.Replace("\\", "\\\\").Replace("'", "\\'") + "'";

    private static string? ParseString(string? gvariant)
    {
        if (gvariant is null) return null;
        var text = gvariant.Trim();
        if (text.Length >= 2 && (text[0] == '\'' || text[0] == '"') && text[^1] == text[0])
            text = text[1..^1].Replace("\\'", "'").Replace("\\\"", "\"").Replace("\\\\", "\\");
        return text;
    }

    /// <summary>Runs gsettings; null when it fails or isn't installed.</summary>
    private static string? Gsettings(params string[] args)
    {
        try
        {
            var info = new ProcessStartInfo("gsettings") { RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false };
            foreach (var arg in args) info.ArgumentList.Add(arg);
            using var process = Process.Start(info);
            if (process is null) return null;
            var output = process.StandardOutput.ReadToEnd();
            process.StandardError.ReadToEnd();
            process.WaitForExit();
            return process.ExitCode == 0 ? output : null;
        }
        catch (System.ComponentModel.Win32Exception)
        {
            return null; // gsettings not installed
        }
    }
}
