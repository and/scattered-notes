using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using ScatteredNotes.App.Platform;
using ScatteredNotes.Core.Updates;

namespace ScatteredNotes.App.Views;

/// <summary>Says a new version is available, shows what is in it, and lets the user decide.</summary>
internal sealed class UpdateWindow : Window
{
    private static UpdateWindow? s_open;

    private readonly AppState _state;
    private readonly Updater _updater;
    private readonly Action _quit;
    private readonly TextBlock _title = new() { FontSize = 18, FontWeight = FontWeight.SemiBold, TextWrapping = TextWrapping.Wrap };
    private readonly TextBlock _subtitle = new() { TextWrapping = TextWrapping.Wrap, Classes = { "WcagSecondaryText" } };
    private readonly Border _notes = new() { BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(8), MinHeight = 200 };
    private readonly StackPanel _buttons = new() { Orientation = Orientation.Horizontal, Spacing = 8, HorizontalAlignment = HorizontalAlignment.Right };
    private readonly ProgressBar _progress = new() { Minimum = 0, Maximum = 1, IsVisible = false };

    /// <summary>Shows a found release, "up to date", or an error message.</summary>
    public static void Show(AppState state, Updater updater, Release? release, string? error, Action quit)
    {
        s_open?.Close();
        s_open = new UpdateWindow(state, updater, quit);
        s_open.Closed += (_, _) => s_open = null;
        s_open.Present(release, error);
        s_open.Show();
        s_open.Activate();
    }

    private UpdateWindow(AppState state, Updater updater, Action quit)
    {
        _state = state;
        _updater = updater;
        _quit = quit;
        Title = "Software Update";
        Width = 560;
        SizeToContent = SizeToContent.Height;
        MaxHeight = 640;
        CanResize = false;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Topmost = true;
        Icon = new WindowIcon(Avalonia.Platform.AssetLoader.Open(new Uri("avares://ScatteredNotes/Assets/AppIcon.ico")));
        this.Themed(BackgroundProperty, "PaneBackground");
        _notes.Themed(Border.BorderBrushProperty, "CardBorder").Themed(Border.BackgroundProperty, "CardBackground");

        var icon = new Image { Width = 56, Height = 56, Source = new Bitmap(Avalonia.Platform.AssetLoader.Open(new Uri("avares://ScatteredNotes/Assets/AppIcon.png"))) };
        var heading = new StackPanel { Spacing = 4 };
        heading.Children.Add(_title);
        heading.Children.Add(_subtitle);
        var top = new DockPanel();
        icon.Margin = new Thickness(0, 0, 14, 0);
        DockPanel.SetDock(icon, Dock.Left);
        top.Children.Add(icon);
        top.Children.Add(heading);

        var automatic = new CheckBox { Content = "Check for updates automatically", IsChecked = state.Settings.CheckForUpdates };
        automatic.IsCheckedChanged += (_, _) => state.Settings.CheckForUpdates = automatic.IsChecked == true;

        var stack = new StackPanel { Spacing = 14, Margin = new Thickness(20) };
        stack.Children.AddRange([top, _notes, _progress, automatic, _buttons]);
        Content = stack;
    }

    private void Present(Release? release, string? error)
    {
        _buttons.Children.Clear();
        _progress.IsVisible = false;
        var current = Updater.CurrentVersion;
        if (error is not null)
        {
            _title.Text = "Couldn't check for updates";
            _subtitle.Text = error;
            _notes.IsVisible = false;
            AddButton("Open Releases Page", () => Updater.OpenInBrowser(Updater.ReleasesPage));
            AddButton("Close", Close, accent: true);
            return;
        }
        if (release is null)
        {
            _title.Text = "Scattered Notes is up to date";
            _subtitle.Text = $"Version {current} is the newest version.";
            _notes.IsVisible = false;
            AddButton("OK", Close, accent: true);
            return;
        }

        _title.Text = $"Scattered Notes {release.Version} is available";
        _subtitle.Text = $"You have version {current}. Your notes are plain files in your notes folder and are not touched by updating.";
        var notes = new MarkdownView(_ => { }) { MaxHeight = 320 };
        notes.Render(release.Notes.Length > 0 ? release.Notes : "No release notes.");
        _notes.Child = new StackPanel { Children = { new TextBlock { Text = "What's new", FontWeight = FontWeight.SemiBold, Margin = new Thickness(24, 14, 24, 0) }, notes } };
        _notes.IsVisible = true;

        AddButton("Skip This Version", () =>
        {
            _updater.Skip(release);
            Close();
        });
        AddButton("Remind Me Later", Close);
        AddButton(Updater.CanInstallInPlace ? "Install and Restart" : "Download", () => _ = InstallAsync(release), accent: true);
    }

    private async Task InstallAsync(Release release)
    {
        foreach (var child in _buttons.Children) child.IsEnabled = false;
        _progress.IsVisible = true;
        _subtitle.Text = "Downloading… Scattered Notes will restart when it's done. Your edits are saved first.";
        try
        {
            if (await Updater.InstallAsync(release, new Progress<double>(p => _progress.Value = p))) _quit();
            else Close();
        }
        catch (Exception e) when (e is IOException or HttpRequestException or UnauthorizedAccessException or TaskCanceledException)
        {
            Present(null, $"The update couldn't be installed: {e.Message}");
        }
    }

    private void AddButton(string label, Action onClick, bool accent = false)
    {
        var button = new Button { Content = label };
        if (accent)
        {
            button.Classes.Add("accent");
            button.IsDefault = true;
        }
        button.Click += (_, _) => onClick();
        _buttons.Children.Add(button);
    }
}
