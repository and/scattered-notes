using Microsoft.Win32;

namespace ScatteredNotes.App.Platform;

/// <summary>Starts the app in the notification area when the user signs in, through the per-user Run key.</summary>
internal static class StartAtLogin
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "Scattered Notes";

    /// <summary>The command line argument used when starting at sign-in: no window, just the tray icon.</summary>
    public const string BackgroundArgument = "--background";

    public static bool IsSupported => OperatingSystem.IsWindows();

    public static void Apply(bool enabled)
    {
        if (!OperatingSystem.IsWindows() || Environment.ProcessPath is not { } exe) return;
        using var key = Registry.CurrentUser.CreateSubKey(RunKey, writable: true);
        if (enabled) key.SetValue(ValueName, $"\"{exe}\" {BackgroundArgument}");
        else key.DeleteValue(ValueName, throwOnMissingValue: false);
    }
}
