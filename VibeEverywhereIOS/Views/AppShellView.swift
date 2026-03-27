import SwiftUI

struct AppShellView: View {
    @ObservedObject var hostsStore: SavedHostsStore
    let tokenStore: TokenStore
    @ObservedObject var activityStore: ActivityLogStore

    var body: some View {
        TabView {
            NavigationStack {
                ConnectView(hostsStore: hostsStore, tokenStore: tokenStore, activityStore: activityStore)
                    .background(ActivityPalette.background.ignoresSafeArea())
            }
            .tabItem {
                Label("Pairing", systemImage: "dot.radiowaves.left.and.right")
            }

            NavigationStack {
                HostAccessView(
                    title: "Inventory",
                    eyebrow: "Saved Devices",
                    description: "Open the current host inventory without rebuilding the inventory track in this branch.",
                    hostsStore: hostsStore,
                    tokenStore: tokenStore,
                    activityStore: activityStore
                )
            }
            .tabItem {
                Label("Inventory", systemImage: "square.stack.3d.up")
            }

            NavigationStack {
                HostAccessView(
                    title: "Explorer",
                    eyebrow: "Connected Work",
                    description: "Resume into host sessions and focused terminal views from the same shared session flow.",
                    hostsStore: hostsStore,
                    tokenStore: tokenStore,
                    activityStore: activityStore
                )
            }
            .tabItem {
                Label("Explorer", systemImage: "rectangle.3.group")
            }

            NavigationStack {
                ActivityView(activityStore: activityStore)
            }
            .tabItem {
                Label("Activity", systemImage: "clock.arrow.circlepath")
            }
        }
        .tint(ActivityPalette.primary)
    }
}

private struct HostAccessView: View {
    let title: String
    let eyebrow: String
    let description: String
    @ObservedObject var hostsStore: SavedHostsStore
    let tokenStore: TokenStore
    @ObservedObject var activityStore: ActivityLogStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(eyebrow)
                        .font(.system(.footnote, design: .monospaced).weight(.medium))
                        .foregroundStyle(ActivityPalette.secondary)
                        .textCase(.uppercase)
                    Text(title)
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(ActivityPalette.foreground)
                    Text(description)
                        .foregroundStyle(ActivityPalette.muted)
                }

                if hostsStore.hosts.isEmpty {
                    Text("No saved hosts yet. Pair a host first.")
                        .foregroundStyle(ActivityPalette.muted)
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(ActivityPalette.surfaceLow, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                } else {
                    VStack(spacing: 14) {
                        ForEach(hostsStore.hosts) { host in
                            HostAccessCard(host: host, token: tokenStore.token(for: host.tokenKey), activityStore: activityStore)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(ActivityPalette.background.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct HostAccessCard: View {
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
                    SessionsView(host: host, token: token, onConnected: {}, activityStore: activityStore)
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
                        message: "Entered the session list from the app shell.",
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
