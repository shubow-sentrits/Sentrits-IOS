import SwiftUI

struct InventoryView: View {
    struct CreateSheetContext: Identifiable {
        let host: SavedHost
        let token: String

        var id: UUID { host.id }
    }

    @ObservedObject var hostsStore: HostsStore
    let tokenStore: TokenStore
    @ObservedObject var activityStore: ActivityLogStore
    @ObservedObject var explorerStore: ExplorerWorkspaceStore
    let notificationPreferences: NotificationPreferencesStore
    let onOpenExplorer: () -> Void

    @ObservedObject private var store: InventoryStore
    @State private var createSheetHost: CreateSheetContext?
    @State private var inventoryError: String?
    @State private var clearStoppedHost: SavedHost?
    private let autoRefreshOnAppear: Bool

    init(
        hostsStore: HostsStore,
        tokenStore: TokenStore,
        activityStore: ActivityLogStore,
        explorerStore: ExplorerWorkspaceStore,
        notificationPreferences: NotificationPreferencesStore,
        onOpenExplorer: @escaping () -> Void,
        sharedStore: InventoryStore,
        previewStore: InventoryStore? = nil,
        autoRefreshOnAppear: Bool = true
    ) {
        self.hostsStore = hostsStore
        self.tokenStore = tokenStore
        self.activityStore = activityStore
        self.explorerStore = explorerStore
        self.notificationPreferences = notificationPreferences
        self.onOpenExplorer = onOpenExplorer
        self.store = previewStore ?? sharedStore
        self.autoRefreshOnAppear = autoRefreshOnAppear
    }

