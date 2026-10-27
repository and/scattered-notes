using Avalonia;

namespace ScatteredNotes.App;

internal static class Program
{
    // Don't use Avalonia or anything that needs a SynchronizationContext before AppMain is called
    [STAThread]
    public static void Main(string[] args)
    {
        // After an update the new exe waits for the old one to quit, which also releases the single-instance lock
        if (Array.IndexOf(args, Platform.Updater.WaitForArgument) is var i and >= 0 && i + 1 < args.Length &&
            int.TryParse(args[i + 1], out var pid))
        {
            try
            {
                System.Diagnostics.Process.GetProcessById(pid).WaitForExit(15000);
            }
            catch (ArgumentException)
            {
                // Already gone
            }
        }
        Platform.Updater.CleanUpAfterUpdate();

        using var instance = SingleInstance.TryStart();
        if (instance is null) return;
        BuildAvaloniaApp().StartWithClassicDesktopLifetime(args, Avalonia.Controls.ShutdownMode.OnExplicitShutdown);
    }

    // Also used by the visual designer
    public static AppBuilder BuildAvaloniaApp() =>
        AppBuilder.Configure<App>()
            .UsePlatformDetect()
            .WithInterFont()
            .LogToTrace();
}
