import SwiftUI

struct SessionDetailView: View {
    @ObservedObject var viewModel: SessionViewModel
    let autoActivate: Bool
    let onSessionEnded: (() -> Void)?
    @State private var isContextPanelPresented = false
    @Environment(\.dismiss) private var dismiss

    init(viewModel: SessionViewModel, autoActivate: Bool = true, onSessionEnded: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.autoActivate = autoActivate
        self.onSessionEnded = onSessionEnded
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            focusedBackground
                .ignoresSafeArea()

            VStack(spacing: layout.verticalSpacing) {
                headerBar
                    .frame(height: layout.headerHeight, alignment: .top)
                    .padding(.horizontal, layout.outerPadding)
                    .padding(.top, layout.topPadding)

                terminalPanel
                    .layoutPriority(1)
                    .padding(.horizontal, layout.terminalHorizontalPadding)

                modeBar
                    .frame(height: layout.modeBarHeight)
                    .padding(.horizontal, layout.outerPadding)

                inputBar
                    .frame(height: layout.inputBarHeight)
                    .padding(.horizontal, layout.outerPadding)
                    .padding(.bottom, layout.bottomPadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if isContextPanelPresented {
                Color.black.opacity(0.24)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                            isContextPanelPresented = false
                        }
                    }
                    .zIndex(1)

                contextPanel
                    .frame(width: 320)
                    .padding(.trailing, 10)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .padding(.top, -10)
        .navigationTitle(viewModel.session.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard autoActivate else { return }
            await viewModel.activate()
        }
        .onChange(of: viewModel.session.isEnded) { _, isEnded in
            guard isEnded else { return }
            onSessionEnded?()
            dismiss()
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: isContextPanelPresented)
        .toolbarTitleDisplayMode(.inline)
    }

    private let layout = FocusedLayoutMetrics()

    private var focusedBackground: some View {
        LinearGradient(
            colors: [Color.focusedBackgroundTop, Color.focusedBackgroundBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            RadialGradient(
                colors: [Color.focusedAccent.opacity(0.14), .clear],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 360
            )
        )
    }

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                compactStatusBadge(viewModel.session.status, tone: sessionStatusColor(viewModel.session.status))
                compactStatusBadge(socketLabel(viewModel.socketState), tone: socketColor(viewModel.socketState))
                compactStatusBadge(viewModel.session.controllerKind.capitalized, tone: viewModel.canSendInput ? .green : .orange)

                Spacer(minLength: 8)

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                        isContextPanelPresented.toggle()
                    }
                } label: {
                    Image(systemName: isContextPanelPresented ? "sidebar.trailing" : "sidebar.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.focusedText)
                        .frame(width: 32, height: 32)
                        .background(Color.focusedPanelSoft.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .frame(height: 32)

            Text(viewModel.session.workspaceRoot)
                .font(.caption)
                .foregroundStyle(Color.focusedMuted)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(height: 16, alignment: .leading)
        }
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
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            if !viewModel.terminal.hasContent {
                Text("Waiting for terminal output...")
                    .font(.footnote)
                    .foregroundStyle(Color.focusedMuted)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 12)
    }

    private var modeBar: some View {
        HStack(spacing: 12) {
            modeIndicator(
                title: viewModel.canSendInput ? "You have control" : "Observer Mode",
                detail: viewModel.canSendInput ? "Direct terminal input is live" : "You are watching this session",
                tone: viewModel.canSendInput ? Color(red: 0.82, green: 0.9, blue: 0.74) : Color.focusedMuted
            )

            Spacer(minLength: 8)

            if viewModel.canSendInput {
                Button("Release") {
                    Task { await viewModel.releaseControl() }
                }
                .buttonStyle(.bordered)
                .tint(Color.focusedAccent)
                .frame(height: 24)

                Button(role: .destructive) {
                    Task { await viewModel.stopSession() }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.red.opacity(0.9))
                .frame(height: 24)
            } else {
                Button("Request Control") {
                    Task { await viewModel.requestControl() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.focusedAccent)
                .frame(height: 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.focusedGlass)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(controlKeys, id: \.label) { key in
                        Button(key.label) {
                            Task { await viewModel.sendTerminalInput(key.payload) }
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.focusedControlKey)
                        .frame(height: 32)
                        .disabled(!viewModel.canSendInput)
                    }
                }
                .padding(.vertical, 1)
            }
            .frame(height: 34)

            HStack(spacing: 10) {
                TextField(
                    viewModel.canSendInput ? "Enter terminal command" : "Request control to send commands",
                    text: $viewModel.inputText
                )
                .textFieldStyle(.plain)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(Color.focusedPanelSoft.opacity(0.92))
                .foregroundStyle(viewModel.canSendInput ? Color.focusedText : Color.focusedMuted)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .disabled(!viewModel.canSendInput)

                Button("Send") {
                    Task { await viewModel.sendInput() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.focusedAccent)
                .frame(height: 46)
                .disabled(!viewModel.canSendInput || viewModel.inputText.isEmpty)
            }
            .frame(height: 46)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.focusedGlass)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var contextPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Context")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.focusedText)

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                        isContextPanelPresented = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.focusedMuted)
                        .frame(width: 28, height: 28)
                        .background(Color.focusedPanelSoft.opacity(0.9))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            contextSection(title: "Project Path") {
                Text(viewModel.session.workspaceRoot)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Color.focusedText)
                    .textSelection(.enabled)
            }

            contextSection(title: "Git Status") {
                Text(gitSummary)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Color.focusedText)
            }

