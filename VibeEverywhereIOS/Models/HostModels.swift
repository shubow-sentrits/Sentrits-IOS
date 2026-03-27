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
    let controllerKind: String
    let controllerClientId: String?

    var id: String { sessionId }
}
