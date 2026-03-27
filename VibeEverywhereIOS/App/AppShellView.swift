import SwiftUI

struct AppShellView: View {
    @ObservedObject var hostsStore: HostsStore
    let tokenStore: TokenStore
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                PairingView(hostsStore: hostsStore, tokenStore: tokenStore)
            }
            .tag(0)
            .tabItem {
                Label("Pairing", systemImage: "dot.radiowaves.left.and.right")
            }

            NavigationStack {
                InventoryView(hostsStore: hostsStore, tokenStore: tokenStore)
            }
                .tag(1)
                .tabItem {
                    Label("Inventory", systemImage: "square.stack.3d.up.fill")
                }

            PlaceholderTabView(
                title: "Explorer",
                message: "Connected session grouping lands here next. Inventory can already open focused sessions."
            )
            .tag(2)
            .tabItem {
                Label("Explorer", systemImage: "safari.fill")
            }

            PlaceholderTabView(
                title: "Activity",
                message: "Activity logging is not implemented in this branch yet."
            )
            .tag(3)
            .tabItem {
                Label("Activity", systemImage: "waveform.path.ecg")
            }
        }
        .tint(Color(red: 0.74, green: 0.81, blue: 0.54))
    }
}

private struct PlaceholderTabView: View {
    let title: String
    let message: String

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.06, blue: 0.07),
                        Color(red: 0.09, green: 0.11, blue: 0.13)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 14) {
                    Text(title)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.88, green: 0.90, blue: 0.93))
                    Text(message)
                        .font(.body)
                        .foregroundStyle(Color.white.opacity(0.72))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .navigationTitle(title)
        }
    }
}