            contextSection(title: "Recent Files") {
                VStack(alignment: .leading, spacing: 8) {
                    if viewModel.hasRecentFiles {
                        ForEach(Array(viewModel.recentFiles.prefix(5)), id: \.self) { file in
                            Text(file)
                                .font(.footnote)
                                .foregroundStyle(Color.focusedText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    } else {
                        Text("No recent files yet.")
                            .font(.footnote)
                            .foregroundStyle(Color.focusedMuted)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(.ultraThinMaterial)
        .background(Color.focusedPanel.opacity(0.92))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.24), radius: 20, x: -6, y: 8)
    }

    private var gitSummary: String {
        let branch = viewModel.primaryGitBranch ?? "unknown branch"
        let modified = viewModel.session.gitModifiedCount ?? viewModel.snapshot?.git?.modifiedCount ?? 0
        let staged = viewModel.session.gitStagedCount ?? viewModel.snapshot?.git?.stagedCount ?? 0
        let untracked = viewModel.session.gitUntrackedCount ?? viewModel.snapshot?.git?.untrackedCount ?? 0
        return "\(branch)\n\(modified) modified\n\(staged) staged\n\(untracked) untracked"
    }

    private func modeIndicator(title: String, detail: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tone.opacity(0.95))
                .lineLimit(1)

            Text(detail)
                .font(.caption2)
                .foregroundStyle(Color.focusedMuted)
                .lineLimit(1)
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func contextSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.focusedMuted)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color.focusedPanelSoft.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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

    private func compactStatusBadge(_ text: String, tone: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tone)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(tone.opacity(0.18))
            .clipShape(Capsule())
    }

    private var controlKeys: [TerminalControlKey] {
        [
            .init(label: "Enter", payload: "\r"),
            .init(label: "Up", payload: "\u{1B}[A"),
            .init(label: "Down", payload: "\u{1B}[B"),
            .init(label: "Left", payload: "\u{1B}[D"),
            .init(label: "Right", payload: "\u{1B}[C"),
            .init(label: "Home", payload: "\u{1B}[H"),
            .init(label: "End", payload: "\u{1B}[F"),
            .init(label: "Tab", payload: "\t"),
            .init(label: "Esc", payload: "\u{1B}"),
            .init(label: "Backspace", payload: "\u{08}"),
            .init(label: "Del", payload: "\u{7F}")
        ]
    }
}

private struct FocusedLayoutMetrics {
    let outerPadding: CGFloat = 14
    let terminalHorizontalPadding: CGFloat = 2
    let topPadding: CGFloat = 10
    let bottomPadding: CGFloat = 10
    let verticalSpacing: CGFloat = 10
    let headerHeight: CGFloat = 58
    let modeBarHeight: CGFloat = 68
    let inputBarHeight: CGFloat = 114
}

private struct TerminalControlKey {
    let label: String
    let payload: String
}

private extension Color {
    static let focusedBackgroundTop = Color(red: 0.06, green: 0.07, blue: 0.08)
    static let focusedBackgroundBottom = Color(red: 0.08, green: 0.1, blue: 0.12)
    static let focusedPanel = Color(red: 0.12, green: 0.14, blue: 0.16)
    static let focusedPanelSoft = Color(red: 0.18, green: 0.2, blue: 0.22)
    static let focusedGlass = Color.white.opacity(0.06)
    static let focusedText = Color(red: 0.95, green: 0.95, blue: 0.92)
    static let focusedMuted = Color(red: 0.66, green: 0.69, blue: 0.72)
    static let focusedAccent = Color(red: 0.76, green: 0.83, blue: 0.57)
    static let focusedControlKey = Color(red: 0.42, green: 0.5, blue: 0.62)
}

#Preview("Focused Session") {
    let context = PreviewAppContext.make()
    NavigationStack {
        SessionDetailView(viewModel: context.focusedSessionViewModel, autoActivate: false)
    }
}
