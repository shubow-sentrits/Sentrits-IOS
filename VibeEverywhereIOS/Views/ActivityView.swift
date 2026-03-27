import SwiftUI

struct ActivityView: View {
    @ObservedObject var activityStore: ActivityLogStore

    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                summaryCards
                activitySections
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(ActivityPalette.background.ignoresSafeArea())
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.large)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("System Stream")
                .font(.system(.footnote, design: .monospaced).weight(.medium))
                .foregroundStyle(ActivityPalette.secondary)
                .textCase(.uppercase)
            Text("Activity")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(ActivityPalette.foreground)
            Text("Important client and session events, trimmed to the signal you actually need.")
                .font(.callout)
                .foregroundStyle(ActivityPalette.muted)
        }
    }

    private var summaryCards: some View {
        let summary = activityStore.summary(calendar: calendar)
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            ActivitySummaryCard(title: "Total Events", value: "\(summary.totalEvents)", tint: ActivityPalette.primary)
            ActivitySummaryCard(title: "Today", value: "\(summary.eventsToday)", tint: ActivityPalette.foreground)
            ActivitySummaryCard(title: "Warnings", value: "\(summary.warningCount)", tint: ActivityPalette.warning)
            ActivitySummaryCard(title: "Active Hosts", value: "\(summary.activeHostCount)", tint: ActivityPalette.secondary)
        }
    }

    private var activitySections: some View {
        let sections = Dictionary(grouping: activityStore.entries) { calendar.startOfDay(for: $0.timestamp) }
            .keys
            .sorted(by: >)

        return VStack(alignment: .leading, spacing: 22) {
            if activityStore.entries.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("No activity yet")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(ActivityPalette.foreground)
                    Text("Pair a host, refresh inventory, or open a session to start building the log.")
                        .foregroundStyle(ActivityPalette.muted)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ActivityPalette.surfaceLow, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else {
                ForEach(sections, id: \.self) { day in
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Text(sectionTitle(for: day))
                                .font(.system(.caption, design: .monospaced).weight(.medium))
                                .foregroundStyle(ActivityPalette.muted)
                                .textCase(.uppercase)
                            Rectangle()
                                .fill(ActivityPalette.surfaceHigh)
                                .frame(height: 1)
                        }

                        let entries = activityStore.entries.filter { calendar.isDate($0.timestamp, inSameDayAs: day) }
                        ForEach(entries) { entry in
                            ActivityEventRow(entry: entry)
                        }
                    }
                }
            }
        }
    }

    private func sectionTitle(for day: Date) -> String {
        if calendar.isDateInToday(day) {
            return "Today"
        }
        if calendar.isDateInYesterday(day) {
            return "Yesterday"
        }
        return day.formatted(.dateTime.month(.abbreviated).day())
    }
}

private struct ActivitySummaryCard: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(ActivityPalette.muted)
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(ActivityPalette.surfaceLow, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct ActivityEventRow: View {
    let entry: ActivityEvent

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(iconBackground)
                    .frame(width: 42, height: 42)
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconTint)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text(entry.title)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(ActivityPalette.foreground)
                    Spacer()
                    Text(entry.timestamp.formatted(.dateTime.hour().minute().second()))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(ActivityPalette.muted)
                }

                Text(entry.message)
                    .font(.subheadline)
                    .foregroundStyle(ActivityPalette.muted)

                HStack(spacing: 8) {
                    ActivityTag(text: entry.severity.rawValue, tint: iconTint.opacity(0.9))
                    if let hostLabel = entry.hostLabel {
                        ActivityTag(text: hostLabel, tint: ActivityPalette.secondary.opacity(0.9))
                    }
                    if let sessionID = entry.sessionID {
                        ActivityTag(text: sessionID, tint: ActivityPalette.primary.opacity(0.9))
                    }
                }
            }
        }
        .padding(18)
        .background(ActivityPalette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var iconName: String {
        switch (entry.category, entry.severity) {
        case (_, .error):
            return "exclamationmark.triangle.fill"
        case (.pairing, _):
            return "link.badge.plus"
        case (.inventory, _):
            return "square.stack.3d.up"
        case (.explorer, _):
            return "rectangle.3.group"
        case (.socket, _):
            return "dot.radiowaves.left.and.right"
        case (.control, _):
            return "cursorarrow.motionlines"
        case (.system, _):
            return "sparkles"
        }
    }

    private var iconTint: Color {
        switch entry.severity {
        case .info:
            return ActivityPalette.primary
        case .warning:
            return ActivityPalette.warning
        case .error:
            return ActivityPalette.error
        }
    }

    private var iconBackground: Color {
        iconTint.opacity(0.16)
    }
}

struct ActivityTag: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .lineLimit(1)
            .font(.system(.caption2, design: .monospaced).weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(ActivityPalette.surfaceHigh, in: Capsule())
    }
}

enum ActivityPalette {
    static let background = Color(red: 12 / 255, green: 14 / 255, blue: 16 / 255)
    static let surfaceLow = Color(red: 17 / 255, green: 20 / 255, blue: 22 / 255)
    static let surface = Color(red: 22 / 255, green: 26 / 255, blue: 30 / 255)
    static let surfaceHigh = Color(red: 32 / 255, green: 38 / 255, blue: 44 / 255)
    static let foreground = Color(red: 224 / 255, green: 230 / 255, blue: 237 / 255)
    static let muted = Color(red: 166 / 255, green: 172 / 255, blue: 178 / 255)
    static let primary = Color(red: 189 / 255, green: 206 / 255, blue: 137 / 255)
    static let secondary = Color(red: 1, green: 191 / 255, blue: 0)
    static let warning = Color(red: 238 / 255, green: 178 / 255, blue: 0)
    static let error = Color(red: 238 / 255, green: 125 / 255, blue: 119 / 255)
}
