import AppKit
import SwiftUI

public final class QuickCapturePanel: NSPanel {
    /// Panels on screen, oldest first. Each use of the shortcut opens a new one, so several notes can be started side by side.
    private static var open: [QuickCapturePanel] = []
    /// Links a panel to its view, which files its own note when the panel closes
    let token = UUID()

    /// Smallest the panel can be dragged to: only enough to still grab it, like a text editor's window
    static let minimumSize = NSSize(width: 60, height: 40)

    /// Opens a new Quick Note panel: where the last one was left, or beside the newest one already open
    public static func present() {
        let panel = QuickCapturePanel()
        panel.showPanel(besides: open.last)
        open.append(panel)
    }

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 390),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView],
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
        
        let hostingView = NSHostingView(rootView: QuickCaptureView(token: token, onDismiss: { [weak self] in
            self?.hidePanel()
        }))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        // The view's own minimum size must not stop the window from being dragged smaller
        hostingView.sizingOptions = []
        
        visualEffect.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor)
        ])
        
        self.contentView = visualEffect

        // The panel can be resized; the size and place of the first one are kept between uses and launches
        contentMinSize = Self.minimumSize
        if let saved = UserDefaults.standard.string(forKey: Self.frameKey) {
            let rect = NSRectFromString(saved)
            if rect.width >= Self.minimumSize.width, rect.height >= Self.minimumSize.height,
               NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) {
                setFrame(rect, display: false)
                hasSavedFrame = true
            }
        }
        for name in [NSWindow.didMoveNotification, NSWindow.didEndLiveResizeNotification] {
            NotificationCenter.default.addObserver(forName: name, object: self, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rememberFrame() }
            }
        }
    }

    private static let frameKey = "QuickCapturePanelFrame"
    /// Whether the person has placed or sized the panel before: then it opens where they left it
    private var hasSavedFrame = false

    /// Only the first panel on screen sets where the next one starts
    private func rememberFrame() {
        guard isVisible, Self.open.first === self || Self.open.isEmpty else { return }
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: Self.frameKey)
    }

    public override var canBecomeKey: Bool {
        return true
    }
    
    public override var canBecomeMain: Bool {
        return true
    }
    
    private func showPanel(besides other: QuickCapturePanel?) {
        if let other, other.isVisible {
            // Another note is open: start this one a little down and to the right of it
            setFrameOrigin(NSPoint(x: other.frame.minX + 28, y: other.frame.minY - 28))
        } else if !hasSavedFrame {
            // First use: centre on the screen where the mouse is
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
        }
        // Keep the new panel on a screen, even when stacked far down
        if let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) }) ?? NSScreen.main,
           !screen.visibleFrame.contains(NSPoint(x: frame.minX + 40, y: frame.maxY - 40)) {
            setFrameOrigin(NSPoint(x: screen.visibleFrame.minX + 60, y: screen.visibleFrame.maxY - frame.height - 60))
        }

        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }

    /// Posted just before the panel hides, so Quick Note can finish an auto-saved note
    public static let willHideNotification = Notification.Name("QuickCapturePanel.willHide")

    public func hidePanel() {
        NotificationCenter.default.post(name: Self.willHideNotification, object: self, userInfo: ["token": token])
        rememberFrame()
        orderOut(nil)
        Self.open.removeAll { $0 === self }
    }
    
    /// The red button closes like Esc does: the note is filed, and the panel goes
    public override func performClose(_ sender: Any?) {
        hidePanel()
    }

    public override func close() {
        hidePanel()
    }

    public override func cancelOperation(_ sender: Any?) {
        hidePanel()
    }
}
