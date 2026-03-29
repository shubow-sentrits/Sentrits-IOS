import Foundation
import os

@MainActor
final class SessionSocket {
    enum ConnectionState: Equatable {
        case idle
        case connecting
        case connected
        case disconnected(String?)
    }

    private let session: URLSession
    private let delegate: NetworkSessionDelegate
    private let logger = Logger(subsystem: "com.vibeeverywhere.ios", category: "SessionSocket")
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var isConnected = false

    var onEvent: ((SessionSocketEvent) -> Void)?
    var onStateChange: ((ConnectionState) -> Void)?

    init(host: SavedHost) {
        let delegate = NetworkSessionDelegate(allowSelfSignedTLS: host.allowSelfSignedTLS)
        self.delegate = delegate
        self.session = Self.makeSession(delegate: delegate)
    }

    func connect(host: SavedHost, sessionId: String, token: String) {
        disconnect(reason: nil)
        onStateChange?(.connecting)

        let url = host.websocketURL
            .appending(path: "/ws/sessions/\(sessionId)")
            .appending(queryItems: [URLQueryItem(name: "access_token", value: token)])
        let request = URLRequest(url: url)
        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
        isConnected = true
        onStateChange?(.connected)
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    func disconnect(reason: String?) {
        isConnected = false
        receiveTask?.cancel()
        receiveTask = nil
        if let task {
            task.cancel(with: .normalClosure, reason: nil)
        }
        task = nil
        onStateChange?(.disconnected(reason))
    }

    private func receiveLoop() async {
        guard let task else { return }
        while !Task.isCancelled, isConnected {
            do {
                let message = try await task.receive()
                switch message {
                case let .data(data):
                    try handle(data: data)
                case let .string(string):
                    try handle(data: Data(string.utf8))
                @unknown default:
                    break
                }
            } catch {
                logger.error("observer websocket receive failed: \(error.localizedDescription, privacy: .public)")
                isConnected = false
                onStateChange?(.disconnected(error.localizedDescription))
                break
            }
        }
    }

    private func handle(data: Data) throws {
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(EventEnvelope.self, from: data)
        switch envelope.type {
        case "session.updated":
            onEvent?(.sessionUpdated(try decoder.decode(SessionMetadata.self, from: data)))
        case "terminal.output":
            onEvent?(.terminalOutput(try decoder.decode(TerminalOutputPayload.self, from: data)))
        case "session.exited":
            onEvent?(.sessionExited(try decoder.decode(SessionExitedPayload.self, from: data)))
        case "error":
            onEvent?(.error(try decoder.decode(SessionErrorPayload.self, from: data)))
        default:
            logger.debug("ignoring unknown observer websocket event")
        }
    }

    static func makeSession(delegate: NetworkSessionDelegate) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }
}

@MainActor
final class SessionControllerSocket {
    private let session: URLSession
    private let delegate: NetworkSessionDelegate
    private let logger = Logger(subsystem: "com.vibeeverywhere.ios", category: "SessionControllerSocket")
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var isOpen = false

    var onEvent: ((SessionControllerSocketEvent) -> Void)?
    var onStateChange: ((SessionSocket.ConnectionState) -> Void)?

    init(host: SavedHost) {
        let delegate = NetworkSessionDelegate(allowSelfSignedTLS: host.allowSelfSignedTLS)
        self.delegate = delegate
        self.session = SessionSocket.makeSession(delegate: delegate)
    }

    func connect(host: SavedHost, sessionId: String, token: String) {
        disconnect(reason: nil)
        onStateChange?(.connecting)

        let url = host.websocketURL
            .appending(path: "/ws/sessions/\(sessionId)/controller")
            .appending(queryItems: [URLQueryItem(name: "access_token", value: token)])
        let request = URLRequest(url: url)
        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
        isOpen = true
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    func disconnect(reason: String?) {
        isOpen = false
        receiveTask?.cancel()
        receiveTask = nil
        if let task {
            task.cancel(with: .normalClosure, reason: nil)
        }
        task = nil
        onStateChange?(.disconnected(reason))
    }

    func sendInput(_ data: String) async {
        guard let task, isOpen, let payload = data.data(using: .utf8) else { return }
        do {
            try await task.send(.data(payload))
        } catch {
            logger.error("controller input send failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func sendResize(_ resize: TerminalResize) async {
        await send(json: ["type": "terminal.resize", "cols": resize.cols, "rows": resize.rows])
    }

    func releaseControl() async {
        await send(json: ["type": "session.control.release"])
    }

    func stopSession() async {
        await send(json: ["type": "session.stop"])
    }

    private func receiveLoop() async {
        guard let task else { return }
        while !Task.isCancelled, isOpen {
            do {
                let message = try await task.receive()
                switch message {
                case let .data(data):
                    onEvent?(.terminalOutput(data))
                case let .string(string):
                    try handleTextFrame(Data(string.utf8))
                @unknown default:
                    break
                }
            } catch {
                logger.error("controller websocket receive failed: \(error.localizedDescription, privacy: .public)")
                isOpen = false
                onStateChange?(.disconnected(error.localizedDescription))
                break
            }
        }
    }

    private func send(json: [String: Any]) async {
        guard let task, isOpen else { return }
        do {
            let data = try JSONSerialization.data(withJSONObject: json)
            let string = String(decoding: data, as: UTF8.self)
            try await task.send(.string(string))
        } catch {
            logger.error("controller websocket send failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handleTextFrame(_ data: Data) throws {
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(EventEnvelope.self, from: data)
        switch envelope.type {
        case "controller.ready":
            let payload = try decoder.decode(ControllerReadyPayload.self, from: data)
            onStateChange?(.connected)
            onEvent?(.ready(payload))
        case "controller.released":
            let payload = try decoder.decode(ControllerReleasedPayload.self, from: data)
            onEvent?(.released(payload))
            disconnect(reason: "Control released.")
        case "controller.rejected":
            let payload = try decoder.decode(SessionErrorPayload.self, from: data)
            onEvent?(.rejected(payload))
            disconnect(reason: payload.message)
        case "session.exited":
            let payload = try decoder.decode(SessionExitedPayload.self, from: data)
            onEvent?(.sessionExited(payload))
            disconnect(reason: "Session exited.")
        case "error":
            let payload = try decoder.decode(SessionErrorPayload.self, from: data)
            onEvent?(.error(payload))
        default:
            logger.debug("ignoring unknown controller websocket event")
        }
    }
}

private struct EventEnvelope: Decodable {
    let type: String
}
