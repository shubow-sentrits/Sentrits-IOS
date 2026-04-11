import Foundation

@MainActor
final class HostsStore: ObservableObject {
    enum SelectionSource: Equatable {
        case discovered(String)
        case saved(UUID)
        case manual
    }

    enum VerificationState: Equatable {
        case idle
        case verifying
        case failed(String)
    }

    struct SelectedHostDetail: Identifiable {
        let source: SelectionSource
        let host: SavedHost
        let discovery: DiscoveryInfo?
        let hostInfo: HostInfo?
        let lastSeenAt: Date?
        let isSaved: Bool
        let hasToken: Bool

        var id: String {
            switch source {
            case let .discovered(hostId):
                return "discovered:\(hostId)"
            case let .saved(id):
                return "saved:\(id.uuidString)"
            case .manual:
                return "manual:\(host.tokenKey)"
            }
        }
    }

    @Published private(set) var discoveredHosts: [DiscoveredHost] = []
    @Published private(set) var savedHosts: [SavedHost] = []
    @Published private(set) var selectedHost: SelectedHostDetail?
    @Published private(set) var verificationState: VerificationState = .idle
    @Published private(set) var discoveryStatus: String?

    private let defaults: UserDefaults
    private let key = "saved_hosts_v1"
    private let listener: DiscoveryListener
    private let tokenStore: TokenStore
    private var cleanupTask: Task<Void, Never>?
    private let discoveryTTL: TimeInterval = 15

    init(
        defaults: UserDefaults = .standard,
        tokenStore: TokenStore,
        listener: DiscoveryListener = DiscoveryListener()
    ) {
        self.defaults = defaults
        self.tokenStore = tokenStore
        self.listener = listener
        load()
        listener.onMessage = { [weak self] message in
            self?.handleDiscovery(message)
        }
        listener.onError = { [weak self] error in
            self?.discoveryStatus = error.localizedDescription
        }
    }

    func startDiscovery() {
        listener.start()
        startCleanupLoopIfNeeded()
    }

    func stopDiscovery() {
        cleanupTask?.cancel()
        cleanupTask = nil
        listener.stop()
    }

    func token(for host: SavedHost) -> String? {
        tokenStore.token(for: host.tokenKey)
    }

    var newDiscoveredHosts: [DiscoveredHost] {
        discoveredHosts.filter { matchingSavedHost(for: $0.identity, endpoint: $0.endpoint) == nil }
    }

    func isHostOnline(_ host: SavedHost) -> Bool {
        matchingDiscoveredHost(for: host) != nil
    }

    func hostState(for discoveredHost: DiscoveredHost) -> String {
        if let savedHost = matchingSavedHost(for: discoveredHost.identity, endpoint: discoveredHost.endpoint),
           tokenStore.token(for: savedHost.tokenKey) != nil {
            return "Paired"
        }
        if matchingSavedHost(for: discoveredHost.identity, endpoint: discoveredHost.endpoint) != nil {
            return "Saved"
        }
        return "New"
    }

    func selectDiscoveredHost(_ discoveredHost: DiscoveredHost) {
        let savedMatch = matchingSavedHost(for: discoveredHost.identity, endpoint: discoveredHost.endpoint)
        let candidate = (savedMatch ?? SavedHost(identity: discoveredHost.identity, endpoint: discoveredHost.endpoint))
            .merged(identity: discoveredHost.identity, endpoint: discoveredHost.endpoint, alias: savedMatch?.alias)
        selectedHost = SelectedHostDetail(
            source: .discovered(discoveredHost.identity.hostId),
            host: candidate,
            discovery: discoveredHost.identity,
            hostInfo: nil,
            lastSeenAt: discoveredHost.lastSeenAt,
            isSaved: savedMatch != nil,
            hasToken: tokenStore.token(for: candidate.tokenKey) != nil
        )

        Task {
            await refreshSelectedHostDetails(for: candidate, source: .discovered(discoveredHost.identity.hostId), discovery: discoveredHost.identity, lastSeenAt: discoveredHost.lastSeenAt)
        }
    }

    func selectSavedHost(_ host: SavedHost) {
        selectedHost = SelectedHostDetail(
            source: .saved(host.id),
            host: host,
            discovery: nil,
            hostInfo: nil,
            lastSeenAt: nil,
            isSaved: true,
            hasToken: tokenStore.token(for: host.tokenKey) != nil
        )

        Task {
            await refreshSelectedHostDetails(for: host, source: .saved(host.id), discovery: nil, lastSeenAt: nil)
        }
    }

