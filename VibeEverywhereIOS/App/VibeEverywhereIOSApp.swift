import SwiftUI

@main
struct VibeEverywhereIOSApp: App {
    @StateObject private var hostsStore = SavedHostsStore()

    private let tokenStore: TokenStore = KeychainTokenStore()

    var body: some Scene {
        WindowGroup {
            AppShellView(hostsStore: hostsStore, tokenStore: tokenStore)
        }
    }
}
