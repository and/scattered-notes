using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Platform.Storage;
using FluentIcons.Common;
using ScatteredNotes.App.Platform;
using ScatteredNotes.Core.Storage;

namespace ScatteredNotes.App.Views;

/// <summary>Notes folder, editor font size, global shortcuts and start at sign-in.</summary>
internal sealed class SettingsWindow : Window
{
    private static SettingsWindow? s_open;

    /// <summary>Shortcuts Windows or another app refused, set by the app after registering.</summary>
    public static Dictionary<HotKeyAction, bool> RegistrationResults { get; } = [];

    /// <summary>Set by the app: checks for a new version and shows the result.</summary>
    public static Func<Task>? CheckForUpdates { get; set; }

    /// <summary>Set by the app: registers the shortcuts again after a change.</summary>
    public static Func<Task>? ReapplyHotKeys { get; set; }

    private readonly AppState _state;
    private readonly TextBlock _folder;
    private readonly StackPanel _shortcuts = new() { Spacing = 10 };

    public static void Show(AppState state, Window? owner)
    {
        if (s_open is not null)
        {
            s_open.Activate();
            return;
        }
        s_open = new SettingsWindow(state);
        s_open.Closed += (_, _) => s_open = null;
        if (owner is { IsVisible: true }) s_open.Show(owner);
        else s_open.Show();
    }

    private SettingsWindow(AppState state)
    {
        _state = state;
        Title = "Settings";
        Width = 560;
        SizeToContent = SizeToContent.Height;
        CanResize = false;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        this.Themed(BackgroundProperty, "PaneBackground");

        _folder = new TextBlock { TextWrapping = TextWrapping.Wrap, FontSize = 12, Classes = { "WcagSecondaryText" } };
        var choose = new Button { Content = "Choose Folder…" };
        choose.Click += async (_, _) => await ChooseFolderAsync();
        var openFolder = new Button { Content = OperatingSystem.IsWindows() ? "Open in File Explorer" : "Reveal in Finder" };
        openFolder.Click += (_, _) =>
        {
            if (Directory.Exists(_state.Store.InboxPath)) NoteMenus.RevealFile(_state.Store.InboxPath);
        };
        var folderCard = Card("Notes folder", Symbol.Folder,
            _folder,
            Ui.Row(8, choose, openFolder),
            Note("Changing the folder moves your notes into it. To use the same notes on a Mac, pick your iCloud Drive or OneDrive folder."));

        var fontSize = new NumericUpDown { Minimum = 10, Maximum = 32, Increment = 1, Value = (decimal)_state.Settings.EditorFontSize, FormatString = "0", Width = 130 };
        fontSize.ValueChanged += (_, e) =>
        {
            if (e.NewValue is { } value) _state.Settings.EditorFontSize = (double)value;
        };
        var editorCard = Card("Editor", Symbol.TextFont, Labeled("Font size", fontSize));

        var shortcutsCard = Card("Global shortcuts", Symbol.Keyboard, _shortcuts,
            Note("These work from any app while Scattered Notes runs in the notification area. Use Ctrl, Alt or Win with a key."));

        var startup = new ToggleSwitch { IsChecked = _state.Settings.StartAtLogin, OnContent = "On", OffContent = "Off", IsEnabled = StartAtLogin.IsSupported };
        startup.IsCheckedChanged += (_, _) =>
        {
            _state.Settings.StartAtLogin = startup.IsChecked == true;
            StartAtLogin.Apply(_state.Settings.StartAtLogin);
        };
        var startupCard = Card("Startup", Symbol.Power, Labeled("Start Scattered Notes when you sign in", startup));

        var autoUpdate = new ToggleSwitch { IsChecked = _state.Settings.CheckForUpdates, OnContent = "On", OffContent = "Off" };
        autoUpdate.IsCheckedChanged += (_, _) => _state.Settings.CheckForUpdates = autoUpdate.IsChecked == true;
        var checkNow = new Button { Content = "Check Now" };
        checkNow.Click += async (_, _) =>
        {
            checkNow.IsEnabled = false;
            if (CheckForUpdates is not null) await CheckForUpdates();
            checkNow.IsEnabled = true;
        };
        var lastCheck = _state.Settings.LastUpdateCheck is { } last ? $"Last checked {last.ToLocalTime():g}. " : "";
        var updatesCard = Card("Updates", Symbol.ArrowSync,
            Labeled("Check for updates automatically", autoUpdate),
            Labeled($"Version {Updater.CurrentVersion}", checkNow),
            Note($"{lastCheck}When a new version is out, Scattered Notes shows what changed and asks before installing it."));

        var stack = new StackPanel { Spacing = 14, Margin = new Thickness(20) };
        stack.Children.AddRange([folderCard, editorCard, shortcutsCard, startupCard, updatesCard]);
        Content = new ScrollViewer { Content = stack };

        KeyDown += (_, e) =>
        {
            if (e.Key != Key.Escape || e.Handled) return;
            Close();
            e.Handled = true;
        };
        RefreshFolder();
        RefreshShortcuts();
    }

