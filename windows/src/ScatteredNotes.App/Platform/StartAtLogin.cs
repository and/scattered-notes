using Microsoft.Win32;

namespace ScatteredNotes.App.Platform;

/// <summary>
/// Starts the app in the notification area when the user signs in: through the per-user Run key on Windows,
/// and an XDG autostart entry (<c>~/.config/autostart</c>) on Linux.
/// </summary>
internal static class StartAtLogin
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "Scattered Notes";

    /// <summary>The command line argument used when starting at sign-in: no window, just the tray icon.</summary>
    public const string BackgroundArgument = "--background";

    public static bool IsSupported => OperatingSystem.IsWindows() || OperatingSystem.IsLinux();

    public static void Apply(bool enabled)
    {
        if (Environment.ProcessPath is not { } exe) return;
        if (OperatingSystem.IsWindows())
        {
            using var key = Registry.CurrentUser.CreateSubKey(RunKey, writable: true);
            if (enabled) key.SetValue(ValueName, $"\"{exe}\" {BackgroundArgument}");
            else key.DeleteValue(ValueName, throwOnMissingValue: false);
        }
        else if (OperatingSystem.IsLinux())
        {
            var file = Path.Combine(LinuxDesktop.ConfigHome, "autostart", "scattered-notes.desktop");
            if (!enabled)
            {
                File.Delete(file);
                return;
            }
            Directory.CreateDirectory(Path.GetDirectoryName(file)!);
            File.WriteAllText(file, LinuxDesktop.Entry(exe, BackgroundArgument) + "X-GNOME-Autostart-enabled=true\n");
        }
    }
}
