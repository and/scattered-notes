using System.Net.Sockets;
using System.Text;

namespace ScatteredNotes.App;

/// <summary>What a later launch asks the running copy to do.</summary>
internal enum InstanceCommand
{
    Show,
    QuickCapture,
    Search,
}

/// <summary>
/// Keeps one copy of the app running. Starting it again (from the Start menu, say) brings the running copy's
/// window forward instead. On Windows this uses named kernel objects. On Linux a locked file marks the running
/// copy and a Unix socket carries the request, which also lets a desktop shortcut that runs
/// <c>ScatteredNotes --quick-capture</c> open Quick Capture in the running copy. On a Mac every launch runs.
/// </summary>
internal sealed class SingleInstance : IDisposable
{
    public const string QuickCaptureArgument = "--quick-capture";
    public const string SearchArgument = "--search";

    private const string MutexName = @"Local\ScatteredNotes.SingleInstance";
    private const string ShowEventName = @"Local\ScatteredNotes.Show";

    private readonly Mutex? _mutex;
    private readonly EventWaitHandle? _showEvent;
    private readonly RegisteredWaitHandle? _registration;
    private readonly FileStream? _lock;
    private readonly Socket? _listener;
    private readonly string? _socketPath;

    /// <summary>Raised on a background thread when another launch asks this one to do something.</summary>
    public static event Action<InstanceCommand>? CommandReceived;

    private SingleInstance(Mutex mutex, EventWaitHandle showEvent)
    {
        _mutex = mutex;
        _showEvent = showEvent;
        _registration = ThreadPool.RegisterWaitForSingleObject(showEvent, (_, _) => CommandReceived?.Invoke(InstanceCommand.Show), null, Timeout.Infinite, executeOnlyOnce: false);
    }

    private SingleInstance(FileStream fileLock, Socket listener, string socketPath)
    {
        _lock = fileLock;
        _listener = listener;
        _socketPath = socketPath;
        new Thread(Listen) { IsBackground = true, Name = "Single instance" }.Start();
    }

    private SingleInstance()
    {
    }

    /// <summary>The command a launch with these arguments asks for.</summary>
    public static InstanceCommand CommandFor(string[] args) =>
        args.Contains(QuickCaptureArgument) ? InstanceCommand.QuickCapture :
        args.Contains(SearchArgument) ? InstanceCommand.Search :
        InstanceCommand.Show;

    /// <summary>null when another copy is already running; that copy has been passed the launch's command.</summary>
    public static SingleInstance? TryStart(string[] args)
    {
        if (OperatingSystem.IsWindows()) return TryStartWindows();
        if (OperatingSystem.IsLinux()) return TryStartLinux(CommandFor(args));
        return new SingleInstance();
    }

    private static SingleInstance? TryStartWindows()
    {
        var mutex = new Mutex(initiallyOwned: true, MutexName, out var createdNew);
        var showEvent = new EventWaitHandle(false, EventResetMode.AutoReset, ShowEventName);
        if (createdNew) return new SingleInstance(mutex, showEvent);

        showEvent.Set();
        showEvent.Dispose();
        mutex.Dispose();
        return null;
    }

    private static SingleInstance? TryStartLinux(InstanceCommand command)
    {
        var directory = RuntimeDirectory();
        var lockPath = Path.Combine(directory, "scattered-notes.lock");
        var socketPath = Path.Combine(directory, "scattered-notes.sock");

        FileStream fileLock;
        try
        {
            // .NET takes an exclusive flock for FileShare.None, which the kernel drops if this process dies
            fileLock = new FileStream(lockPath, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
        }
        catch (IOException)
        {
            // Another copy holds the lock. Pass the command on; it may still be starting, so retry briefly.
            for (var attempt = 0; attempt < 20; attempt++)
            {
                if (TrySend(socketPath, command)) return null;
                Thread.Sleep(100);
            }
            return null;
        }

        if (File.Exists(socketPath)) File.Delete(socketPath); // left by a copy that crashed
        var listener = new Socket(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified);
        listener.Bind(new UnixDomainSocketEndPoint(socketPath));
        listener.Listen(4);
        return new SingleInstance(fileLock, listener, socketPath);
    }

    /// <summary>$XDG_RUNTIME_DIR is private to the user and cleared at logout; ~/.cache is the fallback.</summary>
    private static string RuntimeDirectory()
    {
        var runtime = Environment.GetEnvironmentVariable("XDG_RUNTIME_DIR");
        if (!string.IsNullOrEmpty(runtime) && Directory.Exists(runtime)) return runtime;
        var cache = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".cache", "scattered-notes");
        Directory.CreateDirectory(cache);
        return cache;
    }

    private static bool TrySend(string socketPath, InstanceCommand command)
    {
        try
        {
            using var socket = new Socket(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified);
            socket.Connect(new UnixDomainSocketEndPoint(socketPath));
            socket.Send(Encoding.UTF8.GetBytes(command.ToString() + "\n"));
            return true;
        }
        catch (SocketException)
        {
            return false;
        }
    }

    private void Listen()
    {
        while (true)
        {
            Socket client;
            try
            {
                client = _listener!.Accept();
            }
            catch (Exception e) when (e is SocketException or ObjectDisposedException)
            {
                return; // closed at quit
            }
            using (client)
            {
                try
                {
                    client.ReceiveTimeout = 2000;
                    var buffer = new byte[64];
                    var read = client.Receive(buffer);
                    var text = Encoding.UTF8.GetString(buffer, 0, read).Trim();
                    CommandReceived?.Invoke(Enum.TryParse<InstanceCommand>(text, out var command) ? command : InstanceCommand.Show);
                }
                catch (SocketException)
                {
                    // The other launch gave up; nothing to do
                }
            }
        }
    }

    public void Dispose()
    {
        _registration?.Unregister(null);
        _showEvent?.Dispose();
        _mutex?.Dispose();
        _listener?.Dispose();
        if (_socketPath is not null)
        {
            try
            {
                File.Delete(_socketPath);
            }
            catch (IOException)
            {
                // Removed at the next start instead
            }
        }
        _lock?.Dispose();
    }
}
