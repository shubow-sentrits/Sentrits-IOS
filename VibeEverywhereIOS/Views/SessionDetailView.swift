import SwiftUI

struct SessionDetailView: View {
    @ObservedObject var viewModel: SessionViewModel
    let autoActivate: Bool

    init(viewModel: SessionViewModel, autoActivate: Bool = true) {
        self.viewModel = viewModel
        self.autoActivate = autoActivate
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.focusedBackgroundTop, Color.focusedBackgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                headerPanel
                terminalPanel
                summaryPanel
                inputPanel
            }
            .padding(16)
        }
        .navigationTitle(viewModel.session.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard autoActivate else { return }
            await viewModel.activate()
        }
    }

    private var headerPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.session.workspaceRoot)
                .font(.footnote)
                .foregroundStyle(Color.focusedMuted)
                .lineLimit(1)

            HStack(spacing: 8) {
                focusedPill(viewModel.session.status, tone: sessionStatusColor(viewModel.session.status))
                focusedPill(socketLabel(viewModel.socketState), tone: socketColor(viewModel.socketState))
                focusedPill(viewModel.session.controllerKind, tone: viewModel.canSendInput ? .green : .orange)
            }

            if let lastError = viewModel.lastError {
                Text(lastError)
                    .font(.footnote)
                    .foregroundStyle(.red.opacity(0.9))
            }

            HStack(spacing: 10) {
                Button(viewModel.canSendInput ? "Release Control" : "Request Control") {
                    Task {
                        if viewModel.canSendInput {
                            await viewModel.releaseControl()
                        } else {
                            await viewModel.requestControl()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.focusedAccent)

                Button("Reconnect") {
                    viewModel.connect()
                }
                .buttonStyle(.bordered)

                Button("Refresh Files") {
                    Task { await viewModel.loadSnapshot(force: true) }
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Stop Session", role: .destructive) {
                    Task { await viewModel.stopSession() }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.focusedPanel)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var terminalPanel: some View {
        ZStack {
            TerminalTextView(
                terminal: viewModel.terminal,
                mode: .focused,
                isInputEnabled: viewModel.canSendInput,
                onInput: { data in
                    Task { await viewModel.sendTerminalInput(data) }
                },
                onResize: { resize in
                    Task { await viewModel.sendResizeIfChanged(resize) }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if !viewModel.terminal.hasContent {
                Text("Waiting for terminal output...")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var summaryPanel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                summaryCard(
                    title: "Recent Files",
                    body: viewModel.hasRecentFiles ? viewModel.recentFiles.prefix(4).joined(separator: "\n") : "No recent files yet."
                )
                summaryCard(
                    title: "Git",
                    body: gitSummary
                )
                summaryCard(
                    title: "Session",
                    body: sessionSummary
                )
            }
        }
    }

    private var inputPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Terminal input", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1 ... 4)
                .disabled(!viewModel.canSendInput)

            HStack {
                Button("Send") {
                    Task { await viewModel.sendInput() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.focusedAccent)
                .disabled(!viewModel.canSendInput || viewModel.inputText.isEmpty)

                Text(viewModel.canSendInput ? "Interactive control is live." : "Observer only. Request control to type.")
                    .font(.footnote)
                    .foregroundStyle(Color.focusedMuted)
            }
        }
        .padding(18)
        .background(Color.focusedPanel)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var gitSummary: String {
        let branch = viewModel.primaryGitBranch ?? "unknown branch"
        let modified = viewModel.session.gitModifiedCount ?? viewModel.snapshot?.git?.modifiedCount ?? 0
        let staged = viewModel.session.gitStagedCount ?? viewModel.snapshot?.git?.stagedCount ?? 0
        let untracked = viewModel.session.gitUntrackedCount ?? viewModel.snapshot?.git?.untrackedCount ?? 0
        return "\(branch)\n\(modified) modified\n\(staged) staged\n\(untracked) untracked"
    }

    private var sessionSummary: String {
        [
            "ID \(viewModel.session.sessionId)",
            "Provider \(viewModel.session.provider)",
            "Files \(viewModel.session.recentFileChangeCount ?? viewModel.snapshot?.signals?.recentFileChangeCount ?? 0)",
            "Clients \(viewModel.session.attachedClientCount ?? 0)"
        ].joined(separator: "\n")
    }

    private func summaryCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.focusedMuted)
            Text(body)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Color.focusedText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(width: 220, alignment: .leading)
        .background(Color.focusedPanel)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func socketLabel(_ state: SessionSocket.ConnectionState) -> String {
        switch state {
        case .idle:
            return "idle"
        case .connecting:
            return "connecting"
        case .connected:
            return "connected"
        case let .disconnected(reason):
            return reason ?? "disconnected"
        }
    }

    private func sessionStatusColor(_ status: String) -> Color {
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

    private func socketColor(_ state: SessionSocket.ConnectionState) -> Color {
        switch state {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .idle, .disconnected:
            return .gray
        }
    }

    private func focusedPill(_ text: String, tone: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tone)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tone.opacity(0.18))
            .clipShape(Capsule())
    }
}

private extension Color {
    static let focusedBackgroundTop = Color(red: 0.06, green: 0.07, blue: 0.08)
    static let focusedBackgroundBottom = Color(red: 0.08, green: 0.1, blue: 0.12)
    static let focusedPanel = Color(red: 0.12, green: 0.14, blue: 0.16)
    static let focusedText = Color(red: 0.95, green: 0.95, blue: 0.92)
    static let focusedMuted = Color(red: 0.66, green: 0.69, blue: 0.72)
    static let focusedAccent = Color(red: 0.76, green: 0.83, blue: 0.57)
}

#Preview("Focused Session") {
    let context = PreviewAppContext.make()
    NavigationStack {
        SessionDetailView(viewModel: context.focusedSessionViewModel, autoActivate: false)
    }
}
