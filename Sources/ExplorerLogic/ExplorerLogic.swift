import Foundation

public struct ExplorerSessionState: Equatable, Sendable {
    public let id: String
    public let tags: [String]
    public let isEligible: Bool

    public init(id: String, tags: [String], isEligible: Bool) {
        self.id = id
        self.tags = tags
        self.isEligible = isEligible
    }
}

public enum ExplorerRouteLite: Hashable, Sendable {
    case focusedSession(String)
}

public enum ExplorerLogic {
    public static func normalizeGroupTag(_ rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    public static func groupTabs(localTabs: [String], sessions: [ExplorerSessionState]) -> [String] {
        let tags = sessions
            .filter(\.isEligible)
            .flatMap(\.tags)
            .map(normalizeGroupTag)
            .filter { !$0.isEmpty }
        let merged = Array(Set(localTabs.map(normalizeGroupTag) + tags)).sorted()
        return ["all"] + merged
    }

    public static func filteredSessionIDs(
        selectedGroupTag: String,
        sessions: [ExplorerSessionState],
        hiddenSessionIDs: Set<String>
    ) -> [String] {
        let selected = normalizeGroupTag(selectedGroupTag)
        return sessions
            .filter(\.isEligible)
            .filter { !hiddenSessionIDs.contains($0.id) }
            .filter { selected == "all" || $0.tags.map(normalizeGroupTag).contains(selected) }
            .map(\.id)
    }

    public static func sessionID(for route: ExplorerRouteLite, availableSessionIDs: [String]) -> String? {
        switch route {
        case let .focusedSession(sessionID):
            return availableSessionIDs.contains(sessionID) ? sessionID : nil
        }
    }
}
