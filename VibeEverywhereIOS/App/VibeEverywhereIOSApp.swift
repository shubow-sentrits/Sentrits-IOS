import SwiftUI

@main
struct VibeEverywhereIOSApp: App {
    @StateObject private var hostsStore = SavedHostsStore()

    private let tokenStore: TokenStore = KeychainTokenStore()
    private let client = HostClient()

    var body: some Scene {
        WindowGroup {
            ConnectView(hostsStore: hostsStore, tokenStore: tokenStore, client: client)
        }
    }
}
