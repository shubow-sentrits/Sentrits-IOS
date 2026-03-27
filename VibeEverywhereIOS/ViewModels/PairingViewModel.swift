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
    private let activityStore: ActivityLogStore
    private var pollingTask: Task<Void, Never>?
    private let pollIntervalNanoseconds: UInt64 = 2_000_000_000

    init(host: SavedHost, tokenStore: TokenStore, activityStore: ActivityLogStore) {
        self.host = host
        self.tokenStore = tokenStore
        self.activityStore = activityStore
    }

    func start() async {
        stopPolling()
        phase = .requesting

        do {
            let deviceName = UIDevice.current.name
            let client = HostClient(host: host)
            let response = try await client.startPairing(for: host, deviceName: deviceName)
            phase = .waiting(response)
            activityStore.record(
                category: .pairing,
                title: "Pairing requested",
                message: "Waiting for host approval using code \(response.code).",
                hostLabel: host.displayLabel
            )
            startPollingIfNeeded()
        } catch {
            phase = .failed(error.localizedDescription)
            activityStore.record(
                severity: .warning,
                category: .pairing,
                title: "Pairing request failed",
                message: error.localizedDescription,
                hostLabel: host.displayLabel
            )
        }
    }

    func retryPolling() {
        guard case let .waiting(response) = phase else { return }
        phase = .waiting(response)
        activityStore.record(
            category: .pairing,
            title: "Pairing polling resumed",
            message: "Retrying the pairing claim loop.",
            hostLabel: host.displayLabel
        )
        startPollingIfNeeded(forceRestart: true, response: response)
    }

    func cancel() {
        stopPolling()
        if case .requesting = phase {
            phase = .idle
            activityStore.record(
                severity: .warning,
                category: .pairing,
                title: "Pairing canceled",
                message: "Canceled before the host returned a pairing code.",
                hostLabel: host.displayLabel
            )
        } else if case .waiting = phase {
            activityStore.record(
                severity: .warning,
                category: .pairing,
                title: "Pairing canceled",
                message: "Stopped waiting for host approval.",
                hostLabel: host.displayLabel
            )
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
                        self.activityStore.record(
                            severity: .warning,
                            category: .pairing,
                            title: "Pairing claim interrupted",
                            message: error.localizedDescription,
                            hostLabel: host.displayLabel
                        )
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
                    activityStore.record(
                        category: .pairing,
                        title: "Pairing approved",
                        message: "Token saved for trusted host access.",
                        hostLabel: host.displayLabel
                    )
                } catch {
                    phase = .failed(error.localizedDescription)
                    activityStore.record(
                        severity: .error,
                        category: .pairing,
                        title: "Token save failed",
                        message: error.localizedDescription,
                        hostLabel: host.displayLabel
                    )
                }
            } else {
                phase = .failed("Pairing completed without a token.")
                activityStore.record(
                    severity: .error,
                    category: .pairing,
                    title: "Pairing completed without token",
                    message: "The host approved pairing but no token was returned.",
                    hostLabel: host.displayLabel
                )
            }
            stopPolling()
        case "pending":
            if case let .waiting(request) = phase {
                phase = .waiting(request)
            }
        case "rejected":
            phase = .rejected
            activityStore.record(
                severity: .warning,
                category: .pairing,
                title: "Pairing rejected",
                message: "The host rejected the pairing request.",
                hostLabel: host.displayLabel
            )
            stopPolling()
        case "expired":
            phase = .expired
            activityStore.record(
                severity: .warning,
                category: .pairing,
                title: "Pairing expired",
                message: "The pairing request expired before approval.",
                hostLabel: host.displayLabel
            )
            stopPolling()
        default:
            phase = .failed("Unexpected pairing status: \(response.status)")
            activityStore.record(
                severity: .error,
                category: .pairing,
                title: "Unexpected pairing status",
                message: response.status,
                hostLabel: host.displayLabel
            )
            stopPolling()
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}
