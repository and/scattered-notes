import Foundation
import SwiftUI

@MainActor
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()
    
    private let storageKeyNotesDirectory = "settings.notesDirectory"
    private let storageKeyHotKeyKeyCode = "settings.hotKeyKeyCode"
    private let storageKeyHotKeyModifiers = "settings.hotKeyModifiers"
    private let storageKeyDefaultEditorFontSize = "settings.editorFontSize"
    
    @Published public var notesDirectoryURL: URL {
        didSet {
            UserDefaults.standard.set(notesDirectoryURL.path, forKey: storageKeyNotesDirectory)
        }
    }
    
    @Published public var editorFontSize: Double {
        didSet {
            UserDefaults.standard.set(editorFontSize, forKey: storageKeyDefaultEditorFontSize)
        }
    }
    
    public init(notesDirectoryURL: URL? = nil) {
        let defaultDocs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let defaultScatteredNotes = defaultDocs.appendingPathComponent("ScatteredNotes", isDirectory: true)
        
        if let customURL = notesDirectoryURL {
            self.notesDirectoryURL = customURL
        } else if let savedPath = UserDefaults.standard.string(forKey: storageKeyNotesDirectory),
           !savedPath.isEmpty {
            self.notesDirectoryURL = URL(fileURLWithPath: savedPath, isDirectory: true)
        } else {
            self.notesDirectoryURL = defaultScatteredNotes
        }
        
        let savedFontSize = UserDefaults.standard.double(forKey: storageKeyDefaultEditorFontSize)
        self.editorFontSize = savedFontSize > 0 ? savedFontSize : 14.0
    }
    
    public func resetToDefault() {
        let defaultDocs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.notesDirectoryURL = defaultDocs.appendingPathComponent("ScatteredNotes", isDirectory: true)
        self.editorFontSize = 14.0
    }
}
