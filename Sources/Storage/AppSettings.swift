import Foundation
import SwiftUI

@MainActor
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()
    
    public static var defaultNotesDirectoryURL: URL {
        let defaultDocs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return defaultDocs.appendingPathComponent("ScatteredNotes", isDirectory: true)
    }
    
    private let storageKeyNotesDirectory = "settings.notesDirectory"
    #if os(macOS)
    private let storageKeyQuickCaptureShortcut = "settings.quickCaptureShortcut"
    private let storageKeySearchShortcut = "settings.searchShortcut"
    #endif
    private let storageKeyDefaultEditorFontSize = "settings.editorFontSize"
    
    // Injected so tests can use an isolated suite instead of the app's real preferences
    private let defaults: UserDefaults
    
    @Published public var notesDirectoryURL: URL {
        didSet {
            defaults.set(notesDirectoryURL.path, forKey: storageKeyNotesDirectory)
        }
    }
    
    @Published public var editorFontSize: Double {
        didSet {
            defaults.set(editorFontSize, forKey: storageKeyDefaultEditorFontSize)
        }
    }
    
    #if os(macOS)
    /// Global shortcut that opens Quick Capture from any app
    @Published public var quickCaptureShortcut: HotKeyShortcut {
        didSet { save(quickCaptureShortcut, forKey: storageKeyQuickCaptureShortcut) }
    }
    
    /// Global shortcut that opens search over all notes from any app
    @Published public var searchShortcut: HotKeyShortcut {
        didSet { save(searchShortcut, forKey: storageKeySearchShortcut) }
    }
    
    private func save(_ shortcut: HotKeyShortcut, forKey key: String) {
        defaults.set(try? JSONEncoder().encode(shortcut), forKey: key)
    }
    
    private static func loadShortcut(from defaults: UserDefaults, key: String, fallback: HotKeyShortcut) -> HotKeyShortcut {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(HotKeyShortcut.self, from: $0) } ?? fallback
    }
    #endif
    
    public init(notesDirectoryURL: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        
        if let customURL = notesDirectoryURL {
            self.notesDirectoryURL = customURL
        } else if let savedPath = defaults.string(forKey: storageKeyNotesDirectory),
           !savedPath.isEmpty {
            self.notesDirectoryURL = URL(fileURLWithPath: savedPath, isDirectory: true)
        } else {
            self.notesDirectoryURL = Self.defaultNotesDirectoryURL
        }
        
        let savedFontSize = defaults.double(forKey: storageKeyDefaultEditorFontSize)
        self.editorFontSize = savedFontSize > 0 ? savedFontSize : 14.0
        #if os(macOS)
        self.quickCaptureShortcut = Self.loadShortcut(from: defaults, key: storageKeyQuickCaptureShortcut, fallback: .quickCaptureDefault)
        self.searchShortcut = Self.loadShortcut(from: defaults, key: storageKeySearchShortcut, fallback: .searchDefault)
        #endif
    }
    
    public func resetToDefault() {
        self.notesDirectoryURL = Self.defaultNotesDirectoryURL
        self.editorFontSize = 14.0
    }
}
