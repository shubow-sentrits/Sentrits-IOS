import Foundation

@MainActor
final class ConnectViewModel: ObservableObject {
    @Published var hostName = ""
    @Published var hostAddress = ""
    @Published var port = "18086"
    @Published var statusMessage: String?
    @Published var hostInfo: HostInfo?
    @Published var isBusy = false

    private let client: HostClient

    init(client: HostClient) {
        self.client = client
    }

    func populate(from host: SavedHost) {
        hostName = host.name
        hostAddress = host.address
        port = String(host.port)
    }

    func makeHost() -> SavedHost? {
        guard let portValue = Int(port), !hostAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return SavedHost(
            name: hostName.trimmingCharacters(in: .whitespacesAndNewlines),
            address: hostAddress.trimmingCharacters(in: .whitespacesAndNewlines),
            port: portValue
        )
    }

    func check(host: SavedHost) async {
        isBusy = true
        defer { isBusy = false }

        do {
            try await client.health(for: host)
            let info = try await client.fetchHostInfo(for: host)
            hostInfo = info
            statusMessage = "Reachable: \(info.displayName)"
        } catch {
            statusMessage = error.localizedDescription
            hostInfo = nil
        }
    }
}
