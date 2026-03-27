import Foundation

@MainActor
final class SessionViewModel: ObservableObject {
    @Published var session: SessionSummary
    @Published var socketState: SessionSocket.ConnectionState = .idle
    @Published var snapshot: SessionSnapshot?
    @Published var lastError: String?
    @Published var inputText = ""
    @Published var terminalResize = TerminalResize(cols: 80, rows: 24)

    let host: SavedHost
    let token: String
    let terminal = TerminalEngine()

    private let socket: SessionSocket
    private let activityStore: ActivityLogStore
    private var hasLoadedSnapshot = false

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

    var previewText: String {
        let lines = terminal.renderedText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .suffix(10)
            .map(String.init)
        return lines.joined(separator: "\n")
    }

    var recentFiles: [String] {
        snapshot?.recentFileChanges ?? []
    }

    var hasRecentFiles: Bool {
        !recentFiles.isEmpty
    }

    var primaryGitBranch: String? {
        snapshot?.git?.branch ?? snapshot?.signals?.gitBranch ?? session.gitBranch
    }

    var terminalPlaceholder: String {
        socketState == .connected ? "Waiting for terminal output..." : "Disconnected from session preview."
    }

    func connect() {
        if case .connected = socketState {
            return
        }
        if case .connecting = socketState {
            return
        }
        terminal.reset()
        seedTerminalFromSnapshot()
        activityStore.record(
            category: .socket,
            title: "Connecting to session",
            message: "Opening the live session socket.",
            hostLabel: host.displayLabel,
            sessionID: session.sessionId
        )
        socket.connect(host: host, sessionId: session.sessionId, token: token)
    }

    func disconnect() {
        activityStore.record(
            category: .socket,
            title: "Disconnected from session",
            message: "Closed the session socket from the client.",
            hostLabel: host.displayLabel,
            sessionID: session.sessionId
        )
        socket.disconnect(reason: "Disconnected by client.")
    }

    func activate() async {
        await loadSnapshot(force: false)
        connect()
    }

    func requestControl() async {
        activityStore.record(
            category: .control,
            title: "Control requested",
            message: "Asked for remote control of the session.",
            hostLabel: host.displayLabel,
            sessionID: session.sessionId
        )
        await socket.requestControl()
    }

