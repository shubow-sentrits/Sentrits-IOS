import Foundation
import UIKit

@MainActor
final class PairingViewModel: ObservableObject {
    @Published private(set) var response: PairingRequestResponse?
    @Published var manualToken = ""
    @Published var statusMessage: String?
    @Published var isBusy = false

    private let host: SavedHost
    private let client: HostClient
    private let tokenStore: TokenStore

    init(host: SavedHost, client: HostClient, tokenStore: TokenStore) {
        self.host = host
        self.client = client
        self.tokenStore = tokenStore
    }

    func start() async {
        isBusy = true
        defer { isBusy = false }

        do {
            let deviceName = UIDevice.current.name
            response = try await client.startPairing(for: host, deviceName: deviceName)
            statusMessage = "Pairing requested. Approve it in the host admin UI, then paste the returned token here."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func saveToken() async -> Bool {
        let trimmed = manualToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "Enter the approved bearer token."
            return false
        }

        isBusy = true
        defer { isBusy = false }

        do {
            try await client.validateToken(trimmed, for: host)
            try tokenStore.setToken(trimmed, for: host.tokenKey)
            statusMessage = "Token saved."
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }
}
