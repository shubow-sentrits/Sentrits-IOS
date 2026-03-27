import SwiftUI

@main
struct VibeEverywhereIOSApp: App {
    @StateObject private var hostsStore = SavedHostsStore()

    private let tokenStore: TokenStore = KeychainTokenStore()

    var body: some Scene {
        WindowGroup {
            ConnectView(hostsStore: hostsStore, tokenStore: tokenStore)
        }
    }
}
