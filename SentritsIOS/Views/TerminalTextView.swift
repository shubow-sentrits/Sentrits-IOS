import SwiftUI
import WebKit

struct TerminalTextView: View {
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

    var body: some View {
        TerminalSurface(
            rendererKind: .xterm,
            model: surfaceModel,
            callbacks: .init(
                onInput: onInput,
                onResize: onResize
            )
        )
    }

    private var surfaceModel: TerminalSurfaceModel {
        TerminalSurfaceModel(
            mode: mode,
            isInputEnabled: isInputEnabled,
            useCanonicalDisplay: useCanonicalDisplay,
            bootstrapChunksBase64: bootstrapChunksBase64,
            bootstrapToken: bootstrapToken,
            observerDimensions: observerDimensions,
            resetVersion: terminal.resetVersion,
            outputChunksBase64: terminal.outputChunksBase64
        )
    }
}

private struct TerminalSurface: View {
    let rendererKind: TerminalRendererKind
    let model: TerminalSurfaceModel
    let callbacks: TerminalSurfaceCallbacks

    var body: some View {
        switch rendererKind {
        case .xterm:
            XtermTerminalRendererView(model: model, callbacks: callbacks)
        }
    }
}

private enum TerminalRendererKind {
    case xterm
}

private struct TerminalSurfaceModel: Equatable {
    let mode: TerminalTextView.Mode
    let isInputEnabled: Bool
    let useCanonicalDisplay: Bool
    let bootstrapChunksBase64: [String]
    let bootstrapToken: Int
    let observerDimensions: TerminalResize?
    let resetVersion: Int
    let outputChunksBase64: [String]
}

private struct TerminalSurfaceCallbacks {
    let onInput: (String) -> Void
    let onResize: (TerminalResize) -> Void
}

private struct XtermTerminalRendererView: UIViewRepresentable {
    let model: TerminalSurfaceModel
    let callbacks: TerminalSurfaceCallbacks

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

        var parent: XtermTerminalRendererView
        weak var webView: WKWebView?

        private var isRendererReady = false
        private var lastResetVersion = -1
        private var lastRenderedChunkCount = 0
        private var lastInputEnabled: Bool?
        private var lastMode: TerminalTextView.Mode?
        private var lastUseCanonicalDisplay: Bool?
        private var lastObserverDimensions: TerminalResize?
        private var lastBootstrapToken = -1

        init(parent: XtermTerminalRendererView) {
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
            SentritsDebugTrace.log("ios.focus", "renderer.didFinish", "mode=\(parent.model.mode == .focused ? "focused" : "preview") canonical=\(parent.model.useCanonicalDisplay)")
            synchronizeRendererIfNeeded()
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case Self.inputHandlerName:
                guard let data = message.body as? String else { return }
                parent.callbacks.onInput(data)
            case Self.resizeHandlerName:
                guard let body = message.body as? [String: Any],
                      let cols = body["cols"] as? Int,
                      let rows = body["rows"] as? Int else {
                    return
                }
                parent.callbacks.onResize(TerminalResize(cols: cols, rows: rows))
            case Self.readyHandlerName:
                isRendererReady = true
                SentritsDebugTrace.log("ios.focus", "renderer.ready", "mode=\(parent.model.mode == .focused ? "focused" : "preview") canonical=\(parent.model.useCanonicalDisplay)")
                synchronizeRendererIfNeeded(forceFullReload: true)
            default:
                break
            }
        }

        func synchronizeRendererIfNeeded(forceFullReload: Bool = false) {
            guard isRendererReady, let webView else { return }

            if forceFullReload
                || lastMode != parent.model.mode
                || lastInputEnabled != parent.model.isInputEnabled
                || lastUseCanonicalDisplay != parent.model.useCanonicalDisplay
                || lastObserverDimensions != parent.model.observerDimensions {
                SentritsDebugTrace.log(
                    "ios.focus",
                    "renderer.mode",
                    "focused=\(parent.model.mode == .focused) input=\(parent.model.isInputEnabled) canonical=\(parent.model.useCanonicalDisplay)"
                )
                evaluate("window.vibeTerminal.setMode(\(jsonString(from: modePayload())))", in: webView)
                lastMode = parent.model.mode
                lastInputEnabled = parent.model.isInputEnabled
                lastUseCanonicalDisplay = parent.model.useCanonicalDisplay
                lastObserverDimensions = parent.model.observerDimensions
            }

            if forceFullReload || lastResetVersion != parent.model.resetVersion {
                SentritsDebugTrace.log("ios.focus", "renderer.reset", "resetVersion=\(parent.model.resetVersion)")
                evaluate("window.vibeTerminal.reset()", in: webView)
                lastResetVersion = parent.model.resetVersion
                lastRenderedChunkCount = 0
            }

            if parent.model.useCanonicalDisplay,
               forceFullReload || lastBootstrapToken != parent.model.bootstrapToken {
                SentritsDebugTrace.log(
                    "ios.focus",
                    "renderer.bootstrap",
                    "token=\(parent.model.bootstrapToken) chunks=\(parent.model.bootstrapChunksBase64.count)"
                )
                lastRenderedChunkCount = 0
                evaluate(
                    "window.vibeTerminal.replaceBase64Chunks(\(parent.model.bootstrapToken), \(jsonString(from: parent.model.bootstrapChunksBase64)))",
                    in: webView
                )
                lastBootstrapToken = parent.model.bootstrapToken
            }

            if parent.model.useCanonicalDisplay {
                return
            }

            guard parent.model.outputChunksBase64.count > lastRenderedChunkCount else { return }
            let newChunks = Array(parent.model.outputChunksBase64[lastRenderedChunkCount...])
            evaluate("window.vibeTerminal.appendBase64Chunks(\(jsonString(from: newChunks)))", in: webView)
            lastRenderedChunkCount = parent.model.outputChunksBase64.count
        }

        private func modePayload() -> TerminalModePayload {
            TerminalModePayload(
                mode: parent.model.mode == .focused ? "focused" : "preview",
                inputEnabled: parent.model.isInputEnabled,
                reportResize: parent.model.mode == .focused || parent.model.isInputEnabled,
                fixedCols: parent.model.mode == .preview && !parent.model.isInputEnabled ? parent.model.observerDimensions?.cols : nil,
                fixedRows: parent.model.mode == .preview && !parent.model.isInputEnabled ? parent.model.observerDimensions?.rows : nil
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

private struct TerminalModePayload: Encodable {
    let mode: String
    let inputEnabled: Bool
    let reportResize: Bool
    let fixedCols: Int?
    let fixedRows: Int?
}