    private void RefreshFolder() => _folder.Text = _state.Settings.NotesDirectory;

    private void RefreshShortcuts()
    {
        _shortcuts.Children.Clear();
        _shortcuts.Children.Add(ShortcutRow("Quick Capture", HotKeyAction.QuickCapture, _state.Settings.QuickCaptureShortcut, HotKeyShortcut.QuickCaptureDefault,
            s => _state.Settings.QuickCaptureShortcut = s));
        _shortcuts.Children.Add(ShortcutRow("Search all notes", HotKeyAction.Search, _state.Settings.SearchShortcut, HotKeyShortcut.SearchDefault,
            s => _state.Settings.SearchShortcut = s));
    }

    private Control ShortcutRow(string label, HotKeyAction action, HotKeyShortcut current, HotKeyShortcut fallback, Action<HotKeyShortcut> apply)
    {
        var recorder = new ShortcutRecorder(current);
        recorder.Recorded += async shortcut =>
        {
            apply(shortcut);
            if (ReapplyHotKeys is not null) await ReapplyHotKeys();
            RefreshShortcuts();
        };
        var reset = new Button { Content = "Reset", IsEnabled = current != fallback };
        reset.Click += async (_, _) =>
        {
            apply(fallback);
            if (ReapplyHotKeys is not null) await ReapplyHotKeys();
            RefreshShortcuts();
        };

        var row = new StackPanel { Spacing = 4 };
        row.Children.Add(Labeled(label, Ui.Row(8, recorder, reset)));
        if (RegistrationResults.TryGetValue(action, out var ok) && !ok)
        {
            var reason = OperatingSystem.IsWindows()
                ? $"{current.DisplayString} is already used by Windows or another app. Pick another shortcut."
                : "Global shortcuts only work on Windows.";
            row.Children.Add(Ui.Row(6, Ui.Icon(Symbol.Warning, 14, "WcagOrange"), new TextBlock { Text = reason, FontSize = 12, TextWrapping = TextWrapping.Wrap, Classes = { "WcagOrange" } }));
        }
        return row;
    }

    private async Task ChooseFolderAsync()
    {
        var picked = await StorageProvider.OpenFolderPickerAsync(new FolderPickerOpenOptions { Title = "Choose where to keep your notes", AllowMultiple = false });
        if (picked.Count == 0 || picked[0].TryGetLocalPath() is not { } path) return;
        try
        {
            var moved = _state.Store.RelocateStorage(path);
            RefreshFolder();
            await Dialogs.ShowMessageAsync(this, "Notes folder changed", moved == 0
                ? "Scattered Notes now uses this folder."
                : $"Moved {moved} note{(moved == 1 ? "" : "s")} into the new folder.");
        }
        catch (Exception e) when (e is NoteStore.RelocationException or IOException or UnauthorizedAccessException)
        {
            await Dialogs.ShowMessageAsync(this, "Couldn't use that folder", e.Message);
        }
    }

