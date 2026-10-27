using System.Diagnostics;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Documents;
using Avalonia.Layout;
using Avalonia.Media;
using Markdig;
using Markdig.Extensions.TaskLists;
using Markdig.Syntax;
using Markdig.Syntax.Inlines;

namespace ScatteredNotes.App.Views;

/// <summary>
/// Read-only Markdown preview built from native controls, so checkboxes can be clicked to tick items.
/// </summary>
internal sealed class MarkdownView : UserControl
{
    private static readonly MarkdownPipeline Pipeline = new MarkdownPipelineBuilder()
        .UseTaskLists()
        .UseAutoLinks()
        .UseEmphasisExtras()
        .UsePipeTables()
        .Build();

    private readonly Action<int> _onToggleLine;
    private readonly StackPanel _panel = new() { Spacing = 10, Margin = new Thickness(24, 16) };
    private string? _rendered;

    /// <param name="onToggleLine">Called with the source line of a checkbox that was clicked.</param>
    public MarkdownView(Action<int> onToggleLine)
    {
        _onToggleLine = onToggleLine;
        Content = new ScrollViewer { Content = _panel };
    }

    public void Render(string markdown)
    {
        if (markdown == _rendered) return;
        _rendered = markdown;
        _panel.Children.Clear();
        foreach (var block in Markdown.Parse(markdown, Pipeline)) _panel.Children.Add(BlockView(block));
    }

    private Control BlockView(Block block)
    {
        switch (block)
        {
            case HeadingBlock heading:
                var size = heading.Level switch { 1 => 26, 2 => 21, 3 => 17, _ => 15 };
                return Inlines(heading.Inline, size, FontWeight.SemiBold);
            case ParagraphBlock paragraph:
                return Inlines(paragraph.Inline);
            case ListBlock list:
                return ListView(list);
            case FencedCodeBlock or CodeBlock:
                var code = string.Join("\n", ((LeafBlock)block).Lines.Lines.Take(((LeafBlock)block).Lines.Count).Select(l => l.ToString()));
                return new Border
                {
                    Classes = { "badge" },
                    CornerRadius = new CornerRadius(6),
                    Padding = new Thickness(12, 8),
                    Child = new SelectableTextBlock { Text = code, FontFamily = new FontFamily("Cascadia Mono, Consolas, Menlo, monospace"), FontSize = 13, TextWrapping = TextWrapping.Wrap },
                };
            case QuoteBlock quote:
                var inner = new StackPanel { Spacing = 6 };
                foreach (var child in quote) inner.Children.Add(BlockView(child));
                return new Border { BorderThickness = new Thickness(3, 0, 0, 0), Padding = new Thickness(12, 2), Child = inner }
                    .Themed(Border.BorderBrushProperty, "WcagBorder");
            case ThematicBreakBlock:
                return new Border { Height = 1, Margin = new Thickness(0, 4) }.Themed(Border.BackgroundProperty, "CardBorder");
            case ContainerBlock container:
                var stack = new StackPanel { Spacing = 6 };
                foreach (var child in container) stack.Children.Add(BlockView(child));
                return stack;
            case LeafBlock leaf when leaf.Inline is not null:
                return Inlines(leaf.Inline);
            default:
                return new Border();
        }
    }

    private Control ListView(ListBlock list)
    {
        var stack = new StackPanel { Spacing = 4 };
        var number = int.TryParse(list.OrderedStart, out var start) ? start : 1;
        foreach (var item in list.OfType<ListItemBlock>())
        {
            var task = (item.FirstOrDefault() as ParagraphBlock)?.Inline?.FirstChild as TaskList;
            Control marker;
            if (task is not null)
            {
                var line = item.Line;
                var box = new CheckBox { IsChecked = task.Checked, MinWidth = 0, Padding = new Thickness(0), VerticalAlignment = VerticalAlignment.Top };
                box.Click += (_, _) => _onToggleLine(line);
                marker = box;
            }
            else
            {
                marker = new TextBlock { Text = list.IsOrdered ? $"{number}." : "•", MinWidth = 18, Classes = { "WcagSecondaryText" } };
            }
            number++;

            var content = new StackPanel { Spacing = 4, VerticalAlignment = VerticalAlignment.Center };
            foreach (var child in item) content.Children.Add(BlockView(child));
            if (task is { Checked: true }) content.Opacity = 0.7;

            var row = new DockPanel();
            DockPanel.SetDock(marker, Dock.Left);
            marker.Margin = new Thickness(0, 0, 8, 0);
            row.Children.Add(marker);
            row.Children.Add(content);
            stack.Children.Add(row);
        }
        return stack;
    }

    private static SelectableTextBlock Inlines(ContainerInline? container, double size = 15, FontWeight weight = FontWeight.Normal)
    {
        var block = new SelectableTextBlock { FontSize = size, FontWeight = weight, TextWrapping = TextWrapping.Wrap, LineHeight = size * 1.45 };
        if (container is not null) AddInlines(block.Inlines!, container, null);
        return block;
    }

    private static void AddInlines(InlineCollection target, ContainerInline container, Func<Run, Run>? style)
    {
        foreach (var inline in container)
        {
            switch (inline)
            {
                case TaskList:
                    break;
                case LiteralInline literal:
                    target.Add(Styled(new Run(literal.Content.ToString()), style));
                    break;
                case CodeInline code:
                    target.Add(Styled(new Run(code.Content) { FontFamily = new FontFamily("Cascadia Mono, Consolas, Menlo, monospace") }, style));
                    break;
                case LineBreakInline:
                    target.Add(new LineBreak());
                    break;
                case EmphasisInline emphasis:
                    Func<Run, Run> emphasised = emphasis.DelimiterChar == '~'
                        ? run => { run.TextDecorations = TextDecorations.Strikethrough; return run; }
                        : emphasis.DelimiterCount >= 2
                            ? run => { run.FontWeight = FontWeight.Bold; return run; }
                            : run => { run.FontStyle = FontStyle.Italic; return run; };
                    AddInlines(target, emphasis, run => emphasised(style?.Invoke(run) ?? run));
                    break;
                case LinkInline link:
                    var text = new TextBlock { TextDecorations = TextDecorations.Underline, Classes = { "WcagBlue" }, Cursor = new Avalonia.Input.Cursor(Avalonia.Input.StandardCursorType.Hand) };
                    AddInlines(text.Inlines!, link, style);
                    if (text.Inlines!.Count == 0) text.Text = link.Url;
                    var url = link.Url;
                    text.PointerPressed += (_, _) =>
                    {
                        if (url is not null && Uri.TryCreate(url, UriKind.Absolute, out var uri) && uri.Scheme is "http" or "https" or "mailto")
                            Process.Start(new ProcessStartInfo(uri.ToString()) { UseShellExecute = true });
                    };
                    target.Add(new InlineUIContainer(text));
                    break;
                case AutolinkInline autolink:
                    target.Add(Styled(new Run(autolink.Url), style));
                    break;
                case HtmlInline html:
                    target.Add(Styled(new Run(html.Tag), style));
                    break;
                case ContainerInline nested:
                    AddInlines(target, nested, style);
                    break;
            }
        }
    }

    private static Run Styled(Run run, Func<Run, Run>? style) => style?.Invoke(run) ?? run;
}