    var body: some View {
        let base = AnyView(
            ZStack {
                inventoryBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        titleRow
                        summaryPanel
                        controlsRow
                        sectionList
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 120)
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    await store.refresh()
                }
            }
        )

        let withChrome = AnyView(
            base
                .toolbar(.hidden, for: .navigationBar)
        )

        let withRefresh = AnyView(
            withChrome
        )

        let withSheets = AnyView(
            withRefresh
                .sheet(item: $createSheetHost) { context in
                    CreateSessionSheet(host: context.host, token: context.token) { input in
                        do {
                            _ = try await store.createSession(hostID: context.host.id, input: input)
                        } catch {
                            inventoryError = error.localizedDescription
                        }
                    }
                }
        )

        return AnyView(
            withSheets
                .task {
                    guard autoRefreshOnAppear, store.sections.isEmpty, !store.isRefreshing else { return }
                    await store.refresh()
                }
                .alert("Remove stopped sessions?", isPresented: Binding(
                    get: { clearStoppedHost != nil },
                    set: { isPresented in
                        if !isPresented {
                            clearStoppedHost = nil
                        }
                    }
                ), presenting: clearStoppedHost) { host in
                    Button("Cancel", role: .cancel) {
                        clearStoppedHost = nil
                    }
                    Button("Remove", role: .destructive) {
                        Task {
                            do {
                                try await store.clearStoppedSessions(hostID: host.id)
                            } catch {
                                inventoryError = error.localizedDescription
                            }
                            clearStoppedHost = nil
                        }
                    }
                } message: { host in
                    Text("Remove all stopped sessions for \(hostTitle(host))?")
                }
                .alert("Inventory Error", isPresented: Binding(
                    get: { inventoryError != nil },
                    set: { isPresented in
                        if !isPresented {
                            inventoryError = nil
                        }
                    }
                )) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(inventoryError ?? "")
                }
        )
    }

    private func hostTitle(_ host: SavedHost) -> String {
        if let alias = host.preferredAlias {
            return alias
        }
        if !host.displayName.isEmpty {
            return host.displayName
        }
        return host.address
    }

    private var summaryPanel: some View {
        let sectionCount = store.sections.count
        let sessionCount = store.sections.reduce(0) { $0 + $1.sessions.count }
        let liveCount = store.sections.reduce(0) { partial, section in
            partial + section.sessions.filter { !$0.isEnded }.count
        }

        return VStack(alignment: .leading, spacing: 12) {
            Text("Create, stop, and connect sessions by paired device.")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.68))

            HStack(spacing: 12) {
                inventoryMetric(title: "Devices", value: "\(sectionCount)")
                inventoryMetric(title: "Sessions", value: "\(sessionCount)")
                inventoryMetric(title: "Live", value: "\(liveCount)")
            }
        }
        .padding(18)
        .background(Color("InventoryPanel").opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var titleRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Inventory")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.94))

                Text("Create, stop, and connect sessions by device.")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.62))
            }

            Spacer()

            if store.isRefreshing {
                ProgressView()
                    .tint(Color("InventoryAccent"))
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controlsRow: some View {
        HStack {
            Toggle(isOn: $store.showStoppedSessions) {
                Text("Show ended sessions")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.78))
            }
            .tint(Color("InventoryAccent"))

            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var sectionList: some View {
        VStack(spacing: 18) {
            if store.sections.isEmpty {
                emptyInventoryPanel
            } else {
                ForEach(store.sections) { section in
                    deviceSection(section)
                }
            }
        }
    }

    private var emptyInventoryPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No saved devices yet")
                .font(.headline)
                .foregroundStyle(Color.white.opacity(0.9))
            Text("Pair a device first to load its runtime sessions here.")
                .foregroundStyle(Color.white.opacity(0.66))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color("InventoryPanel").opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func deviceSection(_ section: InventoryDeviceSection) -> some View {
        let visibleSessions = store.visibleSessions(for: section)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(hostTitle(section.host))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.92))
                    Text("\(section.host.address):\(section.host.port)")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.54))
                    if let alias = section.host.preferredAlias {
                        Text(section.host.displayName)
                            .font(.caption)
                            .foregroundStyle(Color("InventoryAccent").opacity(0.92))
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("\(visibleSessions.count) visible")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())

                        Button {
                            clearStoppedHost = section.host
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption.weight(.bold))
                                .frame(width: 30, height: 12)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red.opacity(0.82))
                        .disabled(section.token == nil || store.isBusy(hostID: section.host.id))
                    }

                    Button {
                        if let token = section.token {
                            createSheetHost = CreateSheetContext(host: section.host, token: token)
                        }
                    } label: {
                        Label("New Session", systemImage: "plus")
                            .font(.footnote.weight(.bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color("InventoryAccent"))
                    .disabled(section.token == nil || store.isBusy(hostID: section.host.id))
                }
                .padding(.vertical, -10)
            }

            if let errorMessage = section.errorMessage {
                inventoryMessage(errorMessage, color: .red.opacity(0.84))
            } else if section.token == nil {
                inventoryMessage("Pair this device before loading or creating sessions.", color: Color.white.opacity(0.62))
            } else if visibleSessions.isEmpty {
                inventoryMessage("No sessions for this device.", color: Color.white.opacity(0.62))
            }

            ForEach(visibleSessions) { session in
                sessionCard(section: section, session: session)
            }
        }
        .padding(20)
        .background(Color("InventoryPanel").opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color("InventoryAccent"))
                .frame(width: 5, height: 36)
                .padding(.leading, 8)
                .padding(.top, 18)
        }
    }

    private func sessionCard(section: InventoryDeviceSection, session: SessionSummary) -> some View {
        let isConnected = explorerStore.isConnected(sessionID: session.sessionId, hostID: section.host.id)
        let canConnect = session.isConnectable

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.displayTitle)
                        .font(.headline)
                        .foregroundStyle(Color.white.opacity(0.92))
                    Text(session.sessionId)
                        .font(.caption2.monospaced())
                        .foregroundStyle(Color.white.opacity(0.48))
                    Text(session.workspaceRoot)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.58))
                        .lineLimit(2)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    statusBadge(session.inventoryStateLabel, color: statusColor(for: session))
                    statusBadge(session.supervisionStateLabel, color: supervisionColor(for: session))
                    if let attention = session.attentionState, attention != "none" {
                        statusBadge(attention, color: attentionColor(for: session))
                    }
                }
            }.padding(.vertical, -4)

            HStack(spacing: 8) {
                detailChip(session.provider.uppercased(), tint: Color("InventoryAccent"))
                Button {
                    let sessionKey = session.notificationKey(hostID: section.host.id)
                    let willSubscribe = !notificationPreferences.isSubscribed(sessionKey: sessionKey)
                    notificationPreferences.toggleSubscription(sessionKey: sessionKey)
                    activityStore.record(
                        category: .inventory,
                        title: willSubscribe ? "Subscribed to session notifications" : "Muted session notifications",
                        message: "\(session.displayTitle) on \(hostTitle(section.host)).",
                        hostLabel: section.host.displayLabel,
                        sessionID: session.sessionId
                    )
                } label: {
                    Image(systemName: notificationPreferences.isSubscribed(sessionKey: session.notificationKey(hostID: section.host.id)) ? "bell.fill" : "bell.slash")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(notificationPreferences.isSubscribed(sessionKey: session.notificationKey(hostID: section.host.id)) ? Color("InventoryAccent") : Color.white.opacity(0.55))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
                detailChip("control \(session.controllerKind)", tint: controllerColor(session.controllerKind))
                if let attached = session.attachedClientCount, attached > 0 {
                    detailChip("\(attached) attached", tint: .blue.opacity(0.85))
                }
            }.padding(.vertical, -4)

            HStack(spacing: 8) {
                if let branch = session.gitBranch, !branch.isEmpty {
                    detailChip(branch, tint: session.gitDirty == true ? .orange.opacity(0.9) : .white.opacity(0.55))
                }
                if let fileChanges = session.recentFileChangeCount, fileChanges > 0 {
                    detailChip("+\(fileChanges) files", tint: .yellow.opacity(0.85))
                } else {
                    detailChip("files steady", tint: .white.opacity(0.45))
                }
            }.padding(.vertical, -4)

            if !session.groupTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(session.groupTags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.white.opacity(0.7))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Capsule())
                        }
                    }
                }.padding(.vertical, -4)
            }

            HStack(spacing: 10) {
                Button {
                    Task { @MainActor in
                        if isConnected {
                            if let connected = explorerStore.sessions.first(where: { $0.session.sessionId == session.sessionId && $0.host.id == section.host.id }) {
                                explorerStore.disconnect(connected)
                            }
                        } else {
                            explorerStore.connect(host: section.host, session: session)
                            onOpenExplorer()
                        }
                    }
                } label: {
                    Label(isConnected ? "Disconnect" : "Connect", systemImage: isConnected ? "bolt.slash" : "terminal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(canConnect ? (isConnected ? .gray.opacity(0.7) : Color("InventoryAccent")) : .gray.opacity(0.55))
                .disabled(section.token == nil || !canConnect)

                Button(role: .destructive) {
                    Task {
                        do {
                            try await store.stopSession(hostID: section.host.id, sessionID: session.sessionId)
                            if let connected = explorerStore.sessions.first(where: { $0.session.sessionId == session.sessionId && $0.host.id == section.host.id }) {
                                explorerStore.disconnect(connected)
                            }
                        } catch {
                            inventoryError = error.localizedDescription
                        }
                    }
                } label: {
                    if store.isBusy(sessionID: session.sessionId) {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Stop", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .tint(.red.opacity(0.9))
                .disabled(section.token == nil || store.isBusy(sessionID: session.sessionId))
            }.padding(.bottom, -6)
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func inventoryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.92))
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.white.opacity(0.52))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func inventoryMessage(_ message: String, color: Color) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func detailChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }

    private func statusBadge(_ text: String, color: Color) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    private func statusColor(for session: SessionSummary) -> Color {
        switch session.inventoryStateLabel.lowercased() {
        case "live", "running", "attached", "starting":
            return Color("InventoryAccent")
        case "archived":
            return .orange.opacity(0.92)
        default:
            return .gray.opacity(0.82)
        }
    }

    private func attentionColor(for session: SessionSummary) -> Color {
        switch session.attentionState?.lowercased() {
        case "needs_review":
            return .orange.opacity(0.92)
        case "urgent":
            return .red.opacity(0.92)
        default:
            return .yellow.opacity(0.9)
        }
    }

    private func supervisionColor(for session: SessionSummary) -> Color {
        switch session.supervisionStateLabel.lowercased() {
        case "active":
            return .green.opacity(0.92)
        case "stopped":
            return .gray.opacity(0.82)
        default:
            return .orange.opacity(0.9)
        }
    }

    private func controllerColor(_ kind: String) -> Color {
        switch kind.lowercased() {
        case "remote":
            return .green.opacity(0.92)
        case "observer":
            return .blue.opacity(0.92)
        default:
            return .white.opacity(0.55)
        }
    }

    private var inventoryBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color("InventoryBackground"),
                    Color("InventoryBackgroundAlt")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color("InventoryAccent").opacity(0.14),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 24,
                endRadius: 340
            )
        }
    }

}

