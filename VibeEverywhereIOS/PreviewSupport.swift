import Foundation
import SwiftUI

final class PreviewTokenStore: TokenStore {
    private var tokens: [String: String]

    init(tokens: [String: String] = [:]) {
        self.tokens = tokens
    }

    func token(for hostKey: String) -> String? {
        tokens[hostKey]
    }

    func setToken(_ token: String, for hostKey: String) throws {
        tokens[hostKey] = token
    }

    func removeToken(for hostKey: String) throws {
        tokens.removeValue(forKey: hostKey)
    }
}

enum PreviewFixtures {
    static let hostA = SavedHost(
        hostId: "host_alpha",
        displayName: "Studio Mac",
        alias: "Desk",
        address: "192.168.68.57",
        port: 18086,
        useTLS: false,
        lastConnectedAt: Date()
    )

    static let hostB = SavedHost(
        hostId: "host_beta",
        displayName: "Workshop Linux",
        alias: "Lab",
        address: "192.168.68.91",
        port: 18086,
        useTLS: false,
        lastConnectedAt: Date().addingTimeInterval(-320)
    )

    static let hostInfoA = HostInfo(
        hostId: "host_alpha",
        displayName: "Studio Mac",
        adminHost: "127.0.0.1",
        adminPort: 18085,
        remoteHost: "192.168.68.57",
        remotePort: 18086,
        version: "0.1.0-alpha",
        capabilities: ["pairing", "sessions", "groups", "terminal"],
        pairingMode: "approval",
        tls: HostTLSInfo(enabled: false, mode: nil)
    )

    static let discoveryA = DiscoveryInfo(
        hostId: "host_alpha",
        displayName: "Studio Mac",
        remoteHost: "192.168.68.57",
        remotePort: 18086,
        protocolVersion: "v1",
        tls: false
    )

    static let sessionA = SessionSummary(
        sessionId: "s_12",
        provider: "codex",
        workspaceRoot: "/Users/shubow/dev/VibeEverywhere",
        title: "host-runtime",
        status: "Running",
        conversationId: nil,
        groupTags: ["review", "runtime"],
        controllerKind: "remote",
        controllerClientId: "ios_preview",
        isRecovered: false,
        archivedRecord: false,
        isActive: true,
        inventoryState: "Live",
        activityState: "active",
        supervisionState: "Running",
        attentionState: "info",
        attentionReason: "workspace_changed",
        createdAtUnixMs: 1_744_000_000_000,
        lastStatusAtUnixMs: 1_744_000_060_000,
        lastOutputAtUnixMs: 1_744_000_070_000,
        lastActivityAtUnixMs: 1_744_000_072_000,
        lastFileChangeAtUnixMs: 1_744_000_071_000,
        lastGitChangeAtUnixMs: 1_744_000_071_000,
        lastControllerChangeAtUnixMs: 1_744_000_069_000,
        attentionSinceUnixMs: 1_744_000_071_000,
        currentSequence: 240,
        attachedClientCount: 1,
        recentFileChangeCount: 3,
        gitDirty: true,
        gitBranch: "main",
        gitModifiedCount: 3,
        gitStagedCount: 1,
        gitUntrackedCount: 0
    )

    static let sessionB = SessionSummary(
        sessionId: "s_18",
        provider: "claude",
        workspaceRoot: "/Users/shubow/dev/AnotherProject",
        title: "api-pass",
        status: "AwaitingInput",
        conversationId: "conv_abc123",
        groupTags: ["mobile"],
        controllerKind: "host",
        controllerClientId: nil,
        isRecovered: false,
        archivedRecord: false,
        isActive: true,
        inventoryState: "Live",
        activityState: "idle",
        supervisionState: "AwaitingInput",
        attentionState: "action_required",
        attentionReason: "awaiting_input",
        createdAtUnixMs: 1_744_000_100_000,
        lastStatusAtUnixMs: 1_744_000_160_000,
        lastOutputAtUnixMs: 1_744_000_161_000,
        lastActivityAtUnixMs: 1_744_000_161_000,
        lastFileChangeAtUnixMs: 1_744_000_130_000,
        lastGitChangeAtUnixMs: 1_744_000_130_000,
        lastControllerChangeAtUnixMs: 1_744_000_120_000,
        attentionSinceUnixMs: 1_744_000_161_000,
        currentSequence: 88,
        attachedClientCount: 0,
        recentFileChangeCount: 0,
        gitDirty: false,
        gitBranch: "feature/mobile",
        gitModifiedCount: 0,
        gitStagedCount: 0,
        gitUntrackedCount: 0
    )

