import SwiftUI

/// Where the notes live. iCloud Drive, the default when signed in, shares them with the Mac app.
struct SettingsScreen: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var isPicking = false
    @State private var pickFailed = false
    @State private var iCloudFailed = false
    @AppStorage(MorningReminder.enabledKey) private var morningSummary = false
    @AppStorage(MorningReminder.timeKey) private var morningMinutes = MorningReminder.defaultMinutes
    @State private var notificationsDenied = false
    @Environment(\.openURL) private var openURL

    /// The summary's time as a date today, for the time picker
    private var morningTime: Binding<Date> {
        Binding(
            get: { Calendar.current.date(byAdding: .minute, value: morningMinutes, to: Calendar.current.startOfDay(for: Date())) ?? Date() },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                morningMinutes = (parts.hour ?? 8) * 60 + (parts.minute ?? 0)
            })
    }

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
                Section {
                    Toggle("Morning Summary", isOn: $morningSummary)
                    if morningSummary {
                        DatePicker("Time", selection: morningTime, displayedComponents: .hourAndMinute)
                    }
                    if notificationsDenied {
                        Button("Allow Notifications in iOS Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text(notificationsDenied
                         ? "Notifications for Scattered Notes are turned off in iOS Settings."
                         : "One notification each morning with what is planned that day and how many to-dos are overdue. Tap it to open the Dashboard.")
                }
                .onChange(of: morningSummary) { _, on in
                    Task {
                        if on, !(await MorningReminder.requestPermission()) {
                            notificationsDenied = true
                            morningSummary = false
                            return
                        }
                        notificationsDenied = false
                        await MorningReminder.reschedule()
                    }
                }
                .onChange(of: morningMinutes) { _, _ in
                    Task { await MorningReminder.reschedule() }
                }
                Section {
                    let storage = NoteStorageManager.shared
                    let stats = storage.loadStats
                    LabeledContent("Notes", value: "\(storage.notes.count)")
                    LabeledContent("First load", value: "\(Int(stats.firstLoadMilliseconds)) ms")
                    LabeledContent("Loads since launch", value: "\(stats.loadCount), last \(Int(stats.lastLoadMilliseconds)) ms")
                    LabeledContent("Dashboard items", value: "\(Int(stats.agendaMilliseconds)) ms")
                    LabeledContent("Waiting for iCloud", value: "\(ICloudFolder.placeholderCount(in: storage.rootURL)) notes")
                } header: {
                    Text("Diagnostics")
                } footer: {
                    Text("How long the notes took to load on this iPhone. Notes waiting for iCloud are still downloading; the delay is then the download, not the app.")
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
