import AppKit
import SwiftUI

public final class QuickCapturePanel: NSPanel {
    public static let shared = QuickCapturePanel()
    
    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 390),
            styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        
        // Translucent frosted glass effect
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .popover
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 16
        visualEffect.layer?.masksToBounds = true
        
        let hostingView = NSHostingView(rootView: QuickCaptureView(onDismiss: { [weak self] in
            self?.hidePanel()
        }))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        
        visualEffect.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor)
        ])
        
        self.contentView = visualEffect
    }
    
    public override var canBecomeKey: Bool {
        return true
    }
    
    public override var canBecomeMain: Bool {
        return true
    }
    
    public func toggle() {
        if isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }
    
    public func showPanel() {
        // Center on screen where mouse currently is
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let screen = targetScreen {
            let screenRect = screen.visibleFrame
            let x = screenRect.midX - (frame.width / 2)
            let y = screenRect.midY + (screenRect.height * 0.12) // Slightly above center like Spotlight
            setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            center()
        }
        
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }
    
    public func hidePanel() {
        orderOut(nil)
    }
    
    public override func cancelOperation(_ sender: Any?) {
        hidePanel()
    }
}
