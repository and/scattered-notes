using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Documents;
using Avalonia.Layout;
using Avalonia.Media;
using FluentIcons.Avalonia;
using FluentIcons.Common;
using ScatteredNotes.Core.Models;

namespace ScatteredNotes.App;

/// <summary>Small helpers for building views in code.</summary>
internal static class Ui
{
    /// <summary>Binds a property to a theme resource, so it follows light and dark mode.</summary>
    public static T Themed<T>(this T control, AvaloniaProperty property, string resourceKey) where T : Control
    {
        control.Bind(property, control.GetResourceObservable(resourceKey));
        return control;
    }

    public static SymbolIcon Icon(Symbol symbol, double size = 16, string? brushKey = null, IconVariant variant = IconVariant.Regular)
    {
        var icon = new SymbolIcon { Symbol = symbol, FontSize = size, IconVariant = variant };
        // A class rather than a local value, so selected list rows can override it
        if (brushKey is not null) icon.Classes.Add(brushKey);
        return icon;
    }

    public static TextBlock Text(string text, double size = 14, FontWeight weight = FontWeight.Normal, string? brushKey = null, string? classes = null)
    {
        var block = new TextBlock { Text = text, FontSize = size, FontWeight = weight, TextTrimming = TextTrimming.CharacterEllipsis };
        if (classes is not null) block.Classes.Add(classes);
        if (brushKey is not null) block.Classes.Add(brushKey);
        return block;
    }

    public static StackPanel Row(double spacing, params Control[] children)
    {
        var panel = new StackPanel { Orientation = Orientation.Horizontal, Spacing = spacing, VerticalAlignment = VerticalAlignment.Center };
        panel.Children.AddRange(children);
        return panel;
    }

    public static Button IconButton(Symbol symbol, string tip, Action onClick, string? brushKey = "WcagSecondaryText")
    {
        var button = new Button { Content = Icon(symbol, 16, brushKey), Classes = { "icon" } };
        ToolTip.SetTip(button, tip);
        Avalonia.Automation.AutomationProperties.SetName(button, tip);
        button.Click += (_, _) => onClick();
        return button;
    }

    public static string DestinationBrush(CategoryType type) => type switch
    {
        CategoryType.Project => "WcagPurple",
        CategoryType.Area => "WcagGreen",
        _ => "WcagOrange",
    };

    /// <summary>Fluent icon for an SF Symbol name stored by the Mac app.</summary>
    public static Symbol SymbolFor(string sfSymbol) => sfSymbol switch
    {
        "tray.fill" or "tray.2.fill" => Symbol.MailInbox,
        "folder.fill" => Symbol.Folder,
        "square.stack.3d.up.fill" => Symbol.Stack,
        "rocket.fill" => Symbol.Rocket,
        "globe" => Symbol.Globe,
        "iphone" => Symbol.Phone,
        "heart.fill" => Symbol.Heart,
        "book.fill" => Symbol.Book,
        "briefcase.fill" => Symbol.Briefcase,
        "cart.fill" => Symbol.Cart,
        "chart.bar.fill" => Symbol.DataBarVertical,
        "checkmark.seal.fill" => Symbol.CheckmarkStarburst,
        "hammer.fill" => Symbol.Wrench,
        "lightbulb.fill" => Symbol.Lightbulb,
        "square.grid.2x2.fill" => Symbol.Grid,
        "star.fill" => Symbol.Star,
        _ => Symbol.Folder,
    };

    /// <summary>The icons offered when creating a project or area, as SF Symbol names so the Mac app shows them too.</summary>
    public static readonly string[] PickableIcons =
    [
        "folder.fill", "briefcase.fill", "hammer.fill", "lightbulb.fill", "rocket.fill", "star.fill",
        "heart.fill", "book.fill", "cart.fill", "chart.bar.fill", "checkmark.seal.fill", "square.grid.2x2.fill",
    ];

    /// <summary>Adds text with the search terms in bold.</summary>
    public static void AddHighlighted(InlineCollection inlines, string text, IReadOnlyList<string> terms)
    {
        var index = 0;
        while (index < text.Length)
        {
            (int Index, int Length)? next = null;
            foreach (var term in terms.Where(t => !t.StartsWith('#')))
            {
                if (Core.Search.NoteSearch.Find(text, term, index) is { } hit && (next is null || hit.Index < next.Value.Index)) next = hit;
            }
            if (next is not { } match || match.Length == 0)
            {
                inlines.Add(new Run(text[index..]));
                return;
            }
            if (match.Index > index) inlines.Add(new Run(text[index..match.Index]));
            inlines.Add(new Run(text.Substring(match.Index, match.Length)) { FontWeight = FontWeight.Bold });
            index = match.Index + match.Length;
        }
    }
}
