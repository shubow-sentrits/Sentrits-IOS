import SwiftTerm
import UIKit

final class SentritsSwiftTermView: TerminalView {
    private var preservedTopVisibleRow: Int?

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

    @MainActor
    func preserveViewportAnchor() {
        preservedTopVisibleRow = currentTopVisibleRow
    }

    @MainActor
    func restoreViewportAfterTerminalUpdate() {
        let lineHeight = rowHeight
        guard lineHeight > 0 else {
            preservedTopVisibleRow = nil
            return
        }

        let terminal = getTerminal()
        let cursor = terminal.getCursorLocation()
        let absoluteCursorRow = terminal.getTopVisibleRow() + cursor.y
        var desiredTop = min(max(preservedTopVisibleRow ?? currentTopVisibleRow, 0), maximumTopVisibleRow)

        if absoluteCursorRow < desiredTop {
            desiredTop = absoluteCursorRow
        } else if absoluteCursorRow >= desiredTop + terminalRowCount {
            desiredTop = absoluteCursorRow - terminalRowCount + 1
        }

        desiredTop = min(max(desiredTop, 0), maximumTopVisibleRow)
        let desiredOffsetY = CGFloat(desiredTop) * lineHeight
        if abs(contentOffset.y - desiredOffsetY) > 0.5 {
            contentOffset = CGPoint(x: contentOffset.x, y: desiredOffsetY)
        }
        preservedTopVisibleRow = nil
    }

    override func sizeChanged(source: Terminal) {
        preserveViewportAnchor()
        super.sizeChanged(source: source)
        DispatchQueue.main.async { [weak self] in
            self?.restoreViewportAfterTerminalUpdate()
        }
    }

    override func scrolled(source terminal: Terminal, yDisp: Int) {
        preserveViewportAnchor()
        super.scrolled(source: terminal, yDisp: yDisp)
        restoreViewportAfterTerminalUpdate()
    }

    override func showCursor(source: Terminal) {
        preserveViewportAnchor()
        super.showCursor(source: source)
        restoreViewportAfterTerminalUpdate()
    }
}