    private static Control Card(string title, Symbol symbol, params Control[] children)
    {
        var stack = new StackPanel { Spacing = 10 };
        stack.Children.Add(Ui.Row(8, Ui.Icon(symbol, 16, "WcagBlue"), Ui.Text(title, 15, FontWeight.SemiBold)));
        stack.Children.AddRange(children);
        return new Border { CornerRadius = new CornerRadius(10), BorderThickness = new Thickness(1), Padding = new Thickness(16), Child = stack }
            .Themed(Border.BackgroundProperty, "CardBackground").Themed(Border.BorderBrushProperty, "CardBorder");
    }

    private static Control Labeled(string label, Control control)
    {
        var row = new DockPanel();
        DockPanel.SetDock(control, Dock.Right);
        row.Children.Add(control);
        row.Children.Add(new TextBlock { Text = label, VerticalAlignment = VerticalAlignment.Center, TextWrapping = TextWrapping.Wrap });
        Avalonia.Automation.AutomationProperties.SetName(control, label);
        return row;
    }

    private static TextBlock Note(string text) =>
        new() { Text = text, FontSize = 12, TextWrapping = TextWrapping.Wrap, Classes = { "WcagSecondaryText" } };
}

/// <summary>A button that records the next key combination pressed.</summary>
internal sealed class ShortcutRecorder : Button
{
    private HotKeyShortcut _shortcut;
    private bool _recording;

    public event Action<HotKeyShortcut>? Recorded;

    protected override Type StyleKeyOverride => typeof(Button);

    public ShortcutRecorder(HotKeyShortcut shortcut)
    {
        _shortcut = shortcut;
        MinWidth = 150;
        Click += (_, _) =>
        {
            _recording = true;
            Refresh();
        };
        LostFocus += (_, _) =>
        {
            _recording = false;
            Refresh();
        };
        Refresh();
    }

    private void Refresh()
    {
        Content = _recording ? "Press a shortcut…" : _shortcut.DisplayString;
        ToolTip.SetTip(this, _recording ? "Press Esc to cancel" : "Click, then press the new shortcut");
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (!_recording)
        {
            base.OnKeyDown(e);
            return;
        }
        e.Handled = true;
        if (e.Key == Key.Escape)
        {
            _recording = false;
            Refresh();
            return;
        }
        if (KeyMap.VirtualKey(e.Key) is not { } vk) return; // a modifier on its own, keep waiting

        var modifiers = HotKeyModifiers.None;
        if (e.KeyModifiers.HasFlag(KeyModifiers.Control)) modifiers |= HotKeyModifiers.Control;
        if (e.KeyModifiers.HasFlag(KeyModifiers.Alt)) modifiers |= HotKeyModifiers.Alt;
        if (e.KeyModifiers.HasFlag(KeyModifiers.Shift)) modifiers |= HotKeyModifiers.Shift;
        if (e.KeyModifiers.HasFlag(KeyModifiers.Meta)) modifiers |= HotKeyModifiers.Windows;
        var shortcut = new HotKeyShortcut(modifiers, vk.Code, vk.Name);
        if (!shortcut.IsValidGlobal) return;

        _recording = false;
        _shortcut = shortcut;
        Refresh();
        Recorded?.Invoke(shortcut);
    }
}

/// <summary>Avalonia keys to Win32 virtual-key codes, for the keys a shortcut can use.</summary>
internal static class KeyMap
{
    public static (uint Code, string Name)? VirtualKey(Key key) => key switch
    {
        >= Key.A and <= Key.Z => ((uint)('A' + (key - Key.A)), ((char)('A' + (key - Key.A))).ToString()),
        >= Key.D0 and <= Key.D9 => ((uint)('0' + (key - Key.D0)), ((char)('0' + (key - Key.D0))).ToString()),
        >= Key.F1 and <= Key.F12 => ((uint)(0x70 + (key - Key.F1)), $"F{key - Key.F1 + 1}"),
        Key.Space => (0x20, "Space"),
        Key.Enter => (0x0D, "Enter"),
        Key.OemComma => (0xBC, ","),
        Key.OemPeriod => (0xBE, "."),
        Key.OemQuestion => (0xBF, "/"),
        Key.OemSemicolon => (0xBA, ";"),
        Key.OemOpenBrackets => (0xDB, "["),
        Key.OemCloseBrackets => (0xDD, "]"),
        _ => null,
    };
}
