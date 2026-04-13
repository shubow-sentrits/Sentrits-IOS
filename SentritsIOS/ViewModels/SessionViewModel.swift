import Foundation

extension Notification.Name {
    static let vibeSessionStateDidChange = Notification.Name("vibeSessionStateDidChange")
}

@MainActor
final class SessionViewModel: ObservableObject {
    @Published var session: SessionSummary
    @Published var socketState: SessionSocket.ConnectionState = .idle
    @Published var controllerState: SessionSocket.ConnectionState = .idle
    @Published var snapshot: SessionSnapshot?
    @Published var lastError: String?
    @Published var inputText = ""
    @Published var terminalResize = TerminalResize(cols: 80, rows: 24)
    @Published var terminalBootstrapChunksBase64: [String] = []
    @Published var terminalBootstrapToken = 0

    let host: SavedHost
    let token: String
    let terminal = TerminalEngine()

    private let socket: SessionSocket
    private let controllerSocket: SessionControllerSocket
    private let activityStore: ActivityLogStore
    private var hasLoadedSnapshot = false
    private var activeControllerClientId: String?
    private var focusedTerminalActive = false
    private var snapshotRefreshTask: Task<Void, Never>?
    private var pendingSnapshotRefresh = false
    private var pendingSnapshotRefreshDelayNanoseconds: UInt64 = 0
    private var lastSnapshotRefreshStartedAt: ContinuousClock.Instant?
    private let refreshClock = ContinuousClock()
    private var controllerOutputTraceBudget = 0

