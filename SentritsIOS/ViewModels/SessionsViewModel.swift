import Foundation

enum ExplorerRoute: Hashable {
    case focusedSession(String)
}

@MainActor
final class SessionsViewModel: ObservableObject {
    @Published private(set) var sessionViewModels: [SessionViewModel] = []
    @Published private(set) var hostInfo: HostInfo?
    @Published var selectedGroupTag = "all"
    @Published var errorMessage: String?
    @Published var isLoading = false

    let host: SavedHost
    let token: String
    private let activityStore: ActivityLogStore

    private var localGroupTabs: [String] = []
    private var hiddenSessionIDs: Set<String> = []
    private var refreshTask: Task<Void, Never>?

    init(host: SavedHost, token: String, activityStore: ActivityLogStore) {
        self.host = host
        self.token = token
        self.activityStore = activityStore
    }

    init(
        previewHost host: SavedHost,
        token: String,
        activityStore: ActivityLogStore,
        hostInfo: HostInfo?,
        sessions: [SessionSummary],
        selectedGroupTag: String = "all"
    ) {
        self.host = host
        self.token = token
        self.activityStore = activityStore
        self.hostInfo = hostInfo
        self.selectedGroupTag = selectedGroupTag

        self.sessionViewModels = sessions.map { session in
            let viewModel = SessionViewModel(host: host, token: token, session: session, activityStore: activityStore)
            viewModel.socketState = .connected
            if session.sessionId == PreviewFixtures.sessionA.sessionId {
                viewModel.snapshot = PreviewFixtures.snapshot
                if let tail = PreviewFixtures.snapshot.recentTerminalTail,
                   let data = tail.data(using: .utf8) {
                    viewModel.terminal.ingestBase64(data.base64EncodedString(), seqStart: 0, seqEnd: PreviewFixtures.snapshot.currentSequence ?? 0)
                }
            } else if let data = "Ready for focus view\nAwaiting next action\n".data(using: .utf8) {
                viewModel.terminal.ingestBase64(data.base64EncodedString(), seqStart: 0, seqEnd: session.currentSequence ?? 0)
            }
            return viewModel
        }
    }

    deinit {
        refreshTask?.cancel()
    }

    var groupTabs: [String] {
        let persisted = sessionViewModels
            .flatMap(\.session.normalizedGroupTags)
        let merged = Array(Set(localGroupTabs + persisted)).sorted()
        return ["all"] + merged
    }

    var connectedSessions: [SessionViewModel] {
        let visible = sessionViewModels.filter { !hiddenSessionIDs.contains($0.session.sessionId) }
        guard selectedGroupTag != "all" else {
            return visible
        }
        return visible.filter { $0.session.normalizedGroupTags.contains(selectedGroupTag) }
    }

    var hiddenSessionCount: Int {
        hiddenSessionIDs.count
    }

    func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            await self?.runRefreshLoop()
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        sessionViewModels.forEach { $0.disconnect() }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let client = HostClient(host: host)
            async let infoTask = client.fetchHostInfo(for: host)
            async let sessionsTask = client.listSessions(for: host, token: token)

