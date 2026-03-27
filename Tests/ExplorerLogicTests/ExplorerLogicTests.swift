import Testing
@testable import ExplorerLogic

@Test("group tabs normalize, dedupe, and keep all first")
func groupTabsAreNormalized() {
    let sessions = [
        ExplorerSessionState(id: "one", tags: [" Ops ", "frontend"], isEligible: true),
        ExplorerSessionState(id: "two", tags: ["frontend", "release"], isEligible: true),
        ExplorerSessionState(id: "three", tags: ["ignored"], isEligible: false)
    ]

    #expect(
        ExplorerLogic.groupTabs(localTabs: ["Alpha ", "ops"], sessions: sessions) ==
        ["all", "alpha", "frontend", "ops", "release"]
    )
}

@Test("filtering respects selected group and hidden sessions")
func filtersConnectedSessions() {
    let sessions = [
        ExplorerSessionState(id: "one", tags: ["ops"], isEligible: true),
        ExplorerSessionState(id: "two", tags: ["frontend", "ops"], isEligible: true),
        ExplorerSessionState(id: "three", tags: ["frontend"], isEligible: true)
    ]

    #expect(
        ExplorerLogic.filteredSessionIDs(
            selectedGroupTag: "ops",
            sessions: sessions,
            hiddenSessionIDs: ["two"]
        ) == ["one"]
    )
}

@Test("focused route only resolves existing sessions")
func focusedRouteResolution() {
    #expect(
        ExplorerLogic.sessionID(
            for: .focusedSession("live-2"),
            availableSessionIDs: ["live-1", "live-2"]
        ) == "live-2"
    )

    #expect(
        ExplorerLogic.sessionID(
            for: .focusedSession("missing"),
            availableSessionIDs: ["live-1", "live-2"]
        ) == nil
    )
}
