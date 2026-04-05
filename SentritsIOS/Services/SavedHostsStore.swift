import Foundation

@MainActor
final class SavedHostsStore: ObservableObject {
    @Published private(set) var hosts: [SavedHost] = []

    private let defaults: UserDefaults
    private let key = "saved_hosts_v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func upsert(_ host: SavedHost) {
        if let index = hosts.firstIndex(where: { $0.id == host.id }) {
            hosts[index] = host
        } else if let index = hosts.firstIndex(where: { $0.address == host.address && $0.port == host.port }) {
            hosts[index] = host
        } else {
            hosts.insert(host, at: 0)
        }
        sortHosts()
        persist()
    }

    func touch(hostID: UUID) {
        guard let index = hosts.firstIndex(where: { $0.id == hostID }) else { return }
        hosts[index].lastConnectedAt = Date()
        sortHosts()
        persist()
    }

    func remove(at offsets: IndexSet) {
        hosts.remove(atOffsets: offsets)
        persist()
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SavedHost].self, from: data) else {
            hosts = []
            return
        }
        hosts = decoded
        sortHosts()
    }

    private func persist() {
        guard let encoded = try? JSONEncoder().encode(hosts) else { return }
        defaults.set(encoded, forKey: key)
    }

    private func sortHosts() {
        hosts.sort { lhs, rhs in
            switch (lhs.lastConnectedAt, rhs.lastConnectedAt) {
            case let (l?, r?):
                return l > r
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs.displayLabel.localizedCaseInsensitiveCompare(rhs.displayLabel) == .orderedAscending
            }
        }
    }
}