            hostInfo = try await infoTask
            let fetchedSessions = try await sessionsTask
            synchronize(with: fetchedSessions.filter(\.isExplorerEligible))
            errorMessage = nil
            activityStore.record(
                category: .inventory,
                title: "Explorer refreshed",
                message: "Loaded \(fetchedSessions.count) session\(fetchedSessions.count == 1 ? "" : "s").",
                hostLabel: host.displayLabel
            )
        } catch {
            errorMessage = error.localizedDescription
            activityStore.record(
                severity: .warning,
                category: .inventory,
                title: "Explorer refresh failed",
                message: error.localizedDescription,
                hostLabel: host.displayLabel
            )
        }
    }

    func createGroup(named rawValue: String) {
        let tag = SessionSummary.normalizeGroupTag(rawValue)
        guard !tag.isEmpty else { return }
        if !localGroupTabs.contains(tag) {
            localGroupTabs.append(tag)
        }
        selectedGroupTag = tag
    }

    func selectGroup(_ tag: String) {
        selectedGroupTag = tag
    }

    func focusedSession(for route: ExplorerRoute) -> SessionViewModel? {
        switch route {
        case let .focusedSession(sessionID):
            return sessionViewModels.first(where: { $0.session.sessionId == sessionID })
        }
    }

    func disconnect(_ viewModel: SessionViewModel) {
        hiddenSessionIDs.insert(viewModel.session.sessionId)
        viewModel.disconnect()
    }

    func reconnectHiddenSessions() {
        let hidden = hiddenSessionIDs
        hiddenSessionIDs.removeAll()
        for viewModel in sessionViewModels where hidden.contains(viewModel.session.sessionId) {
            viewModel.connect()
        }
    }

    func addSelectedGroup(to viewModel: SessionViewModel) async {
        guard selectedGroupTag != "all" else { return }
        await updateGroupTags(for: viewModel, mode: .add, tags: [selectedGroupTag])
    }

    func addGroup(_ tag: String, to viewModel: SessionViewModel) async {
        await updateGroupTags(for: viewModel, mode: .add, tags: [tag])
    }

    func removeGroup(_ tag: String, from viewModel: SessionViewModel) async {
        await updateGroupTags(for: viewModel, mode: .remove, tags: [tag])
    }

    func availableGroups(for viewModel: SessionViewModel) -> [String] {
        groupTabs
            .filter { $0 != "all" && !viewModel.session.normalizedGroupTags.contains($0) }
    }

    private func runRefreshLoop() async {
        await refresh()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(8))
            if Task.isCancelled {
                break
            }
            await refresh()
        }
    }

    private func synchronize(with sessions: [SessionSummary]) {
        let existingByID = Dictionary(uniqueKeysWithValues: sessionViewModels.map { ($0.session.sessionId, $0) })

        var nextViewModels: [SessionViewModel] = []
        nextViewModels.reserveCapacity(sessions.count)

        for session in sessions {
            if let existing = existingByID[session.sessionId] {
                existing.updateSession(session)
                nextViewModels.append(existing)
                if !hiddenSessionIDs.contains(session.sessionId) {
                    existing.connect()
                }
            } else {
                let viewModel = SessionViewModel(host: host, token: token, session: session, activityStore: activityStore)
                nextViewModels.append(viewModel)
                if !hiddenSessionIDs.contains(session.sessionId) {
                    viewModel.connect()
                }
            }
        }

        let liveIDs = Set(sessions.map(\.sessionId))
        for existing in sessionViewModels where !liveIDs.contains(existing.session.sessionId) {
            existing.disconnect()
            hiddenSessionIDs.remove(existing.session.sessionId)
        }

        sessionViewModels = nextViewModels.sorted {
            if $0.session.lastActivityAtUnixMs != $1.session.lastActivityAtUnixMs {
                return ($0.session.lastActivityAtUnixMs ?? 0) > ($1.session.lastActivityAtUnixMs ?? 0)
            }
            return $0.session.displayTitle.localizedCaseInsensitiveCompare($1.session.displayTitle) == .orderedAscending
        }

        if !groupTabs.contains(selectedGroupTag) {
            selectedGroupTag = "all"
        }
    }

    private func updateGroupTags(for viewModel: SessionViewModel, mode: SessionGroupTagsUpdateMode, tags: [String]) async {
        do {
            let client = HostClient(host: host)
            let normalizedTags = tags
                .map(SessionSummary.normalizeGroupTag)
                .filter { !$0.isEmpty }
            let response = try await client.updateSessionGroupTags(
                sessionId: viewModel.session.sessionId,
                mode: mode,
                tags: normalizedTags,
                host: host,
                token: token
            )
            viewModel.updateGroupTags(response.groupTags)
            if mode == .add {
                localGroupTabs.append(contentsOf: response.groupTags)
                activityStore.record(
                    category: .explorer,
                    title: "Group tag added",
                    message: "Updated session groups to \(response.groupTags.joined(separator: ", ")).",
                    hostLabel: host.displayLabel,
                    sessionID: viewModel.session.sessionId
                )
            } else if mode == .remove {
                activityStore.record(
                    category: .explorer,
                    title: "Group tag removed",
                    message: "Updated session groups to \(response.groupTags.joined(separator: ", ")).",
                    hostLabel: host.displayLabel,
                    sessionID: viewModel.session.sessionId
                )
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            activityStore.record(
                severity: .warning,
                category: .explorer,
                title: "Group tag update failed",
                message: error.localizedDescription,
                hostLabel: host.displayLabel,
                sessionID: viewModel.session.sessionId
            )
        }
    }
}
