using Avalonia;

namespace ScatteredNotes.App;

internal static class Program
{
    // Don't use Avalonia or anything that needs a SynchronizationContext before AppMain is called
    [STAThread]
    public static void Main(string[] args)
    {
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
