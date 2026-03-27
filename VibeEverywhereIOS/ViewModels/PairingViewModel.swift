import Foundation
import UIKit

@MainActor
final class PairingViewModel: ObservableObject {
    enum Phase {
        case idle
        case requesting
        case waiting(PairingRequestResponse)
        case approved(deviceName: String?)
        case rejected
        case expired
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle

    private let host: SavedHost
    private let tokenStore: TokenStore
    private var pollingTask: Task<Void, Never>?
    private let pollIntervalNanoseconds: UInt64 = 2_000_000_000

    init(host: SavedHost, tokenStore: TokenStore) {
        self.host = host
        self.tokenStore = tokenStore
    }

    func start() async {
        stopPolling()
        phase = .requesting

        do {
            let deviceName = UIDevice.current.name
            let client = HostClient(host: host)
            let response = try await client.startPairing(for: host, deviceName: deviceName)
            phase = .waiting(response)
            startPollingIfNeeded()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func retryPolling() {
        guard case let .waiting(response) = phase else { return }
        phase = .waiting(response)
        startPollingIfNeeded(forceRestart: true, response: response)
    }

    func cancel() {
        stopPolling()
        if case .requesting = phase {
            phase = .idle
        }
    }

    deinit {
        pollingTask?.cancel()
    }

    private func startPollingIfNeeded(forceRestart: Bool = false, response explicitResponse: PairingRequestResponse? = nil) {
        let response: PairingRequestResponse
        if let explicitResponse {
            response = explicitResponse
        } else if case let .waiting(currentResponse) = phase {
            response = currentResponse
        } else {
            return
        }

        if forceRestart {
            stopPolling()
        } else if pollingTask != nil {
            return
        }

        pollingTask = Task { [host] in
            let client = HostClient(host: host)
            while !Task.isCancelled {
                do {
                    let claim = try await client.claimPairing(for: host, pairingId: response.pairingId, code: response.code)
                    await MainActor.run {
                        self.handleClaimResponse(claim)
                    }
                    if claim.status != "pending" {
                        return
                    }
                } catch {
                    await MainActor.run {
                        self.phase = .failed(error.localizedDescription)
                        self.stopPolling()
                    }
                    return
                }

                do {
                    try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
                } catch {
                    return
                }
            }
        }
    }

    private func handleClaimResponse(_ response: PairingClaimResponse) {
        switch response.status {
        case "approved":
            if let token = response.token {
                do {
                    try tokenStore.setToken(token, for: host.tokenKey)
                    phase = .approved(deviceName: response.deviceName)
                } catch {
                    phase = .failed(error.localizedDescription)
                }
            } else {
                phase = .failed("Pairing completed without a token.")
            }
            stopPolling()
        case "pending":
            if case let .waiting(request) = phase {
                phase = .waiting(request)
            }
        case "rejected":
            phase = .rejected
            stopPolling()
        case "expired":
            phase = .expired
            stopPolling()
        default:
            phase = .failed("Unexpected pairing status: \(response.status)")
            stopPolling()
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}
