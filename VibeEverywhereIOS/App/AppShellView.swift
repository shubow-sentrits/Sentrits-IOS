import SwiftUI
import UserNotifications

@MainActor
final class NotificationPreferencesStore: ObservableObject {
    @Published var quietEnabled: Bool
    @Published var stoppedEnabled: Bool
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let defaults: UserDefaults
    private let quietKey = "notifications.event.quiet"
    private let stoppedKey = "notifications.event.stopped"
    private let sessionsKey = "notifications.sessions"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.quietEnabled = defaults.object(forKey: quietKey) as? Bool ?? true
        self.stoppedEnabled = defaults.object(forKey: stoppedKey) as? Bool ?? true
        Task { await refreshAuthorizationStatus() }
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        if authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        await refreshAuthorizationStatus()
    }

    func setQuietEnabled(_ value: Bool) {
        quietEnabled = value
        defaults.set(value, forKey: quietKey)
    }

    func setStoppedEnabled(_ value: Bool) {
        stoppedEnabled = value
        defaults.set(value, forKey: stoppedKey)
    }

    func isSubscribed(sessionKey: String) -> Bool {
        subscribedSessionKeys.contains(sessionKey)
    }

    func toggleSubscription(sessionKey: String) {
        var keys = subscribedSessionKeys
        if keys.contains(sessionKey) {
            keys.remove(sessionKey)
        } else {
            keys.insert(sessionKey)
        }
        defaults.set(Array(keys).sorted(), forKey: sessionsKey)
        objectWillChange.send()
    }

    func shouldNotify(for event: InventoryNotificationEvent, sessionKey: String) -> Bool {
        guard isSubscribed(sessionKey: sessionKey) else { return false }
        switch event {
        case .becameQuiet: return quietEnabled
        case .stopped: return stoppedEnabled
        }
    }

    private var subscribedSessionKeys: Set<String> {
        Set(defaults.stringArray(forKey: sessionsKey) ?? [])
    }
}


struct AppShellView: View {
    @ObservedObject var hostsStore: HostsStore
    let tokenStore: TokenStore
    @ObservedObject var activityStore: ActivityLogStore

    @State private var selectedTab = 0
    @State private var focusedSessionID: String?
    @State private var focusedHostID: UUID?
    @StateObject private var explorerStore: ExplorerWorkspaceStore
    @ObservedObject var notificationPreferences: NotificationPreferencesStore

    init(hostsStore: HostsStore, tokenStore: TokenStore, activityStore: ActivityLogStore, notificationPreferences: NotificationPreferencesStore) {
        self.hostsStore = hostsStore
        self.tokenStore = tokenStore
        self.activityStore = activityStore
        self.notificationPreferences = notificationPreferences
        _explorerStore = StateObject(
            wrappedValue: ExplorerWorkspaceStore(
                hostsStore: hostsStore,
                tokenStore: tokenStore,
                activityStore: activityStore
            )
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                PairingView(hostsStore: hostsStore, tokenStore: tokenStore, activityStore: activityStore)
            }
            .tag(0)
            .tabItem {
                Label("Pairing", systemImage: "dot.radiowaves.left.and.right")
            }

            NavigationStack {
                InventoryView(
                    hostsStore: hostsStore,
                    tokenStore: tokenStore,
                    activityStore: activityStore,
                    explorerStore: explorerStore,
                    notificationPreferences: notificationPreferences,
                    onOpenExplorer: { selectedTab = 2 }
                )
            }
            .tag(1)
            .tabItem {
                Label("Inventory", systemImage: "square.stack.3d.up.fill")
            }

            NavigationStack {
                ExplorerWorkspaceView(
                    explorerStore: explorerStore,
                    onFocusSession: { sessionID, hostID in
                        focusedSessionID = sessionID
                        focusedHostID = hostID
                    }
                )
            }
            .tag(2)
            .tabItem {
                Label("Explorer", systemImage: "rectangle.3.group")
            }

            NavigationStack {
                ActivityView(activityStore: activityStore)
            }
            .tag(3)
            .tabItem {
                Label("Activity", systemImage: "clock.arrow.circlepath")
            }

            NavigationStack {
                NotificationConfigView(notificationPreferences: notificationPreferences)
            }
            .tag(4)
            .tabItem {
                Label("Config", systemImage: "bell.badge")
            }
        }
        .tint(Color("AppTint"))
        .fullScreenCover(isPresented: Binding(
            get: { focusedSessionViewModel != nil },
            set: { if !$0 { clearFocusedSession() } }
        )) {
            if let viewModel = focusedSessionViewModel {
                NavigationStack {
                    SessionDetailView(
                        viewModel: viewModel,
                        onClose: {
                            clearFocusedSession()
                        },
                        onSessionEnded: {
                            explorerStore.disconnect(viewModel)
                            clearFocusedSession()
                        }
                    )
                }
            }
        }
        .task {
            await explorerStore.syncConnectedHosts()
        }
        .onChange(of: hostsStore.savedHosts) {
            Task { await explorerStore.syncConnectedHosts() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .vibeSessionStateDidChange)) { _ in
            explorerStore.pruneEndedSessions()
            if focusedSessionViewModel?.session.isEnded == true {
                clearFocusedSession()
            }
        }
    }

    private var focusedSessionViewModel: SessionViewModel? {
        guard let focusedSessionID, let focusedHostID else { return nil }
        return explorerStore.sessionViewModel(sessionID: focusedSessionID, hostID: focusedHostID)
    }

    private func clearFocusedSession() {
        focusedSessionID = nil
        focusedHostID = nil
    }
}

