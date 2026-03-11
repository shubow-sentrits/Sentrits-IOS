import Foundation

struct SavedHost: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var address: String
    var port: Int
    var lastConnectedAt: Date?

    init(id: UUID = UUID(), name: String, address: String, port: Int, lastConnectedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.address = address
        self.port = port
        self.lastConnectedAt = lastConnectedAt
    }

    var baseURL: URL {
        URL(string: "http://\(address):\(port)")!
    }

    var websocketURL: URL {
        URL(string: "ws://\(address):\(port)")!
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
    let tls: Bool?
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
