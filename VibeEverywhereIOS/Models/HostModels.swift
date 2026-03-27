import Foundation

struct SavedHost: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var address: String
    var port: Int
    var useTLS: Bool
    var allowSelfSignedTLS: Bool
    var lastConnectedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        address: String,
        port: Int,
        useTLS: Bool = false,
        allowSelfSignedTLS: Bool = false,
        lastConnectedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.port = port
        self.useTLS = useTLS
        self.allowSelfSignedTLS = allowSelfSignedTLS
        self.lastConnectedAt = lastConnectedAt
    }

    var baseURL: URL {
        let scheme = useTLS ? "https" : "http"
        return URL(string: "\(scheme)://\(address):\(port)")!
    }

    var websocketURL: URL {
        let scheme = useTLS ? "wss" : "ws"
        return URL(string: "\(scheme)://\(address):\(port)")!
    }

    var tokenKey: String {
        "\(address):\(port)"
    }

    var displayLabel: String {
        name.isEmpty ? "\(address):\(port)" : "\(name) (\(address):\(port))"
    }
}

struct HostInfo: Codable {
    let hostId: String?
    let displayName: String
    let version: String?
    let capabilities: [String]?
    let pairingMode: String?
    let tls: HostTLSInfo?
}

struct HostTLSInfo: Codable {
    let enabled: Bool
    let mode: String?
}

struct PairingRequestPayload: Codable {
    let deviceName: String
    let deviceType: String
}

struct PairingRequestResponse: Codable {
    let pairingId: String
    let code: String
    let status: String
}

struct PairingClaimPayload: Codable {
    let pairingId: String
    let code: String
}

struct PairingClaimPendingResponse: Codable {
    let status: String
}

struct PairingRecordResponse: Codable {
    let deviceId: String?
    let deviceName: String?
    let deviceType: String?
    let token: String
    let status: String
    let approvedAtUnixMs: Int?
}

struct SessionSummary: Codable, Identifiable, Hashable {
    let sessionId: String
    let provider: String
    let workspaceRoot: String
    let title: String
    let status: String
    let conversationId: String?
    let groupTags: [String]
    let controllerKind: String
    let controllerClientId: String?
    let isRecovered: Bool?
    let archivedRecord: Bool?
    let isActive: Bool?
    let inventoryState: String?
    let activityState: String?
    let supervisionState: String?
    let attentionState: String?
    let attentionReason: String?
    let createdAtUnixMs: Int64?
    let lastStatusAtUnixMs: Int64?
    let lastOutputAtUnixMs: Int64?
    let lastActivityAtUnixMs: Int64?
    let lastFileChangeAtUnixMs: Int64?
    let lastGitChangeAtUnixMs: Int64?
    let lastControllerChangeAtUnixMs: Int64?
    let attentionSinceUnixMs: Int64?
    let currentSequence: UInt64?
    let attachedClientCount: Int?
    let recentFileChangeCount: Int?
    let gitDirty: Bool?
    let gitBranch: String?
    let gitModifiedCount: Int?
    let gitStagedCount: Int?
    let gitUntrackedCount: Int?

    init(
        sessionId: String,
        provider: String,
        workspaceRoot: String,
        title: String,
        status: String,
        conversationId: String? = nil,
        groupTags: [String] = [],
        controllerKind: String,
        controllerClientId: String? = nil,
        isRecovered: Bool? = nil,
        archivedRecord: Bool? = nil,
        isActive: Bool? = nil,
        inventoryState: String? = nil,
        activityState: String? = nil,
        supervisionState: String? = nil,
        attentionState: String? = nil,
        attentionReason: String? = nil,
        createdAtUnixMs: Int64? = nil,
        lastStatusAtUnixMs: Int64? = nil,
        lastOutputAtUnixMs: Int64? = nil,
        lastActivityAtUnixMs: Int64? = nil,
        lastFileChangeAtUnixMs: Int64? = nil,
        lastGitChangeAtUnixMs: Int64? = nil,
        lastControllerChangeAtUnixMs: Int64? = nil,
        attentionSinceUnixMs: Int64? = nil,
        currentSequence: UInt64? = nil,
        attachedClientCount: Int? = nil,
        recentFileChangeCount: Int? = nil,
        gitDirty: Bool? = nil,
        gitBranch: String? = nil,
        gitModifiedCount: Int? = nil,
        gitStagedCount: Int? = nil,
        gitUntrackedCount: Int? = nil
    ) {
        self.sessionId = sessionId
        self.provider = provider
        self.workspaceRoot = workspaceRoot
        self.title = title
        self.status = status
        self.conversationId = conversationId
        self.groupTags = groupTags
        self.controllerKind = controllerKind
        self.controllerClientId = controllerClientId
        self.isRecovered = isRecovered
        self.archivedRecord = archivedRecord
        self.isActive = isActive
        self.inventoryState = inventoryState
        self.activityState = activityState
        self.supervisionState = supervisionState
        self.attentionState = attentionState
        self.attentionReason = attentionReason
        self.createdAtUnixMs = createdAtUnixMs
        self.lastStatusAtUnixMs = lastStatusAtUnixMs
        self.lastOutputAtUnixMs = lastOutputAtUnixMs
        self.lastActivityAtUnixMs = lastActivityAtUnixMs
        self.lastFileChangeAtUnixMs = lastFileChangeAtUnixMs
        self.lastGitChangeAtUnixMs = lastGitChangeAtUnixMs
        self.lastControllerChangeAtUnixMs = lastControllerChangeAtUnixMs
        self.attentionSinceUnixMs = attentionSinceUnixMs
        self.currentSequence = currentSequence
        self.attachedClientCount = attachedClientCount
        self.recentFileChangeCount = recentFileChangeCount
        self.gitDirty = gitDirty
        self.gitBranch = gitBranch
        self.gitModifiedCount = gitModifiedCount
        self.gitStagedCount = gitStagedCount
        self.gitUntrackedCount = gitUntrackedCount
    }

    var id: String { sessionId }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? sessionId : trimmed
    }

    var inventoryStateLabel: String {
        if let inventoryState, !inventoryState.isEmpty {
            return inventoryState
        }
        return status
    }

    var isEnded: Bool {
        switch (inventoryState ?? status).lowercased() {
        case "ended", "exited", "stopped":
            return true
        default:
            return false
        }
    }
}
