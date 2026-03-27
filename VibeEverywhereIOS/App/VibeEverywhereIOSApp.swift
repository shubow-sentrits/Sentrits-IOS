import SwiftUI

@main
struct VibeEverywhereIOSApp: App {
    private let tokenStore: TokenStore
    @StateObject private var hostsStore: HostsStore
    @StateObject private var activityStore = ActivityLogStore()

    init() {
        let tokenStore = KeychainTokenStore()
        self.tokenStore = tokenStore
        _hostsStore = StateObject(wrappedValue: HostsStore(tokenStore: tokenStore))
    }

    var body: some Scene {
        WindowGroup {
            AppShellView(hostsStore: hostsStore, tokenStore: tokenStore, activityStore: activityStore)
                .preferredColorScheme(.dark)
        }
    }
}
