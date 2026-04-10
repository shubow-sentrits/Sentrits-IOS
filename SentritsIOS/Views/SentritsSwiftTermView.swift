import SwiftTerm
import UIKit

final class SentritsSwiftTermView: TerminalView {
    private var preservedTopVisibleRow: Int?
    private var userDetachedFromLiveBottom = false
    private let liveBottomThresholdRows = 1

    private var terminalRowCount: Int {
        max(getTerminal().rows, 1)
    }

    private var rowHeight: CGFloat {
        let height = bounds.height
        if height <= 0 {
            return 0
        }
        return height / CGFloat(terminalRowCount)
    }

    private var currentTopVisibleRow: Int {
        let lineHeight = rowHeight
        guard lineHeight > 0 else { return 0 }
        return max(0, Int(round(contentOffset.y / lineHeight)))
    }

    private var maximumTopVisibleRow: Int {
        let lineHeight = rowHeight
        guard lineHeight > 0 else { return 0 }
        let totalRows = max(Int(round(contentSize.height / lineHeight)), terminalRowCount)
        return max(0, totalRows - terminalRowCount)
    }

    private var isNearLiveBottom: Bool {
        maximumTopVisibleRow - currentTopVisibleRow <= liveBottomThresholdRows
    }

    @MainActor
    private func refreshLiveBottomState() {
        userDetachedFromLiveBottom = !isNearLiveBottom
    }

    @MainActor
    func beginProgrammaticUpdatePreservingViewportIfNeeded() {
        refreshLiveBottomState()
        preservedTopVisibleRow = userDetachedFromLiveBottom ? currentTopVisibleRow : nil
    }

    @MainActor
    func endProgrammaticUpdatePreservingViewportIfNeeded() {
        let lineHeight = rowHeight
        guard lineHeight > 0 else {
            preservedTopVisibleRow = nil
            refreshLiveBottomState()
            return
        }

        if let preservedTopVisibleRow {
            let desiredTop = min(max(preservedTopVisibleRow, 0), maximumTopVisibleRow)
            let desiredOffsetY = CGFloat(desiredTop) * lineHeight
            if abs(contentOffset.y - desiredOffsetY) > 0.5 {
                contentOffset = CGPoint(x: contentOffset.x, y: desiredOffsetY)
            }
        }
        preservedTopVisibleRow = nil
        refreshLiveBottomState()
    }

    override func sizeChanged(source: Terminal) {
        beginProgrammaticUpdatePreservingViewportIfNeeded()
        super.sizeChanged(source: source)
        DispatchQueue.main.async { [weak self] in
            self?.endProgrammaticUpdatePreservingViewportIfNeeded()
        }
    }

    override func scrolled(source terminal: Terminal, yDisp: Int) {
        super.scrolled(source: terminal, yDisp: yDisp)
        refreshLiveBottomState()
    }

    override func showCursor(source: Terminal) {
        super.showCursor(source: source)
        refreshLiveBottomState()
    }
}