private struct CreateSessionSheet: View {
    let host: SavedHost
    let token: String
    let onSubmit: (CreateSessionInput) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var input = CreateSessionInput()
    @State private var setups: [SessionSetup] = []
    @State private var isLoadingSetups = false
    @State private var isSavingSetup = false
    @State private var setupStatus: String?
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Device") {
                    Text(host.displayLabel)
                    Text(host.useTLS ? "HTTPS / WSS" : "HTTP / WS")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Saved Setup") {
                    Picker("Setup", selection: $input.selectedSetupID) {
                        Text("Custom launch").tag("")
                        ForEach(setups) { setup in
                            Text(setup.name).tag(setup.setupId)
                        }
                    }
                    .onChange(of: input.selectedSetupID) { _, newValue in
                        guard let setup = setups.first(where: { $0.setupId == newValue }) else { return }
                        apply(setup: setup)
                    }

                    TextField("Setup name", text: $input.setupName)
                    Button(isSavingSetup ? "Saving…" : "Save Setup") {
                        Task { await saveSetup() }
                    }
                    .disabled(isSavingSetup || input.normalizedWorkspaceRoot.isEmpty)

                    if let setupStatus {
                        Text(setupStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Session") {
                    TextField("Workspace path", text: $input.workspaceRoot)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("Launch Mode", selection: $input.launchMode) {
                        ForEach(SessionLaunchMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    TextField(input.launchMode == .shell ? "Shell command" : "Command", text: $input.commandText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Title", text: $input.title)
                    Picker("Provider", selection: $input.provider) {
                        ForEach(SessionProvider.allCases) { provider in
                            Text(provider.label).tag(provider)
                        }
                    }
                    TextField("Conversation ID", text: $input.conversationId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Group tags (comma separated)", text: $input.groupTagsText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("New Session")
            .task {
                await loadSetups()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        Task {
                            isSubmitting = true
                            await onSubmit(input)
                            isSubmitting = false
                            dismiss()
                        }
                    }
                    .disabled(isSubmitting || input.normalizedWorkspaceRoot.isEmpty)
                }
            }
        }
    }

    private func loadSetups() async {
        isLoadingSetups = true
        defer { isLoadingSetups = false }
        do {
            setups = try await HostClient(host: host).fetchSessionSetups(for: host, token: token)
        } catch {
            setupStatus = error.localizedDescription
        }
    }

    private func saveSetup() async {
        isSavingSetup = true
        defer { isSavingSetup = false }
        do {
            let saved = try await HostClient(host: host).saveSessionSetup(host: host, token: token, input: input)
            input.selectedSetupID = saved.setupId
            input.setupName = saved.name
            setups = try await HostClient(host: host).fetchSessionSetups(for: host, token: token)
            setupStatus = "Saved \(saved.name)."
        } catch {
            setupStatus = error.localizedDescription
        }
    }

    private func apply(setup: SessionSetup) {
        input.setupName = setup.name
        input.provider = SessionProvider(rawValue: setup.provider) ?? .codex
        input.workspaceRoot = setup.workspaceRoot
        input.title = setup.title
        input.conversationId = setup.conversationId ?? ""
        input.groupTagsText = (setup.groupTags ?? []).joined(separator: ", ")
        if let shell = setup.commandShell, !shell.isEmpty {
            input.launchMode = .shell
            input.commandText = shell
        } else if let argv = setup.commandArgv, !argv.isEmpty {
            input.launchMode = .argv
            input.commandText = argv.joined(separator: " ")
        } else {
            input.launchMode = .providerDefault
            input.commandText = ""
        }
    }
}

#Preview("Inventory") {
    let context = PreviewAppContext.make()
    NavigationStack {
        InventoryView(
            hostsStore: context.hostsStore,
            tokenStore: context.tokenStore,
            activityStore: context.activityStore,
            explorerStore: context.explorerStore,
            notificationPreferences: context.notificationPreferences,
            onOpenExplorer: {},
            sharedStore: context.inventoryStore,
            previewStore: context.inventoryStore,
            autoRefreshOnAppear: false
        )
    }
}
