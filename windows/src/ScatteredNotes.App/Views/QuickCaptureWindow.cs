using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using FluentIcons.Common;
using ScatteredNotes.Core.Models;

namespace ScatteredNotes.App.Views;

/// <summary>
/// The floating capture window opened by the global shortcut. Type, optionally tag a destination with
/// @Project, +Project or [[Project]], then Ctrl+Enter saves. Esc hides it.
/// </summary>
internal sealed class QuickCaptureWindow : Window
{
    private readonly AppState _state;
    private readonly TextBox _text;
    private readonly DropDownButton _destinationButton;
    private readonly Button _save;
    private Destination _destination = Destination.Inbox;
    private bool _destinationPicked;

    public QuickCaptureWindow(AppState state)
    {
        _state = state;
        Title = "Quick Capture";
        Width = 660;
        Height = 390;
        CanResize = true;
        Topmost = true;
        ShowInTaskbar = false;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Icon = new WindowIcon(Avalonia.Platform.AssetLoader.Open(new Uri("avares://ScatteredNotes/Assets/AppIcon.ico")));
        TransparencyLevelHint = [WindowTransparencyLevel.Mica, WindowTransparencyLevel.None];
        this.Themed(BackgroundProperty, "CardBackground");

        var destinationMenu = new MenuFlyout();
        _destinationButton = new DropDownButton { Padding = new Thickness(10, 4), Flyout = destinationMenu };
        destinationMenu.Opening += (_, _) => FillDestinationMenu(destinationMenu);
        var close = Ui.IconButton(Symbol.Dismiss, "Close (Esc)", Hide);
        var header = new DockPanel { Margin = new Thickness(16, 12, 12, 10) };
        DockPanel.SetDock(close, Dock.Right);
        header.Children.Add(close);
        header.Children.Add(new Border { Child = _destinationButton, HorizontalAlignment = HorizontalAlignment.Left });

        _text = new TextBox
        {
            AcceptsReturn = true,
            AcceptsTab = true,
            NewLine = "\n",
            TextWrapping = TextWrapping.Wrap,
            FontSize = 15,
            LineHeight = 22,
            BorderThickness = new Thickness(0),
            Background = Brushes.Transparent,
            Padding = new Thickness(20, 14),
            VerticalContentAlignment = VerticalAlignment.Top,
            PlaceholderText = "Type a quick note, thought, or checklist…\nTip: +project files it in a project, #tag tags it, @name mentions a person.",
        };
        _text.Resources["TextControlBackgroundFocused"] = Brushes.Transparent;
        _text.Resources["TextControlBackgroundPointerOver"] = Brushes.Transparent;
        Avalonia.Automation.AutomationProperties.SetName(_text, "Quick note");
        _text.TextChanged += (_, _) =>
        {
            if (!_destinationPicked && QuickCapture.DetectDestination(_text.Text ?? "", _state.Store.Projects) is { } detected)
                _destination = detected;
            _save!.IsEnabled = !string.IsNullOrWhiteSpace(_text.Text);
            RefreshDestination();
        };

        _save = new Button { Content = Ui.Row(6, Ui.Icon(Symbol.ArrowCircleUp, 16), new TextBlock { Text = "Save Note" }), Classes = { "accent" }, IsEnabled = false };
        _save.Click += (_, _) => Save();
        var hints = Ui.Row(12, Hint("Esc", "Close"), Hint("+project", "File"), Hint("#tag", "Tag"), Hint("Ctrl+Enter", "Save"));
        var footer = new DockPanel { Margin = new Thickness(16, 10) };
        DockPanel.SetDock(_save, Dock.Right);
        footer.Children.Add(_save);
        footer.Children.Add(hints);

        var root = new DockPanel();
        var headerBorder = new Border { Child = header, BorderThickness = new Thickness(0, 0, 0, 1) }.Themed(Border.BorderBrushProperty, "CardBorder");
        var footerBorder = new Border { Child = footer, BorderThickness = new Thickness(0, 1, 0, 0) }.Themed(Border.BorderBrushProperty, "CardBorder");
        DockPanel.SetDock(headerBorder, Dock.Top);
        DockPanel.SetDock(footerBorder, Dock.Bottom);
        root.Children.Add(headerBorder);
        root.Children.Add(footerBorder);
        root.Children.Add(_text);
        Content = root;

        AddHandler(KeyDownEvent, OnKeyDown, Avalonia.Interactivity.RoutingStrategies.Tunnel);
        Closing += (_, e) =>
        {
            // Keep the window (and any unsaved text) for next time
            e.Cancel = true;
            Hide();
        };
        RefreshDestination();
    }

