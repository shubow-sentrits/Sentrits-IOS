import SwiftUI

struct ExplorerWorkspaceView: View {
    @ObservedObject var explorerStore: ExplorerWorkspaceStore
    let onFocusSession: (String, UUID) -> Void
    @State private var draftGroupName = ""
    @State private var isCreateGroupPresented = false

    var body: some View {
        ZStack {
            explorerBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    titleRow
                    heroPanel
                    groupStrip
                    content
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await explorerStore.syncConnectedHosts()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isCreateGroupPresented) {
            createGroupSheet
                .presentationDetents([.height(240)])
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

    private var explorerBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Color.explorerBackground, Color(red: 0.08, green: 0.10, blue: 0.09)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.explorerAccent.opacity(0.12),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 28,
                endRadius: 360
            )
        }
    }

    private var heroPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text("Connected sessions stay here. Focus one when you need the larger terminal.")
                    .font(.subheadline)
                    .foregroundStyle(Color.explorerMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    isCreateGroupPresented = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.explorerHighlight)
                .accessibilityLabel("Create group")
            }

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

    private var titleRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Explorer")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.94))

            Text("Focused live sessions for control and supervision.")
                .font(.subheadline)
                .foregroundStyle(Color.explorerMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

#Preview("Explorer") {
    let context = PreviewAppContext.make()
    NavigationStack {
        ExplorerWorkspaceView(explorerStore: context.explorerStore, onFocusSession: { _, _ in })
    }
}
