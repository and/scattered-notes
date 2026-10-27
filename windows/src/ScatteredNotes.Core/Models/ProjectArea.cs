namespace ScatteredNotes.Core.Models;

public enum CategoryType
{
    Inbox,
    Project,
    Area,
}

public static class CategoryTypeExtensions
{
    /// <summary>The value written to the <c>type</c> frontmatter key.</summary>
    public static string RawValue(this CategoryType type) => type switch
    {
        CategoryType.Project => "project",
        CategoryType.Area => "area",
        _ => "inbox",
    };

    public static CategoryType? FromRawValue(string value) => value switch
    {
        "inbox" => CategoryType.Inbox,
        "project" => CategoryType.Project,
        "area" => CategoryType.Area,
        _ => null,
    };

    public static string DisplayName(this CategoryType type) => type switch
    {
        CategoryType.Project => "Projects",
        CategoryType.Area => "Areas",
        _ => "Inbox",
    };

    /// <summary>SF Symbol name, as stored by the Mac app; the Windows UI maps it to a Fluent icon.</summary>
    public static string IconName(this CategoryType type) => type switch
    {
        CategoryType.Project => "folder.fill",
        CategoryType.Area => "square.stack.3d.up.fill",
        _ => "tray.fill",
    };
}

/// <summary>A project or area folder.</summary>
public sealed record ProjectArea(string Name, CategoryType Type, string? CustomIcon = null)
{
    public string Id => $"{Type.RawValue()}:{Name.ToLowerInvariant()}";

    public string IconName => string.IsNullOrEmpty(CustomIcon) ? Type.IconName() : CustomIcon;
}
