import Foundation

struct CreateSessionInput: Equatable {
    var title: String = ""
    var workspaceRoot: String = ""
    var provider: SessionProvider = .codex
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

    var normalizedGroupTags: [String] {
        groupTagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
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

    private let hostsStore: SavedHostsStore
    private let tokenStore: TokenStore

    init(hostsStore: SavedHostsStore, tokenStore: TokenStore) {
        self.hostsStore = hostsStore
        self.tokenStore = tokenStore
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        var nextSections: [InventoryDeviceSection] = []
        var failures: [String] = []

        for host in hostsStore.hosts {
            let token = tokenStore.token(for: host.tokenKey)
            guard let token else {
                nextSections.append(
                    InventoryDeviceSection(host: host, token: nil, sessions: [], hostInfo: nil, errorMessage: nil)
                )
                continue
            }

            do {
                let client = HostClient(host: host)
                async let hostInfo = client.fetchHostInfo(for: host)
                async let sessions = client.listSessions(for: host, token: token)

                nextSections.append(
                    InventoryDeviceSection(
                        host: host,
                        token: token,
                        sessions: sortSessions(try await sessions),
                        hostInfo: try await hostInfo,
                        errorMessage: nil
                    )
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
            }
        }

        sections = nextSections.sorted {
            $0.host.displayLabel.localizedCaseInsensitiveCompare($1.host.displayLabel) == .orderedAscending
        }
        errorMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
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

    var errorDescription: String? {
        switch self {
        case .hostUnavailable:
            return "This device is no longer available."
        case .missingToken:
            return "This device is not paired yet."
        case .invalidWorkspaceRoot:
            return "Enter a workspace path before creating a session."
        }
    }
}
