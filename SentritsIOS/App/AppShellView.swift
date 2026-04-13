import SwiftUI
import UserNotifications

enum QuietNotificationThreshold: Int, CaseIterable, Identifiable {
    case seconds5 = 5
    case seconds15 = 15
    case seconds30 = 30
    case seconds60 = 60

    var id: Int { rawValue }

    var label: String { "\(rawValue)s" }
}

@MainActor
final class NotificationPreferencesStore: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var quietEnabled: Bool
    @Published var stoppedEnabled: Bool
    @Published var quietThreshold: QuietNotificationThreshold
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let defaults: UserDefaults
    private let quietKey = "notifications.event.quiet"
    private let stoppedKey = "notifications.event.stopped"
    private let quietThresholdKey = "notifications.event.quiet.threshold"
    private let sessionsKey = "notifications.sessions"
    private let subscriptionTimestampsKey = "notifications.sessions.subscribedAt"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.quietEnabled = defaults.object(forKey: quietKey) as? Bool ?? false
        self.stoppedEnabled = defaults.object(forKey: stoppedKey) as? Bool ?? false
        self.quietThreshold = QuietNotificationThreshold(rawValue: defaults.integer(forKey: quietThresholdKey)) ?? .seconds15
        super.init()
        UNUserNotificationCenter.current().delegate = self
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

    func setQuietThreshold(_ value: QuietNotificationThreshold) {
        quietThreshold = value
        defaults.set(value.rawValue, forKey: quietThresholdKey)
    }

    func isSubscribed(sessionKey: String) -> Bool {
        subscribedSessionKeys.contains(sessionKey)
    }

    func toggleSubscription(sessionKey: String) {
        var keys = subscribedSessionKeys
        var timestamps = subscribedSessionTimestamps
        if keys.contains(sessionKey) {
            keys.remove(sessionKey)
            timestamps.removeValue(forKey: sessionKey)
        } else {
            keys.insert(sessionKey)
            timestamps[sessionKey] = Int64(Date().timeIntervalSince1970 * 1000)
        }
        defaults.set(Array(keys).sorted(), forKey: sessionsKey)
        defaults.set(timestamps, forKey: subscriptionTimestampsKey)
        objectWillChange.send()
    }

    func setSubscription(sessionKey: String, subscribed: Bool) {
        setSubscriptions(sessionKeys: [sessionKey], subscribed: subscribed)
    }

    func setSubscriptions(sessionKeys: [String], subscribed: Bool) {
        guard !sessionKeys.isEmpty else { return }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let normalizedKeys = Array(Set(sessionKeys))
        var keys = subscribedSessionKeys
        var timestamps = subscribedSessionTimestamps
        var didChange = false

        for sessionKey in normalizedKeys {
            if subscribed {
                if !keys.contains(sessionKey) {
                    keys.insert(sessionKey)
                    timestamps[sessionKey] = now
                    didChange = true
                }
            } else {
                if keys.remove(sessionKey) != nil {
                    timestamps.removeValue(forKey: sessionKey)
                    didChange = true
                }
            }
        }

        guard didChange else { return }
        defaults.set(Array(keys).sorted(), forKey: sessionsKey)
        defaults.set(timestamps, forKey: subscriptionTimestampsKey)
        objectWillChange.send()
    }

    func shouldNotify(for event: InventoryNotificationEvent, sessionKey: String) -> Bool {
        guard isSubscribed(sessionKey: sessionKey) else { return false }
        switch event {
        case .becameQuiet: return quietEnabled
        case .stopped: return stoppedEnabled
        }
    }

    func pruneSubscriptions(keepingOnly liveKeys: Set<String>) {
        let stale = subscribedSessionKeys.subtracting(liveKeys)
        guard !stale.isEmpty else { return }
        setSubscriptions(sessionKeys: Array(stale), subscribed: false)
    }

    func subscriptionStartedAtUnixMs(sessionKey: String) -> Int64? {
        subscribedSessionTimestamps[sessionKey]
    }

    private var subscribedSessionKeys: Set<String> {
        Set(defaults.stringArray(forKey: sessionsKey) ?? [])
    }

    private var subscribedSessionTimestamps: [String: Int64] {
        let raw = defaults.dictionary(forKey: subscriptionTimestampsKey) ?? [:]
        var timestamps: [String: Int64] = [:]
        for (key, value) in raw {
            if let int64Value = value as? Int64 {
                timestamps[key] = int64Value
            } else if let intValue = value as? Int {
                timestamps[key] = Int64(intValue)
            } else if let doubleValue = value as? Double {
                timestamps[key] = Int64(doubleValue)
            } else if let numberValue = value as? NSNumber {
                timestamps[key] = numberValue.int64Value
            }
        }
        return timestamps
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}


struct AppShellView: View {
    @ObservedObject var hostsStore: HostsStore
    let tokenStore: TokenStore
    @ObservedObject var activityStore: ActivityLogStore