@MainActor
final class ExplorerWorkspaceStore: ObservableObject {
    @Published private(set) var sessions: [SessionViewModel] = []
    @Published var selectedGroupTag = "all"
    @Published private(set) var isRefreshing = false
    @Published var errorMessage: String?

    private let hostsStore: HostsStore
    private let tokenStore: TokenStore
    private let activityStore: ActivityLogStore
    private var localGroupTabs: [String] = []

    init(hostsStore: HostsStore, tokenStore: TokenStore, activityStore: ActivityLogStore) {
        self.hostsStore = hostsStore
        self.tokenStore = tokenStore
        self.activityStore = activityStore
    }

    var groupTabs: [String] {
        let persisted = sessions.flatMap { $0.session.normalizedGroupTags }
        let merged = Array(Set(localGroupTabs + persisted)).sorted()
        return ["all"] + merged
    }

    var visibleSessions: [SessionViewModel] {
        guard selectedGroupTag != "all" else { return sessions }
        return sessions.filter { $0.session.normalizedGroupTags.contains(selectedGroupTag) }
    }

    func isConnected(sessionID: String, hostID: UUID) -> Bool {
        sessions.contains { $0.session.sessionId == sessionID && $0.host.id == hostID }
    }

    func sessionViewModel(sessionID: String, hostID: UUID) -> SessionViewModel? {
        sessions.first { $0.session.sessionId == sessionID && $0.host.id == hostID }
    }

    func connect(host: SavedHost, session: SessionSummary) {
        guard let token = hostsStore.token(for: host) ?? tokenStore.token(for: host.tokenKey) else {
            errorMessage = "This device is not paired yet."
            return
        }

        if let existing = sessions.first(where: { $0.session.sessionId == session.sessionId && $0.host.id == host.id }) {
            existing.updateSession(session)
            existing.connect()
            return
        }

        let viewModel = SessionViewModel(host: host, token: token, session: session, activityStore: activityStore)
        sessions.insert(viewModel, at: 0)
        sortSessions()
        viewModel.connect()
        hostsStore.touch(hostID: host.id)
        activityStore.record(
            category: .explorer,
            title: "Session added to explorer",
            message: "Connected session preview opened in Explorer.",
            hostLabel: host.displayLabel,
            sessionID: session.sessionId
        )
    }

    func disconnect(_ viewModel: SessionViewModel) {
        viewModel.disconnect()
        sessions.removeAll { $0.session.sessionId == viewModel.session.sessionId && $0.host.id == viewModel.host.id }
        if !groupTabs.contains(selectedGroupTag) {
            selectedGroupTag = "all"
        }
    }