    func releaseControl() async {
        activityStore.record(
            category: .control,
            title: "Control released",
            message: "Released remote control for the session.",
            hostLabel: host.displayLabel,
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

    func sendTerminalInput(_ data: String) async {
        guard !data.isEmpty, canSendInput else { return }
        await socket.sendInput(data)
    }

    func sendResizeIfChanged(_ resize: TerminalResize) async {
        guard resize != terminalResize else { return }
        terminalResize = resize
        await socket.sendResize(resize)
    }

    func loadSnapshot(force: Bool) async {
        if hasLoadedSnapshot, !force {
            return
        }

        do {
            let client = HostClient(host: host)
            let snapshot = try await client.fetchSessionSnapshot(sessionId: session.sessionId, host: host, token: token)
            self.snapshot = snapshot
            hasLoadedSnapshot = true
            updateSession(from: snapshot)
            seedTerminalFromSnapshot()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func updateSession(_ summary: SessionSummary) {
        session = summary
    }

    func updateGroupTags(_ tags: [String]) {
        session = SessionSummary(
            sessionId: session.sessionId,
            provider: session.provider,
            workspaceRoot: session.workspaceRoot,
            title: session.title,
            status: session.status,
            conversationId: session.conversationId,
            groupTags: tags,
            controllerKind: session.controllerKind,
            controllerClientId: session.controllerClientId,
            isRecovered: session.isRecovered,
            archivedRecord: session.archivedRecord,
            isActive: session.isActive,
            inventoryState: session.inventoryState,
            activityState: session.activityState,
            supervisionState: session.supervisionState,
            attentionState: session.attentionState,
            attentionReason: session.attentionReason,
            createdAtUnixMs: session.createdAtUnixMs,
            lastStatusAtUnixMs: session.lastStatusAtUnixMs,
            lastOutputAtUnixMs: session.lastOutputAtUnixMs,
            lastActivityAtUnixMs: session.lastActivityAtUnixMs,
            lastFileChangeAtUnixMs: session.lastFileChangeAtUnixMs,
            lastGitChangeAtUnixMs: session.lastGitChangeAtUnixMs,
            lastControllerChangeAtUnixMs: session.lastControllerChangeAtUnixMs,
            attentionSinceUnixMs: session.attentionSinceUnixMs,
            currentSequence: session.currentSequence,
            attachedClientCount: session.attachedClientCount,
            recentFileChangeCount: session.recentFileChangeCount,
            gitDirty: session.gitDirty,
            gitBranch: session.gitBranch,
            gitModifiedCount: session.gitModifiedCount,
            gitStagedCount: session.gitStagedCount,
            gitUntrackedCount: session.gitUntrackedCount
        )
    }

    func stopSession() async {
        do {
            let client = HostClient(host: host)
            try await client.stopSession(sessionId: session.sessionId, host: host, token: token)
            activityStore.record(
                category: .explorer,
                title: "Session stop requested",
                message: "Sent a stop request for the focused session.",
                hostLabel: host.displayLabel,
                sessionID: session.sessionId
            )
            await loadSnapshot(force: true)
        } catch {
            lastError = error.localizedDescription
            activityStore.record(
                severity: .error,
                category: .explorer,
                title: "Session stop failed",
                message: error.localizedDescription,
                hostLabel: host.displayLabel,
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
                conversationId: metadata.conversationId,
                groupTags: metadata.groupTags,
                controllerKind: metadata.controllerKind,
                controllerClientId: metadata.controllerClientId,
                isRecovered: metadata.isRecovered,
                archivedRecord: metadata.archivedRecord,
                isActive: metadata.isActive,
                inventoryState: metadata.inventoryState,
                activityState: metadata.activityState,
                supervisionState: metadata.supervisionState,
                attentionState: metadata.attentionState,
                attentionReason: metadata.attentionReason,
                createdAtUnixMs: metadata.createdAtUnixMs,
                lastStatusAtUnixMs: metadata.lastStatusAtUnixMs,
                lastOutputAtUnixMs: metadata.lastOutputAtUnixMs,
                lastActivityAtUnixMs: metadata.lastActivityAtUnixMs,
                lastFileChangeAtUnixMs: metadata.lastFileChangeAtUnixMs,
                lastGitChangeAtUnixMs: metadata.lastGitChangeAtUnixMs,
                lastControllerChangeAtUnixMs: metadata.lastControllerChangeAtUnixMs,
                attentionSinceUnixMs: metadata.attentionSinceUnixMs,
                currentSequence: metadata.currentSequence,
                attachedClientCount: metadata.attachedClientCount,
                recentFileChangeCount: metadata.recentFileChangeCount,
                gitDirty: metadata.gitDirty,
                gitBranch: metadata.gitBranch,
                gitModifiedCount: metadata.gitModifiedCount,
                gitStagedCount: metadata.gitStagedCount,
                gitUntrackedCount: metadata.gitUntrackedCount
            )
            if previousStatus != metadata.status {
                activityStore.record(
                    category: .explorer,
                    title: "Session status changed",
                    message: "Session moved from \(previousStatus) to \(metadata.status).",
                    hostLabel: host.displayLabel,
                    sessionID: metadata.sessionId
                )
            }
            if previousController != metadata.controllerKind {
                activityStore.record(
                    category: .control,
                    title: "Control mode changed",
                    message: "Session control is now \(metadata.controllerKind).",
                    hostLabel: host.displayLabel,
                    sessionID: metadata.sessionId
                )
            }
        case let .terminalOutput(output):
            terminal.ingestBase64(output.dataBase64, seqStart: output.seqStart, seqEnd: output.seqEnd)
        case let .sessionExited(payload):
            session = SessionSummary(
                sessionId: session.sessionId,
                provider: session.provider,
                workspaceRoot: session.workspaceRoot,
                title: session.title,
                status: payload.status,
                conversationId: session.conversationId,
                groupTags: session.groupTags,
                controllerKind: session.controllerKind,
                controllerClientId: session.controllerClientId,
                isRecovered: session.isRecovered,
                archivedRecord: session.archivedRecord,
                isActive: false,
                inventoryState: session.inventoryState,
                activityState: session.activityState,
                supervisionState: session.supervisionState,
                attentionState: session.attentionState,
                attentionReason: session.attentionReason,
                createdAtUnixMs: session.createdAtUnixMs,
                lastStatusAtUnixMs: session.lastStatusAtUnixMs,
                lastOutputAtUnixMs: session.lastOutputAtUnixMs,
                lastActivityAtUnixMs: session.lastActivityAtUnixMs,
                lastFileChangeAtUnixMs: session.lastFileChangeAtUnixMs,
                lastGitChangeAtUnixMs: session.lastGitChangeAtUnixMs,
                lastControllerChangeAtUnixMs: session.lastControllerChangeAtUnixMs,
                attentionSinceUnixMs: session.attentionSinceUnixMs,
                currentSequence: session.currentSequence,
                attachedClientCount: session.attachedClientCount,
                recentFileChangeCount: session.recentFileChangeCount,
                gitDirty: session.gitDirty,
                gitBranch: session.gitBranch,
                gitModifiedCount: session.gitModifiedCount,
                gitStagedCount: session.gitStagedCount,
                gitUntrackedCount: session.gitUntrackedCount
            )
            socketState = .disconnected("Session exited.")
            activityStore.record(
                severity: .warning,
                category: .explorer,
                title: "Session exited",
                message: "The remote session ended with status \(payload.status).",
                hostLabel: host.displayLabel,
                sessionID: payload.sessionId
            )
        case let .error(payload):
            lastError = "\(payload.code): \(payload.message)"
            activityStore.record(
                severity: .error,
                category: .socket,
                title: "Session error",
                message: "\(payload.code): \(payload.message)",
                hostLabel: host.displayLabel,
                sessionID: payload.sessionId ?? session.sessionId
            )
        }
    }

    private func updateSession(from snapshot: SessionSnapshot) {
        session = SessionSummary(
            sessionId: snapshot.sessionId,
            provider: snapshot.provider,
            workspaceRoot: snapshot.workspaceRoot,
            title: snapshot.title,
            status: snapshot.status,
            conversationId: snapshot.conversationId,
            groupTags: snapshot.groupTags,
            controllerKind: session.controllerKind,
            controllerClientId: session.controllerClientId,
            isRecovered: session.isRecovered,
            archivedRecord: session.archivedRecord,
            isActive: session.isActive,
            inventoryState: session.inventoryState,
            activityState: session.activityState,
            supervisionState: snapshot.signals?.supervisionState ?? session.supervisionState,
            attentionState: snapshot.signals?.attentionState ?? session.attentionState,
            attentionReason: snapshot.signals?.attentionReason ?? session.attentionReason,
            createdAtUnixMs: session.createdAtUnixMs,
            lastStatusAtUnixMs: session.lastStatusAtUnixMs,
            lastOutputAtUnixMs: snapshot.signals?.lastOutputAtUnixMs ?? session.lastOutputAtUnixMs,
            lastActivityAtUnixMs: snapshot.signals?.lastActivityAtUnixMs ?? session.lastActivityAtUnixMs,
            lastFileChangeAtUnixMs: snapshot.signals?.lastFileChangeAtUnixMs ?? session.lastFileChangeAtUnixMs,
            lastGitChangeAtUnixMs: snapshot.signals?.lastGitChangeAtUnixMs ?? session.lastGitChangeAtUnixMs,
            lastControllerChangeAtUnixMs: snapshot.signals?.lastControllerChangeAtUnixMs ?? session.lastControllerChangeAtUnixMs,
            attentionSinceUnixMs: snapshot.signals?.attentionSinceUnixMs ?? session.attentionSinceUnixMs,
            currentSequence: snapshot.currentSequence ?? snapshot.signals?.currentSequence ?? session.currentSequence,
            attachedClientCount: session.attachedClientCount,
            recentFileChangeCount: snapshot.signals?.recentFileChangeCount ?? session.recentFileChangeCount,
            gitDirty: snapshot.signals?.gitDirty ?? session.gitDirty,
            gitBranch: snapshot.git?.branch ?? snapshot.signals?.gitBranch ?? session.gitBranch,
            gitModifiedCount: snapshot.git?.modifiedCount ?? snapshot.signals?.gitModifiedCount ?? session.gitModifiedCount,
            gitStagedCount: snapshot.git?.stagedCount ?? snapshot.signals?.gitStagedCount ?? session.gitStagedCount,
            gitUntrackedCount: snapshot.git?.untrackedCount ?? snapshot.signals?.gitUntrackedCount ?? session.gitUntrackedCount
        )
    }

    private func seedTerminalFromSnapshot() {
        guard terminal.renderedText.isEmpty,
              let tail = snapshot?.recentTerminalTail,
              !tail.isEmpty else {
            return
        }
        terminal.ingestBase64(Data(tail.utf8).base64EncodedString(), seqEnd: snapshot?.currentSequence ?? 0)
    }

    private func recordSocketState(_ state: SessionSocket.ConnectionState) {
        switch state {
        case .idle, .connecting:
            return
        case .connected:
            activityStore.record(
                category: .socket,
                title: "Session connected",
                message: "Live socket is connected.",
                hostLabel: host.displayLabel,
                sessionID: session.sessionId
            )
        case let .disconnected(reason):
            activityStore.record(
                severity: reason == nil ? .info : .warning,
                category: .socket,
                title: "Session disconnected",
                message: reason ?? "The live socket disconnected.",
                hostLabel: host.displayLabel,
                sessionID: session.sessionId
            )
        }
    }
}
