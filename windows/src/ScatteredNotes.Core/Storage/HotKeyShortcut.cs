using System.Text.Json.Serialization;

namespace ScatteredNotes.Core.Storage;

/// <summary>Modifier bits, with the values Win32 <c>RegisterHotKey</c> uses.</summary>
[Flags]
public enum HotKeyModifiers : uint
{
    None = 0,
    Alt = 0x1,
    Control = 0x2,
    Shift = 0x4,
    Windows = 0x8,
}

/// <summary>A key plus modifiers that can be registered as a global hot key and shown in menus and settings.</summary>
/// <param name="VirtualKey">Win32 virtual-key code, e.g. 0x4E for N.</param>
/// <param name="KeyName">How the key is shown, e.g. "N" or "F5".</param>
public sealed record HotKeyShortcut(
    [property: JsonPropertyName("modifiers")] HotKeyModifiers Modifiers,
    [property: JsonPropertyName("virtualKey")] uint VirtualKey,
    [property: JsonPropertyName("keyName")] string KeyName)
{
    public static readonly HotKeyShortcut QuickCaptureDefault = new(HotKeyModifiers.Control | HotKeyModifiers.Alt, 0x4E, "N");
    public static readonly HotKeyShortcut SearchDefault = new(HotKeyModifiers.Control | HotKeyModifiers.Alt, 0x46, "F");

    /// <summary>Windows order, e.g. "Ctrl+Alt+N".</summary>
    public string DisplayString
    {
        get
        {
            var parts = new List<string>();
            if (Modifiers.HasFlag(HotKeyModifiers.Windows)) parts.Add("Win");
            if (Modifiers.HasFlag(HotKeyModifiers.Control)) parts.Add("Ctrl");
            if (Modifiers.HasFlag(HotKeyModifiers.Alt)) parts.Add("Alt");
            if (Modifiers.HasFlag(HotKeyModifiers.Shift)) parts.Add("Shift");
            parts.Add(KeyName);
            return string.Join("+", parts);
        }
    }

    /// <summary>
    /// A global shortcut needs Ctrl, Alt or Win: a bare key or Shift+key would stop that key from typing
    /// in every other app.
    /// </summary>
    public bool IsValidGlobal =>
        (Modifiers & (HotKeyModifiers.Control | HotKeyModifiers.Alt | HotKeyModifiers.Windows)) != 0;
}
