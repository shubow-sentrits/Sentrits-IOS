import Foundation

@MainActor
final class ConnectViewModel: ObservableObject {
    @Published var hostAlias = ""
    @Published var hostAddress = ""
    @Published var port = "18086"
    @Published var useTLS = false
    @Published var allowSelfSignedTLS = false

    func populate(from host: SavedHost) {
        hostAlias = host.alias ?? ""
        hostAddress = host.address
        port = String(host.port)
        useTLS = host.useTLS
        allowSelfSignedTLS = host.allowSelfSignedTLS
    }

    func makeEndpoint() -> HostEndpoint? {
        guard let portValue = Int(port), !hostAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return HostEndpoint(
            address: hostAddress.trimmingCharacters(in: .whitespacesAndNewlines),
            port: portValue,
            useTLS: useTLS,
            allowSelfSignedTLS: allowSelfSignedTLS
        )
    }

    var alias: String? {
        hostAlias.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
