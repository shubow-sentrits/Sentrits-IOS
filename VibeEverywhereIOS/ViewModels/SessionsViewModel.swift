import Foundation

@MainActor
final class SessionsViewModel: ObservableObject {
    @Published private(set) var sessions: [SessionSummary] = []
    @Published private(set) var hostInfo: HostInfo?
    @Published var errorMessage: String?
    @Published var isLoading = false

    let host: SavedHost
    let token: String
    private let client: HostClient

    init(host: SavedHost, token: String, client: HostClient) {
        self.host = host
        self.token = token
        self.client = client
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            hostInfo = try await client.fetchHostInfo(for: host)
            sessions = try await client.listSessions(for: host, token: token)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
