import Foundation

@MainActor
final class SessionsViewModel: ObservableObject {
    @Published private(set) var sessions: [SessionSummary] = []
    @Published private(set) var hostInfo: HostInfo?
    @Published var errorMessage: String?
    @Published var isLoading = false

    let host: SavedHost
    let token: String
    private let activityStore: ActivityLogStore

    init(host: SavedHost, token: String, activityStore: ActivityLogStore) {
        self.host = host
        self.token = token
        self.activityStore = activityStore
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let client = HostClient(host: host)
            hostInfo = try await client.fetchHostInfo(for: host)
            sessions = try await client.listSessions(for: host, token: token)
            errorMessage = nil
            activityStore.record(
                category: .inventory,
                title: "Inventory refreshed",
                message: "Loaded \(sessions.count) session\(sessions.count == 1 ? "" : "s").",
                host: host
            )
        } catch {
            errorMessage = error.localizedDescription
            activityStore.record(
                severity: .warning,
                category: .inventory,
                title: "Inventory refresh failed",
                message: error.localizedDescription,
                host: host
            )
        }
    }
}
