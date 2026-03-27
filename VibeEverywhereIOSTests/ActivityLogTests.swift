import XCTest
@testable import VibeEverywhereIOS

final class ActivityLogTests: XCTestCase {
    func testRecordKeepsMostRecentEntriesWithinBound() {
        var log = ActivityLog(maxEntries: 3)

        log.record(ActivityEvent(timestamp: Date(timeIntervalSince1970: 1), severity: .info, category: .system, title: "1", message: "1"))
        log.record(ActivityEvent(timestamp: Date(timeIntervalSince1970: 2), severity: .info, category: .system, title: "2", message: "2"))
        log.record(ActivityEvent(timestamp: Date(timeIntervalSince1970: 3), severity: .warning, category: .pairing, title: "3", message: "3"))
        log.record(ActivityEvent(timestamp: Date(timeIntervalSince1970: 4), severity: .error, category: .socket, title: "4", message: "4"))

        XCTAssertEqual(log.entries.count, 3)
        XCTAssertEqual(log.entries.map(\.title), ["4", "3", "2"])
    }

    func testSummaryCountsTodayWarningsErrorsAndHosts() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let yesterday = now.addingTimeInterval(-86_400)

        let log = ActivityLog(
            entries: [
                ActivityEvent(timestamp: now, severity: .info, category: .inventory, title: "A", message: "A", hostLabel: "alpha"),
                ActivityEvent(timestamp: now.addingTimeInterval(-60), severity: .warning, category: .pairing, title: "B", message: "B", hostLabel: "alpha"),
                ActivityEvent(timestamp: yesterday, severity: .error, category: .socket, title: "C", message: "C", hostLabel: "beta")
            ],
            maxEntries: 10
        )

        let summary = log.summary(now: now, calendar: calendar)

        XCTAssertEqual(summary.totalEvents, 3)
        XCTAssertEqual(summary.eventsToday, 2)
        XCTAssertEqual(summary.warningCount, 1)
        XCTAssertEqual(summary.errorCount, 1)
        XCTAssertEqual(summary.activeHostCount, 2)
    }
}
