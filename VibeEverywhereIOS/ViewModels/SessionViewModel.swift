import Foundation

@MainActor
final class SessionViewModel: ObservableObject {
    @Published var session: SessionSummary
    @Published var socketState: SessionSocket.ConnectionState = .idle
    @Published var lastError: String?
    @Published var inputText = ""
    @Published var terminalResize = TerminalResize(cols: 80, rows: 24)

    let host: SavedHost
    let token: String
    let terminal = TerminalEngine()

    private let socket: SessionSocket

    init(host: SavedHost, token: String, session: SessionSummary) {
        self.host = host
        self.token = token
        self.session = session
        self.socket = SessionSocket(host: host)

        socket.onStateChange = { [weak self] state in
            Task { @MainActor in
                self?.socketState = state
            }
        }

        socket.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.apply(event: event)
            }
        }
    }

    var hasRemoteControl: Bool {
        session.controllerKind == "remote" && session.controllerClientId != nil
    }

    var canSendInput: Bool { hasRemoteControl }

    func connect() {
        terminal.reset()
        socket.connect(host: host, sessionId: session.sessionId, token: token)
    }

    func disconnect() {
        socket.disconnect(reason: "Disconnected by client.")
    }

    func requestControl() async {
        await socket.requestControl()
    }

    func releaseControl() async {
        await socket.releaseControl()
    }

    func sendInput() async {
        let payload = inputText
        guard !payload.isEmpty, canSendInput else { return }
        inputText = ""
        await socket.sendInput(payload)
    }

    func sendTerminalInput(_ data: String) async {
        guard !data.isEmpty, canSendInput else { return }
        await socket.sendInput(data)
    }

    func sendResizeIfChanged(_ resize: TerminalResize) async {
        guard resize != terminalResize else { return }
        terminalResize = resize
        await socket.sendResize(resize)
    }

    func stopSession() async {
        do {
            let client = HostClient(host: host)
            try await client.stopSession(sessionId: session.sessionId, host: host, token: token)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func apply(event: SessionSocketEvent) {
        switch event {
        case let .sessionUpdated(metadata):
            session = SessionSummary(
                sessionId: metadata.sessionId,
                provider: metadata.provider,
                workspaceRoot: metadata.workspaceRoot,
                title: metadata.title,
                status: metadata.status,
                controllerKind: metadata.controllerKind,
                controllerClientId: metadata.controllerClientId
            )
        case let .terminalOutput(output):
            terminal.ingestBase64(output.dataBase64, seqStart: output.seqStart, seqEnd: output.seqEnd)
        case let .sessionExited(payload):
            session = SessionSummary(
                sessionId: session.sessionId,
                provider: session.provider,
                workspaceRoot: session.workspaceRoot,
                title: session.title,
                status: payload.status,
                controllerKind: session.controllerKind,
                controllerClientId: session.controllerClientId
            )
            socketState = .disconnected("Session exited.")
        case let .error(payload):
            lastError = "\(payload.code): \(payload.message)"
        }
    }
}
