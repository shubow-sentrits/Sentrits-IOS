import SwiftUI

struct ConnectView: View {
    @ObservedObject var hostsStore: SavedHostsStore
    let tokenStore: TokenStore
    let client: HostClient

    @StateObject private var viewModel: ConnectViewModel
    @State private var pairingHost: SavedHost?
    @State private var sessionsHost: SavedHost?
    @State private var sessionsToken: String?

    init(hostsStore: SavedHostsStore, tokenStore: TokenStore, client: HostClient) {
        self.hostsStore = hostsStore
        self.tokenStore = tokenStore
        self.client = client
        _viewModel = StateObject(wrappedValue: ConnectViewModel(client: client))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Host") {
                    TextField("Name", text: $viewModel.hostName)
                    TextField("IP or hostname", text: $viewModel.hostAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Port", text: $viewModel.port)
                        .keyboardType(.numberPad)
                }

                Section {
                    Button("Check Reachability") {
                        guard let host = viewModel.makeHost() else {
                            viewModel.statusMessage = "Enter a valid host and port."
                            return
                        }
                        Task { await viewModel.check(host: host) }
                    }
                    .disabled(viewModel.isBusy)

                    Button("Start Pairing") {
                        guard let host = viewModel.makeHost() else {
                            viewModel.statusMessage = "Enter a valid host and port."
                            return
                        }
                        hostsStore.upsert(host)
                        pairingHost = host
                    }
                    .disabled(viewModel.isBusy)

                    Button("Open Sessions") {
                        guard let host = viewModel.makeHost() else {
                            viewModel.statusMessage = "Enter a valid host and port."
                            return
                        }
                        guard let token = tokenStore.token(for: host.tokenKey) else {
                            viewModel.statusMessage = "No saved token for this host. Pair first."
                            return
                        }
                        hostsStore.upsert(host)
                        sessionsToken = token
                        sessionsHost = host
                    }
                    .disabled(viewModel.isBusy)
                }

                if let info = viewModel.hostInfo {
                    Section("Host Info") {
                        LabeledContent("Display Name", value: info.displayName)
                        LabeledContent("Host ID", value: info.hostId ?? "Unknown")
                        LabeledContent("Version", value: info.version ?? "Unknown")
                        LabeledContent("Pairing", value: info.pairingMode ?? "Unknown")
                    }
                }

                if let statusMessage = viewModel.statusMessage {
                    Section("Status") {
                        Text(statusMessage)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Saved Hosts") {
                    if hostsStore.hosts.isEmpty {
                        Text("No saved hosts yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(hostsStore.hosts) { host in
                            VStack(alignment: .leading, spacing: 6) {
                                Button(host.displayLabel) {
                                    viewModel.populate(from: host)
                                }
                                .buttonStyle(.plain)

                                HStack {
                                    if tokenStore.token(for: host.tokenKey) != nil {
                                        Text("Token saved")
                                    } else {
                                        Text("No token")
                                    }
                                    if let lastConnectedAt = host.lastConnectedAt {
                                        Text(lastConnectedAt.formatted(date: .abbreviated, time: .shortened))
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .onDelete(perform: hostsStore.remove)
                    }
                }
            }
            .navigationTitle("VibeEverywhere")
            .sheet(item: $pairingHost) { host in
                NavigationStack {
                    PairingView(
                        host: host,
                        tokenStore: tokenStore,
                        client: client,
                        onComplete: { token in
                            hostsStore.upsert(host)
                            sessionsToken = token
                            sessionsHost = host
                            pairingHost = nil
                        }
                    )
                }
            }
            .navigationDestination(item: $sessionsHost) { host in
                if let token = sessionsToken {
                    SessionsView(
                        host: host,
                        token: token,
                        client: client,
                        onConnected: { hostsStore.touch(hostID: host.id) }
                    )
                }
            }
        }
    }
}
