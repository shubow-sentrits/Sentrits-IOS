import SwiftUI

struct SessionDetailView: View {
    let host: SavedHost
    let token: String
    let session: SessionSummary
    @ObservedObject var activityStore: ActivityLogStore

    @StateObject private var viewModel: SessionViewModel

    init(host: SavedHost, token: String, session: SessionSummary, activityStore: ActivityLogStore) {
        self.host = host
        self.token = token
        self.session = session
        self.activityStore = activityStore
        _viewModel = StateObject(wrappedValue: SessionViewModel(host: host, token: token, session: session, activityStore: activityStore))
    }

    var body: some View {
        VStack(spacing: 12) {
            statusPanel
            terminalPanel
            inputPanel
        }
        .padding()
        .background(ActivityPalette.background.ignoresSafeArea())
        .navigationTitle(session.title.isEmpty ? session.sessionId : session.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.connect()
        }
        .onDisappear {
            viewModel.disconnect()
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.session.workspaceRoot)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                statusPill("session: \(viewModel.session.status)", color: sessionStatusColor(viewModel.session.status))
                statusPill("socket: \(socketLabel(viewModel.socketState))", color: socketColor(viewModel.socketState))
                statusPill("control: \(viewModel.session.controllerKind)", color: viewModel.canSendInput ? .green : .orange)
            }

            if let lastError = viewModel.lastError {
                Text(lastError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Request Control") {
                    Task { await viewModel.requestControl() }
                }
                .buttonStyle(.borderedProminent)

                Button("Release Control") {
                    Task { await viewModel.releaseControl() }
                }
                .buttonStyle(.bordered)

                Button("Reconnect") {
                    viewModel.connect()
                }
                .buttonStyle(.bordered)

                Button("Stop Session", role: .destructive) {
                    Task { await viewModel.stopSession() }
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var terminalPanel: some View {
        GeometryReader { geometry in
            TerminalTextView(text: viewModel.terminal.renderedText)
                .task(id: geometry.size) {
                    let resize = computeResize(size: geometry.size)
                    await viewModel.sendResizeIfChanged(resize)
                }
        }
        .frame(maxHeight: .infinity)
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
                .disabled(!viewModel.canSendInput || viewModel.inputText.isEmpty)

                Text(viewModel.canSendInput ? "Input enabled" : "Observer only. Request control to type.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func computeResize(size: CGSize) -> TerminalResize {
        let cols = max(Int((size.width - 24) / 8), 20)
        let rows = max(Int((size.height - 24) / 17), 8)
        return TerminalResize(cols: cols, rows: rows)
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
        case "running", "attached", "starting":
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
            return .red
        }
    }

    private func statusPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
