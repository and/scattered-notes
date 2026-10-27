import AppKit
import SwiftUI

public enum AccessibleTheme {
    public static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(NSColor(name: nil, dynamicProvider: { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua])
            return match == .darkAqua ? dark : light
        }))
    }
}

extension Color {
    /// WCAG AA/AAA Accessible Green (Contrast >= 6.7:1 in Light, >= 10:1 in Dark)
    public static let wcagGreen = AccessibleTheme.dynamic(
        light: NSColor(red: 22/255.0, green: 101/255.0, blue: 52/255.0, alpha: 1.0),
        dark: NSColor(red: 74/255.0, green: 222/255.0, blue: 128/255.0, alpha: 1.0)
    )
    
    /// WCAG AA/AAA Accessible Orange (Contrast >= 5.0:1 in Light, >= 7.8:1 in Dark)
    public static let wcagOrange = AccessibleTheme.dynamic(
        light: NSColor(red: 194/255.0, green: 65/255.0, blue: 12/255.0, alpha: 1.0),
        dark: NSColor(red: 251/255.0, green: 146/255.0, blue: 60/255.0, alpha: 1.0)
    )
    
    /// WCAG AA/AAA Accessible Purple (Contrast >= 8.6:1 in Light, >= 7.2:1 in Dark)
    public static let wcagPurple = AccessibleTheme.dynamic(
        light: NSColor(red: 107/255.0, green: 33/255.0, blue: 168/255.0, alpha: 1.0),
        dark: NSColor(red: 192/255.0, green: 132/255.0, blue: 252/255.0, alpha: 1.0)
    )
    
    /// WCAG AA/AAA Accessible Blue (Contrast >= 6.5:1 in Light, >= 7.6:1 in Dark)
    public static let wcagBlue = AccessibleTheme.dynamic(
        light: NSColor(red: 29/255.0, green: 78/255.0, blue: 216/255.0, alpha: 1.0),
        dark: NSColor(red: 96/255.0, green: 165/255.0, blue: 250/255.0, alpha: 1.0)
    )
    
    /// WCAG AA/AAA Secondary Text (Contrast >= 6.0:1 in Light, >= 11:1 in Dark)
    public static let wcagSecondaryText = AccessibleTheme.dynamic(
        light: NSColor(red: 71/255.0, green: 85/255.0, blue: 105/255.0, alpha: 1.0),
        dark: NSColor(red: 203/255.0, green: 213/255.0, blue: 225/255.0, alpha: 1.0)
    )
    
    /// WCAG AA Placeholder Text (Contrast >= 4.5:1 in Light, >= 6.5:1 in Dark)
    public static let wcagPlaceholderText = AccessibleTheme.dynamic(
        light: NSColor(red: 100/255.0, green: 116/255.0, blue: 139/255.0, alpha: 1.0),
        dark: NSColor(red: 148/255.0, green: 163/255.0, blue: 184/255.0, alpha: 1.0)
    )
    
    /// WCAG Non-Text UI Border (Contrast >= 3.0:1)
    public static let wcagBorder = AccessibleTheme.dynamic(
        light: NSColor(red: 148/255.0, green: 163/255.0, blue: 184/255.0, alpha: 1.0),
        dark: NSColor(red: 100/255.0, green: 116/255.0, blue: 139/255.0, alpha: 1.0)
    )
    
    /// Background of the selected note row. White text on it has contrast >= 6.7:1 in Light, >= 9:1 in Dark.
    public static let wcagSelection = AccessibleTheme.dynamic(
        light: NSColor(red: 29/255.0, green: 78/255.0, blue: 216/255.0, alpha: 1.0),
        dark: NSColor(red: 30/255.0, green: 64/255.0, blue: 175/255.0, alpha: 1.0)
    )
    
    /// WCAG Badge Background Tint
    public static let wcagBadgeBackground = AccessibleTheme.dynamic(
        light: NSColor(white: 0.92, alpha: 1.0),
        dark: NSColor(white: 0.22, alpha: 1.0)
    )
}

/// Draws `color` normally, but white where the row sits on the accent colored selection highlight,
/// where the theme's own colors (orange, purple, grey) would lose contrast.
struct ProminenceAwareColor: ViewModifier {
    let color: Color
    @Environment(\.backgroundProminence) private var prominence

    func body(content: Content) -> some View {
        content.foregroundColor(prominence == .increased ? .white : color)
    }
}

extension View {
    func prominenceAwareColor(_ color: Color) -> some View {
        modifier(ProminenceAwareColor(color: color))
    }
}
