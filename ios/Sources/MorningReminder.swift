import BackgroundTasks
import SwiftUI
import UserNotifications

/// The morning notification: at the time set in Settings, a summary of what is planned that day (see
/// `MorningSummary`). Notifications for the next week are prepared from the notes each time the app is
/// left or the setting changes, and again in the background now and then, so ticks made on the Mac reach
/// the next morning's summary. Tapping one opens the Dashboard.
@MainActor
enum MorningReminder {
    static let enabledKey = "morningSummary.enabled"
    /// Minutes after midnight
    static let timeKey = "morningSummary.minutes"
    static let defaultMinutes = 8 * 60
    /// Days prepared ahead, so the summary still comes when the app isn't opened for a while
    nonisolated static let daysAhead = 7
    static let refreshTaskID = "com.scatterednotes.ios.morningSummary"
    private static let requestPrefix = "morningSummary-"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    static var minutes: Int {
        UserDefaults.standard.object(forKey: timeKey) as? Int ?? defaultMinutes
    }

    /// Asks iOS for permission to notify. False when the person said no, now or earlier.
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default: return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    /// Replaces the prepared notifications with ones worked out from the notes as they are now
    static func reschedule(storage: NoteStorageManager = .shared, now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(requestPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard isEnabled else { return }

        let notes = storage.notes
        let minutes = minutes
        let calendar = Calendar.current
        // Reading every note once for each day takes a moment with many notes, so not on the main thread
        let planned = await Task.detached(priority: .utility) { () -> [(Date, MorningSummary)] in
            let today = calendar.startOfDay(for: now)
            return (0..<daysAhead).compactMap { offset in
                guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                      let at = calendar.date(byAdding: .minute, value: minutes, to: day), at > now,
                      let summary = MorningSummary.make(notes: notes, day: day, calendar: calendar) else { return nil }
                return (at, summary)
            }
        }.value

        for (at, summary) in planned {
            let content = UNMutableNotificationContent()
            content.title = summary.title
            content.body = summary.body
            content.sound = .default
            content.threadIdentifier = "morningSummary"
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: at)
            let request = UNNotificationRequest(
                identifier: requestPrefix + ISO8601DateFormatter.string(from: at, timeZone: .current, formatOptions: [.withFullDate]),
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
            try? await center.add(request)
        }
        scheduleBackgroundRefresh(now: now)
    }

    // MARK: - Background refresh

    /// Called once at launch, before the app finishes launching
    static func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskID, using: .main) { task in
            MainActor.assumeIsolated {
                let work = Task { @MainActor in
                    NoteStorageManager.shared.loadAll()
                    await reschedule()
                    task.setTaskCompleted(success: true)
                }
                task.expirationHandler = { work.cancel() }
            }
        }
    }

    /// Asks iOS to wake the app about an hour before the next summary. iOS decides when, and may not at all.
    private static func scheduleBackgroundRefresh(now: Date) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshTaskID)
        guard isEnabled else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var next = calendar.date(byAdding: .minute, value: minutes - 60, to: today) ?? now
        if next <= now { next = calendar.date(byAdding: .day, value: 1, to: next) ?? now }
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = next
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// Shows the summary while the app is open, and opens the Dashboard when one is tapped
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationRouter()
    static let openDashboard = Notification.Name("ScatteredNotes.openDashboard")

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { NotificationCenter.default.post(name: Self.openDashboard, object: nil) }
    }
}
