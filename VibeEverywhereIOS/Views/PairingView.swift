import SwiftUI

struct PairingView: View {
    let host: SavedHost
    let tokenStore: TokenStore
    @ObservedObject var activityStore: ActivityLogStore
    let onComplete: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PairingViewModel

    init(host: SavedHost, tokenStore: TokenStore, activityStore: ActivityLogStore, onComplete: @escaping (String) -> Void) {
        self.host = host
        self.tokenStore = tokenStore
        self.activityStore = activityStore
        self.onComplete = onComplete
        _viewModel = StateObject(wrappedValue: PairingViewModel(host: host, tokenStore: tokenStore, activityStore: activityStore))
    }

    var body: some View {
        Form {
            Section("Host") {
                Text(host.displayLabel)
                Text(host.useTLS ? "HTTPS/WSS" : "HTTP/WS")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Pairing Request") {
                if let response = viewModel.response {
                    LabeledContent("Pairing ID", value: response.pairingId)
                    LabeledContent("Code", value: response.code)
                    LabeledContent("Status", value: response.status)
                    Text("Approve this pairing in the host admin UI. The app will claim the token automatically once approval completes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Start Pairing Request") {
                        Task { await viewModel.start() }
                    }
                    .disabled(viewModel.isBusy)
                }
            }

            if viewModel.isWaitingForApproval {
                Section("Approval") {
                    HStack {
                        ProgressView()
                        Text("Waiting for host approval")
                    }
                    .foregroundStyle(.secondary)
                }
            }

            if let retryableError = viewModel.retryableError {
                Section("Retry") {
                    Text(retryableError)
                        .foregroundStyle(.red)
                    Button("Retry Claim Polling") {
                        viewModel.retryPolling()
                    }
                }
            }

            if let statusMessage = viewModel.statusMessage {
                Section("Status") {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Pair Host")
        .scrollContentBackground(.hidden)
        .background(ActivityPalette.background.ignoresSafeArea())
        .onChange(of: viewModel.statusMessage) {
            guard viewModel.statusMessage == "Pairing approved. Token saved.",
                  let hostToken = tokenStore.token(for: host.tokenKey) else {
                return
            }
            onComplete(hostToken)
        }
        .onDisappear {
            viewModel.cancel()
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if viewModel.isWaitingForApproval {
                    Button("Cancel") {
                        viewModel.cancel()
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close") {
                    viewModel.cancel()
                    dismiss()
                }
            }
        }
    }
}
