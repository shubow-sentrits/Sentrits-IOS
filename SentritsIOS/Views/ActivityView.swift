import SwiftUI

struct ActivityView: View {
    @ObservedObject var activityStore: ActivityLogStore
    @State private var showClearConfirmation = false

    private let calendar = Calendar.current

    var body: some View {
        ZStack {
            activityBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    titleRow
                    header
                    summaryCards
                    activitySections
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .alert("Clear activity log?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                activityStore.clear()
            }
        } message: {
            Text("This removes all activity entries from the current device.")
        }
    }

    private var activityBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color("ActivityBackground"),
                    Color("ActivityBackgroundAlt")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color("ActivityPrimary").opacity(0.14),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 26,
                endRadius: 340
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("System Stream")
                .font(.system(.footnote, design: .monospaced).weight(.medium))
                .foregroundStyle(Color("ActivitySecondary"))
                .textCase(.uppercase)
            Text("Important client and session events, trimmed to the signal you actually need.")
                .font(.callout)
                .foregroundStyle(Color("ActivityMuted"))
        }
    }

    private var titleRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Activity")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Color("ActivityForeground"))

                Text("Important host and session events.")
                    .font(.subheadline)
                    .foregroundStyle(Color("ActivityMuted"))
            }

            Spacer()

            Button {
                showClearConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color("ActivityForeground"))
                    .frame(width: 36, height: 36)
                    .background(Color("ActivitySurfaceLow"), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(activityStore.entries.isEmpty)
            .opacity(activityStore.entries.isEmpty ? 0.45 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryCards: some View {
        let summary = activityStore.summary(calendar: calendar)
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            ActivitySummaryCard(title: "Total Events", value: "\(summary.totalEvents)", tint: Color("ActivityPrimary"))
            ActivitySummaryCard(title: "Today", value: "\(summary.eventsToday)", tint: Color("ActivityForeground"))
            ActivitySummaryCard(title: "Warnings", value: "\(summary.warningCount)", tint: Color("ActivityWarning"))
            ActivitySummaryCard(title: "Active Hosts", value: "\(summary.activeHostCount)", tint: Color("ActivitySecondary"))
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
                        .foregroundStyle(Color("ActivityForeground"))
                    Text("Pair a host, refresh inventory, or open a session to start building the log.")
                        .foregroundStyle(Color("ActivityMuted"))
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color("ActivitySurfaceLow"), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else {
                ForEach(sections, id: \.self) { day in
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Text(sectionTitle(for: day))
                                .font(.system(.caption, design: .monospaced).weight(.medium))
                                .foregroundStyle(Color("ActivityMuted"))
                                .textCase(.uppercase)
                            Rectangle()
                                .fill(Color("ActivitySurfaceHigh"))
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
                .foregroundStyle(Color("ActivityMuted"))
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color("ActivitySurfaceLow"), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                        .foregroundStyle(Color("ActivityForeground"))
                    Spacer()
                    Text(entry.timestamp.formatted(.dateTime.hour().minute().second()))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color("ActivityMuted"))
                }

                Text(entry.message)
                    .font(.subheadline)
                    .foregroundStyle(Color("ActivityMuted"))

                HStack(spacing: 8) {
                    ActivityTag(text: entry.severity.rawValue, tint: iconTint.opacity(0.9))
                    if let hostLabel = entry.hostLabel {
                        ActivityTag(text: hostLabel, tint: Color("ActivitySecondary").opacity(0.9))
                    }
                    if let sessionID = entry.sessionID {
                        ActivityTag(text: sessionID, tint: Color("ActivityPrimary").opacity(0.9))
                    }
                }
            }
        }
        .padding(18)
        .background(Color("ActivitySurface"), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
            return Color("ActivityPrimary")
        case .warning:
            return Color("ActivityWarning")
        case .error:
            return Color("ActivityError")
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
            .background(Color("ActivitySurfaceHigh"), in: Capsule())
    }
}

#Preview("Activity") {
    NavigationStack {
        ActivityView(activityStore: PreviewAppContext.make().activityStore)
    }
}
