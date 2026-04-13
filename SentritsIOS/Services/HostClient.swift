import Foundation
import os

struct SnapshotRequestOptions {
    let viewId: String
    let cols: Int
    let rows: Int
}

final class NetworkSessionDelegate: NSObject, URLSessionDelegate {
    private let allowSelfSignedTLS: Bool

    init(allowSelfSignedTLS: Bool) {
        self.allowSelfSignedTLS = allowSelfSignedTLS
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard allowSelfSignedTLS,
              challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case httpStatus(Int, String)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The daemon returned an invalid response."
        case let .httpStatus(status, body):
            return body.isEmpty ? "Request failed with status \(status)." : "Request failed with status \(status): \(body)"
        case .encodingFailed:
            return "Failed to encode request."
        }
    }
}

actor HostClient {
    private let session: URLSession
    private let logger = Logger(subsystem: "com.vibeeverywhere.ios", category: "HostClient")
    private let delegate: NetworkSessionDelegate

    init(host: SavedHost? = nil) {
        let allowSelfSignedTLS = host?.allowSelfSignedTLS ?? false
        let delegate = NetworkSessionDelegate(allowSelfSignedTLS: allowSelfSignedTLS)
        self.delegate = delegate
        self.session = HostClient.makeSession(delegate: delegate)
    }

    init(session: URLSession, delegate: NetworkSessionDelegate) {
        self.session = session
        self.delegate = delegate
    }

    func health(for host: SavedHost) async throws {
        _ = try await requestText(path: "/health", endpoint: host.endpoint, token: nil)
    }

    func health(for endpoint: HostEndpoint) async throws {
        _ = try await requestText(path: "/health", endpoint: endpoint, token: nil)
    }

    func fetchDiscoveryInfo(for host: SavedHost) async throws -> DiscoveryInfo {
        try await requestJSON(path: "/discovery/info", endpoint: host.endpoint, token: nil, method: "GET")
    }

    func fetchDiscoveryInfo(for endpoint: HostEndpoint) async throws -> DiscoveryInfo {
        try await requestJSON(path: "/discovery/info", endpoint: endpoint, token: nil, method: "GET")
    }

    func fetchHostInfo(for host: SavedHost) async throws -> HostInfo {
        try await requestJSON(path: "/host/info", endpoint: host.endpoint, token: nil, method: "GET")
    }

    func fetchHostInfo(for endpoint: HostEndpoint) async throws -> HostInfo {
        try await requestJSON(path: "/host/info", endpoint: endpoint, token: nil, method: "GET")
    }

    func fetchLaunchRecords(for host: SavedHost, token: String) async throws -> [LaunchRecord] {
        try await requestJSON(path: "/host/records", endpoint: host.endpoint, token: token, method: "GET")
    }

    func postHostConfig(host: SavedHost, token: String, payload: HostConfigPayload) async throws {
        let bodyData = try JSONEncoder().encode(payload)
        _ = try await requestData(path: "/host/config", endpoint: host.endpoint, token: token, method: "POST", bodyData: bodyData)
    }

    func startPairing(for host: SavedHost, deviceName: String) async throws -> PairingRequestResponse {
        let body = PairingRequestPayload(deviceName: deviceName, deviceType: "mobile")
        return try await requestJSON(path: "/pairing/request", endpoint: host.endpoint, token: nil, method: "POST", body: body)
    }

    func claimPairing(for host: SavedHost, pairingId: String, code: String) async throws -> PairingClaimResponse {
        let body = PairingClaimPayload(pairingId: pairingId, code: code)
        let bodyData = try JSONEncoder().encode(body)
        let (data, response) = try await requestData(path: "/pairing/claim", endpoint: host.endpoint, token: nil, method: "POST", bodyData: bodyData, acceptedStatusCodes: Set([200, 202]))
        do {
            return try JSONDecoder().decode(PairingClaimResponse.self, from: data)
        } catch {
            logger.error("decode failed for /pairing/claim: \(String(describing: response), privacy: .public)")
            throw error
        }
    }

    func listSessions(for host: SavedHost, token: String) async throws -> [SessionSummary] {
        try await requestJSON(path: "/sessions", endpoint: host.endpoint, token: token, method: "GET")
    }

    func fetchSessionSnapshot(
        sessionId: String,
        host: SavedHost,
        token: String,
        options: SnapshotRequestOptions? = nil
    ) async throws -> SessionSnapshot {
        let path = "/sessions/\(sessionId)/snapshot"
        var queryItems: [URLQueryItem] = []
        if let options {
            queryItems = [
                URLQueryItem(name: "viewId", value: options.viewId),
                URLQueryItem(name: "cols", value: String(options.cols)),
                URLQueryItem(name: "rows", value: String(options.rows))
            ]
        }
        return try await requestJSON(path: path, endpoint: host.endpoint, token: token, method: "GET", queryItems: queryItems)
    }

    func updateSessionGroupTags(
        sessionId: String,
        mode: SessionGroupTagsUpdateMode,
        tags: [String],
        host: SavedHost,
        token: String
    ) async throws -> SessionGroupTagsResponse {
        let body = SessionGroupTagsUpdateRequest(mode: mode, tags: tags)
        return try await requestJSON(
            path: "/sessions/\(sessionId)/groups",
            endpoint: host.endpoint,
            token: token,
            method: "POST",
            body: body
        )
    }

    func createSession(host: SavedHost, token: String, input: CreateSessionInput) async throws -> SessionSummary {
        let payload = CreateSessionPayload(
            provider: input.provider.rawValue,
            workspaceRoot: input.normalizedWorkspaceRoot,
            title: input.normalizedTitle,
            conversationId: input.normalizedConversationID,
            commandArgv: input.normalizedCommandArgv,
            commandShell: input.normalizedCommandShell,
            groupTags: input.normalizedGroupTags
        )
        return try await requestJSON(path: "/sessions", endpoint: host.endpoint, token: token, method: "POST", body: payload)
    }

    func stopSession(sessionId: String, host: SavedHost, token: String) async throws {
        _ = try await requestText(path: "/sessions/\(sessionId)/stop", endpoint: host.endpoint, token: token, method: "POST")
    }

    func clearInactiveSessions(host: SavedHost, token: String) async throws {
        _ = try await requestText(path: "/sessions/clear-inactive", endpoint: host.endpoint, token: token, method: "POST")
    }

    func validateToken(_ token: String, for host: SavedHost) async throws {
        _ = try await listSessions(for: host, token: token)
    }

    private func requestText(path: String, endpoint: HostEndpoint, token: String?, method: String = "GET") async throws -> String {
        let (data, _) = try await requestData(path: path, endpoint: endpoint, token: token, method: method, bodyData: nil)
        return String(decoding: data, as: UTF8.self)
    }

    private func requestJSON<Response: Decodable>(
        path: String,
        endpoint: HostEndpoint,
        token: String?,
        method: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        let (data, response) = try await requestData(path: path, endpoint: endpoint, token: token, method: method, bodyData: nil, queryItems: queryItems)
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            logDecodeFailure(path: path, response: response, data: data, error: error)
            throw error
        }
    }

    private func requestJSON<Response: Decodable, Body: Encodable>(
        path: String,
        endpoint: HostEndpoint,
        token: String?,
        method: String,
        body: Body? = nil
    ) async throws -> Response {
        let bodyData: Data?
        if let body {
            bodyData = try JSONEncoder().encode(body)
        } else {
            bodyData = nil
        }

        let (data, response) = try await requestData(path: path, endpoint: endpoint, token: token, method: method, bodyData: bodyData)
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            logDecodeFailure(path: path, response: response, data: data, error: error)
            throw error
        }
    }

    private func logDecodeFailure(path: String, response: HTTPURLResponse, data: Data, error: Error) {
        let bodyPreview = SentritsDebugTrace.summarizeData(data, textLimit: 240, hexLimit: 24)
        if let decodingError = error as? DecodingError {
            let reason = Self.describe(decodingError)
            logger.error(
                "[ios.focus][decode.failed] path=\(path, privacy: .public) status=\(response.statusCode) reason=\(reason, privacy: .public) body=\(bodyPreview, privacy: .public)"
            )
            return
        }
        logger.error(
            "[ios.focus][decode.failed] path=\(path, privacy: .public) status=\(response.statusCode) error=\(error.localizedDescription, privacy: .public) body=\(bodyPreview, privacy: .public)"
        )
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case let .typeMismatch(type, context):
            return "typeMismatch(\(type)) path=\(codingPath(context.codingPath)) debug=\(context.debugDescription)"
        case let .valueNotFound(type, context):
            return "valueNotFound(\(type)) path=\(codingPath(context.codingPath)) debug=\(context.debugDescription)"
        case let .keyNotFound(key, context):
            return "keyNotFound(\(key.stringValue)) path=\(codingPath(context.codingPath)) debug=\(context.debugDescription)"
        case let .dataCorrupted(context):
            return "dataCorrupted path=\(codingPath(context.codingPath)) debug=\(context.debugDescription)"
        @unknown default:
            return "unknown DecodingError"
        }
    }

    private static func codingPath(_ path: [CodingKey]) -> String {
        if path.isEmpty {
            return "<root>"
        }
        return path.map(\.stringValue).joined(separator: ".")
    }

    private func requestData(
        path: String,
        endpoint: HostEndpoint,
        token: String?,
        method: String,
        bodyData: Data?,
        queryItems: [URLQueryItem] = [],
        acceptedStatusCodes: Set<Int> = Set(200 ... 299)
    ) async throws -> (Data, HTTPURLResponse) {
        var components = URLComponents(url: endpoint.baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else {
            throw APIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        if SentritsDebugTrace.shouldTraceHTTP(path) {
            SentritsDebugTrace.log("ios.focus", "http.request", "\(method) \(request.url?.absoluteString ?? path)")
        }
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let bodyData {
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard acceptedStatusCodes.contains(httpResponse.statusCode) else {
            let body = String(decoding: data, as: UTF8.self)
            if SentritsDebugTrace.shouldTraceHTTP(path) {
                SentritsDebugTrace.log("ios.focus", "http.error", "\(method) \(request.url?.absoluteString ?? path) status=\(httpResponse.statusCode)")
            }
            throw APIError.httpStatus(httpResponse.statusCode, body)
        }
        if SentritsDebugTrace.shouldTraceHTTP(path) {
            SentritsDebugTrace.log("ios.focus", "http.response", "\(method) \(request.url?.absoluteString ?? path) status=\(httpResponse.statusCode) bytes=\(data.count)")
        }
        return (data, httpResponse)
    }

    private static func makeSession(delegate: NetworkSessionDelegate) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }
}

private struct CreateSessionPayload: Encodable {
    let provider: String
    let workspaceRoot: String
    let title: String
    let conversationId: String?
    let commandArgv: [String]?
    let commandShell: String?
    let groupTags: [String]
}

private struct SessionGroupTagsUpdateRequest: Encodable {
    let mode: SessionGroupTagsUpdateMode
    let tags: [String]
}
