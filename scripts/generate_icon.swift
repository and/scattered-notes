import AppKit

func drawMasterIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }
    
    // Draw macOS Squircle Container
    let margin = size * 0.10
    let squircleRect = CGRect(x: margin, y: margin, width: size - 2 * margin, height: size - 2 * margin)
    let cornerRadius = squircleRect.width * 0.224
    let squirclePath = CGPath(roundedRect: squircleRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    
    // Squircle Drop Shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.03), blur: size * 0.06, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(squirclePath)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    
    // Clip to Squircle
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()
    
    // Gradient Background: Deep Indigo to Vibrant Electric Violet/Blue
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        NSColor(red: 0.11, green: 0.08, blue: 0.30, alpha: 1.0).cgColor, // Deep Midnight Navy
        NSColor(red: 0.22, green: 0.16, blue: 0.55, alpha: 1.0).cgColor, // Rich Indigo
        NSColor(red: 0.35, green: 0.28, blue: 0.85, alpha: 1.0).cgColor  // Vibrant Electric Violet
    ] as CFArray
    let bgLocations: [CGFloat] = [0.0, 0.55, 1.0]
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: bgLocations) {
        ctx.drawLinearGradient(gradient, start: CGPoint(x: squircleRect.midX, y: squircleRect.maxY), end: CGPoint(x: squircleRect.midX, y: squircleRect.minY), options: [])
    }
    
    // Subtle interior border glow
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.18).cgColor)
    ctx.setLineWidth(size * 0.008)
    ctx.addPath(squirclePath)
    ctx.strokePath()
    
    // Draw 3 "Scattered" Floating Note Cards
    // 1. Back Note (Rotated Left)
    ctx.saveGState()
    ctx.translateBy(x: squircleRect.midX - size * 0.06, y: squircleRect.midY - size * 0.02)
    ctx.rotate(by: -12.0 * .pi / 180.0)
    let card1Rect = CGRect(x: -size * 0.24, y: -size * 0.26, width: size * 0.48, height: size * 0.52)
    let card1Path = CGPath(roundedRect: card1Rect, cornerWidth: size * 0.035, cornerHeight: size * 0.035, transform: nil)
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.02), blur: size * 0.04, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    ctx.addPath(card1Path)
    ctx.setFillColor(NSColor(red: 0.95, green: 0.94, blue: 1.0, alpha: 0.35).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    
    // 2. Middle Note (Rotated Right)
    ctx.saveGState()
    ctx.translateBy(x: squircleRect.midX + size * 0.06, y: squircleRect.midY - size * 0.01)
    ctx.rotate(by: 8.0 * .pi / 180.0)
    let card2Rect = CGRect(x: -size * 0.24, y: -size * 0.26, width: size * 0.48, height: size * 0.52)
    let card2Path = CGPath(roundedRect: card2Rect, cornerWidth: size * 0.035, cornerHeight: size * 0.035, transform: nil)
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.025), blur: size * 0.045, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(card2Path)
    ctx.setFillColor(NSColor(red: 0.90, green: 0.92, blue: 1.0, alpha: 0.65).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    
    // 3. Foreground Main Note (Straight / Crisp)
    ctx.saveGState()
    ctx.translateBy(x: squircleRect.midX, y: squircleRect.midY + size * 0.02)
    let mainCardRect = CGRect(x: -size * 0.24, y: -size * 0.26, width: size * 0.48, height: size * 0.52)
    let mainCardPath = CGPath(roundedRect: mainCardRect, cornerWidth: size * 0.04, cornerHeight: size * 0.04, transform: nil)
    
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.035), blur: size * 0.05, color: NSColor.black.withAlphaComponent(0.4).cgColor)
    ctx.addPath(mainCardPath)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()
    
    // Note Card Lines (representing quick thoughts / checklists)
    let lineX = mainCardRect.minX + size * 0.06
    let lineEndX = mainCardRect.maxX - size * 0.06
    let lineY1 = mainCardRect.maxY - size * 0.10
    let lineY2 = mainCardRect.maxY - size * 0.17
    let lineY3 = mainCardRect.maxY - size * 0.24
    let lineY4 = mainCardRect.maxY - size * 0.31
    
    ctx.setLineCap(.round)
    
    // Top Title Bar placeholder
    ctx.setLineWidth(size * 0.016)
    ctx.setStrokeColor(NSColor(red: 0.38, green: 0.35, blue: 0.85, alpha: 0.85).cgColor)
    ctx.strokeLineSegments(between: [CGPoint(x: lineX, y: lineY1), CGPoint(x: lineX + size * 0.20, y: lineY1)])
    
    // Body lines
    ctx.setLineWidth(size * 0.012)
    ctx.setStrokeColor(NSColor(red: 0.75, green: 0.77, blue: 0.85, alpha: 0.7).cgColor)
    ctx.strokeLineSegments(between: [CGPoint(x: lineX, y: lineY2), CGPoint(x: lineEndX, y: lineY2)])
    ctx.strokeLineSegments(between: [CGPoint(x: lineX, y: lineY3), CGPoint(x: lineEndX - size * 0.08, y: lineY3)])
    ctx.strokeLineSegments(between: [CGPoint(x: lineX, y: lineY4), CGPoint(x: lineEndX - size * 0.14, y: lineY4)])
    
    ctx.restoreGState()
    
    // Quick-Capture Lightning Sparkle Emblem on Bottom-Right of Note
    ctx.saveGState()
    let sparkCenter = CGPoint(x: squircleRect.midX + size * 0.16, y: squircleRect.midY - size * 0.16)
    let sparkRadius = size * 0.10
    let sparkCircleRect = CGRect(x: sparkCenter.x - sparkRadius, y: sparkCenter.y - sparkRadius, width: sparkRadius * 2, height: sparkRadius * 2)
    
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.015), blur: size * 0.03, color: NSColor(red: 1.0, green: 0.65, blue: 0.0, alpha: 0.6).cgColor)
    ctx.addEllipse(in: sparkCircleRect)
    
    // Vibrant Orange-Amber Gradient for Quick Action Badge
    let badgeColors = [
        NSColor(red: 1.0, green: 0.75, blue: 0.15, alpha: 1.0).cgColor,
        NSColor(red: 1.0, green: 0.45, blue: 0.08, alpha: 1.0).cgColor
    ] as CFArray
    if let badgeGrad = CGGradient(colorsSpace: colorSpace, colors: badgeColors, locations: [0.0, 1.0]) {
        ctx.saveGState()
        ctx.addEllipse(in: sparkCircleRect)
        ctx.clip()
        ctx.drawLinearGradient(badgeGrad, start: CGPoint(x: sparkCenter.x, y: sparkCircleRect.maxY), end: CGPoint(x: sparkCenter.x, y: sparkCircleRect.minY), options: [])
        ctx.restoreGState()
    }
    
    // White Lightning Bolt inside Badge
    let boltPath = CGMutablePath()
    let bx = sparkCenter.x
    let by = sparkCenter.y
    let bs = sparkRadius * 0.60
    
    boltPath.move(to: CGPoint(x: bx + bs * 0.15, y: by + bs * 0.85))
    boltPath.addLine(to: CGPoint(x: bx - bs * 0.55, y: by - bs * 0.05))
    boltPath.addLine(to: CGPoint(x: bx - bs * 0.05, y: by - bs * 0.05))
    boltPath.addLine(to: CGPoint(x: bx - bs * 0.25, y: by - bs * 0.85))
    boltPath.addLine(to: CGPoint(x: bx + bs * 0.60, y: by + bs * 0.10))
    boltPath.addLine(to: CGPoint(x: bx + bs * 0.08, y: by + bs * 0.10))
    boltPath.closeSubpath()
    
    ctx.addPath(boltPath)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()
    
    ctx.restoreGState()
    
    ctx.restoreGState() // Squircle clip
    image.unlockFocus()
    return image
}

let masterImage = drawMasterIcon(size: 1024)

guard let tiffData = masterImage.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData) else {
    fatalError("Failed to get bitmap")
}

let fileManager = FileManager.default
let iconsetDir = URL(fileURLWithPath: "AppIcon.iconset")
try? fileManager.removeItem(at: iconsetDir)
try! fileManager.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for item in sizes {
    let resized = drawMasterIcon(size: CGFloat(item.px))
    if let tiff = resized.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        let fileURL = iconsetDir.appendingPathComponent(item.name)
        try! png.write(to: fileURL)
    }
}

print("Generated iconset successfully.")
