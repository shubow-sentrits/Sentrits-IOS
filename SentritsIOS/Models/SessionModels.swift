import Foundation
import os

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

enum SentritsDebugTrace {
    private static let logger = Logger(subsystem: "com.vibeeverywhere.ios", category: "SentritsDebug")

    static var isEnabled: Bool {
#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        return environment["SENTRITS_DEBUG_TRACE"] == "1" || environment["SENTRITS_DEBUG_TRACE"] == "true"
#else
        return false
#endif
    }

    static func log(_ scope: String, _ event: String, _ details: @autoclosure () -> String) {
#if DEBUG
        guard isEnabled else { return }
        let message = details()
        logger.debug("[\(scope, privacy: .public)][\(event, privacy: .public)] \(message, privacy: .public)")
#else
        _ = scope
        _ = event
        _ = details
#endif
    }

    static func shouldTraceHTTP(_ path: String) -> Bool {
#if DEBUG
        return path.contains("/snapshot") ||
            path.contains("/controller") ||
            path.contains("/ws/")
#else
        _ = path
        return false
#endif
    }

    static func summarizeText(_ text: String, limit: Int = 80) -> String {
        guard !text.isEmpty else { return "empty" }
        let prefix = String(text.prefix(limit))
        let escaped = prefix
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\u{1B}", with: "\\e")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        return text.count > limit ? "\(escaped)..." : escaped
    }

    static func summarizeData(_ data: Data, textLimit: Int = 80, hexLimit: Int = 16) -> String {
        guard !data.isEmpty else { return "empty" }
        let text = String(decoding: data, as: UTF8.self)
        let hexBytes = data.prefix(hexLimit).map { String(format: "%02x", $0) }.joined(separator: " ")
        return "text=\"\(summarizeText(text, limit: textLimit))\" hex=\(hexBytes)"
    }

    static func summarizeBase64Chunks(_ chunks: [String], limit: Int = 1) -> String {
        guard !chunks.isEmpty else { return "empty" }
        let summaries = chunks.prefix(limit).compactMap { chunk -> String? in
            guard let data = Data(base64Encoded: chunk) else { return nil }
            return summarizeData(data)
        }
        if summaries.isEmpty {
            return "undecodable"
        }
        return summaries.joined(separator: " | ")
    }
}
