import SwiftUI

struct SessionsView: View {
    let host: SavedHost
    let token: String
    let onConnected: () -> Void
    @ObservedObject var activityStore: ActivityLogStore

    @StateObject private var viewModel: SessionsViewModel
    @State private var draftGroupName = ""
    @State private var isCreateGroupPresented = false
    private let autoStart: Bool

    init(host: SavedHost, token: String, onConnected: @escaping () -> Void, activityStore: ActivityLogStore) {
        self.host = host
        self.token = token
        self.onConnected = onConnected
        self.activityStore = activityStore
        self.autoStart = true
        _viewModel = StateObject(wrappedValue: SessionsViewModel(host: host, token: token, activityStore: activityStore))
    }

    init(
        host: SavedHost,
        token: String,
        onConnected: @escaping () -> Void,
        activityStore: ActivityLogStore,
        viewModel: SessionsViewModel,
        autoStart: Bool
    ) {
        self.host = host
        self.token = token
        self.onConnected = onConnected
        self.activityStore = activityStore
        self.autoStart = autoStart
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ZStack {
            explorerBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    heroPanel
                    groupStrip
                    content
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Explorer")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ExplorerRoute.self) { route in
            if let focusedViewModel = viewModel.focusedSession(for: route) {
                SessionDetailView(viewModel: focusedViewModel)
            }
        }
        .task {
            guard autoStart else { return }
            onConnected()
            viewModel.start()
        }
        .refreshable {
            guard autoStart else { return }
            await viewModel.refresh()
        }
        .sheet(isPresented: $isCreateGroupPresented) {
            createGroupSheet
                .presentationDetents([.height(240)])
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if viewModel.hiddenSessionCount > 0 {
                    Button("Reconnect") {
                        viewModel.reconnectHiddenSessions()
                    }
                }

                Button {
                    isCreateGroupPresented = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .accessibilityLabel("Create group")
            }
        }
    }

