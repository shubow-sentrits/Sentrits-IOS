import Foundation
import os

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

    init(session: URLSession = HostClient.makeSession()) {
        self.session = session
    }

    func health(for host: SavedHost) async throws {
        _ = try await requestText(path: "/health", host: host, token: nil)
    }

    func fetchHostInfo(for host: SavedHost) async throws -> HostInfo {
        try await requestJSON(path: "/host/info", host: host, token: nil, method: "GET")
    }

    func startPairing(for host: SavedHost, deviceName: String) async throws -> PairingRequestResponse {
        let body = PairingRequestPayload(deviceName: deviceName, deviceType: "mobile")
        return try await requestJSON(path: "/pairing/request", host: host, token: nil, method: "POST", body: body)
    }

    func listSessions(for host: SavedHost, token: String) async throws -> [SessionSummary] {
        try await requestJSON(path: "/sessions", host: host, token: token, method: "GET")
    }

    func stopSession(sessionId: String, host: SavedHost, token: String) async throws {
        _ = try await requestText(path: "/sessions/\(sessionId)/stop", host: host, token: token, method: "POST")
    }

    func validateToken(_ token: String, for host: SavedHost) async throws {
        _ = try await listSessions(for: host, token: token)
    }

    private func requestText(path: String, host: SavedHost, token: String?, method: String = "GET") async throws -> String {
        let (data, _) = try await requestData(path: path, host: host, token: token, method: method, bodyData: nil)
        return String(decoding: data, as: UTF8.self)
    }

    private func requestJSON<Response: Decodable>(
        path: String,
        host: SavedHost,
        token: String?,
        method: String
    ) async throws -> Response {
        let (data, response) = try await requestData(path: path, host: host, token: token, method: method, bodyData: nil)
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            logger.error("decode failed for \(path, privacy: .public): \(String(describing: response), privacy: .public)")
            throw error
        }
    }

    private func requestJSON<Response: Decodable, Body: Encodable>(
        path: String,
        host: SavedHost,
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

        let (data, response) = try await requestData(path: path, host: host, token: token, method: method, bodyData: bodyData)
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            logger.error("decode failed for \(path, privacy: .public): \(String(describing: response), privacy: .public)")
            throw error
        }
    }

    private func requestData(
        path: String,
        host: SavedHost,
        token: String?,
        method: String,
        bodyData: Data?
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: host.baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 10
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
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let body = String(decoding: data, as: UTF8.self)
            throw APIError.httpStatus(httpResponse.statusCode, body)
        }
        return (data, httpResponse)
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }
}