    @State private var selectedTab = 0
    @State private var focusedSessionID: String?
    @State private var focusedHostID: UUID?
    @State private var pendingInventoryRefreshTask: Task<Void, Never>?
    @StateObject private var explorerStore: ExplorerWorkspaceStore
    @StateObject private var inventoryStore: InventoryStore
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
        _inventoryStore = StateObject(
            wrappedValue: InventoryStore(
                hostsStore: hostsStore,
                tokenStore: tokenStore,
                notificationPreferences: notificationPreferences,
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
                    onOpenExplorer: { selectedTab = 2 },
                    sharedStore: inventoryStore
                )
            }
            .tag(1)
            .tabItem {
                Label("Inventory", systemImage: "square.stack.3d.up.fill")
            }

            NavigationStack {
                ExplorerWorkspaceView(
                    explorerStore: explorerStore,
                    notificationPreferences: notificationPreferences,
                    activityStore: activityStore,
                    onFocusSession: { sessionID, hostID in
                        if let viewModel = explorerStore.sessionViewModel(sessionID: sessionID, hostID: hostID) {
                            SentritsDebugTrace.log(
                                "ios.explorer",
                                "focus",
                                "host=\(viewModel.host.displayLabel) id=\(viewModel.host.id.uuidString) endpoint=\(viewModel.host.address):\(viewModel.host.port) session=\(sessionID)"
                            )
                        }
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
                        notificationPreferences: notificationPreferences,
                        activityStore: activityStore,
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
            await inventoryStore.refresh()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { break }
                await inventoryStore.refresh()
            }
        }
        .task {
            await explorerStore.syncConnectedHosts()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { break }
                await explorerStore.syncConnectedHosts()
            }
        }
        .onChange(of: hostsStore.savedHosts) {
            pendingInventoryRefreshTask?.cancel()
            Task { await inventoryStore.refresh() }
        }
        .onChange(of: hostsStore.savedHosts) {
            Task { await explorerStore.syncConnectedHosts() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .vibeSessionStateDidChange)) { _ in
            pendingInventoryRefreshTask?.cancel()
            pendingInventoryRefreshTask = Task {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                await inventoryStore.refresh()
            }
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
        SentritsDebugTrace.log(
            "ios.explorer",
            "connect",
            "host=\(host.displayLabel) id=\(host.id.uuidString) endpoint=\(host.address):\(host.port) session=\(session.sessionId)"
        )
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
        var sessionsByHost: [UUID: [String: SessionSummary]] = [:]
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

            if sessionsByHost[host.id] == nil {
                do {
                    let client = HostClient(host: host)
                    let summaries = try await client.listSessions(for: host, token: token)
                    sessionsByHost[host.id] = Dictionary(uniqueKeysWithValues: summaries.map { ($0.sessionId, $0) })
                } catch {
                    errorMessage = error.localizedDescription
                    sessionsByHost[host.id] = [:]
                }
            }

            if let refreshed = sessionsByHost[host.id]?[viewModel.session.sessionId] {
                viewModel.updateSession(refreshed)
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
    @AppStorage("terminal.renderer.kind") private var terminalRendererRawValue = TerminalRendererKind.swiftTerm.rawValue

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

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Quiet notification delay")
                                .font(.headline)
                                .foregroundStyle(Color.white.opacity(0.9))
                            Text("Send the quiet alert only after the session has remained quiet for this long.")
                                .font(.footnote)
                                .foregroundStyle(Color.white.opacity(0.6))

                            Picker("Quiet notification delay", selection: Binding(
                                get: { notificationPreferences.quietThreshold },
                                set: { notificationPreferences.setQuietThreshold($0) }
                            )) {
                                ForEach(QuietNotificationThreshold.allCases) { threshold in
                                    Text(threshold.label).tag(threshold)
                                }
                            }
                            .pickerStyle(.segmented)
                            .disabled(!notificationPreferences.quietEnabled)
                        }

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

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Terminal renderer")
                                .font(.headline)
                                .foregroundStyle(Color.white.opacity(0.9))
                            Text("SwiftTerm is the default native renderer. Switch back to xterm.js if you need the old fallback.")
                                .font(.footnote)
                                .foregroundStyle(Color.white.opacity(0.6))

                            Picker("Terminal renderer", selection: Binding(
                                get: { terminalRenderer },
                                set: { terminalRendererRawValue = $0.rawValue }
                            )) {
                                ForEach(TerminalRendererKind.allCases) { renderer in
                                    Text(renderer.label).tag(renderer)
                                }
                            }
                            .pickerStyle(.segmented)

                            Text(terminalRenderer.detail)
                                .font(.caption)
                                .foregroundStyle(Color.white.opacity(0.52))
                        }
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

    private var terminalRenderer: TerminalRendererKind {
        TerminalRendererKind(rawValue: terminalRendererRawValue) ?? .swiftTerm
    }
}
