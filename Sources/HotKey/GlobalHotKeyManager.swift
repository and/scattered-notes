import Foundation
import Carbon
import AppKit

public enum HotKeyAction: UInt32, CaseIterable, Sendable {
    case quickCapture = 1
    case search = 2
}

/// Registers system-wide hot keys that work while another app is frontmost.
@MainActor
public final class GlobalHotKeyManager: ObservableObject {
    public static let shared = GlobalHotKeyManager()

    private var hotKeyRefs: [HotKeyAction: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private var actions: [HotKeyAction: () -> Void] = [:]

    /// Actions whose last registration failed, e.g. because another app already owns the shortcut
    @Published public private(set) var failures: [HotKeyAction: OSStatus] = [:]

    private init() {}

    public func setAction(_ action: HotKeyAction, handler: @escaping () -> Void) {
        actions[action] = handler
    }

    /// Registers `shortcut` for `action`, replacing any earlier one. Returns noErr on success.
    @discardableResult
    public func register(_ action: HotKeyAction, shortcut: HotKeyShortcut) -> OSStatus {
        unregister(action)
        installHandlerIfNeeded()

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x53434154) // 'SCAT'
        hotKeyID.id = action.rawValue

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr, let ref {
            hotKeyRefs[action] = ref
            failures[action] = nil
        } else {
            failures[action] = status
            print("Failed to register \(action) hotkey: \(status)")
        }
        return status
    }

    public func unregister(_ action: HotKeyAction) {
        if let ref = hotKeyRefs.removeValue(forKey: action) {
            UnregisterEventHotKey(ref)
        }
        failures[action] = nil
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handler: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr, let action = HotKeyAction(rawValue: hotKeyID.id) else { return noErr }
            let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                manager.actions[action]?()
            }
            return noErr
        }

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, selfPointer, &eventHandler)
        if status != noErr {
            print("Failed to install event handler: \(status)")
        }
    }
}
