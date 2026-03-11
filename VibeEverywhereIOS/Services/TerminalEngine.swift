import Foundation

@MainActor
final class TerminalEngine: ObservableObject {
    @Published private(set) var renderedText = ""
    @Published private(set) var nextExpectedSequence = 0

    func reset() {
        renderedText = ""
        nextExpectedSequence = 0
    }

    func ingestBase64(_ dataBase64: String, seqEnd: Int) {
        guard let data = Data(base64Encoded: dataBase64) else { return }
        let cleaned = sanitizeTerminalOutput(data)
        renderedText.append(cleaned)
        nextExpectedSequence = seqEnd + 1
    }

    private func sanitizeTerminalOutput(_ data: Data) -> String {
        let text = String(decoding: data, as: UTF8.self)
        return stripANSI(from: text)
    }

    private func stripANSI(from string: String) -> String {
        let pattern = #"\u{001B}\[[0-9;?]*[ -/]*[@-~]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return string }
        let range = NSRange(location: 0, length: string.utf16.count)
        return regex.stringByReplacingMatches(in: string, options: [], range: range, withTemplate: "")
    }
}
