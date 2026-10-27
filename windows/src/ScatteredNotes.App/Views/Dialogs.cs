using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;

namespace ScatteredNotes.App.Views;

/// <summary>Small modal dialogs in the Windows 11 content dialog style.</summary>
internal static class Dialogs
{
    private static Window MakeDialog(string title, Control content, Button primary, Button cancel)
    {
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, HorizontalAlignment = HorizontalAlignment.Right };
        buttons.Children.Add(primary);
        buttons.Children.Add(cancel);

        var body = new StackPanel { Spacing = 16, Margin = new Thickness(24) };
        body.Children.Add(Ui.Text(title, 20, FontWeight.SemiBold));
        body.Children.Add(content);
        body.Children.Add(buttons);

        var dialog = new Window
        {
            Title = title,
            Content = body,
            SizeToContent = SizeToContent.WidthAndHeight,
            MinWidth = 380,
            MaxWidth = 520,
            CanResize = false,
            ShowInTaskbar = false,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
        };
        cancel.Click += (_, _) => dialog.Close(false);
        cancel.IsCancel = true;
        primary.IsDefault = true;
        dialog.KeyDown += (_, e) =>
        {
            if (e.Key != Key.Escape) return;
            dialog.Close(false);
            e.Handled = true;
        };
        return dialog;
    }

    public static async Task<bool> ConfirmAsync(Window owner, string title, string message, string confirmLabel)
    {
        var confirm = new Button { Content = confirmLabel, Classes = { "accent" } };
        var dialog = MakeDialog(title, new TextBlock { Text = message, TextWrapping = TextWrapping.Wrap }, confirm, new Button { Content = "Cancel" });
        confirm.Click += (_, _) => dialog.Close(true);
        return await dialog.ShowDialog<bool>(owner);
    }

    /// <summary>Asks for a project or area name and icon. null when cancelled.</summary>
    public static async Task<(string Name, string Icon)?> NewFolderAsync(Window owner, string kind)
    {
        var name = new TextBox { PlaceholderText = $"{kind} name" };
        var icons = new ListBox
        {
            ItemsSource = Ui.PickableIcons,
            SelectedIndex = 0,
            ItemTemplate = new Avalonia.Controls.Templates.FuncDataTemplate<string>((icon, _) => Ui.Icon(Ui.SymbolFor(icon), 20)),
            ItemsPanel = new Avalonia.Controls.Templates.FuncTemplate<Panel?>(() => new WrapPanel()),
            Background = Brushes.Transparent,
        };
        var content = new StackPanel { Spacing = 10 };
        content.Children.Add(name);
        content.Children.Add(Ui.Text("Icon", 12, brushKey: "WcagSecondaryText"));
        content.Children.Add(icons);

        var create = new Button { Content = "Create", Classes = { "accent" }, IsEnabled = false };
        name.TextChanged += (_, _) => create.IsEnabled = !string.IsNullOrWhiteSpace(name.Text);
        var dialog = MakeDialog($"New {kind}", content, create, new Button { Content = "Cancel" });
        (string, string)? result = null;
        create.Click += (_, _) =>
        {
            result = (name.Text!.Trim(), icons.SelectedItem as string ?? "folder.fill");
            dialog.Close(true);
        };
        dialog.Opened += (_, _) => name.Focus();
        await dialog.ShowDialog<bool>(owner);
        return result;
    }

    public static async Task ShowMessageAsync(Window owner, string title, string message)
    {
        var ok = new Button { Content = "OK", Classes = { "accent" } };
        var dialog = MakeDialog(title, new TextBlock { Text = message, TextWrapping = TextWrapping.Wrap }, ok, new Button { Content = "Close", IsVisible = false });
        ok.Click += (_, _) => dialog.Close(true);
        await dialog.ShowDialog<bool>(owner);
    }
}
