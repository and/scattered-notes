import Foundation
import Carbon
import AppKit

@MainActor
public final class GlobalHotKeyManager {
    public static let shared = GlobalHotKeyManager()
    
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    public var onHotKeyPressed: (() -> Void)?
    
    private init() {}
    
    public func registerDefaultHotKey() {
        // Register Option + N (kVK_ANSI_N is 45 = 0x2D)
        register(keyCode: UInt32(kVK_ANSI_N), carbonModifiers: UInt32(optionKey))
    }
    
    public func register(keyCode: UInt32, carbonModifiers: UInt32) {
        unregister()
        
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x53434154) // 'SCAT'
        hotKeyID.id = 1
        
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        let handler: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let userData = userData else { return noErr }
            let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                manager.onHotKeyPressed?()
            }
            return noErr
        }
        
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            selfPointer,
            &eventHandler
        )
        
        if status == noErr {
            let regStatus = RegisterEventHotKey(
                keyCode,
                carbonModifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )
            if regStatus != noErr {
                print("Failed to register hotkey: \(regStatus)")
            }
        } else {
            print("Failed to install event handler: \(status)")
        }
    }
    
    public func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }
}
