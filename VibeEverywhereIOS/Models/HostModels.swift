import Foundation

struct HostEndpoint: Codable, Equatable, Hashable {
    var address: String
    var port: Int
    var useTLS: Bool
    var allowSelfSignedTLS: Bool

    init(
        address: String,
        port: Int,
        useTLS: Bool = false,
        allowSelfSignedTLS: Bool = false
    ) {
        self.address = address
        self.port = port
        self.useTLS = useTLS
        self.allowSelfSignedTLS = allowSelfSignedTLS
    }

    var baseURL: URL {
        let scheme = useTLS ? "https" : "http"
        return URL(string: "\(scheme)://\(address):\(port)")!
    }

    var websocketURL: URL {
        let scheme = useTLS ? "wss" : "ws"
        return URL(string: "\(scheme)://\(address):\(port)")!
    }

    var displayAddress: String {
        "\(address):\(port)"
    }
}

struct SavedHost: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var hostId: String?
    var displayName: String
    var alias: String?
    var address: String
    var port: Int
    var useTLS: Bool
    var allowSelfSignedTLS: Bool
    var lastConnectedAt: Date?

    init(
        id: UUID = UUID(),
        hostId: String? = nil,
        displayName: String,
        alias: String? = nil,
        address: String,
        port: Int,
        useTLS: Bool = false,
        allowSelfSignedTLS: Bool = false,
        lastConnectedAt: Date? = nil
    ) {
        self.id = id
        self.hostId = hostId?.trimmedNilIfEmpty
        self.displayName = displayName
        self.alias = alias?.trimmedNilIfEmpty
        self.address = address
        self.port = port
        self.useTLS = useTLS
        self.allowSelfSignedTLS = allowSelfSignedTLS
        self.lastConnectedAt = lastConnectedAt
    }

    init(
        id: UUID = UUID(),
        identity: DiscoveryInfo,
        endpoint: HostEndpoint,
        alias: String? = nil,
        lastConnectedAt: Date? = nil
    ) {
        self.init(
            id: id,
            hostId: identity.hostId,
            displayName: identity.displayName,
            alias: alias,
            address: endpoint.address,
            port: endpoint.port,
            useTLS: endpoint.useTLS || identity.tls,
            allowSelfSignedTLS: endpoint.allowSelfSignedTLS,
            lastConnectedAt: lastConnectedAt
        )
    }

    var baseURL: URL {
        endpoint.baseURL
    }

    var websocketURL: URL {
        endpoint.websocketURL
    }

    var tokenKey: String {
        if let hostId = hostId?.trimmedNilIfEmpty {
            return "host:\(hostId)"
        }
        return "endpoint:\(address):\(port):\(useTLS ? 1 : 0)"
    }

    var endpoint: HostEndpoint {
        HostEndpoint(address: address, port: port, useTLS: useTLS, allowSelfSignedTLS: allowSelfSignedTLS)
    }

    var displayLabel: String {
        if let alias = alias?.trimmedNilIfEmpty {
            return "\(alias) · \(displayName)"
        }
        return displayName
    }

    var detailLabel: String {
        endpoint.displayAddress
    }

    var secondaryLabel: String {
        if alias?.trimmedNilIfEmpty != nil {
            return "\(displayName) · \(detailLabel)"
        }
        return detailLabel
    }

    func merged(
        identity: DiscoveryInfo? = nil,
        hostInfo: HostInfo? = nil,
        endpoint: HostEndpoint? = nil,
        alias: String? = nil
    ) -> SavedHost {
        SavedHost(
            id: id,
            hostId: identity?.hostId ?? hostInfo?.hostId ?? hostId,
            displayName: identity?.displayName ?? hostInfo?.displayName ?? displayName,
            alias: alias ?? self.alias,
            address: endpoint?.address ?? self.address,
            port: endpoint?.port ?? self.port,
            useTLS: endpoint?.useTLS ?? hostInfo?.tls?.enabled ?? identity?.tls ?? self.useTLS,
            allowSelfSignedTLS: endpoint?.allowSelfSignedTLS ?? self.allowSelfSignedTLS,
            lastConnectedAt: lastConnectedAt
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case hostId
        case displayName
        case alias
        case address
        case port
        case useTLS
        case allowSelfSignedTLS
        case lastConnectedAt
        case name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        hostId = try container.decodeIfPresent(String.self, forKey: .hostId)?.trimmedNilIfEmpty
        let legacyName = try container.decodeIfPresent(String.self, forKey: .name)?.trimmedNilIfEmpty
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)?.trimmedNilIfEmpty
            ?? legacyName
            ?? "Unknown Host"
        alias = try container.decodeIfPresent(String.self, forKey: .alias)?.trimmedNilIfEmpty
        address = try container.decode(String.self, forKey: .address)
        port = try container.decode(Int.self, forKey: .port)
        useTLS = try container.decodeIfPresent(Bool.self, forKey: .useTLS) ?? false
        allowSelfSignedTLS = try container.decodeIfPresent(Bool.self, forKey: .allowSelfSignedTLS) ?? false
        lastConnectedAt = try container.decodeIfPresent(Date.self, forKey: .lastConnectedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(hostId, forKey: .hostId)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(alias, forKey: .alias)
        try container.encode(address, forKey: .address)
        try container.encode(port, forKey: .port)
        try container.encode(useTLS, forKey: .useTLS)
        try container.encode(allowSelfSignedTLS, forKey: .allowSelfSignedTLS)
        try container.encodeIfPresent(lastConnectedAt, forKey: .lastConnectedAt)
    }
}

