import Foundation

@MainActor
final class TerminalEngine: ObservableObject {
    @Published private(set) var outputChunksBase64: [String] = []
    @Published private(set) var nextExpectedSequence = 0
    @Published private(set) var resetVersion = 0

    private var pendingChunks: [Int: TerminalChunk] = [:]

    var hasContent: Bool {
        !outputChunksBase64.isEmpty
    }

    var renderedText: String {
        outputChunksBase64.compactMap { chunk in
            guard let data = Data(base64Encoded: chunk) else { return nil }
            return String(decoding: data, as: UTF8.self)
        }.joined()
    }

    func reset() {
        outputChunksBase64 = []
        nextExpectedSequence = 0
        pendingChunks.removeAll()
        resetVersion &+= 1
    }

    func ingestBase64(_ dataBase64: String, seqStart: Int, seqEnd: Int) {
        guard seqEnd >= seqStart else { return }
        guard Data(base64Encoded: dataBase64) != nil else { return }

        if outputChunksBase64.isEmpty, pendingChunks.isEmpty, nextExpectedSequence == 0 {
            nextExpectedSequence = seqStart
        }

        guard seqEnd >= nextExpectedSequence else { return }

        let chunk = TerminalChunk(seqStart: seqStart, seqEnd: seqEnd, dataBase64: dataBase64)
        if let existing = pendingChunks[seqStart], existing.seqEnd >= seqEnd {
            return
        }

        pendingChunks[seqStart] = chunk
        flushPendingChunksIfPossible()
    }

    func ingestBase64(_ dataBase64: String, seqEnd: Int) {
        ingestBase64(dataBase64, seqStart: seqEnd, seqEnd: seqEnd)
    }

    private func flushPendingChunksIfPossible() {
        if outputChunksBase64.isEmpty, nextExpectedSequence == 0, let firstSequence = pendingChunks.keys.min() {
            nextExpectedSequence = firstSequence
        }

        while let chunk = pendingChunks[nextExpectedSequence] {
            outputChunksBase64.append(chunk.dataBase64)
            pendingChunks.removeValue(forKey: nextExpectedSequence)
            nextExpectedSequence = chunk.seqEnd + 1
        }
    }
}

private struct TerminalChunk {
    let seqStart: Int
    let seqEnd: Int
    let dataBase64: String
}
