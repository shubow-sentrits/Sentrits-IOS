import Foundation

@MainActor
final class ActivityLogStore: ObservableObject {
    @Published private(set) var log: ActivityLog

    init(maxEntries: Int = 200, seed: [ActivityEvent] = []) {
        log = ActivityLog(entries: seed, maxEntries: maxEntries)
    }

    var entries: [ActivityEvent] {
        log.entries
    }

    func record(
        severity: ActivitySeverity = .info,
        category: ActivityCategory,
        title: String,
        message: String,
        host: SavedHost? = nil,
        hostLabel: String? = nil,
        sessionID: String? = nil,
        timestamp: Date = Date()
    ) {
        let entry = ActivityEvent(
            timestamp: timestamp,
            severity: severity,
            category: category,
            title: title,
            message: message,
            hostLabel: hostLabel ?? host?.displayLabel,
            sessionID: sessionID
        )
        log.record(entry)
    }

    func summary(now: Date = Date(), calendar: Calendar = .current) -> ActivitySummary {
        log.summary(now: now, calendar: calendar)
    }
}
