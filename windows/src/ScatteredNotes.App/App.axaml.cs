using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;
using Avalonia.Threading;
using ScatteredNotes.App.Platform;
using ScatteredNotes.App.Views;
using ScatteredNotes.Core.Storage;

namespace ScatteredNotes.App;

public partial class App : Application
{
    private AppState? _state;
    private MainWindow? _main;
    private QuickCaptureWindow? _capture;
    private GlobalHotKeys? _hotKeys;
    private NativeMenuItem? _captureItem;
    private NativeMenuItem? _searchItem;
    private Updater? _updater;
    private DispatcherTimer? _updateTimer;

    public override void Initialize() => AvaloniaXamlLoader.Load(this);

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            // --settings and --notes-folder point a development build at test data instead of the real notes
            var args = desktop.Args ?? [];
            string? Arg(string name) => Array.IndexOf(args, name) is var i and >= 0 && i + 1 < args.Length ? args[i + 1] : null;
            var settings = new AppSettings(Arg("--settings") ?? AppSettings.DefaultSettingsPath, Arg("--notes-folder"));
            var store = new NoteStore(settings);
            _state = new AppState(settings, store) { ShowMainWindow = ShowMain };
            _main = new MainWindow(_state);

            SetUpTrayIcon();
            _hotKeys = new GlobalHotKeys();
            _hotKeys.Pressed += action => Dispatcher.UIThread.Post(() => OnHotKey(action));
            SettingsWindow.ReapplyHotKeys = RegisterHotKeysAsync;
            _ = RegisterHotKeysAsync();
            SingleInstance.ShowRequested += () => Dispatcher.UIThread.Post(ShowMain);

            _updater = new Updater(settings);
            SettingsWindow.CheckForUpdates = () => CheckForUpdatesAsync(userInitiated: true);
            // A few seconds after launch, then hourly; each check only runs when a day has passed
            _updateTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(5) };
            _updateTimer.Tick += (_, _) =>
            {
                _updateTimer.Interval = TimeSpan.FromHours(1);
                if (_updater.IsCheckDue) _ = CheckForUpdatesAsync(userInitiated: false);
            };
            _updateTimer.Start();

            // Keep the Run entry pointing at this copy of the app, which may have moved
            if (settings.StartAtLogin) StartAtLogin.Apply(true);

            desktop.ShutdownRequested += (_, _) => _main.FlushEditor();
            desktop.Exit += (_, _) =>
            {
                _hotKeys.Dispose();
                store.Dispose();
            };

            if (!args.Contains(StartAtLogin.BackgroundArgument)) ShowMain();
            // Development aid for screenshots: open a note whose title contains the text
            if (Arg("--open-note") is { } title && store.Notes.FirstOrDefault(n => n.DisplayTitle.Contains(title, StringComparison.OrdinalIgnoreCase)) is { } note)
                _state.OpenNote(note);
        }
        base.OnFrameworkInitializationCompleted();
    }

    private void ShowMain() => _main?.ShowAndActivate();

    private void ShowCapture()
    {
        if (_state is null) return;
        _capture ??= new QuickCaptureWindow(_state);
        _capture.ShowAndFocus();
    }

    private void ShowSearch()
    {
        if (_state is null) return;
        SearchPalette.Show(_state, _main);
    }

    private void OnHotKey(HotKeyAction action)
    {
        if (action == HotKeyAction.QuickCapture) ShowCapture();
        else ShowSearch();
    }

    private async Task RegisterHotKeysAsync()
    {
        if (_hotKeys is null || _state is null) return;
        var settings = _state.Settings;
        SettingsWindow.RegistrationResults[HotKeyAction.QuickCapture] = await _hotKeys.RegisterAsync(HotKeyAction.QuickCapture, settings.QuickCaptureShortcut);
        SettingsWindow.RegistrationResults[HotKeyAction.Search] = await _hotKeys.RegisterAsync(HotKeyAction.Search, settings.SearchShortcut);
        if (_captureItem is not null) _captureItem.Header = $"Quick Capture\t{settings.QuickCaptureShortcut.DisplayString}";
        if (_searchItem is not null) _searchItem.Header = $"Search All Notes\t{settings.SearchShortcut.DisplayString}";
    }

    /// <summary>Automatic checks stay quiet unless there is something new; a check the user asked for always answers.</summary>
    private async Task CheckForUpdatesAsync(bool userInitiated)
    {
        if (_updater is null || _state is null) return;
        try
        {
            var release = await _updater.CheckAsync(userInitiated);
            if (release is not null || userInitiated) UpdateWindow.Show(_state, _updater, release, null, Quit);
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException)
        {
            if (userInitiated)
                UpdateWindow.Show(_state, _updater, null, "GitHub couldn't be reached. Check your internet connection and try again.", Quit);
        }
    }

    private void SetUpTrayIcon()
    {
        _captureItem = new NativeMenuItem("Quick Capture");
        _captureItem.Click += (_, _) => ShowCapture();
        _searchItem = new NativeMenuItem("Search All Notes");
        _searchItem.Click += (_, _) => ShowSearch();
        var open = new NativeMenuItem("Open Scattered Notes");
        open.Click += (_, _) => ShowMain();
        var settings = new NativeMenuItem("Settings…");
        settings.Click += (_, _) =>
        {
            if (_state is not null) SettingsWindow.Show(_state, _main);
        };
        var updates = new NativeMenuItem("Check for Updates…");
        updates.Click += (_, _) => _ = CheckForUpdatesAsync(userInitiated: true);
        var quit = new NativeMenuItem("Quit Scattered Notes");
        quit.Click += (_, _) => Quit();

        var menu = new NativeMenu();
        menu.Items.Add(open);
        menu.Items.Add(_captureItem);
        menu.Items.Add(_searchItem);
        menu.Items.Add(new NativeMenuItemSeparator());
        menu.Items.Add(settings);
        menu.Items.Add(updates);
        menu.Items.Add(new NativeMenuItemSeparator());
        menu.Items.Add(quit);

        var tray = new TrayIcon
        {
            Icon = new WindowIcon(Avalonia.Platform.AssetLoader.Open(new Uri("avares://ScatteredNotes/Assets/AppIcon.ico"))),
            ToolTipText = "Scattered Notes",
            Menu = menu,
        };
        tray.Clicked += (_, _) => ShowMain();
        TrayIcon.SetIcons(this, [tray]);
    }

    private void Quit()
    {
        _main?.FlushEditor();
        if (_main is not null) _main.AllowClose = true;
        (ApplicationLifetime as IClassicDesktopStyleApplicationLifetime)?.Shutdown();
    }
}