    func verifyManualHost(endpoint: HostEndpoint, alias: String?) async {
        verificationState = .verifying

        do {
            let client = HostClient(host: SavedHost(displayName: endpoint.displayAddress, address: endpoint.address, port: endpoint.port, useTLS: endpoint.useTLS, allowSelfSignedTLS: endpoint.allowSelfSignedTLS))
            let discovery = try await client.fetchDiscoveryInfo(for: endpoint)
            let hostInfo = try? await client.fetchHostInfo(for: endpoint)
            let savedMatch = matchingSavedHost(for: discovery, endpoint: endpoint)
            let candidate = (savedMatch ?? SavedHost(identity: discovery, endpoint: endpoint, alias: alias))
                .merged(identity: discovery, hostInfo: hostInfo, endpoint: endpoint, alias: alias)
            selectedHost = SelectedHostDetail(
                source: .manual,
                host: candidate,
                discovery: discovery,
                hostInfo: hostInfo,
                lastSeenAt: nil,
                isSaved: savedMatch != nil,
                hasToken: tokenStore.token(for: candidate.tokenKey) != nil
            )
            verificationState = .idle
            discoveryStatus = "Verified \(candidate.displayName)."
        } catch {
            verificationState = .failed(error.localizedDescription)
        }
    }

    func saveSelectedHost(alias: String?) {
        guard let selectedHost else { return }
        let host = selectedHost.host.merged(
            identity: selectedHost.discovery,
            hostInfo: selectedHost.hostInfo,
            alias: alias?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? selectedHost.host.alias
        )
        upsert(host)
        self.selectedHost = SelectedHostDetail(
            source: .saved(host.id),
            host: host,
            discovery: selectedHost.discovery,
            hostInfo: selectedHost.hostInfo,
            lastSeenAt: selectedHost.lastSeenAt,
            isSaved: true,
            hasToken: tokenStore.token(for: host.tokenKey) != nil
        )
    }

    func markSelectedHostPaired(alias: String?) {
        saveSelectedHost(alias: alias)
    }

    func removeSavedHosts(at offsets: IndexSet) {
        let removed = offsets.map { savedHosts[$0] }
        savedHosts.remove(atOffsets: offsets)
        persist()

        if let selectedHost,
           removed.contains(where: { $0.id == selectedHost.host.id }) {
            self.selectedHost = nil
        }
    }

    func touch(hostID: UUID) {
        guard let index = savedHosts.firstIndex(where: { $0.id == hostID }) else { return }
        savedHosts[index].lastConnectedAt = Date()
        sortHosts()
        persist()
    }

    private func refreshSelectedHostDetails(
        for host: SavedHost,
        source: SelectionSource,
        discovery: DiscoveryInfo?,
        lastSeenAt: Date?
    ) async {
        do {
            let client = HostClient(host: host)
            let hostInfo = try await client.fetchHostInfo(for: host)
            let refreshed = host.merged(identity: discovery, hostInfo: hostInfo)
            if case let .saved(savedID) = source {
                upsert(refreshed.merged(alias: refreshed.alias).withID(savedID))
            }
            selectedHost = SelectedHostDetail(
                source: source,
                host: refreshed,
                discovery: discovery,
                hostInfo: hostInfo,
                lastSeenAt: lastSeenAt,
                isSaved: matchingSavedHost(for: refreshed) != nil,
                hasToken: tokenStore.token(for: refreshed.tokenKey) != nil
            )
        } catch {
            guard selectedHost?.source == source else { return }
            discoveryStatus = error.localizedDescription
        }
    }

    private func handleDiscovery(_ message: DiscoveryListener.Message) {
        let resolvedAddress = Self.preferredDiscoveryAddress(advertisedHost: message.payload.remoteHost, sourceAddress: message.sourceAddress)
        let endpoint = HostEndpoint(
            address: resolvedAddress,
            port: message.payload.remotePort,
            useTLS: message.payload.tls
        )
        let incoming = DiscoveredHost(
            identity: message.payload,
            endpoint: endpoint,
            announcedAddress: message.sourceAddress,
            lastSeenAt: message.receivedAt
        )

        if let index = discoveredHosts.firstIndex(where: { $0.identity.hostId == incoming.identity.hostId }) {
            discoveredHosts[index] = incoming
        } else if let index = discoveredHosts.firstIndex(where: { $0.endpoint == incoming.endpoint }) {
            discoveredHosts[index] = incoming
        } else {
            discoveredHosts.append(incoming)
        }

        discoveredHosts.sort { lhs, rhs in
            lhs.lastSeenAt > rhs.lastSeenAt
        }

        if case let .discovered(hostId)? = selectedHost?.source,
           hostId == incoming.identity.hostId {
            selectDiscoveredHost(incoming)
        }
    }