    static let snapshot = SessionSnapshot(
        sessionId: sessionA.sessionId,
        provider: sessionA.provider,
        workspaceRoot: sessionA.workspaceRoot,
        title: sessionA.title,
        status: sessionA.status,
        conversationId: sessionA.conversationId,
        groupTags: sessionA.groupTags,
        currentSequence: sessionA.currentSequence,
        recentTerminalTail: "$ ninja -C build\n[1/4] Building runtime\n[2/4] Linking vibe-hostd\nReady for smoke\n",
        recentFileChanges: [
            "src/net/http_shared.cpp",
            "web/remote_client/app.js",
            "development_memo/ios_client_rebuild_plan.md"
        ],
        signals: SessionSnapshotSignals(
            lastOutputAtUnixMs: sessionA.lastOutputAtUnixMs,
            lastActivityAtUnixMs: sessionA.lastActivityAtUnixMs,
            lastFileChangeAtUnixMs: sessionA.lastFileChangeAtUnixMs,
            lastGitChangeAtUnixMs: sessionA.lastGitChangeAtUnixMs,
            lastControllerChangeAtUnixMs: sessionA.lastControllerChangeAtUnixMs,
            attentionSinceUnixMs: sessionA.attentionSinceUnixMs,
            currentSequence: sessionA.currentSequence,
            recentFileChangeCount: sessionA.recentFileChangeCount,
            supervisionState: sessionA.supervisionState,
            attentionState: sessionA.attentionState,
            attentionReason: sessionA.attentionReason,
            gitDirty: sessionA.gitDirty,
            gitBranch: sessionA.gitBranch,
            gitModifiedCount: sessionA.gitModifiedCount,
            gitStagedCount: sessionA.gitStagedCount,
            gitUntrackedCount: sessionA.gitUntrackedCount
        ),
        git: SessionSnapshotGit(
            branch: sessionA.gitBranch,
            modifiedCount: sessionA.gitModifiedCount,
            stagedCount: sessionA.gitStagedCount,
            untrackedCount: sessionA.gitUntrackedCount,
            modifiedFiles: ["src/net/http_shared.cpp"],
            stagedFiles: ["web/remote_client/app.js"],
            untrackedFiles: []
        )
    )

    static let activitySeed: [ActivityEvent] = [
        ActivityEvent(severity: .info, category: .pairing, title: "Pairing approved", message: "Token saved for trusted host access.", hostLabel: hostA.displayLabel),
        ActivityEvent(severity: .info, category: .explorer, title: "Session added to explorer", message: "Connected session preview opened in Explorer.", hostLabel: hostA.displayLabel, sessionID: sessionA.sessionId),
        ActivityEvent(severity: .warning, category: .control, title: "Awaiting input", message: "Session is waiting on a confirmation.", hostLabel: hostB.displayLabel, sessionID: sessionB.sessionId)
    ]
}

extension PreviewFixtures {
    static let discoveredHostA = DiscoveredHost(
        identity: discoveryA,
        endpoint: HostEndpoint(address: hostA.address, port: hostA.port, useTLS: false),
        announcedAddress: hostA.address,
        lastSeenAt: Date()
    )

    static let discoveredHostB = DiscoveredHost(
        identity: DiscoveryInfo(
            hostId: hostB.hostId ?? "host_beta",
            displayName: hostB.displayName,
            remoteHost: hostB.address,
            remotePort: hostB.port,
            protocolVersion: "v1",
            tls: false
        ),
        endpoint: HostEndpoint(address: hostB.address, port: hostB.port, useTLS: false),
        announcedAddress: hostB.address,
        lastSeenAt: Date().addingTimeInterval(-5)
    )
}

@MainActor
struct PreviewAppContext {
    let tokenStore: PreviewTokenStore
    let hostsStore: HostsStore
    let activityStore: ActivityLogStore
    let inventoryStore: InventoryStore
    let explorerStore: ExplorerWorkspaceStore
    let focusedSessionViewModel: SessionViewModel

    static func make() -> PreviewAppContext {
        let tokenStore = PreviewTokenStore(tokens: [
            PreviewFixtures.hostA.tokenKey: "preview-token-alpha",
            PreviewFixtures.hostB.tokenKey: "preview-token-beta"
        ])
        let hostsStore = HostsStore.previewStore(tokenStore: tokenStore)
        let activityStore = ActivityLogStore(seed: PreviewFixtures.activitySeed)
        let inventoryStore = InventoryStore.previewStore(hostsStore: hostsStore, tokenStore: tokenStore)
        let explorerStore = ExplorerWorkspaceStore.previewStore(hostsStore: hostsStore, tokenStore: tokenStore, activityStore: activityStore)
        let focusedSessionViewModel = explorerStore.sessions.first ?? SessionViewModel(host: PreviewFixtures.hostA, token: "preview-token-alpha", session: PreviewFixtures.sessionA, activityStore: activityStore)
        if focusedSessionViewModel.snapshot == nil {
            focusedSessionViewModel.snapshot = PreviewFixtures.snapshot
            focusedSessionViewModel.socketState = .connected
            focusedSessionViewModel.controllerState = .connected
            if let tail = PreviewFixtures.snapshot.recentTerminalTail {
                focusedSessionViewModel.terminal.ingestBase64(tail.data(using: .utf8)!.base64EncodedString(), seqStart: 0, seqEnd: 0)
            }
        }
        return PreviewAppContext(
            tokenStore: tokenStore,
            hostsStore: hostsStore,
            activityStore: activityStore,
            inventoryStore: inventoryStore,
            explorerStore: explorerStore,
            focusedSessionViewModel: focusedSessionViewModel
        )
    }
}