    func stop(_ viewModel: SessionViewModel) async {
        do {
            let client = HostClient(host: viewModel.host)
            try await client.stopSession(
                sessionId: viewModel.session.sessionId,
                host: viewModel.host,
                token: viewModel.token
            )
            viewModel.updateSession(
                SessionSummary(
                    sessionId: viewModel.session.sessionId,
                    provider: viewModel.session.provider,
                    workspaceRoot: viewModel.session.workspaceRoot,
                    title: viewModel.session.title,
                    status: "Exited",
                    conversationId: viewModel.session.conversationId,
                    groupTags: viewModel.session.groupTags,
                    controllerKind: viewModel.session.controllerKind,
                    controllerClientId: viewModel.session.controllerClientId,
                    isRecovered: viewModel.session.isRecovered,
                    archivedRecord: viewModel.session.archivedRecord,
                    isActive: false,
                    inventoryState: "archived",
                    activityState: viewModel.session.activityState,
                    supervisionState: "stopped",
                    attentionState: viewModel.session.attentionState,
                    attentionReason: viewModel.session.attentionReason,
                    createdAtUnixMs: viewModel.session.createdAtUnixMs,
                    lastStatusAtUnixMs: viewModel.session.lastStatusAtUnixMs,
                    lastOutputAtUnixMs: viewModel.session.lastOutputAtUnixMs,
                    lastActivityAtUnixMs: viewModel.session.lastActivityAtUnixMs,
                    lastFileChangeAtUnixMs: viewModel.session.lastFileChangeAtUnixMs,
                    lastGitChangeAtUnixMs: viewModel.session.lastGitChangeAtUnixMs,
                    lastControllerChangeAtUnixMs: viewModel.session.lastControllerChangeAtUnixMs,
                    attentionSinceUnixMs: viewModel.session.attentionSinceUnixMs,
                    currentSequence: viewModel.session.currentSequence,
                    attachedClientCount: viewModel.session.attachedClientCount,
                    recentFileChangeCount: viewModel.session.recentFileChangeCount,
                    gitDirty: viewModel.session.gitDirty,
                    gitBranch: viewModel.session.gitBranch,
                    gitModifiedCount: viewModel.session.gitModifiedCount,
                    gitStagedCount: viewModel.session.gitStagedCount,
                    gitUntrackedCount: viewModel.session.gitUntrackedCount
                )
            )
            disconnect(viewModel)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectGroup(_ tag: String) {
        selectedGroupTag = tag
    }

    func createGroup(named rawValue: String) {
        let tag = SessionSummary.normalizeGroupTag(rawValue)
        guard !tag.isEmpty else { return }
        if !localGroupTabs.contains(tag) {
            localGroupTabs.append(tag)
        }
        selectedGroupTag = tag
    }

    func addSelectedGroup(to viewModel: SessionViewModel) async {
        guard selectedGroupTag != "all" else { return }
        await addGroup(selectedGroupTag, to: viewModel)
    }

    func addGroup(_ tag: String, to viewModel: SessionViewModel) async {
        await updateGroupTags(for: viewModel, mode: .add, tags: [tag])
    }

    func removeGroup(_ tag: String, from viewModel: SessionViewModel) async {
        await updateGroupTags(for: viewModel, mode: .remove, tags: [tag])
    }

    func availableGroups(for viewModel: SessionViewModel) -> [String] {
        groupTabs.filter { $0 != "all" && !viewModel.session.normalizedGroupTags.contains($0) }
    }

    func syncConnectedHosts() async {
        isRefreshing = true
        defer { isRefreshing = false }

        var next: [SessionViewModel] = []
        for viewModel in sessions {
            guard let hostIndex = hostsStore.savedHosts.firstIndex(where: { $0.id == viewModel.host.id }) else {
                viewModel.disconnect()
                continue
            }
            let host = hostsStore.savedHosts[hostIndex]
            guard let token = hostsStore.token(for: host) ?? tokenStore.token(for: host.tokenKey) else {
                viewModel.disconnect()
                continue
            }

            if host.address != viewModel.host.address || host.port != viewModel.host.port || token != viewModel.token {
                let replacement = SessionViewModel(host: host, token: token, session: viewModel.session, activityStore: activityStore)
                replacement.connect()
                next.append(replacement)
            } else {
                next.append(viewModel)
            }
        }

        sessions = next
        sortSessions()
        if !groupTabs.contains(selectedGroupTag) {
            selectedGroupTag = "all"
        }
    }

    func pruneEndedSessions() {
        sessions.removeAll { $0.session.isEnded }
        if !groupTabs.contains(selectedGroupTag) {
            selectedGroupTag = "all"
        }
    }

    private func updateGroupTags(for viewModel: SessionViewModel, mode: SessionGroupTagsUpdateMode, tags: [String]) async {
        do {
            let client = HostClient(host: viewModel.host)
            let normalized = tags.map(SessionSummary.normalizeGroupTag).filter { !$0.isEmpty }
            let response = try await client.updateSessionGroupTags(
                sessionId: viewModel.session.sessionId,
                mode: mode,
                tags: normalized,
                host: viewModel.host,
                token: viewModel.token
            )
            viewModel.updateGroupTags(response.groupTags)
            if mode == .add {
                localGroupTabs.append(contentsOf: response.groupTags)
            }
            if !groupTabs.contains(selectedGroupTag) {
                selectedGroupTag = "all"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sortSessions() {
        sessions.sort {
            let lhsActivity = $0.session.lastActivityAtUnixMs ?? $0.session.createdAtUnixMs ?? 0
            let rhsActivity = $1.session.lastActivityAtUnixMs ?? $1.session.createdAtUnixMs ?? 0
            if lhsActivity != rhsActivity {
                return lhsActivity > rhsActivity
            }
            return $0.session.displayTitle.localizedCaseInsensitiveCompare($1.session.displayTitle) == .orderedAscending
        }
    }
}
extension ExplorerWorkspaceStore {
    static func previewStore(hostsStore: HostsStore, tokenStore: TokenStore, activityStore: ActivityLogStore) -> ExplorerWorkspaceStore {
        let store = ExplorerWorkspaceStore(hostsStore: hostsStore, tokenStore: tokenStore, activityStore: activityStore)
        let token = tokenStore.token(for: PreviewFixtures.hostA.tokenKey) ?? "preview-token"
        let primary = SessionViewModel(host: PreviewFixtures.hostA, token: token, session: PreviewFixtures.sessionA, activityStore: activityStore)
        primary.snapshot = PreviewFixtures.snapshot
        primary.socketState = .connected
        if let tail = PreviewFixtures.snapshot.recentTerminalTail {
            primary.terminal.ingestBase64(tail.data(using: .utf8)!.base64EncodedString(), seqStart: 0, seqEnd: 0)
        }

        let secondary = SessionViewModel(host: PreviewFixtures.hostA, token: token, session: PreviewFixtures.sessionB, activityStore: activityStore)
        secondary.socketState = .disconnected("Observer")
        secondary.terminal.ingestBase64("JCBnaXQgc3RhdHVzXG4/IENvbmZpcm0gZGVwbG95P1xu", seqStart: 0, seqEnd: 0)

        store.sessions = [primary, secondary]
        store.selectedGroupTag = "all"
        return store
    }
}

#Preview("App Shell") {
    let context = PreviewAppContext.make()
    AppShellView(
        hostsStore: context.hostsStore,
        tokenStore: context.tokenStore,
        activityStore: context.activityStore,
        notificationPreferences: context.notificationPreferences
    )
}

private struct NotificationConfigView: View {
    @ObservedObject var notificationPreferences: NotificationPreferencesStore

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color("ActivityBackground"), Color("ActivityBackgroundAlt")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Config")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.94))
                            Text("Choose which subscribed session events can notify this device.")
                                .font(.subheadline)
                                .foregroundStyle(Color.white.opacity(0.62))
                        }
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Permission")
                                    .font(.headline)
                                    .foregroundStyle(Color.white.opacity(0.92))
                                Text(permissionDescription)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.white.opacity(0.64))
                            }
                            Spacer()
                            Button(authorizationButtonTitle) {
                                Task { await notificationPreferences.requestAuthorizationIfNeeded() }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color("AppTint"))
                            .disabled(notificationPreferences.authorizationStatus == .authorized || notificationPreferences.authorizationStatus == .provisional)
                        }

