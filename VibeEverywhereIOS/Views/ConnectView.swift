import SwiftUI

struct ConnectView: View {
    @ObservedObject var hostsStore: HostsStore
    let tokenStore: TokenStore
    @ObservedObject var activityStore: ActivityLogStore

    var body: some View {
        TabView {
            NavigationStack {
                PairingView(hostsStore: hostsStore, tokenStore: tokenStore, activityStore: activityStore)
            }
            .tabItem {
                Label("Pairing", systemImage: "dot.radiowaves.left.and.right")
            }

            NavigationStack {
                ShellPlaceholderView(
                    title: "Inventory",
                    subtitle: "Device-grouped sessions land here once the pairing foundation is in place."
                )
            }
            .tabItem {
                Label("Inventory", systemImage: "square.stack.3d.up")
            }

            NavigationStack {
                ShellPlaceholderView(
                    title: "Explorer",
                    subtitle: "Connected-session workspace remains intentionally untouched in this branch."
                )
            }
            .tabItem {
                Label("Explorer", systemImage: "rectangle.split.3x3")
            }

            NavigationStack {
                ActivityView(activityStore: activityStore)
            }
            .tabItem {
                Label("Activity", systemImage: "clock.arrow.circlepath")
            }
        }
        .tint(Color(red: 0.87, green: 0.69, blue: 0.44))
    }
}

private struct ShellPlaceholderView: View {
    let title: String
    let subtitle: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.09, blue: 0.11),
                    Color(red: 0.15, green: 0.12, blue: 0.10),
                    Color(red: 0.05, green: 0.06, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.system(size: 34, weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(Color.white.opacity(0.72))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
