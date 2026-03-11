import Foundation

struct SessionMetadata: Codable {
    let sessionId: String
    let provider: String
    let workspaceRoot: String
    let title: String
    let status: String
    let controllerKind: String
    let controllerClientId: String?
}

enum SessionSocketEvent {
    case sessionUpdated(SessionMetadata)
    case terminalOutput(TerminalOutputPayload)
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

struct SessionErrorPayload: Codable {
    let sessionId: String?
    let code: String
    let message: String
}

struct TerminalResize: Equatable {
    let cols: Int
    let rows: Int
}