                        Toggle(isOn: Binding(get: { notificationPreferences.quietEnabled }, set: { notificationPreferences.setQuietEnabled($0) })) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Session became quiet")
                                    .font(.headline)
                                    .foregroundStyle(Color.white.opacity(0.9))
                                Text("Notify when a subscribed session transitions from active to quiet.")
                                    .font(.footnote)
                                    .foregroundStyle(Color.white.opacity(0.6))
                            }
                        }
                        .tint(Color("AppTint"))

                        Toggle(isOn: Binding(get: { notificationPreferences.stoppedEnabled }, set: { notificationPreferences.setStoppedEnabled($0) })) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Session stopped")
                                    .font(.headline)
                                    .foregroundStyle(Color.white.opacity(0.9))
                                Text("Notify when a subscribed session exits or errors.")
                                    .font(.footnote)
                                    .foregroundStyle(Color.white.opacity(0.6))
                            }
                        }
                        .tint(Color("AppTint"))
                    }
                    .padding(18)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await notificationPreferences.refreshAuthorizationStatus()
        }
    }

    private var authorizationButtonTitle: String {
        switch notificationPreferences.authorizationStatus {
        case .authorized, .provisional: return "Enabled"
        case .denied: return "Denied"
        default: return "Allow"
        }
    }

    private var permissionDescription: String {
        switch notificationPreferences.authorizationStatus {
        case .authorized, .provisional: return "System notifications are enabled for Sentrits."
        case .denied: return "Notifications are denied in system settings."
        default: return "Allow notifications to receive quiet and stopped session alerts."
        }
    }
}
