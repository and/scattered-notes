import SwiftUI

/// Where the notes live. iCloud Drive, the default when signed in, shares them with the Mac app.
struct SettingsScreen: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var isPicking = false
    @State private var pickFailed = false
    @State private var iCloudFailed = false

    private var kind: NotesFolder.Kind { NotesFolder.kind(of: settings.notesDirectoryURL) }

    private var folderName: String {
        switch kind {
        case .iCloud: "iCloud Drive"
        case .picked: settings.notesDirectoryURL.lastPathComponent
        case .onDevice: "On this iPhone"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Folder", value: folderName)
                    if kind != .iCloud {
                        Button("Use iCloud Drive") {
                            Task { iCloudFailed = !(await NotesFolder.useICloud()) }
                        }
                    }
                    Button("Choose Folder…") { isPicking = true }
                    if kind != .onDevice {
                        Button("Use Folder on This iPhone") { NotesFolder.useOnDevice() }
                    }
                } header: {
                    Text("Notes Folder")
                } footer: {
                    Text("iCloud Drive keeps your notes in sync with the Mac app when it also uses iCloud Drive (Settings → Notes Folder → Use iCloud Drive on the Mac). Notes kept on this iPhone move into iCloud Drive when you switch. The folder on this iPhone appears in the Files app under Scattered Notes.")
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
            .alert("iCloud Drive isn't available", isPresented: $iCloudFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Sign in to iCloud and turn on iCloud Drive in the Settings app, then try again.")
            }
        }
    }
}
