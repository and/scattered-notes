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
    private let storageKeyHotKeyKeyCode = "settings.hotKeyKeyCode"
    private let storageKeyHotKeyModifiers = "settings.hotKeyModifiers"
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
    }
    
    public func resetToDefault() {
        self.notesDirectoryURL = Self.defaultNotesDirectoryURL
        self.editorFontSize = 14.0
    }
}
