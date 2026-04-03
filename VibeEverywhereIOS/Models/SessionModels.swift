import Foundation

struct SessionMetadata: Codable {
    let sessionId: String
    let provider: String
    let workspaceRoot: String
    let title: String
    let status: String
    let conversationId: String?
    let groupTags: [String]
    let controllerKind: String
    let controllerClientId: String?
    let isRecovered: Bool?
    let archivedRecord: Bool?
    let isActive: Bool?
    let inventoryState: String?
    let activityState: String?
    let supervisionState: String?
    let attentionState: String?
    let attentionReason: String?
    let createdAtUnixMs: Int64?
    let lastStatusAtUnixMs: Int64?
    let lastOutputAtUnixMs: Int64?
    let lastActivityAtUnixMs: Int64?
    let lastFileChangeAtUnixMs: Int64?
    let lastGitChangeAtUnixMs: Int64?
    let lastControllerChangeAtUnixMs: Int64?
    let attentionSinceUnixMs: Int64?
    let ptyCols: Int?
    let ptyRows: Int?
    let currentSequence: Int?
    let attachedClientCount: Int?
    let recentFileChangeCount: Int?
    let gitDirty: Bool?
    let gitBranch: String?
    let gitModifiedCount: Int?
    let gitStagedCount: Int?
    let gitUntrackedCount: Int?
}

enum SessionSocketEvent {
    case sessionUpdated(SessionMetadata)
    case sessionActivity(SessionActivityMetadata)
    case terminalOutput(TerminalOutputPayload)
    case sessionExited(SessionExitedPayload)
    case error(SessionErrorPayload)
}

struct SessionActivityMetadata: Codable {
    let sessionId: String
    let activityState: String?
    let groupTags: [String]?
    let isActive: Bool?
    let supervisionState: String?
    let attentionState: String?
    let attentionReason: String?
    let lastOutputAtUnixMs: Int64?
    let lastActivityAtUnixMs: Int64?
    let lastFileChangeAtUnixMs: Int64?
    let lastGitChangeAtUnixMs: Int64?
    let lastControllerChangeAtUnixMs: Int64?
    let attentionSinceUnixMs: Int64?
    let ptyCols: Int?
    let ptyRows: Int?
    let currentSequence: Int?
    let attachedClientCount: Int?
    let recentFileChangeCount: Int?
    let gitDirty: Bool?
    let gitBranch: String?
    let gitModifiedCount: Int?
    let gitStagedCount: Int?
    let gitUntrackedCount: Int?
}

enum SessionControllerSocketEvent {
    case ready(ControllerReadyPayload)
    case terminalOutput(Data)
    case released(ControllerReleasedPayload)
    case rejected(SessionErrorPayload)
    case sessionExited(SessionExitedPayload)
    case error(SessionErrorPayload)
}

struct TerminalOutputPayload: Codable {
    let sessionId: String
    let seqStart: Int
    let seqEnd: Int
    let dataEncoding: String
    let dataBase64: String
}

struct SessionExitedPayload: Codable {
    let sessionId: String
    let status: String
}

struct ControllerReadyPayload: Codable {
    let sessionId: String
    let controllerKind: String
    let controllerClientId: String?
}

struct ControllerReleasedPayload: Codable {
    let sessionId: String
}

struct SessionErrorPayload: Codable {
    let sessionId: String?
    let code: String
    let message: String
}

struct SessionSnapshot: Codable {
    let sessionId: String
    let provider: String
    let workspaceRoot: String
    let title: String
    let status: String
    let conversationId: String?
    let groupTags: [String]
    let currentSequence: Int?
    let recentTerminalTail: String?
    let terminalScreen: SessionTerminalScreenSnapshot?
    let terminalViewport: SessionTerminalViewportSnapshot?
    let recentFileChanges: [String]
    let signals: SessionSnapshotSignals?
    let git: SessionSnapshotGit?
}

struct SessionTerminalScreenSnapshot: Codable {
    let ptyCols: Int?
    let ptyRows: Int?
    let renderRevision: Int?
    let cursorRow: Int?
    let cursorColumn: Int?
    let visibleLines: [String]?
    let scrollbackLines: [String]?
    let bootstrapAnsi: String?
}

struct SessionTerminalViewportSnapshot: Codable {
    let viewId: String?
    let cols: Int?
    let rows: Int?
    let renderRevision: Int?
    let totalLineCount: Int?
    let viewportTopLine: Int?
    let horizontalOffset: Int?
    let cursorRow: Int?
    let cursorColumn: Int?
    let visibleLines: [String]?
    let bootstrapAnsi: String?
}

struct SessionSnapshotSignals: Codable {
    let lastOutputAtUnixMs: Int64?
    let lastActivityAtUnixMs: Int64?
    let lastFileChangeAtUnixMs: Int64?
    let lastGitChangeAtUnixMs: Int64?
    let lastControllerChangeAtUnixMs: Int64?
    let attentionSinceUnixMs: Int64?
    let ptyCols: Int?
    let ptyRows: Int?
    let currentSequence: Int?
    let recentFileChangeCount: Int?
    let supervisionState: String?
    let attentionState: String?
    let attentionReason: String?
    let gitDirty: Bool?
    let gitBranch: String?
    let gitModifiedCount: Int?
    let gitStagedCount: Int?
    let gitUntrackedCount: Int?
}

struct SessionSnapshotGit: Codable {
    let branch: String?
    let modifiedCount: Int?
    let stagedCount: Int?
    let untrackedCount: Int?
    let modifiedFiles: [String]?
    let stagedFiles: [String]?
    let untrackedFiles: [String]?
}

struct SessionGroupTagsResponse: Codable {
    let sessionId: String
    let groupTags: [String]
}

enum SessionGroupTagsUpdateMode: String, Codable {
    case add
    case remove
    case set
}

struct TerminalResize: Equatable {
    let cols: Int
    let rows: Int
}