    public void ShowAndFocus()
    {
        Show();
        Activate();
        _text.Focus();
    }

    private void OnKeyDown(object? sender, KeyEventArgs e)
    {
        var ctrl = e.KeyModifiers.HasFlag(OperatingSystem.IsMacOS() ? KeyModifiers.Meta : KeyModifiers.Control);
        if (e.Key == Key.Escape && !_destinationButton.Flyout!.IsOpen)
        {
            Hide();
            e.Handled = true;
        }
        else if (e.Key == Key.Enter && ctrl)
        {
            Save();
            e.Handled = true;
        }
    }

    private void Save()
    {
        var text = _text.Text ?? "";
        if (string.IsNullOrWhiteSpace(text)) return;

        // A destination typed inline that does not exist yet is created
        var destination = _destination;
        if (destination.Type == CategoryType.Project && destination.Name is { } project &&
            !_state.Store.Projects.Any(p => p.Name.Equals(project, StringComparison.OrdinalIgnoreCase)))
        {
            destination = destination with { Name = _state.Store.CreateProject(project) ?? project };
        }

        var content = QuickCapture.Content(text, destination);
        _state.Store.CreateNote("", content, destination.Type, destination.Name, QuickCapture.Tags(content));
        _text.Text = "";
        _destination = Destination.Inbox;
        _destinationPicked = false;
        RefreshDestination();
        Hide();
    }

    private void RefreshDestination()
    {
        var brush = Ui.DestinationBrush(_destination.Type);
        var icon = _destination.Type switch
        {
            CategoryType.Project => _state.Store.Projects.FirstOrDefault(p => p.Name == _destination.Name)?.IconName ?? "folder.fill",
            _ => "tray.fill",
        };
        _destinationButton.Content = Ui.Row(6, Ui.Icon(Ui.SymbolFor(icon), 14, brush), Ui.Text(_destination.DisplayName, 13, FontWeight.SemiBold, brush));
        Avalonia.Automation.AutomationProperties.SetName(_destinationButton, $"Save to {_destination.DisplayName}");
    }

    private void FillDestinationMenu(MenuFlyout menu)
    {
        menu.Items.Clear();
        void Add(string header, string icon, Destination destination)
        {
            var item = new MenuItem { Header = header, Icon = Ui.Icon(Ui.SymbolFor(icon), 16, Ui.DestinationBrush(destination.Type)) };
            item.Click += (_, _) =>
            {
                _destination = destination;
                _destinationPicked = true;
                RefreshDestination();
            };
            menu.Items.Add(item);
        }
        Add("Inbox", "tray.fill", Destination.Inbox);
        if (_state.Store.Projects.Count > 0) menu.Items.Add(new Separator());
        foreach (var p in _state.Store.Projects) Add(p.Name, p.IconName, new Destination(CategoryType.Project, p.Name));
        menu.Items.Add(new Separator());
        var create = new MenuItem { Header = "New Project…", Icon = Ui.Icon(Symbol.Add) };
        create.Click += async (_, _) =>
        {
            if (await Dialogs.NewFolderAsync(this, "Project") is not { } result) return;
            if (_state.Store.CreateProject(result.Name, result.Icon) is not { } name) return;
            _destination = new Destination(CategoryType.Project, name);
            _destinationPicked = true;
            RefreshDestination();
        };
        menu.Items.Add(create);
    }

    private static Control Hint(string key, string label)
    {
        var keyBox = new Border
        {
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(4),
            Padding = new Thickness(5, 1),
            Child = new TextBlock { Text = key, FontSize = 11, FontWeight = FontWeight.Bold },
        }.Themed(Border.BorderBrushProperty, "WcagBorder");
        return Ui.Row(4, keyBox, Ui.Text(label, 11, FontWeight.Medium, "WcagSecondaryText"));
    }
}
