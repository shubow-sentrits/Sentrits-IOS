import SwiftUI

struct SessionsView: View {
    let host: SavedHost
    let token: String
    let onConnected: () -> Void
    @ObservedObject var activityStore: ActivityLogStore

    @StateObject private var viewModel: SessionsViewModel

    init(host: SavedHost, token: String, onConnected: @escaping () -> Void, activityStore: ActivityLogStore) {
        self.host = host
        self.token = token
        self.onConnected = onConnected
        self.activityStore = activityStore
        _viewModel = StateObject(wrappedValue: SessionsViewModel(host: host, token: token, activityStore: activityStore))
    }

    var body: some View {
        List {
            if let info = viewModel.hostInfo {
                Section("Host") {
                    LabeledContent("Display Name", value: info.displayName)
                    LabeledContent("Version", value: info.version ?? "Unknown")
                }
            }

            Section("Sessions") {
                if viewModel.sessions.isEmpty, !viewModel.isLoading {
                    Text("No sessions returned.")
                        .foregroundStyle(.secondary)
                }

                ForEach(viewModel.sessions) { session in
                    NavigationLink(value: session) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(session.title.isEmpty ? session.sessionId : session.title)
                                .font(.headline)
                            Text(session.workspaceRoot)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                Text(session.provider)
                                Text(session.status)
                                Text("controller: \(session.controllerKind)")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Section("Error") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Sessions")
        .scrollContentBackground(.hidden)
        .background(ActivityPalette.background.ignoresSafeArea())
        .navigationDestination(for: SessionSummary.self) { session in
            SessionDetailView(host: host, token: token, session: session, activityStore: activityStore)
        }
        .task {
            onConnected()
            await viewModel.refresh()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.isLoading {
                    ProgressView()
                }
            }
        }
    }
}
