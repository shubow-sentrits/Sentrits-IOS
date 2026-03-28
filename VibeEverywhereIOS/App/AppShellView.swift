import SwiftUI

struct AppShellView: View {
    @ObservedObject var hostsStore: HostsStore
    let tokenStore: TokenStore
    @ObservedObject var activityStore: ActivityLogStore

    @State private var selectedTab = 0
    @State private var focusedSessionID: String?
    @State private var focusedHostID: UUID?
    @StateObject private var explorerStore: ExplorerWorkspaceStore

    init(hostsStore: HostsStore, tokenStore: TokenStore, activityStore: ActivityLogStore) {
        self.hostsStore = hostsStore
        self.tokenStore = tokenStore
        self.activityStore = activityStore
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
        }
        .tint(ActivityPalette.primary)
        .fullScreenCover(isPresented: Binding(
            get: { focusedSessionViewModel != nil },
            set: { if !$0 { clearFocusedSession() } }
        )) {
            if let viewModel = focusedSessionViewModel {
                NavigationStack {
                    SessionDetailView(viewModel: viewModel) {
                        explorerStore.disconnect(viewModel)
                        clearFocusedSession()
                    }
                }
            }
        }
        .task {
            await explorerStore.syncConnectedHosts()
        }
        .onChange(of: hostsStore.savedHosts) {
            Task { await explorerStore.syncConnectedHosts() }
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
        await viewModel.stopSession()
        if viewModel.session.isEnded {
            disconnect(viewModel)
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

private struct ExplorerWorkspaceView: View {
    @ObservedObject var explorerStore: ExplorerWorkspaceStore
    let onFocusSession: (String, UUID) -> Void
    @State private var draftGroupName = ""
    @State private var isCreateGroupPresented = false

    var body: some View {
        ZStack {
            Color.explorerBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    heroPanel
                    groupStrip
                    content
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .refreshable {
                await explorerStore.syncConnectedHosts()
            }
        }
        .navigationTitle("Explorer")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isCreateGroupPresented) {
            createGroupSheet
                .presentationDetents([.height(240)])
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isCreateGroupPresented = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
        }
        .alert("Explorer Error", isPresented: Binding(
            get: { explorerStore.errorMessage != nil },
            set: { if !$0 { explorerStore.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(explorerStore.errorMessage ?? "")
        }
    }

    private var heroPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connected sessions stay here. Focus one when you need the larger terminal.")
                .font(.subheadline)
                .foregroundStyle(Color.explorerMuted)

            HStack(spacing: 10) {
                explorerMetric(value: "\(explorerStore.sessions.count)", label: "Connected")
                explorerMetric(value: "\(max(0, explorerStore.groupTabs.count - 1))", label: "Groups")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.explorerPanel)
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }

    private var groupStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(explorerStore.groupTabs, id: \.self) { tag in
                    Button {
                        explorerStore.selectGroup(tag)
                    } label: {
                        Text(tag == "all" ? "All" : "#\(tag)")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(explorerStore.selectedGroupTag == tag ? Color.explorerAccent : Color.explorerPanelSoft)
                            .foregroundStyle(explorerStore.selectedGroupTag == tag ? Color.explorerBackground : Color.explorerText)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if explorerStore.visibleSessions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("No connected sessions match this group.")
                    .font(.headline)
                    .foregroundStyle(Color.explorerText)
                Text("Connect a session from Inventory. All always shows every connected session.")
                    .font(.subheadline)
                    .foregroundStyle(Color.explorerMuted)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.explorerPanelSoft)
            .clipShape(RoundedRectangle(cornerRadius: 24))
        } else {
            LazyVStack(spacing: 16) {
                ForEach(explorerStore.visibleSessions, id: \.session.sessionId) { sessionViewModel in
                    sessionTile(for: sessionViewModel)
                }
            }
        }
    }

    private func sessionTile(for sessionViewModel: SessionViewModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(sessionViewModel.session.displayTitle)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.explorerText)
                    Text(sessionViewModel.host.displayLabel)
                        .font(.footnote)
                        .foregroundStyle(Color.explorerMuted)
                    Text(sessionViewModel.session.workspaceRoot)
                        .font(.footnote)
                        .foregroundStyle(Color.explorerMuted)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    onFocusSession(sessionViewModel.session.sessionId, sessionViewModel.host.id)
                } label: {
                    Label("Focus", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.explorerAccent)
            }

            TerminalTextView(
                terminal: sessionViewModel.terminal,
                mode: .preview,
                isInputEnabled: false,
                onInput: { _ in },
                onResize: { _ in }
            )
            .frame(height: 218)

            HStack(spacing: 8) {
                explorerTag(sessionViewModel.session.status, tone: sessionTone(for: sessionViewModel.session.status))
                explorerTag(socketText(for: sessionViewModel.socketState), tone: socketTone(for: sessionViewModel.socketState))
                explorerTag(sessionViewModel.session.controllerKind, tone: sessionViewModel.canSendInput ? Color.green : Color.orange)
                if let branch = sessionViewModel.primaryGitBranch, !branch.isEmpty {
                    explorerTag(branch, tone: Color.explorerAccent.opacity(0.8))
                }
            }

            HStack(spacing: 8) {
                Button {
                    onFocusSession(sessionViewModel.session.sessionId, sessionViewModel.host.id)
                } label: {
                    Label("Focus", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.explorerAccent)
                .controlSize(.small)

                Button(sessionViewModel.canSendInput ? "Release" : "Request Control") {
                    Task {
                        if sessionViewModel.canSendInput {
                            await sessionViewModel.releaseControl()
                        } else {
                            await sessionViewModel.requestControl()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.explorerHighlight)
                .controlSize(.small)

                Spacer()

                Button("Stop", role: .destructive) {
                    Task { await explorerStore.stop(sessionViewModel) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Disconnect") {
                    explorerStore.disconnect(sessionViewModel)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(spacing: 8) {
                if explorerStore.selectedGroupTag != "all",
                   !sessionViewModel.session.normalizedGroupTags.contains(explorerStore.selectedGroupTag) {
                    Button("Add To Group") {
                        Task { await explorerStore.addSelectedGroup(to: sessionViewModel) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.explorerHighlight.opacity(0.92))
                    .controlSize(.small)
                }

                Menu("Groups") {
                    ForEach(explorerStore.availableGroups(for: sessionViewModel), id: \.self) { tag in
                        Button("Add #\(tag)") {
                            Task { await explorerStore.addGroup(tag, to: sessionViewModel) }
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.explorerPanelSoft)
                .controlSize(.small)

                Spacer()

                if !sessionViewModel.session.groupTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(sessionViewModel.session.groupTags, id: \.self) { tag in
                                Button {
                                    Task { await explorerStore.removeGroup(tag, from: sessionViewModel) }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text("#\(tag)")
                                        Image(systemName: "minus.circle.fill")
                                            .font(.caption2)
                                    }
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 6)
                                    .background(Color.explorerPanelSoft)
                                    .foregroundStyle(Color.explorerText)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.explorerPanel)
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 26))
    }

    private var createGroupSheet: some View {
        NavigationStack {
            Form {
                Section("New Group") {
                    TextField("group-name", text: $draftGroupName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Create Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        draftGroupName = ""
                        isCreateGroupPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        explorerStore.createGroup(named: draftGroupName)
                        draftGroupName = ""
                        isCreateGroupPresented = false
                    }
                    .disabled(SessionSummary.normalizeGroupTag(draftGroupName).isEmpty)
                }
            }
        }
    }

    private func explorerMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Color.explorerText)
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.explorerMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.explorerPanelSoft)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func explorerTag(_ text: String, tone: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tone)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tone.opacity(0.18))
            .clipShape(Capsule())
    }

    private func sessionTone(for status: String) -> Color {
        switch status.lowercased() {
        case "running", "attached", "starting", "awaitinginput":
            return .green
        case "exited":
            return .gray
        case "error":
            return .red
        default:
            return .orange
        }
    }

    private func socketText(for state: SessionSocket.ConnectionState) -> String {
        switch state {
        case .idle: return "idle"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case let .disconnected(reason): return reason ?? "disconnected"
        }
    }

    private func socketTone(for state: SessionSocket.ConnectionState) -> Color {
        switch state {
        case .connected: return .green
        case .connecting: return .orange
        case .idle, .disconnected: return .gray
        }
    }
}


private extension Color {
    static let explorerBackground = Color(red: 0.05, green: 0.06, blue: 0.08)
    static let explorerPanel = Color(red: 0.12, green: 0.14, blue: 0.18)
    static let explorerPanelSoft = Color(red: 0.16, green: 0.18, blue: 0.22)
    static let explorerText = Color(red: 0.95, green: 0.96, blue: 0.94)
    static let explorerMuted = Color(red: 0.67, green: 0.70, blue: 0.75)
    static let explorerAccent = Color(red: 0.77, green: 0.84, blue: 0.58)
    static let explorerHighlight = Color(red: 0.90, green: 0.74, blue: 0.44)
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

#Preview("Explorer") {
    let context = PreviewAppContext.make()
    NavigationStack {
        ExplorerWorkspaceView(explorerStore: context.explorerStore, onFocusSession: { _, _ in })
    }
}

#Preview("App Shell") {
    let context = PreviewAppContext.make()
    AppShellView(
        hostsStore: context.hostsStore,
        tokenStore: context.tokenStore,
        activityStore: context.activityStore
    )
}