    init(host: SavedHost, token: String, session: SessionSummary, activityStore: ActivityLogStore) {
        self.host = host
        self.token = token
        self.session = session
        self.activityStore = activityStore
        self.socket = SessionSocket(host: host)
        self.controllerSocket = SessionControllerSocket(host: host)

        socket.onStateChange = { [weak self] state in
            Task { @MainActor in
                self?.socketState = state
                self?.recordSocketState(state, title: "Session")
            }
        }

        socket.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.apply(event: event)
            }
        }

        controllerSocket.onStateChange = { [weak self] state in
            Task { @MainActor in
                self?.controllerState = state
                self?.recordSocketState(state, title: "Controller")
                if case .disconnected = state {
                    self?.activeControllerClientId = nil
                    self?.terminal.resetSequenceTracking()
                }
            }
        }

        controllerSocket.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.apply(controllerEvent: event)
            }
        }
    }

    var hasRemoteControl: Bool { session.controllerKind == "remote" && session.controllerClientId != nil }

    var canSendInput: Bool { controllerState == .connected }

    var hasRenderableTerminalContent: Bool {
        !terminalBootstrapChunksBase64.isEmpty || terminal.hasContent
    }

    var usesCanonicalFocusedDisplay: Bool {
        !canSendInput && !terminalBootstrapChunksBase64.isEmpty
    }

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

    var observerTerminalDimensions: TerminalResize? {
        guard let cols = session.ptyCols, let rows = session.ptyRows, cols > 0, rows > 0 else {
            return nil
        }
        return TerminalResize(cols: cols, rows: rows)
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
        controllerSocket.disconnect(reason: "Disconnected by client.")
        socket.disconnect(reason: "Disconnected by client.")
    }

    func activate() async {
        SentritsDebugTrace.log("ios.focus", "activate.begin", "session=\(session.sessionId) focused=\(focusedTerminalActive)")
        if !focusedTerminalActive {
            await loadSnapshot(force: false)
        }
        connect()
        SentritsDebugTrace.log("ios.focus", "activate.end", "session=\(session.sessionId) socket=\(String(describing: socketState))")
    }

    func setFocusedTerminalActive(_ active: Bool) {
        focusedTerminalActive = active
        SentritsDebugTrace.log(
            "ios.focus",
            active ? "focused.activate" : "focused.deactivate",
            "session=\(session.sessionId) bootstrapChunks=\(terminalBootstrapChunksBase64.count) hasTerminal=\(terminal.hasContent)"
        )
        if active {
            scheduleFocusedSnapshotRefresh(delayNanoseconds: 0)
        } else {
            snapshotRefreshTask?.cancel()
            snapshotRefreshTask = nil
            terminalBootstrapChunksBase64 = []
        }
    }

    func requestControl() async {
        if case .connected = controllerState {
            return
        }
        if case .connecting = controllerState {
            return
        }
        activityStore.record(
            category: .control,
            title: "Control requested",
            message: "Asked for remote control of the session.",
            hostLabel: host.displayLabel,
            sessionID: session.sessionId
        )
        SentritsDebugTrace.log("ios.focus", "control.request", "session=\(session.sessionId) resize=\(terminalResize.cols)x\(terminalResize.rows)")
        controllerSocket.connect(host: host, sessionId: session.sessionId, token: token)
    }

    func releaseControl() async {
        activityStore.record(
            category: .control,
            title: "Control released",
            message: "Released remote control for the session.",
            hostLabel: host.displayLabel,
            sessionID: session.sessionId
        )
        await controllerSocket.releaseControl()
    }

    func sendInput() async {
        let payload = inputText
        guard !payload.isEmpty, canSendInput else { return }
        inputText = ""
        await controllerSocket.sendInput(payload)
    }

    func sendTerminalInput(_ data: String) async {
        guard !data.isEmpty, canSendInput else { return }
        await controllerSocket.sendInput(data)
    }

    func sendResizeIfChanged(_ resize: TerminalResize) async {
        guard resize != terminalResize else { return }
        terminalResize = resize
        await controllerSocket.sendResize(resize)
    }

    func handleFocusedTerminalResize(_ resize: TerminalResize) async {
        let changed = resize != terminalResize
        terminalResize = resize
        guard changed else { return }
        if canSendInput {
            await controllerSocket.sendResize(resize)
        }
        scheduleFocusedSnapshotRefresh(delayNanoseconds: canSendInput ? 120_000_000 : 60_000_000)
    }

    func loadSnapshot(force: Bool) async {
        if hasLoadedSnapshot, !force {
            return
        }

        do {
            let client = HostClient(host: host)
            let snapshot = try await client.fetchSessionSnapshot(
                sessionId: session.sessionId,
                host: host,
                token: token,
                options: focusedTerminalActive ? currentSnapshotOptions() : nil
            )
            SentritsDebugTrace.log(
                "ios.focus",
                "snapshot.loaded",
                "session=\(session.sessionId) focused=\(focusedTerminalActive) screen=\(snapshot.terminalScreen != nil) viewport=\(snapshot.terminalViewport != nil) bootstrap=\((snapshot.terminalViewport?.bootstrapAnsi ?? snapshot.terminalScreen?.bootstrapAnsi ?? snapshot.recentTerminalTail ?? "").count)"
            )
            self.snapshot = snapshot
            hasLoadedSnapshot = true
            updateSession(from: snapshot)
            applySnapshotToTerminal(snapshot, bootstrapCanonical: focusedTerminalActive)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func updateSession(_ summary: SessionSummary) {
        session = summary
        publishSessionStateChanged()
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
            ptyCols: session.ptyCols,
            ptyRows: session.ptyRows,
            currentSequence: session.currentSequence,
            attachedClientCount: session.attachedClientCount,
            recentFileChangeCount: session.recentFileChangeCount,
            gitDirty: session.gitDirty,
            gitBranch: session.gitBranch,
            gitModifiedCount: session.gitModifiedCount,
            gitStagedCount: session.gitStagedCount,
            gitUntrackedCount: session.gitUntrackedCount
        )
        publishSessionStateChanged()
    }

    func stopSession() async {
        guard canSendInput else { return }
        await controllerSocket.stopSession()
        activityStore.record(
            category: .explorer,
            title: "Session stop requested",
            message: "Sent a stop request on the controller stream.",
            hostLabel: host.displayLabel,
            sessionID: session.sessionId
        )
    }

    private func apply(event: SessionSocketEvent) {
        switch event {
        case let .sessionUpdated(metadata):
            let previousStatus = session.status
            let previousController = session.controllerKind
            let previousPtyCols = session.ptyCols
            let previousPtyRows = session.ptyRows
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
                ptyCols: metadata.ptyCols,
                ptyRows: metadata.ptyRows,
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
            if controllerState == .connected,
               (metadata.controllerKind != "remote" ||
                (activeControllerClientId != nil && metadata.controllerClientId != activeControllerClientId)) {
                controllerSocket.disconnect(reason: "Control moved to another client.")
            }
            if focusedTerminalActive, metadata.ptyCols != previousPtyCols || metadata.ptyRows != previousPtyRows {
                scheduleFocusedSnapshotRefresh(delayNanoseconds: 0)
            }
            publishSessionStateChanged()
        case let .sessionActivity(metadata):
            let previousActivityPtyCols = session.ptyCols
            let previousActivityPtyRows = session.ptyRows
            session = SessionSummary(
                sessionId: session.sessionId,
                provider: session.provider,
                workspaceRoot: session.workspaceRoot,
                title: session.title,
                status: session.status,
                conversationId: session.conversationId,
                groupTags: metadata.groupTags ?? session.groupTags,
                controllerKind: session.controllerKind,
                controllerClientId: session.controllerClientId,
                isRecovered: session.isRecovered,
                archivedRecord: session.archivedRecord,
                isActive: metadata.isActive ?? session.isActive,
                inventoryState: session.inventoryState,
                activityState: metadata.activityState ?? session.activityState,
                supervisionState: metadata.supervisionState ?? session.supervisionState,
                attentionState: metadata.attentionState ?? session.attentionState,
                attentionReason: metadata.attentionReason ?? session.attentionReason,
                createdAtUnixMs: session.createdAtUnixMs,
                lastStatusAtUnixMs: session.lastStatusAtUnixMs,
                lastOutputAtUnixMs: metadata.lastOutputAtUnixMs ?? session.lastOutputAtUnixMs,
                lastActivityAtUnixMs: metadata.lastActivityAtUnixMs ?? session.lastActivityAtUnixMs,
                lastFileChangeAtUnixMs: metadata.lastFileChangeAtUnixMs ?? session.lastFileChangeAtUnixMs,
                lastGitChangeAtUnixMs: metadata.lastGitChangeAtUnixMs ?? session.lastGitChangeAtUnixMs,
                lastControllerChangeAtUnixMs: metadata.lastControllerChangeAtUnixMs ?? session.lastControllerChangeAtUnixMs,
                attentionSinceUnixMs: metadata.attentionSinceUnixMs ?? session.attentionSinceUnixMs,
                ptyCols: metadata.ptyCols ?? session.ptyCols,
                ptyRows: metadata.ptyRows ?? session.ptyRows,
                currentSequence: metadata.currentSequence ?? session.currentSequence,
                attachedClientCount: metadata.attachedClientCount ?? session.attachedClientCount,
                recentFileChangeCount: metadata.recentFileChangeCount ?? session.recentFileChangeCount,
                gitDirty: metadata.gitDirty ?? session.gitDirty,
                gitBranch: metadata.gitBranch ?? session.gitBranch,
                gitModifiedCount: metadata.gitModifiedCount ?? session.gitModifiedCount,
                gitStagedCount: metadata.gitStagedCount ?? session.gitStagedCount,
                gitUntrackedCount: metadata.gitUntrackedCount ?? session.gitUntrackedCount
            )
            if focusedTerminalActive,
               metadata.ptyCols != nil && metadata.ptyCols != previousActivityPtyCols ||
               metadata.ptyRows != nil && metadata.ptyRows != previousActivityPtyRows {
                scheduleFocusedSnapshotRefresh(delayNanoseconds: 0)
            }
            publishSessionStateChanged()
        case let .terminalOutput(output):
            guard controllerState != .connected else { return }
            if focusedTerminalActive {
                if usesCanonicalFocusedDisplay {
                    SentritsDebugTrace.log("ios.focus", "observer.output.refresh", "session=\(session.sessionId) seq=\(output.seqStart)-\(output.seqEnd)")
                    scheduleFocusedSnapshotRefresh(delayNanoseconds: 30_000_000)
                    return
                }
                SentritsDebugTrace.log(
                    "ios.focus",
                    "observer.output.raw",
                    "session=\(session.sessionId) seq=\(output.seqStart)-\(output.seqEnd) controllerState=\(String(describing: controllerState)) canonical=\(usesCanonicalFocusedDisplay)"
                )
            }
            terminal.ingestBase64(output.dataBase64, seqStart: output.seqStart, seqEnd: output.seqEnd)
        case let .sessionExited(payload):
            controllerSocket.disconnect(reason: "Session exited.")
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
                supervisionState: "stopped",
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
                ptyCols: session.ptyCols,
                ptyRows: session.ptyRows,
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
            publishSessionStateChanged()
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

    private func apply(controllerEvent: SessionControllerSocketEvent) {
        switch controllerEvent {
        case let .ready(payload):
            activeControllerClientId = payload.controllerClientId
            let rawChunksBeforeClear = terminal.outputChunksBase64.count
            let bootstrapSummary = SentritsDebugTrace.summarizeBase64Chunks(terminalBootstrapChunksBase64)
            terminal.clearBufferedOutput()
            controllerOutputTraceBudget = 8
            SentritsDebugTrace.log(
                "ios.focus",
                "control.ready",
                "session=\(session.sessionId) controllerClientId=\(payload.controllerClientId ?? "nil") resize=\(terminalResize.cols)x\(terminalResize.rows) focused=\(focusedTerminalActive) canonical=\(usesCanonicalFocusedDisplay) bootstrapToken=\(terminalBootstrapToken) bootstrapChunks=\(terminalBootstrapChunksBase64.count) bootstrapSummary=\(bootstrapSummary) rawChunksBeforeClear=\(rawChunksBeforeClear) rawChunksAfterClear=\(terminal.outputChunksBase64.count)"
            )
            activityStore.record(
                category: .control,
                title: "Control granted",
                message: "Focused terminal is now using the privileged controller stream.",
                hostLabel: host.displayLabel,
                sessionID: session.sessionId
            )
            Task {
                await controllerSocket.sendResize(terminalResize)
            }
        case let .terminalOutput(data):
            if controllerOutputTraceBudget > 0 {
                controllerOutputTraceBudget -= 1
                SentritsDebugTrace.log(
                    "ios.focus",
                    "controller.output.raw",
                    "session=\(session.sessionId) bytes=\(data.count) summary=\(SentritsDebugTrace.summarizeData(data)) rawChunksBefore=\(terminal.outputChunksBase64.count)"
                )
            }
            terminal.appendBase64Raw(data.base64EncodedString())
        case .released:
            controllerOutputTraceBudget = 0
            activityStore.record(
                category: .control,
                title: "Control released",
                message: "Focused terminal returned to observer mode.",
                hostLabel: host.displayLabel,
                sessionID: session.sessionId
            )
            scheduleFocusedSnapshotRefresh(delayNanoseconds: 0)
        case let .rejected(payload):
            controllerOutputTraceBudget = 0
            lastError = "\(payload.code): \(payload.message)"
            activityStore.record(
                severity: .warning,
                category: .control,
                title: "Control request rejected",
                message: payload.message,
                hostLabel: host.displayLabel,
                sessionID: payload.sessionId ?? session.sessionId
            )
        case let .sessionExited(payload):
            controllerOutputTraceBudget = 0
            controllerSocket.disconnect(reason: "Session exited.")
            apply(event: .sessionExited(payload))
        case let .error(payload):
            controllerOutputTraceBudget = 0
            lastError = "\(payload.code): \(payload.message)"
            activityStore.record(
                severity: .error,
                category: .control,
                title: "Controller error",
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
            ptyCols: snapshot.signals?.ptyCols ?? session.ptyCols,
            ptyRows: snapshot.signals?.ptyRows ?? session.ptyRows,
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

    private func applySnapshotToTerminal(_ snapshot: SessionSnapshot, bootstrapCanonical: Bool) {
        guard bootstrapCanonical else {
            seedTerminalFromSnapshot()
            return
        }

        let bootstrap = Self.buildViewportBootstrap(snapshot.terminalViewport, screen: snapshot.terminalScreen)
            ?? Self.buildScreenBootstrap(snapshot.terminalScreen)
            ?? snapshot.recentTerminalTail

        guard let bootstrap, !bootstrap.isEmpty else {
            terminalBootstrapChunksBase64 = []
            SentritsDebugTrace.log("ios.focus", "bootstrap.missing", "session=\(session.sessionId)")
            return
        }

        let nextChunks = Self.makeBootstrapChunks(from: bootstrap)
        guard nextChunks != terminalBootstrapChunksBase64 else {
            SentritsDebugTrace.log("ios.focus", "bootstrap.unchanged", "session=\(session.sessionId) chunks=\(nextChunks.count)")
            return
        }

        terminalBootstrapChunksBase64 = nextChunks
        terminalBootstrapToken &+= 1
        SentritsDebugTrace.log(
            "ios.focus",
            "bootstrap.applied",
            "session=\(session.sessionId) chunks=\(terminalBootstrapChunksBase64.count) chars=\(bootstrap.count) token=\(terminalBootstrapToken)"
        )
    }

    private static func makeBootstrapChunks(from text: String) -> [String] {
        let data = Data(text.utf8)
        let chunkSize = 12 * 1024
        guard !data.isEmpty else { return [] }
        var chunks: [String] = []
        chunks.reserveCapacity((data.count / chunkSize) + 1)
        var index = data.startIndex
        while index < data.endIndex {
            let endIndex = data.index(index, offsetBy: chunkSize, limitedBy: data.endIndex) ?? data.endIndex
            chunks.append(data[index..<endIndex].base64EncodedString())
            index = endIndex
        }
        return chunks
    }

    private static func buildScreenBootstrap(_ screen: SessionTerminalScreenSnapshot?) -> String? {
        guard let screen else { return nil }
        if let bootstrapAnsi = screen.bootstrapAnsi, !bootstrapAnsi.isEmpty {
            return bootstrapAnsi
        }

        let scrollback = screen.scrollbackLines ?? []
        let visible = screen.visibleLines ?? []
        let cursorRow = max(0, screen.cursorRow ?? 0)
        let cursorColumn = max(0, screen.cursorColumn ?? 0)

        var chunks: [String] = []
        if !scrollback.isEmpty {
            chunks.append(scrollback.joined(separator: "\r\n"))
            chunks.append("\r\n")
        }

        chunks.append("\u{1B}[0m\u{1B}[2J\u{1B}[H")
        for index in visible.indices {
            chunks.append(visible[index])
            if index < visible.count - 1 {
                chunks.append("\u{1B}[E")
            }
        }
        chunks.append("\u{1B}[\(cursorRow + 1);\(cursorColumn + 1)H")
        return chunks.joined()
    }

    private static func buildViewportBootstrap(
        _ viewport: SessionTerminalViewportSnapshot?,
        screen: SessionTerminalScreenSnapshot?
    ) -> String? {
        guard let viewport else { return nil }
        if let bootstrapAnsi = viewport.bootstrapAnsi, !bootstrapAnsi.isEmpty {
            return bootstrapAnsi
        }

        let visible = viewport.visibleLines ?? []
        let cursorRow = max(0, viewport.cursorRow ?? 0)
        let cursorColumn = max(0, viewport.cursorColumn ?? 0)
        let viewportTopLine = max(0, viewport.viewportTopLine ?? 0)
        let horizontalOffset = max(0, viewport.horizontalOffset ?? 0)
        let cols = max(0, viewport.cols ?? 0)
        let allLines = (screen?.scrollbackLines ?? []) + (screen?.visibleLines ?? [])

        var chunks: [String] = []
        if viewportTopLine > 0, !allLines.isEmpty {
            let history = allLines
                .prefix(min(viewportTopLine, allLines.count))
                .map { clipColumns($0, startColumn: horizontalOffset, maxColumns: cols > 0 ? cols : Int.max) }
            if !history.isEmpty {
                chunks.append(history.joined(separator: "\r\n"))
                chunks.append("\r\n")
            }
        }

        chunks.append("\u{1B}[0m\u{1B}[2J\u{1B}[H")
        for index in visible.indices {
            chunks.append(visible[index])
            if index < visible.count - 1 {
                chunks.append("\u{1B}[E")
            }
        }
        chunks.append("\u{1B}[\(cursorRow + 1);\(cursorColumn + 1)H")
        return chunks.joined()
    }

    private static func clipColumns(_ line: String, startColumn: Int, maxColumns: Int) -> String {
        guard !line.isEmpty, maxColumns > 0 else { return "" }
        let scalars = Array(line)
        let start = max(0, startColumn)
        guard start < scalars.count else { return "" }
        let end = min(scalars.count, start + maxColumns)
        return String(scalars[start..<end])
    }

    private func currentSnapshotOptions() -> SnapshotRequestOptions {
        SnapshotRequestOptions(
            viewId: "ios-focused-\(session.sessionId)",
            cols: terminalResize.cols,
            rows: terminalResize.rows
        )
    }

    private func scheduleFocusedSnapshotRefresh(delayNanoseconds: UInt64) {
        guard focusedTerminalActive else { return }
        pendingSnapshotRefresh = true
        if !snapshotRefreshTaskIsActive {
            pendingSnapshotRefreshDelayNanoseconds = delayNanoseconds
            snapshotRefreshTask = Task { [weak self] in
                await self?.runFocusedSnapshotRefreshLoop()
            }
            return
        }

        if pendingSnapshotRefreshDelayNanoseconds == 0 {
            return
        }
        if delayNanoseconds == 0 {
            pendingSnapshotRefreshDelayNanoseconds = 0
        } else if pendingSnapshotRefreshDelayNanoseconds == 0 {
            pendingSnapshotRefreshDelayNanoseconds = delayNanoseconds
        } else {
            pendingSnapshotRefreshDelayNanoseconds = min(pendingSnapshotRefreshDelayNanoseconds, delayNanoseconds)
        }
    }

    private var snapshotRefreshTaskIsActive: Bool {
        snapshotRefreshTask != nil
    }

    private func runFocusedSnapshotRefreshLoop() async {
        defer {
            snapshotRefreshTask = nil
        }

        while focusedTerminalActive {
            guard pendingSnapshotRefresh else { break }
            pendingSnapshotRefresh = false
            let requestedDelay = pendingSnapshotRefreshDelayNanoseconds
            pendingSnapshotRefreshDelayNanoseconds = 0

            if requestedDelay > 0 {
                try? await Task.sleep(nanoseconds: requestedDelay)
            }
            guard !Task.isCancelled, focusedTerminalActive else { return }

            let minimumIntervalNanoseconds: UInt64 = canSendInput ? 140_000_000 : 90_000_000
            if let lastStartedAt = lastSnapshotRefreshStartedAt {
                let elapsed = lastStartedAt.duration(to: refreshClock.now)
                let elapsedNanoseconds = UInt64(max(0, elapsed.components.seconds)) * 1_000_000_000
                    + UInt64(max(0, elapsed.components.attoseconds / 1_000_000_000))
                if elapsedNanoseconds < minimumIntervalNanoseconds {
                    let remaining = minimumIntervalNanoseconds - elapsedNanoseconds
                    SentritsDebugTrace.log("ios.focus", "snapshot.refresh.coalesce", "session=\(session.sessionId) remainingNs=\(remaining)")
                    try? await Task.sleep(nanoseconds: remaining)
                }
            }
            guard !Task.isCancelled, focusedTerminalActive else { return }

            lastSnapshotRefreshStartedAt = refreshClock.now

            do {
                SentritsDebugTrace.log(
                    "ios.focus",
                    "snapshot.refresh.request",
                    "session=\(self.session.sessionId) delayNs=\(requestedDelay) resize=\(self.terminalResize.cols)x\(self.terminalResize.rows)"
                )
                let client = HostClient(host: self.host)
                let snapshot = try await client.fetchSessionSnapshot(
                    sessionId: self.session.sessionId,
                    host: self.host,
                    token: self.token,
                    options: self.currentSnapshotOptions()
                )
                guard !Task.isCancelled else { return }
                self.snapshot = snapshot
                self.hasLoadedSnapshot = true
                self.updateSession(from: snapshot)
                self.applySnapshotToTerminal(snapshot, bootstrapCanonical: true)
                self.lastError = nil
                SentritsDebugTrace.log(
                    "ios.focus",
                    "snapshot.refresh.response",
                    "session=\(self.session.sessionId) screen=\(snapshot.terminalScreen != nil) viewport=\(snapshot.terminalViewport != nil)"
                )
            } catch {
                guard !Task.isCancelled else { return }
                self.lastError = error.localizedDescription
                SentritsDebugTrace.log("ios.focus", "snapshot.refresh.error", "session=\(self.session.sessionId) error=\(error.localizedDescription)")
            }
        }
    }

    private func recordSocketState(_ state: SessionSocket.ConnectionState, title: String) {
        switch state {
        case .idle, .connecting:
            return
        case .connected:
            activityStore.record(
                category: .socket,
                title: "\(title) connected",
                message: "\(title) socket is connected.",
                hostLabel: host.displayLabel,
                sessionID: session.sessionId
            )
        case let .disconnected(reason):
            activityStore.record(
                severity: reason == nil ? .info : .warning,
                category: .socket,
                title: "\(title) disconnected",
                message: reason ?? "\(title) socket disconnected.",
                hostLabel: host.displayLabel,
                sessionID: session.sessionId
            )
        }
    }

    private func publishSessionStateChanged() {
        NotificationCenter.default.post(
            name: .vibeSessionStateDidChange,
            object: nil,
            userInfo: [
                "hostID": host.id.uuidString,
                "sessionID": session.sessionId
            ]
        )
    }
}
