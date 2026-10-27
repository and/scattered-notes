using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using ScatteredNotes.Core.Storage;

namespace ScatteredNotes.App.Platform;

public enum HotKeyAction
{
    QuickCapture = 1,
    Search = 2,
}

/// <summary>
/// System-wide shortcuts through Win32 <c>RegisterHotKey</c>. Hot keys belong to the thread that registers
/// them, so a dedicated thread owns them and runs a message loop; other threads post work to it.
/// On other systems nothing is registered and every registration reports failure.
/// </summary>
internal sealed partial class GlobalHotKeys : IDisposable
{
    private const uint WmHotKey = 0x0312;
    private const uint WmApp = 0x8000;
    private const uint WmQuit = 0x0012;
    private const uint ModNoRepeat = 0x4000;

    private readonly ConcurrentQueue<Action> _work = new();
    private readonly Thread? _thread;
    private readonly ManualResetEventSlim _ready = new();
    private uint _threadId;

    /// <summary>Raised on the hot key thread; marshal to the UI thread before touching controls.</summary>
    public event Action<HotKeyAction>? Pressed;

    public GlobalHotKeys()
    {
        if (!OperatingSystem.IsWindows()) return;
        _thread = new Thread(Run) { IsBackground = true, Name = "Global hot keys" };
        _thread.Start();
        _ready.Wait();
    }

    /// <summary>Registers (or re-registers) a shortcut. Returns false when Windows or another app already uses it.</summary>
    public Task<bool> RegisterAsync(HotKeyAction action, HotKeyShortcut shortcut)
    {
        if (_thread is null) return Task.FromResult(false);
        var done = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        Post(() =>
        {
            UnregisterHotKey(IntPtr.Zero, (int)action);
            done.SetResult(shortcut.IsValidGlobal &&
                RegisterHotKey(IntPtr.Zero, (int)action, (uint)shortcut.Modifiers | ModNoRepeat, shortcut.VirtualKey));
        });
        return done.Task;
    }

    public void Unregister(HotKeyAction action) => Post(() => UnregisterHotKey(IntPtr.Zero, (int)action));

    private void Post(Action work)
    {
        _work.Enqueue(work);
        PostThreadMessage(_threadId, WmApp, IntPtr.Zero, IntPtr.Zero);
    }

    private void Run()
    {
        _threadId = GetCurrentThreadId();
        // Creates the thread's message queue before anyone posts to it
        PeekMessage(out _, IntPtr.Zero, 0, 0, 0);
        _ready.Set();
        while (GetMessage(out var msg, IntPtr.Zero, 0, 0) > 0)
        {
            if (msg.message == WmHotKey && Enum.IsDefined(typeof(HotKeyAction), (int)msg.wParam))
                Pressed?.Invoke((HotKeyAction)(int)msg.wParam);
            else if (msg.message == WmApp)
                while (_work.TryDequeue(out var work)) work();
        }
    }

    public void Dispose()
    {
        if (_thread is null) return;
        Post(() =>
        {
            foreach (var action in Enum.GetValues<HotKeyAction>()) UnregisterHotKey(IntPtr.Zero, (int)action);
        });
        PostThreadMessage(_threadId, WmQuit, IntPtr.Zero, IntPtr.Zero);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Msg
    {
        public IntPtr hwnd;
        public uint message;
        public IntPtr wParam;
        public IntPtr lParam;
        public uint time;
        public int ptX;
        public int ptY;
    }

    [LibraryImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [LibraryImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool UnregisterHotKey(IntPtr hWnd, int id);

    [LibraryImport("user32.dll", EntryPoint = "GetMessageW")]
    private static partial int GetMessage(out Msg lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax);

    [LibraryImport("user32.dll", EntryPoint = "PeekMessageW")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool PeekMessage(out Msg lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax, uint wRemoveMsg);

    [LibraryImport("user32.dll", EntryPoint = "PostThreadMessageW")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool PostThreadMessage(uint idThread, uint msg, IntPtr wParam, IntPtr lParam);

    [LibraryImport("kernel32.dll")]
    private static partial uint GetCurrentThreadId();
}
