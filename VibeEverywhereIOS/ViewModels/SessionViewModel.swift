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
    private let activityStore: ActivityLogStore

    init(host: SavedHost, token: String, session: SessionSummary, activityStore: ActivityLogStore) {
        self.host = host
        self.token = token
        self.session = session
        self.activityStore = activityStore
        self.socket = SessionSocket(host: host)

        socket.onStateChange = { [weak self] state in
            Task { @MainActor in
                self?.socketState = state
                self?.recordSocketState(state)
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
        activityStore.record(
            category: .socket,
            title: "Connecting to session",
            message: "Opening the live session socket.",
            host: host,
            sessionID: session.sessionId
        )
        socket.connect(host: host, sessionId: session.sessionId, token: token)
    }

    func disconnect() {
        activityStore.record(
            category: .socket,
            title: "Disconnected from session",
            message: "Closed the session socket from the client.",
            host: host,
            sessionID: session.sessionId
        )
        socket.disconnect(reason: "Disconnected by client.")
    }

    func requestControl() async {
        activityStore.record(
            category: .control,
            title: "Control requested",
            message: "Asked for remote control of the session.",
            host: host,
            sessionID: session.sessionId
        )
        await socket.requestControl()
    }

    func releaseControl() async {
        activityStore.record(
            category: .control,
            title: "Control released",
            message: "Released remote control back to the session.",
            host: host,
            sessionID: session.sessionId
        )
        await socket.releaseControl()
    }

    func sendInput() async {
        let payload = inputText
        guard !payload.isEmpty, canSendInput else { return }
        inputText = ""
        await socket.sendInput(payload)
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
            activityStore.record(
                category: .explorer,
                title: "Session stop requested",
                message: "Sent a stop request for the focused session.",
                host: host,
                sessionID: session.sessionId
            )
        } catch {
            lastError = error.localizedDescription
            activityStore.record(
                severity: .error,
                category: .explorer,
                title: "Session stop failed",
                message: error.localizedDescription,
                host: host,
                sessionID: session.sessionId
            )
        }
    }

    private func apply(event: SessionSocketEvent) {
        switch event {
        case let .sessionUpdated(metadata):
            let previousStatus = session.status
            let previousController = session.controllerKind
            session = SessionSummary(
                sessionId: metadata.sessionId,
                provider: metadata.provider,
                workspaceRoot: metadata.workspaceRoot,
                title: metadata.title,
                status: metadata.status,
                controllerKind: metadata.controllerKind,
                controllerClientId: metadata.controllerClientId
            )
            if previousStatus != metadata.status {
                activityStore.record(
                    category: .explorer,
                    title: "Session status changed",
                    message: "Session moved from \(previousStatus) to \(metadata.status).",
                    host: host,
                    sessionID: metadata.sessionId
                )
            }
            if previousController != metadata.controllerKind {
                activityStore.record(
                    category: .control,
                    title: "Control mode changed",
                    message: "Session control is now \(metadata.controllerKind).",
                    host: host,
                    sessionID: metadata.sessionId
                )
            }
        case let .terminalOutput(output):
            terminal.ingestBase64(output.dataBase64, seqEnd: output.seqEnd)
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
            activityStore.record(
                severity: .warning,
                category: .explorer,
                title: "Session exited",
                message: "The remote session ended with status \(payload.status).",
                host: host,
                sessionID: payload.sessionId
            )
        case let .error(payload):
            lastError = "\(payload.code): \(payload.message)"
            activityStore.record(
                severity: .error,
                category: .socket,
                title: "Session error",
                message: "\(payload.code): \(payload.message)",
                host: host,
                sessionID: payload.sessionId ?? session.sessionId
            )
        }
    }

    private func recordSocketState(_ state: SessionSocket.ConnectionState) {
        switch state {
        case .idle:
            return
        case .connecting:
            return
        case .connected:
            activityStore.record(
                category: .socket,
                title: "Session connected",
                message: "Live socket is connected.",
                host: host,
                sessionID: session.sessionId
            )
        case let .disconnected(reason):
            let severity: ActivitySeverity = reason == nil ? .info : .warning
            activityStore.record(
                severity: severity,
                category: .socket,
                title: "Session disconnected",
                message: reason ?? "The live socket disconnected.",
                host: host,
                sessionID: session.sessionId
            )
        }
    }
}
