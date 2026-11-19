using System.Diagnostics;

namespace ScatteredNotes.App.Platform;

/// <summary>Linux desktop integration that doesn't need its own class: desktop entries and the file manager.</summary>
internal static class LinuxDesktop
{
    public static string ConfigHome =>
        Environment.GetEnvironmentVariable("XDG_CONFIG_HOME") is { Length: > 0 } config
            ? config
            : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".config");

    /// <summary>A freedesktop.org desktop entry that runs <paramref name="exe"/>.</summary>
    public static string Entry(string exe, string? argument = null)
    {
        // Exec quoting: the path in double quotes with ", `, $ and \ escaped
        var quoted = "\"" + exe.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("`", "\\`").Replace("$", "\\$") + "\"";
        return $"""
            [Desktop Entry]
            Type=Application
            Name=Scattered Notes
            Comment=Capture notes from anywhere; the Dashboard gathers your to-dos and dates
            Exec={quoted}{(argument is null ? "" : " " + argument)}
            Icon=scattered-notes
            Terminal=false
            Categories=Office;
            StartupWMClass=ScatteredNotes

            """;
    }

    /// <summary>Opens the file manager with the file selected, or the folder when the file manager can't select.</summary>
    public static void Reveal(string path)
    {
        var uri = new Uri(path).AbsoluteUri;
        if (Run("gdbus", "call", "--session", "--dest", "org.freedesktop.FileManager1",
                "--object-path", "/org/freedesktop/FileManager1", "--method", "org.freedesktop.FileManager1.ShowItems",
                $"['{uri.Replace("'", "%27")}']", "")) return;
        var folder = Directory.Exists(path) ? path : Path.GetDirectoryName(path);
        if (folder is not null) Run("xdg-open", folder);
    }

    private static bool Run(string program, params string[] args)
    {
        try
        {
            var info = new ProcessStartInfo(program) { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true };
            foreach (var arg in args) info.ArgumentList.Add(arg);
            using var process = Process.Start(info);
            if (process is null) return false;
            process.StandardOutput.ReadToEnd();
            process.StandardError.ReadToEnd();
            if (!process.WaitForExit(5000)) return true; // still opening; assume it worked
            return process.ExitCode == 0;
        }
        catch (System.ComponentModel.Win32Exception)
        {
            return false;
        }
    }
}
