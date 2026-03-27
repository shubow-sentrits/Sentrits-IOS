import Foundation
import UIKit

@MainActor
final class PairingViewModel: ObservableObject {
    @Published private(set) var response: PairingRequestResponse?
    @Published var statusMessage: String?
    @Published var isBusy = false
    @Published private(set) var isWaitingForApproval = false
    @Published private(set) var retryableError: String?

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
        isBusy = true
        retryableError = nil
        defer { isBusy = false }

        do {
            let deviceName = UIDevice.current.name
            let client = HostClient(host: host)
            response = try await client.startPairing(for: host, deviceName: deviceName)
            isWaitingForApproval = true
            statusMessage = "Waiting for host approval."
            if let response {
                activityStore.record(
                    category: .pairing,
                    title: "Pairing requested",
                    message: "Waiting for approval using code \(response.code).",
                    host: host
                )
            }
            startPollingIfNeeded()
        } catch {
            isWaitingForApproval = false
            statusMessage = error.localizedDescription
            retryableError = error.localizedDescription
            activityStore.record(
                severity: .warning,
                category: .pairing,
                title: "Pairing request failed",
                message: error.localizedDescription,
                host: host
            )
        }
    }

    func retryPolling() {
        retryableError = nil
        statusMessage = "Waiting for host approval."
        isWaitingForApproval = true
        activityStore.record(
            category: .pairing,
            title: "Pairing polling resumed",
            message: "Retrying claim polling after an interruption.",
            host: host
        )
        startPollingIfNeeded(forceRestart: true)
    }

    func cancel() {
        stopPolling()
        isWaitingForApproval = false
        activityStore.record(
            severity: .warning,
            category: .pairing,
            title: "Pairing canceled",
            message: "Stopped waiting for host approval on this device.",
            host: host
        )
    }

    deinit {
        pollingTask?.cancel()
    }

    private func startPollingIfNeeded(forceRestart: Bool = false) {
        guard let response else { return }
        if forceRestart {
            stopPolling()
        } else if pollingTask != nil {
            return
        }

        pollingTask = Task { [host, tokenStore] in
            let client = HostClient(host: host)
            while !Task.isCancelled {
                do {
                    let claim = try await client.claimPairing(for: host, pairingId: response.pairingId, code: response.code)
                    try tokenStore.setToken(claim.token, for: host.tokenKey)
                    await MainActor.run {
                        self.isWaitingForApproval = false
                        self.retryableError = nil
                        self.statusMessage = "Pairing approved. Token saved."
                        self.activityStore.record(
                            category: .pairing,
                            title: "Pairing approved",
                            message: "Token saved and ready for session access.",
                            host: host
                        )
                        self.stopPolling()
                    }
                    return
                } catch APIError.pairingStillPending {
                    await MainActor.run {
                        self.isWaitingForApproval = true
                        self.retryableError = nil
                        self.statusMessage = "Waiting for host approval."
                    }
                } catch {
                    await MainActor.run {
                        self.isWaitingForApproval = false
                        self.retryableError = error.localizedDescription
                        self.statusMessage = "Pairing claim failed. Retry to continue waiting."
                        self.activityStore.record(
                            severity: .warning,
                            category: .pairing,
                            title: "Pairing claim interrupted",
                            message: error.localizedDescription,
                            host: host
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

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}