    private var heroPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(hostInfoTitle)
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color("ExplorerHighlight"))

                    Text(host.displayLabel)
                        .font(.subheadline)
                        .foregroundStyle(Color("ExplorerMuted"))
                }

                Spacer()

                if viewModel.isLoading {
                    ProgressView()
                        .tint(Color("ExplorerHighlight"))
                }
            }

            HStack(spacing: 10) {
                explorerMetric(value: "\(viewModel.connectedSessions.count)", label: "Connected")
                explorerMetric(value: "\(viewModel.groupTabs.count - 1)", label: "Groups")
                explorerMetric(value: hostInfoVersion, label: "Runtime")
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(Color.red.opacity(0.9))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color("ExplorerPanel"))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }

    private var groupStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(viewModel.groupTabs, id: \.self) { tag in
                    Button {
                        viewModel.selectGroup(tag)
                    } label: {
                        Text(tag == "all" ? "All" : "#\(tag)")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(viewModel.selectedGroupTag == tag ? Color("ExplorerAccent") : Color("ExplorerPanelSoft"))
                            .foregroundStyle(viewModel.selectedGroupTag == tag ? Color("ExplorerBackground") : Color("ExplorerText"))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.connectedSessions.isEmpty, !viewModel.isLoading {
            VStack(alignment: .leading, spacing: 10) {
                Text("No connected sessions match this group.")
                    .font(.headline)
                    .foregroundStyle(Color("ExplorerText"))

                Text("Explorer only shows live sessions. Pull to refresh or switch back to All.")
                    .font(.subheadline)
                    .foregroundStyle(Color("ExplorerMuted"))
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color("ExplorerPanelSoft"))
            .clipShape(RoundedRectangle(cornerRadius: 24))
        } else {
            LazyVStack(spacing: 16) {
                ForEach(viewModel.connectedSessions, id: \.session.sessionId) { sessionViewModel in
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
                        .foregroundStyle(Color("ExplorerText"))

                    Text(sessionViewModel.session.workspaceRoot)
                        .font(.footnote)
                        .foregroundStyle(Color("ExplorerMuted"))
                        .lineLimit(1)
                }

                Spacer()

                NavigationLink(value: ExplorerRoute.focusedSession(sessionViewModel.session.sessionId)) {
                    Label("Focus", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("ExplorerAccent"))
            }

            TerminalTextView(
                terminal: sessionViewModel.terminal,
                mode: .preview,
                isInputEnabled: false,
                onInput: { _ in },
                onResize: { _ in }
            )
            .frame(height: 168)

            HStack(spacing: 8) {
                explorerPill(sessionViewModel.session.status, tone: sessionTone(for: sessionViewModel.session.status))
                explorerPill(sessionViewModel.session.supervisionStateLabel, tone: supervisionTone(for: sessionViewModel.session))
                explorerPill(socketText(for: sessionViewModel.socketState), tone: socketTone(for: sessionViewModel.socketState))
                explorerPill(sessionViewModel.session.controllerKind, tone: sessionViewModel.canSendInput ? Color.green : Color.orange)
                if let branch = sessionViewModel.primaryGitBranch, !branch.isEmpty {
                    explorerPill(branch, tone: Color("ExplorerAccent").opacity(0.8))
                }
            }

            if !sessionViewModel.session.groupTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(sessionViewModel.session.groupTags, id: \.self) { tag in
                            Button {
                                Task { await viewModel.removeGroup(tag, from: sessionViewModel) }
                            } label: {
                                HStack(spacing: 6) {
                                    Text("#\(tag)")
                                    Image(systemName: "minus.circle.fill")
                                        .font(.caption)
                                }
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color("ExplorerPanelSoft"))
                                .foregroundStyle(Color("ExplorerText"))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Button(sessionViewModel.canSendInput ? "Release" : "Request Control") {
                    Task {
                        if sessionViewModel.canSendInput {
                            await sessionViewModel.releaseControl()
                        } else {
                            await sessionViewModel.requestControl()
                        }
                    }
                }
                .buttonStyle(.bordered)
                .tint(Color("ExplorerHighlight"))

                if viewModel.selectedGroupTag != "all",
                   !sessionViewModel.session.normalizedGroupTags.contains(viewModel.selectedGroupTag) {
                    Button("Add To Group") {
                        Task { await viewModel.addSelectedGroup(to: sessionViewModel) }
                    }
                    .buttonStyle(.bordered)
                }

                Menu("Groups") {
                    ForEach(viewModel.availableGroups(for: sessionViewModel), id: \.self) { tag in
                        Button("Add #\(tag)") {
                            Task {
                                await viewModel.addGroup(tag, to: sessionViewModel)
                            }
                        }
                    }
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Disconnect") {
                    viewModel.disconnect(sessionViewModel)
                }
                .buttonStyle(.bordered)

                Button("Stop", role: .destructive) {
                    Task { await sessionViewModel.stopSession() }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color("ExplorerPanel"))
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
                        viewModel.createGroup(named: draftGroupName)
                        draftGroupName = ""
                        isCreateGroupPresented = false
                    }
                    .disabled(SessionSummary.normalizeGroupTag(draftGroupName).isEmpty)
                }
            }
        }
    }

    private var hostInfoTitle: String {
        viewModel.hostInfo?.displayName ?? "Connected Sessions"
    }

    private var hostInfoVersion: String {
        viewModel.hostInfo?.version ?? "unknown"
    }

    private func socketText(for state: SessionSocket.ConnectionState) -> String {
        switch state {
        case .idle:
            return "idle"
        case .connecting:
            return "connecting"
        case .connected:
            return "linked"
        case let .disconnected(reason):
            return reason == nil ? "offline" : "offline"
        }
    }

    private func sessionTone(for status: String) -> Color {
        switch status.lowercased() {
        case "running", "awaitinginput", "attached", "starting":
            return Color.green
        case "error":
            return Color.red
        case "exited":
            return Color.gray
        default:
            return Color.orange
        }
    }

    private func socketTone(for state: SessionSocket.ConnectionState) -> Color {
        switch state {
        case .connected:
            return Color.green
        case .connecting:
            return Color.orange
        case .idle, .disconnected:
            return Color.gray
        }
    }

    private func supervisionTone(for session: SessionSummary) -> Color {
        switch session.supervisionStateLabel.lowercased() {
        case "active":
            return Color.green
        case "stopped":
            return Color.gray
        default:
            return Color.orange
        }
    }

    private func explorerMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color("ExplorerText"))
            Text(label.uppercased())
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color("ExplorerMuted"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color("ExplorerPanelSoft"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func explorerPill(_ text: String, tone: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tone)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tone.opacity(0.16))
            .clipShape(Capsule())
    }

    private var explorerBackground: some View {
        LinearGradient(
            colors: [Color("ExplorerBackground"), Color("ExplorerBackgroundAlt")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            RadialGradient(
                colors: [Color("ExplorerAccent").opacity(0.18), .clear],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 440
            )
        )
    }
}

#Preview("Explorer Sessions") {
    let context = PreviewAppContext.make()
    let previewViewModel = SessionsViewModel(
        previewHost: PreviewFixtures.hostA,
        token: "preview-token-alpha",
        activityStore: context.activityStore,
        hostInfo: PreviewFixtures.hostInfoA,
        sessions: [PreviewFixtures.sessionA, PreviewFixtures.sessionB]
    )

    NavigationStack {
        SessionsView(
            host: PreviewFixtures.hostA,
            token: "preview-token-alpha",
            onConnected: {},
            activityStore: context.activityStore,
            viewModel: previewViewModel,
            autoStart: false
        )
    }
}
