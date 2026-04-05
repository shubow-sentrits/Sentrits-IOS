import Foundation

enum ActivitySeverity: String, Codable, Hashable {
    case info
    case warning
    case error
}

enum ActivityCategory: String, Codable, Hashable {
    case pairing
    case inventory
    case explorer
    case socket
    case control
    case system
}

struct ActivityEvent: Identifiable, Codable, Hashable {
    let id: UUID
    let timestamp: Date
    let severity: ActivitySeverity
    let category: ActivityCategory
    let title: String
    let message: String
    let hostLabel: String?
    let sessionID: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        severity: ActivitySeverity,
        category: ActivityCategory,
        title: String,
        message: String,
        hostLabel: String? = nil,
        sessionID: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.severity = severity
        self.category = category
        self.title = title
        self.message = message
        self.hostLabel = hostLabel
        self.sessionID = sessionID
    }
}

struct ActivitySummary: Equatable {
    let totalEvents: Int
    let eventsToday: Int
    let warningCount: Int
    let errorCount: Int
    let activeHostCount: Int
}

struct ActivityLog: Equatable {
    private(set) var entries: [ActivityEvent]
    let maxEntries: Int

    init(entries: [ActivityEvent] = [], maxEntries: Int = 200) {
        self.maxEntries = max(1, maxEntries)
        self.entries = Array(entries.sorted { $0.timestamp > $1.timestamp }.prefix(max(1, maxEntries)))
    }

    mutating func record(_ event: ActivityEvent) {
        entries.insert(event, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
    }

    func summary(now: Date = Date(), calendar: Calendar = .current) -> ActivitySummary {
        let startOfToday = calendar.startOfDay(for: now)
        let todayEntries = entries.filter { $0.timestamp >= startOfToday }
        let warningCount = entries.filter { $0.severity == .warning }.count
        let errorCount = entries.filter { $0.severity == .error }.count
        let hostLabels = Set(entries.compactMap(\.hostLabel))
        return ActivitySummary(
            totalEvents: entries.count,
            eventsToday: todayEntries.count,
            warningCount: warningCount,
            errorCount: errorCount,
            activeHostCount: hostLabels.count
        )
    }
}
