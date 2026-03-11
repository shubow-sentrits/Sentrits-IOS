import SwiftUI

struct PairingView: View {
    let host: SavedHost
    let tokenStore: TokenStore
    let client: HostClient
    let onComplete: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PairingViewModel

    init(host: SavedHost, tokenStore: TokenStore, client: HostClient, onComplete: @escaping (String) -> Void) {
        self.host = host
        self.tokenStore = tokenStore
        self.client = client
        self.onComplete = onComplete
        _viewModel = StateObject(wrappedValue: PairingViewModel(host: host, client: client, tokenStore: tokenStore))
    }

    var body: some View {
        Form {
            Section("Host") {
                Text(host.displayLabel)
            }

            Section("Pairing Request") {
                if let response = viewModel.response {
                    LabeledContent("Pairing ID", value: response.pairingId)
                    LabeledContent("Code", value: response.code)
                    LabeledContent("Status", value: response.status)
                    Text("Approve this pairing in the host admin UI at http://127.0.0.1:18085, then paste the returned bearer token below.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Start Pairing Request") {
                        Task { await viewModel.start() }
                    }
                    .disabled(viewModel.isBusy)
                }
            }

            if viewModel.response != nil {
                Section("Approved Token") {
                    TextField("Bearer token", text: $viewModel.manualToken, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Validate and Save Token") {
                        Task {
                            let saved = await viewModel.saveToken()
                            if saved {
                                onComplete(viewModel.manualToken.trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                        }
                    }
                    .disabled(viewModel.isBusy)
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close") { dismiss() }
            }
        }
    }
}