    private func startCleanupLoopIfNeeded() {
        guard cleanupTask == nil else { return }

        cleanupTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                await MainActor.run {
                    self?.pruneStaleDiscoveryHosts()
                }
            }
        }
    }

    private func pruneStaleDiscoveryHosts() {
        let cutoff = Date().addingTimeInterval(-discoveryTTL)
        discoveredHosts.removeAll { $0.lastSeenAt < cutoff }
    }

    private func upsert(_ host: SavedHost) {
        if let hostId = host.hostId,
           let index = savedHosts.firstIndex(where: { $0.hostId == hostId }) {
            savedHosts[index] = host.withID(savedHosts[index].id)
        } else if let index = savedHosts.firstIndex(where: { $0.address == host.address && $0.port == host.port && $0.useTLS == host.useTLS }) {
            savedHosts[index] = host.withID(savedHosts[index].id)
        } else {
            savedHosts.insert(host, at: 0)
        }
        sortHosts()
        persist()
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SavedHost].self, from: data) else {
            savedHosts = []
            return
        }
        savedHosts = decoded
        sortHosts()
    }

    private func persist() {
        guard let encoded = try? JSONEncoder().encode(savedHosts) else { return }
        defaults.set(encoded, forKey: key)
    }

    private func sortHosts() {
        savedHosts.sort { lhs, rhs in
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

    private func matchingSavedHost(for discovery: DiscoveryInfo, endpoint: HostEndpoint) -> SavedHost? {
        if let host = savedHosts.first(where: { $0.hostId == discovery.hostId }) {
            return host
        }
        return savedHosts.first(where: { $0.address == endpoint.address && $0.port == endpoint.port && $0.useTLS == endpoint.useTLS })
    }

    private func matchingSavedHost(for host: SavedHost) -> SavedHost? {
        if let hostId = host.hostId,
           let matched = savedHosts.first(where: { $0.hostId == hostId }) {
            return matched
        }
        return savedHosts.first(where: { $0.address == host.address && $0.port == host.port && $0.useTLS == host.useTLS })
    }

    private func matchingDiscoveredHost(for host: SavedHost) -> DiscoveredHost? {
        if let hostId = host.hostId,
           let matched = discoveredHosts.first(where: { $0.identity.hostId == hostId }) {
            return matched
        }
        return discoveredHosts.first(where: { $0.endpoint == host.endpoint })
    }
    private static func preferredDiscoveryAddress(advertisedHost: String, sourceAddress: String) -> String {
        guard let normalized = advertisedHost.nilIfEmpty else {
            return sourceAddress
        }

        switch normalized.lowercased() {
        case "0.0.0.0", "::", "::0", "localhost", "127.0.0.1":
            return sourceAddress
        default:
            return normalized
        }
    }
}

private extension SavedHost {
    func withID(_ id: UUID) -> SavedHost {
        SavedHost(
            id: id,
            hostId: hostId,
            displayName: displayName,
            alias: alias,
            address: address,
            port: port,
            useTLS: useTLS,
            allowSelfSignedTLS: allowSelfSignedTLS,
            lastConnectedAt: lastConnectedAt
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension HostsStore {
    static func previewStore(tokenStore: TokenStore) -> HostsStore {
        let suiteName = "preview.hosts.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let store = HostsStore(defaults: defaults, tokenStore: tokenStore, listener: DiscoveryListener())
        store.savedHosts = [PreviewFixtures.hostA, PreviewFixtures.hostB]
        store.discoveredHosts = [PreviewFixtures.discoveredHostA, PreviewFixtures.discoveredHostB]
        store.selectedHost = SelectedHostDetail(
            source: .saved(PreviewFixtures.hostA.id),
            host: PreviewFixtures.hostA,
            discovery: PreviewFixtures.discoveryA,
            hostInfo: PreviewFixtures.hostInfoA,
            lastSeenAt: Date(),
            isSaved: true,
            hasToken: true
        )
        store.discoveryStatus = "Previewing live discovery"
        return store
    }
}
