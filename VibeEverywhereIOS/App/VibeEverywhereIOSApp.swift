import SwiftUI

@main
struct VibeEverywhereIOSApp: App {
    private let tokenStore: TokenStore
    @StateObject private var hostsStore: HostsStore

    init() {
        let tokenStore = KeychainTokenStore()
        self.tokenStore = tokenStore
        _hostsStore = StateObject(wrappedValue: HostsStore(tokenStore: tokenStore))
    }

    var body: some Scene {
        WindowGroup {
            AppShellView(hostsStore: hostsStore, tokenStore: tokenStore)
                .preferredColorScheme(.dark)
        }
    }
}
