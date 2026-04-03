import SwiftUI
import WebKit

struct TerminalTextView: UIViewRepresentable {
    enum Mode {
        case preview
        case focused
    }

    @ObservedObject var terminal: TerminalEngine
    let mode: Mode
    let isInputEnabled: Bool
    let useCanonicalDisplay: Bool
    let bootstrapChunksBase64: [String]
    let bootstrapToken: Int
    let observerDimensions: TerminalResize?
    let onInput: (String) -> Void
    let onResize: (TerminalResize) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: Coordinator.inputHandlerName)
        controller.add(context.coordinator, name: Coordinator.resizeHandlerName)
        controller.add(context.coordinator, name: Coordinator.readyHandlerName)
        configuration.userContentController = controller
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.loadRenderer()
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.synchronizeRendererIfNeeded()
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.inputHandlerName)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.resizeHandlerName)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.readyHandlerName)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let inputHandlerName = "terminalInput"
        static let resizeHandlerName = "terminalResize"
        static let readyHandlerName = "terminalReady"

        var parent: TerminalTextView
        weak var webView: WKWebView?

        private var isRendererReady = false
        private var lastResetVersion = -1
        private var lastRenderedChunkCount = 0
        private var lastInputEnabled: Bool?
        private var lastMode: Mode?
        private var lastUseCanonicalDisplay: Bool?
        private var lastObserverDimensions: TerminalResize?
        private var lastBootstrapToken = -1

        init(parent: TerminalTextView) {
            self.parent = parent
        }

        func loadRenderer() {
            guard let webView else { return }
            let htmlURL = Bundle.main.url(forResource: "terminal", withExtension: "html", subdirectory: "Terminal")
                ?? Bundle.main.url(forResource: "terminal", withExtension: "html")
            guard let htmlURL else {
                return
            }
            let readAccessURL = htmlURL.deletingLastPathComponent()
            webView.loadFileURL(htmlURL, allowingReadAccessTo: readAccessURL)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            SentritsDebugTrace.log("ios.focus", "renderer.didFinish", "mode=\(parent.mode == .focused ? "focused" : "preview") canonical=\(parent.useCanonicalDisplay)")
            synchronizeRendererIfNeeded()
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case Self.inputHandlerName:
                guard let data = message.body as? String else { return }
                parent.onInput(data)
            case Self.resizeHandlerName:
                guard let body = message.body as? [String: Any],
                      let cols = body["cols"] as? Int,
                      let rows = body["rows"] as? Int else {
                    return
                }
                parent.onResize(TerminalResize(cols: cols, rows: rows))
            case Self.readyHandlerName:
                isRendererReady = true
                SentritsDebugTrace.log("ios.focus", "renderer.ready", "mode=\(parent.mode == .focused ? "focused" : "preview") canonical=\(parent.useCanonicalDisplay)")
                synchronizeRendererIfNeeded(forceFullReload: true)
            default:
                break
            }
        }

        func synchronizeRendererIfNeeded(forceFullReload: Bool = false) {
            guard isRendererReady, let webView else { return }

            if forceFullReload || lastMode != parent.mode || lastInputEnabled != parent.isInputEnabled || lastUseCanonicalDisplay != parent.useCanonicalDisplay || lastObserverDimensions != parent.observerDimensions {
                SentritsDebugTrace.log(
                    "ios.focus",
                    "renderer.mode",
                    "focused=\(parent.mode == .focused) input=\(parent.isInputEnabled) canonical=\(parent.useCanonicalDisplay)"
                )
                evaluate("window.vibeTerminal.setMode(\(jsonString(from: modePayload())))", in: webView)
                lastMode = parent.mode
                lastInputEnabled = parent.isInputEnabled
                lastUseCanonicalDisplay = parent.useCanonicalDisplay
                lastObserverDimensions = parent.observerDimensions
            }

            if forceFullReload || lastResetVersion != parent.terminal.resetVersion {
                SentritsDebugTrace.log("ios.focus", "renderer.reset", "resetVersion=\(parent.terminal.resetVersion)")
                evaluate("window.vibeTerminal.reset()", in: webView)
                lastResetVersion = parent.terminal.resetVersion
                lastRenderedChunkCount = 0
            }

            if parent.useCanonicalDisplay,
               forceFullReload || lastBootstrapToken != parent.bootstrapToken {
                SentritsDebugTrace.log(
                    "ios.focus",
                    "renderer.bootstrap",
                    "token=\(parent.bootstrapToken) chunks=\(parent.bootstrapChunksBase64.count)"
                )
                evaluate("window.vibeTerminal.reset()", in: webView)
                lastRenderedChunkCount = 0
                if !parent.bootstrapChunksBase64.isEmpty {
                    for batch in parent.bootstrapChunksBase64.chunked(into: 8) {
                        evaluate("window.vibeTerminal.appendBase64Chunks(\(jsonString(from: batch)))", in: webView)
                    }
                }
                lastBootstrapToken = parent.bootstrapToken
            }

            if parent.useCanonicalDisplay {
                return
            }

            guard parent.terminal.outputChunksBase64.count > lastRenderedChunkCount else { return }
            let newChunks = Array(parent.terminal.outputChunksBase64[lastRenderedChunkCount...])
            evaluate("window.vibeTerminal.appendBase64Chunks(\(jsonString(from: newChunks)))", in: webView)
            lastRenderedChunkCount = parent.terminal.outputChunksBase64.count
        }

        private func modePayload() -> TerminalModePayload {
            TerminalModePayload(
                mode: parent.mode == .focused ? "focused" : "preview",
                inputEnabled: parent.isInputEnabled,
                reportResize: parent.mode == .focused || parent.isInputEnabled,
                fixedCols: parent.mode == .preview && !parent.isInputEnabled ? parent.observerDimensions?.cols : nil,
                fixedRows: parent.mode == .preview && !parent.isInputEnabled ? parent.observerDimensions?.rows : nil
            )
        }

        private func evaluate(_ script: String, in webView: WKWebView) {
            webView.evaluateJavaScript(script)
        }

        private func jsonString(from value: some Encodable) -> String {
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(value),
                  let string = String(data: data, encoding: .utf8) else {
                return "null"
            }
            return string
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        var result: [[Element]] = []
        result.reserveCapacity((count / size) + 1)
        var index = startIndex
        while index < endIndex {
            let end = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(Array(self[index..<end]))
            index = end
        }
        return result
    }
}

private struct TerminalModePayload: Encodable {
    let mode: String
    let inputEnabled: Bool
    let reportResize: Bool
    let fixedCols: Int?
    let fixedRows: Int?
}
