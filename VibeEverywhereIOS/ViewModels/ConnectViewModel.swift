import Foundation

@MainActor
final class ConnectViewModel: ObservableObject {
    @Published var hostName = ""
    @Published var hostAddress = ""
    @Published var port = "18086"
    @Published var useTLS = false
    @Published var allowSelfSignedTLS = false
    @Published var statusMessage: String?
    @Published var hostInfo: HostInfo?
    @Published var isBusy = false

    func populate(from host: SavedHost) {
        hostName = host.name
        hostAddress = host.address
        port = String(host.port)
        useTLS = host.useTLS
        allowSelfSignedTLS = host.allowSelfSignedTLS
    }

    func makeHost() -> SavedHost? {
        guard let portValue = Int(port), !hostAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return SavedHost(
            name: hostName.trimmingCharacters(in: .whitespacesAndNewlines),
            address: hostAddress.trimmingCharacters(in: .whitespacesAndNewlines),
            port: portValue,
            useTLS: useTLS,
            allowSelfSignedTLS: allowSelfSignedTLS
        )
    }

    func check(host: SavedHost) async {
        isBusy = true
        defer { isBusy = false }

        do {
            let client = HostClient(host: host)
            try await client.health(for: host)
            let info = try await client.fetchHostInfo(for: host)
            hostInfo = info
            let tlsStatus = info.tls?.enabled == true ? "TLS enabled" : "TLS disabled"
            statusMessage = "Reachable: \(info.displayName) (\(tlsStatus))"
        } catch {
            statusMessage = error.localizedDescription
            hostInfo = nil
        }
    }
}
