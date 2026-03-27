import SwiftUI

struct AppShellView: View {
    @ObservedObject var hostsStore: HostsStore
    let tokenStore: TokenStore
    @ObservedObject var activityStore: ActivityLogStore

    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                PairingView(hostsStore: hostsStore, tokenStore: tokenStore, activityStore: activityStore)
            }
            .tag(0)
            .tabItem {
                Label("Pairing", systemImage: "dot.radiowaves.left.and.right")
            }

            NavigationStack {
                InventoryView(hostsStore: hostsStore, tokenStore: tokenStore, activityStore: activityStore)
            }
            .tag(1)
            .tabItem {
                Label("Inventory", systemImage: "square.stack.3d.up.fill")
            }

            NavigationStack {
                ExplorerHostAccessView(hostsStore: hostsStore, tokenStore: tokenStore, activityStore: activityStore)
            }
            .tag(2)
            .tabItem {
                Label("Explorer", systemImage: "rectangle.3.group")
            }

            NavigationStack {
                ActivityView(activityStore: activityStore)
            }
            .tag(3)
            .tabItem {
                Label("Activity", systemImage: "clock.arrow.circlepath")
            }
        }
        .tint(ActivityPalette.primary)
    }
}

private struct ExplorerHostAccessView: View {
    @ObservedObject var hostsStore: HostsStore
    let tokenStore: TokenStore
    @ObservedObject var activityStore: ActivityLogStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connected Work")
                        .font(.system(.footnote, design: .monospaced).weight(.medium))
                        .foregroundStyle(ActivityPalette.secondary)
                        .textCase(.uppercase)
                    Text("Explorer")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(ActivityPalette.foreground)
                    Text("Open a paired host and move into the grouped live-session workspace.")
                        .foregroundStyle(ActivityPalette.muted)
                }

                if hostsStore.savedHosts.isEmpty {
                    Text("No saved hosts yet. Pair a host first.")
                        .foregroundStyle(ActivityPalette.muted)
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(ActivityPalette.surfaceLow, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                } else {
                    VStack(spacing: 14) {
                        ForEach(hostsStore.savedHosts) { host in
                            ExplorerHostCard(host: host, token: tokenStore.token(for: host.tokenKey), activityStore: activityStore)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(ActivityPalette.background.ignoresSafeArea())
        .navigationTitle("Explorer")
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct ExplorerHostCard: View {
    let host: SavedHost
    let token: String?
    @ObservedObject var activityStore: ActivityLogStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(host.displayLabel)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(ActivityPalette.foreground)

            HStack(spacing: 8) {
                ActivityTag(text: token == nil ? "Needs Pairing" : "Token Ready", tint: token == nil ? ActivityPalette.warning : ActivityPalette.primary)
                if let lastConnectedAt = host.lastConnectedAt {
                    ActivityTag(text: lastConnectedAt.formatted(date: .abbreviated, time: .shortened), tint: ActivityPalette.muted)
                }
            }

            if let token {
                NavigationLink {
                    SessionsView(
                        host: host,
                        token: token,
                        onConnected: {},
                        activityStore: activityStore
                    )
                } label: {
                    Text("Open Sessions")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(Color.black.opacity(0.78))
                        .background(
                            LinearGradient(
                                colors: [ActivityPalette.primary, ActivityPalette.primary.opacity(0.72)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                }
                .simultaneousGesture(TapGesture().onEnded {
                    activityStore.record(
                        category: .explorer,
                        title: "Opened host sessions",
                        message: "Entered the explorer session list from the app shell.",
                        host: host
                    )
                })
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ActivityPalette.surfaceLow, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
