using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using FluentIcons.Common;
using ScatteredNotes.Core.Agenda;
using ScatteredNotes.Core.Models;

namespace ScatteredNotes.App.Views;

/// <summary>One agenda line with a completion circle, used by the dashboard and the editor's agenda column.</summary>
internal static class AgendaRow
{
    public static Control Build(AgendaItem item, Action onToggle, string? dateLabel = null, Note? note = null,
        Action<Note>? onOpenNote = null, IReadOnlyList<string>? details = null)
    {
        var toggle = new Button
        {
            Classes = { "icon" },
            Padding = new Thickness(2),
            VerticalAlignment = VerticalAlignment.Top,
            Content = Ui.Icon(item.IsDone ? Symbol.CheckmarkCircle : Symbol.Circle, 18,
                item.IsDone ? "WcagGreen" : "WcagSecondaryText", item.IsDone ? IconVariant.Filled : IconVariant.Regular),
        };
        var tip = item.IsDone ? "Mark as not done" : "Mark as done";
        ToolTip.SetTip(toggle, tip);
        Avalonia.Automation.AutomationProperties.SetName(toggle, $"{tip}: {item.Text}");
        toggle.Click += (_, _) => onToggle();

        var text = new SelectableTextBlock
        {
            Text = item.Text,
            TextWrapping = TextWrapping.Wrap,
            VerticalAlignment = VerticalAlignment.Center,
            TextDecorations = item.IsDone ? TextDecorations.Strikethrough : null,
        };
        if (item.IsDone) text.Classes.Add("WcagSecondaryText");

        var middle = new StackPanel { Spacing = 2, VerticalAlignment = VerticalAlignment.Center };
        middle.Children.Add(text);
        foreach (var (detail, index) in (details ?? []).Select((d, i) => (d, i)))
            middle.Children.Add(Ui.Text(detail, 11, index == 0 ? FontWeight.Medium : FontWeight.Normal, index == 0 && details!.Count > 1 ? DetailBrush(detail, item) : "WcagSecondaryText"));

        var row = new DockPanel { Margin = new Thickness(8, 5) };
        DockPanel.SetDock(toggle, Dock.Left);
        row.Children.Add(toggle);

        var trailing = Ui.Row(10);
        if (dateLabel is not null) trailing.Children.Add(Ui.Text(dateLabel, 12, FontWeight.Medium, "WcagOrange"));
        if (note is not null && onOpenNote is not null)
        {
            var link = new Button
            {
                Classes = { "link" },
                Content = new TextBlock { Text = note.DisplayTitle, FontSize = 12, MaxWidth = 160, TextTrimming = TextTrimming.CharacterEllipsis },
            };
            ToolTip.SetTip(link, $"Open \"{note.DisplayTitle}\"");
            link.Click += (_, _) => onOpenNote(note);
            trailing.Children.Add(link);
        }
        if (trailing.Children.Count > 0)
        {
            DockPanel.SetDock(trailing, Dock.Right);
            row.Children.Add(trailing);
        }
        middle.Margin = new Thickness(8, 0, 0, 0);
        row.Children.Add(middle);

        var hover = new Border { CornerRadius = new CornerRadius(8), Child = row, Background = Brushes.Transparent };
        hover.PointerEntered += (_, _) => hover.Themed(Border.BackgroundProperty, "HoverBackground");
        hover.PointerExited += (_, _) => hover.Background = Brushes.Transparent;
        return hover;
    }

    private static string DetailBrush(string label, AgendaItem item) =>
        label.StartsWith("Overdue", StringComparison.Ordinal) && !item.IsDone ? "WcagOrange" : "WcagBlue";
}
