namespace ScatteredNotes.App;

/// <summary>
/// Keeps one copy of the app running. Starting it again (from the Start menu, say) brings the running copy's
/// window forward instead. Named kernel objects only exist on Windows; elsewhere every launch runs.
/// </summary>
internal sealed class SingleInstance : IDisposable
{
    private const string MutexName = @"Local\ScatteredNotes.SingleInstance";
    private const string ShowEventName = @"Local\ScatteredNotes.Show";

    private readonly Mutex? _mutex;
    private readonly EventWaitHandle? _showEvent;
    private RegisteredWaitHandle? _registration;

    /// <summary>Raised on a thread pool thread when another launch asks this one to show its window.</summary>
    public static event Action? ShowRequested;

    private SingleInstance(Mutex? mutex, EventWaitHandle? showEvent)
    {
        _mutex = mutex;
        _showEvent = showEvent;
        if (showEvent is not null)
            _registration = ThreadPool.RegisterWaitForSingleObject(showEvent, (_, _) => ShowRequested?.Invoke(), null, Timeout.Infinite, executeOnlyOnce: false);
    }

    /// <summary>null when another copy is already running; that copy has been asked to show itself.</summary>
    public static SingleInstance? TryStart()
    {
        if (!OperatingSystem.IsWindows()) return new SingleInstance(null, null);

        var mutex = new Mutex(initiallyOwned: true, MutexName, out var createdNew);
        var showEvent = new EventWaitHandle(false, EventResetMode.AutoReset, ShowEventName);
        if (createdNew) return new SingleInstance(mutex, showEvent);

        showEvent.Set();
        showEvent.Dispose();
        mutex.Dispose();
        return null;
    }

    public void Dispose()
    {
        _registration?.Unregister(null);
        _showEvent?.Dispose();
        _mutex?.Dispose();
    }
}