struct HostInfo: Codable {
    let hostId: String?
    let displayName: String
    let adminHost: String?
    let adminPort: Int?
    let remoteHost: String?
    let remotePort: Int?
    let version: String?
    let capabilities: [String]?
    let pairingMode: String?
    let tls: HostTLSInfo?
}

struct HostTLSInfo: Codable {
    let enabled: Bool
    let mode: String?
}

struct DiscoveryInfo: Codable, Equatable, Hashable {
    let hostId: String
    let displayName: String
    let remoteHost: String
    let remotePort: Int
    let protocolVersion: String?
    let tls: Bool

    var endpoint: HostEndpoint {
        HostEndpoint(address: remoteHost, port: remotePort, useTLS: tls)
    }
}

struct DiscoveredHost: Identifiable, Equatable, Hashable {
    let identity: DiscoveryInfo
    let endpoint: HostEndpoint
    let announcedAddress: String
    var lastSeenAt: Date

    var id: String { identity.hostId }

    var displayName: String { identity.displayName }

    var age: TimeInterval {
        Date().timeIntervalSince(lastSeenAt)
    }

    func refreshed(at date: Date, announcedAddress: String, endpoint: HostEndpoint) -> DiscoveredHost {
        DiscoveredHost(identity: identity, endpoint: endpoint, announcedAddress: announcedAddress, lastSeenAt: date)
    }
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

struct PairingClaimResponse: Codable {
    let deviceId: String?
    let deviceName: String?
    let deviceType: String?
    let token: String?
    let status: String
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
    let ptyCols: Int?
    let ptyRows: Int?
    let currentSequence: Int?
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
        ptyCols: Int? = nil,
        ptyRows: Int? = nil,
        currentSequence: Int? = nil,
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
        self.ptyCols = ptyCols
        self.ptyRows = ptyRows
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

    var supervisionStateLabel: String {
        if let supervisionState, !supervisionState.isEmpty {
            return supervisionState
        }
        return isEnded ? "stopped" : "quiet"
    }

    var isEnded: Bool {
        switch (inventoryState ?? status).lowercased() {
        case "ended", "exited", "stopped", "archived", "error":
            return true
        default:
            return false
        }
    }

    var isConnectable: Bool {
        if isEnded {
            return false
        }
        if let isActive {
            return isActive
        }
        return isExplorerEligible
    }


    var isNotificationActive: Bool {
        supervisionStateLabel.lowercased() == "active"
    }

    var isNotificationQuiet: Bool {
        supervisionStateLabel.lowercased() == "quiet"
    }

    func notificationKey(hostID: UUID) -> String {
        "\(hostID.uuidString):\(sessionId)"
    }

    var normalizedGroupTags: [String] {
        groupTags.map(Self.normalizeGroupTag).filter { !$0.isEmpty }
    }

    var isExplorerEligible: Bool {
        if let isActive {
            return isActive
        }

        switch status.lowercased() {
        case "exited", "error":
            return false
        default:
            return true
        }
    }

    static func normalizeGroupTag(_ rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
