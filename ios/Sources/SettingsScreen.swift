import SwiftUI

/// Where the notes live. Picking the same iCloud Drive folder the Mac app uses shares the notes.
struct SettingsScreen: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var isPicking = false
    @State private var pickFailed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Folder", value: NotesFolder.isCustom ? settings.notesDirectoryURL.lastPathComponent : "On this iPhone")
                    Button("Choose Folder…") { isPicking = true }
                    if NotesFolder.isCustom {
                        Button("Use Folder on This iPhone") { NotesFolder.useDefault() }
                    }
                } header: {
                    Text("Notes Folder")
                } footer: {
                    Text("To see the same notes as on your Mac, choose the folder in iCloud Drive that the Mac app uses (Settings → Notes Folder on the Mac). The folder on this iPhone appears in the Files app under Scattered Notes.")
                }
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                }
            }
            .navigationTitle("Settings")
            .fileImporter(isPresented: $isPicking, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result {
                    pickFailed = !NotesFolder.use(url)
                }
            }
            .alert("Can't open that folder", isPresented: $pickFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Choose a folder in the Files app that Scattered Notes is allowed to open, such as one in iCloud Drive.")
            }
        }
    }
}
