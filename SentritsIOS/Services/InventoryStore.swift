import Foundation
import UserNotifications

enum InventoryNotificationEvent: String, CaseIterable {
    case becameQuiet
    case stopped

    var title: String {
        switch self {
        case .becameQuiet: return "Session became quiet"
        case .stopped: return "Session stopped"
        }
    }
}

private struct InventorySessionNotificationTransition {
    let event: InventoryNotificationEvent
    let host: SavedHost
    let session: SessionSummary
}

struct CreateSessionInput: Equatable {
    var title: String = ""
    var workspaceRoot: String = ""
    var provider: SessionProvider = .codex
    var conversationId: String = ""
    var commandText: String = ""
    var launchMode: SessionLaunchMode = .providerDefault
    var selectedSetupID: String = ""
    var setupName: String = ""
    var groupTagsText: String = ""

    var normalizedTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }

        let fallback = URL(fileURLWithPath: workspaceRoot).lastPathComponent
        return fallback.isEmpty ? "New Session" : fallback
    }

    var normalizedWorkspaceRoot: String {
        workspaceRoot.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedConversationID: String? {
        conversationId.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var normalizedSetupID: String? {
        selectedSetupID.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var normalizedSetupName: String {
        setupName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? normalizedTitle
    }

    var normalizedCommandArgv: [String]? {
        guard launchMode == .argv else { return nil }
        let tokens = commandText.split(whereSeparator: \.isWhitespace).map(String.init)
        return tokens.isEmpty ? nil : tokens
    }

    var normalizedCommandShell: String? {
        guard launchMode == .shell else { return nil }
        return commandText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var normalizedGroupTags: [String] {
        groupTagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

enum SessionProvider: String, CaseIterable, Identifiable {
    case codex
    case claude

    var id: String { rawValue }

    var label: String {
        rawValue.capitalized
    }
}

struct InventoryDeviceSection: Identifiable {
    let host: SavedHost
    let token: String?
    let sessions: [SessionSummary]
    let hostInfo: HostInfo?
    let errorMessage: String?

    var id: UUID { host.id }
}

@MainActor
final class InventoryStore: ObservableObject {
    @Published private(set) var sections: [InventoryDeviceSection] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var busyHostIDs: Set<UUID> = []
    @Published private(set) var busySessionIDs: Set<String> = []
    @Published var errorMessage: String?
    @Published var showStoppedSessions = true

    private let hostsStore: HostsStore
    private let tokenStore: TokenStore
    private let notificationPreferences: NotificationPreferencesStore
    private let activityStore: ActivityLogStore
    private var lastRefreshAtUnixMs: Int64?

    init(hostsStore: HostsStore, tokenStore: TokenStore, notificationPreferences: NotificationPreferencesStore, activityStore: ActivityLogStore) {
        self.hostsStore = hostsStore
        self.tokenStore = tokenStore
        self.notificationPreferences = notificationPreferences
        self.activityStore = activityStore
    }

    func refresh() async {
        SentritsDebugTrace.log("ios.inventory", "refresh.begin", "hosts=\(hostsStore.savedHosts.count)")
        isRefreshing = true
        defer { isRefreshing = false }

        var nextSections: [InventoryDeviceSection] = []
        var failures: [String] = []

        for host in hostsStore.savedHosts {
            let token = hostsStore.token(for: host)
            let hostIdentity = "host=\(host.displayLabel) id=\(host.id.uuidString) endpoint=\(host.address):\(host.port)"
            guard let token else {
                nextSections.append(
                    InventoryDeviceSection(host: host, token: nil, sessions: [], hostInfo: nil, errorMessage: nil)
                )
                SentritsDebugTrace.log("ios.inventory", "refresh.host.missing_token", hostIdentity)
                continue
            }

            do {
                let client = HostClient(host: host)
                async let hostInfo = client.fetchHostInfo(for: host)
                async let sessions = client.listSessions(for: host, token: token)
                let fetchedSessions = try await sessions
                let fetchedHostInfo = try await hostInfo

                if let expectedHostId = host.hostId,
                   let actualHostId = fetchedHostInfo.hostId,
                   !expectedHostId.isEmpty,
                   !actualHostId.isEmpty,
                   expectedHostId != actualHostId {
                    throw InventoryStoreError.hostIdentityMismatch(
                        expected: expectedHostId,
                        actual: actualHostId
                    )
                }

                hostsStore.syncSavedHostMetadata(hostID: host.id, hostInfo: fetchedHostInfo)
                let refreshedHost = hostsStore.savedHosts.first(where: { $0.id == host.id }) ?? host
                nextSections.append(
                    InventoryDeviceSection(
                        host: refreshedHost,
                        token: token,
                        sessions: sortSessions(fetchedSessions),
                        hostInfo: fetchedHostInfo,
                        errorMessage: nil
                    )
                )
                SentritsDebugTrace.log(
                    "ios.inventory",
                    "refresh.host",
                    "\(hostIdentity) sessions=\(fetchedSessions.count) hostInfo=\(fetchedHostInfo.displayName)"
                )
            } catch {
                failures.append("\(host.displayLabel): \(error.localizedDescription)")
                nextSections.append(
                    InventoryDeviceSection(
                        host: host,
                        token: token,
                        sessions: [],
                        hostInfo: nil,
                        errorMessage: error.localizedDescription
                    )
                )
                SentritsDebugTrace.log(
                    "ios.inventory",
                    "refresh.host.error",
                    "\(hostIdentity) error=\(error.localizedDescription)"
                )
            }
        }

        let sortedSections = nextSections.sorted {
            $0.host.displayLabel.localizedCaseInsensitiveCompare($1.host.displayLabel) == .orderedAscending
        }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let previousRefreshAt = lastRefreshAtUnixMs
        let transitions = notificationTransitions(from: sections, to: sortedSections, previousRefreshAtUnixMs: previousRefreshAt, currentRefreshAtUnixMs: now)
        sections = sortedSections
        lastRefreshAtUnixMs = now
        errorMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
        SentritsDebugTrace.log(
            "ios.inventory",
            "refresh.end",
            "sections=\(sections.count) failures=\(failures.count) totalSessions=\(sections.reduce(0) { $0 + $1.sessions.count })"
        )
        await deliverNotifications(for: transitions)
    }

    func visibleSessions(for section: InventoryDeviceSection) -> [SessionSummary] {
        if showStoppedSessions {
            return section.sessions
        }
        return section.sessions.filter { !$0.isEnded }
    }

    func createSession(hostID: UUID, input: CreateSessionInput) async throws -> SessionSummary {
        guard let section = sections.first(where: { $0.host.id == hostID }) else {
            throw InventoryStoreError.hostUnavailable
        }
        guard let token = section.token else {
            throw InventoryStoreError.missingToken
        }

        let workspaceRoot = input.normalizedWorkspaceRoot
        guard !workspaceRoot.isEmpty else {
            throw InventoryStoreError.invalidWorkspaceRoot
        }

        busyHostIDs.insert(hostID)
        defer { busyHostIDs.remove(hostID) }

        let client = HostClient(host: section.host)
        let created = try await client.createSession(
            host: section.host,
            token: token,
            input: input
        )
        await refresh()
        return created
    }

    func stopSession(hostID: UUID, sessionID: String) async throws {
        guard let section = sections.first(where: { $0.host.id == hostID }) else {
            throw InventoryStoreError.hostUnavailable
        }
        guard let token = section.token else {
            throw InventoryStoreError.missingToken
        }

        busySessionIDs.insert(sessionID)
        defer { busySessionIDs.remove(sessionID) }

        let client = HostClient(host: section.host)
        try await client.stopSession(sessionId: sessionID, host: section.host, token: token)
        await refresh()
    }

    func clearStoppedSessions(hostID: UUID) async throws {
        guard let section = sections.first(where: { $0.host.id == hostID }) else {
            throw InventoryStoreError.hostUnavailable
        }
        guard let token = section.token else {
            throw InventoryStoreError.missingToken
        }

        busyHostIDs.insert(hostID)
        defer { busyHostIDs.remove(hostID) }

        let client = HostClient(host: section.host)
        try await client.clearInactiveSessions(host: section.host, token: token)
        await refresh()
    }

    func isBusy(hostID: UUID) -> Bool {
        busyHostIDs.contains(hostID)
    }

    func isBusy(sessionID: String) -> Bool {
        busySessionIDs.contains(sessionID)
    }

    private func sortSessions(_ sessions: [SessionSummary]) -> [SessionSummary] {
        sessions.sorted { lhs, rhs in
            if lhs.isEnded != rhs.isEnded {
                return !lhs.isEnded
            }

            let lhsActivity = lhs.lastActivityAtUnixMs ?? lhs.createdAtUnixMs ?? 0
            let rhsActivity = rhs.lastActivityAtUnixMs ?? rhs.createdAtUnixMs ?? 0
            if lhsActivity != rhsActivity {
                return lhsActivity > rhsActivity
            }

            return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
        }
    }
}

enum InventoryStoreError: LocalizedError {
    case hostUnavailable
    case missingToken
    case invalidWorkspaceRoot
    case hostIdentityMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .hostUnavailable:
            return "This device is no longer available."
        case .missingToken:
            return "This device is not paired yet."
        case .invalidWorkspaceRoot:
            return "Enter a workspace path before creating a session."
        case .hostIdentityMismatch:
            return "This saved device now points to a different Sentrits host. Re-pair or update the host entry."
        }
    }
}

extension InventoryStore {
    static func previewStore(hostsStore: HostsStore, tokenStore: TokenStore, activityStore: ActivityLogStore) -> InventoryStore {
        let store = InventoryStore(hostsStore: hostsStore, tokenStore: tokenStore, notificationPreferences: NotificationPreferencesStore(), activityStore: activityStore)
        store.sections = [
            InventoryDeviceSection(
                host: PreviewFixtures.hostA,
                token: tokenStore.token(for: PreviewFixtures.hostA.tokenKey),
                sessions: [PreviewFixtures.sessionA, PreviewFixtures.sessionB],
                hostInfo: PreviewFixtures.hostInfoA,
                errorMessage: nil
            ),
            InventoryDeviceSection(
                host: PreviewFixtures.hostB,
                token: tokenStore.token(for: PreviewFixtures.hostB.tokenKey),
                sessions: [],
                hostInfo: nil,
                errorMessage: nil
            )
        ]
        store.showStoppedSessions = true
        return store
    }
}

private extension InventoryStore {
    var supervisionQuietDelayMs: Int64 { 5_000 }

    func quietDurationSeconds(for session: SessionSummary, at timestampUnixMs: Int64) -> Int64? {
        guard session.isNotificationQuiet,
              let lastOutputAt = session.lastOutputAtUnixMs else { return nil }
        let quietStartedAt = lastOutputAt + supervisionQuietDelayMs
        return max(0, (timestampUnixMs - quietStartedAt) / 1000)
    }

    func quietStartedAtUnixMs(for session: SessionSummary) -> Int64? {
        guard session.isNotificationQuiet,
              let lastOutputAt = session.lastOutputAtUnixMs else { return nil }
        return lastOutputAt + supervisionQuietDelayMs
    }

    func notificationTransitions(
        from previous: [InventoryDeviceSection],
        to next: [InventoryDeviceSection],
        previousRefreshAtUnixMs: Int64?,
        currentRefreshAtUnixMs: Int64
    ) -> [InventorySessionNotificationTransition] {
        let previousSessions = Dictionary(uniqueKeysWithValues: previous.flatMap { section in
            section.sessions.map { ($0.notificationKey(hostID: section.host.id), $0) }
        })
        let quietThreshold = Int64(notificationPreferences.quietThreshold.rawValue)

        return next.flatMap { section in
            section.sessions.compactMap { session in
                let sessionKey = session.notificationKey(hostID: section.host.id)
                guard let prior = previousSessions[sessionKey] else { return nil }
                let subscribedAt = notificationPreferences.subscriptionStartedAtUnixMs(sessionKey: sessionKey) ?? .min

                let priorQuietDuration = previousRefreshAtUnixMs.flatMap { quietDurationSeconds(for: prior, at: $0) } ?? 0
                let currentQuietDuration = quietDurationSeconds(for: session, at: currentRefreshAtUnixMs) ?? 0

                if session.isNotificationQuiet,
                   (quietStartedAtUnixMs(for: session) ?? .min) >= subscribedAt,
                   currentQuietDuration >= quietThreshold,
                   priorQuietDuration < quietThreshold,
                   notificationPreferences.shouldNotify(for: .becameQuiet, sessionKey: sessionKey) {
                    return InventorySessionNotificationTransition(event: .becameQuiet, host: section.host, session: session)
                }

                if !prior.isEnded,
                   session.isEnded,
                   (session.lastStatusAtUnixMs ?? .min) >= subscribedAt,
                   notificationPreferences.shouldNotify(for: .stopped, sessionKey: sessionKey) {
                    return InventorySessionNotificationTransition(event: .stopped, host: section.host, session: session)
                }

                return nil
            }
        }
    }

    func deliverNotifications(for transitions: [InventorySessionNotificationTransition]) async {
        guard !transitions.isEmpty else { return }
        await notificationPreferences.requestAuthorizationIfNeeded()
        guard notificationPreferences.authorizationStatus == .authorized ||
                notificationPreferences.authorizationStatus == .provisional else { return }

        let center = UNUserNotificationCenter.current()
        for transition in transitions {
            let content = UNMutableNotificationContent()
            content.title = transition.event.title
            switch transition.event {
            case .becameQuiet:
                content.body = "\(transition.session.displayTitle) on \(transition.host.displayLabel) is now quiet."
            case .stopped:
                content.body = "\(transition.session.displayTitle) on \(transition.host.displayLabel) has stopped."
            }
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "session-\(transition.session.notificationKey(hostID: transition.host.id))-\(transition.event.rawValue)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
            activityStore.record(
                category: .inventory,
                title: "Notification sent",
                message: "\(transition.event.title) for \(transition.session.displayTitle).",
                hostLabel: transition.host.displayLabel,
                sessionID: transition.session.sessionId
            )
        }
    }
}
