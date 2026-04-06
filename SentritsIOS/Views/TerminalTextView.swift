import SwiftUI
import WebKit
import SwiftTerm

enum TerminalRendererKind: String, CaseIterable, Identifiable {
    case swiftTerm = "swiftterm"
    case xterm = "xterm"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .swiftTerm:
            return "SwiftTerm"
        case .xterm:
            return "xterm.js"
        }
    }

    var detail: String {
        switch self {
        case .swiftTerm:
            return "Native iOS terminal renderer"
        case .xterm:
            return "Web fallback renderer"
        }
    }
}

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
    @AppStorage("terminal.renderer.kind") private var rendererKindRawValue = TerminalRendererKind.swiftTerm.rawValue

    var body: some View {
        TerminalSurface(
            rendererKind: rendererKind,
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

    private var rendererKind: TerminalRendererKind {
        TerminalRendererKind(rawValue: rendererKindRawValue) ?? .swiftTerm
    }
}

private struct TerminalSurface: View {
    let rendererKind: TerminalRendererKind
    let model: TerminalSurfaceModel
    let callbacks: TerminalSurfaceCallbacks

    var body: some View {
        switch rendererKind {
        case .swiftTerm:
            SwiftTermTerminalRendererView(model: model, callbacks: callbacks)
        case .xterm:
            XtermTerminalRendererView(model: model, callbacks: callbacks)
        }
    }
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

private func summarizeBase64Chunks(_ chunks: [String], limit: Int = 1) -> String {
    guard !chunks.isEmpty else { return "empty" }
    let summaries = chunks.prefix(limit).compactMap { chunk -> String? in
        guard let data = Data(base64Encoded: chunk) else { return nil }
        return SentritsDebugTrace.summarizeData(data)
    }
    if summaries.isEmpty {
        return "undecodable"
    }
    return summaries.joined(separator: " | ")
}

private struct SwiftTermTerminalRendererView: UIViewRepresentable {
    let model: TerminalSurfaceModel
    let callbacks: TerminalSurfaceCallbacks

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> TerminalView {
        let terminalView = SentritsSwiftTermView(frame: .zero)
        terminalView.terminalDelegate = context.coordinator
        terminalView.nativeBackgroundColor = .clear
        terminalView.backgroundColor = .explorerPanel
        terminalView.caretColor = UIColor(named: "FocusedText") ?? .white
        terminalView.selectedTextBackgroundColor = UIColor(named: "FocusedPanelSoft")?.withAlphaComponent(0.4) ?? UIColor.white.withAlphaComponent(0.2)
        context.coordinator.terminalView = terminalView
        context.coordinator.synchronizeRendererIfNeeded(forceFullReload: true)
        return terminalView
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.synchronizeRendererIfNeeded()
    }

    final class Coordinator: NSObject, TerminalViewDelegate {
        var parent: SwiftTermTerminalRendererView
        weak var terminalView: TerminalView?

        private var lastResetVersion = -1
        private var lastRenderedChunkCount = 0
        private var lastBootstrapToken = -1
        private var lastInputEnabled: Bool?
        private var lastMode: TerminalTextView.Mode?
        private var lastUseCanonicalDisplay: Bool?
        private var lastObserverDimensions: TerminalResize?

        init(parent: SwiftTermTerminalRendererView) {
            self.parent = parent
        }

        @MainActor
        func synchronizeRendererIfNeeded(forceFullReload: Bool = false) {
            guard let terminalView else { return }

            if forceFullReload
                || lastMode != parent.model.mode
                || lastInputEnabled != parent.model.isInputEnabled
                || lastUseCanonicalDisplay != parent.model.useCanonicalDisplay
                || lastObserverDimensions != parent.model.observerDimensions {
                SentritsDebugTrace.log(
                    "ios.focus",
                    "swiftterm.mode",
                    "focused=\(parent.model.mode == .focused) input=\(parent.model.isInputEnabled) canonical=\(parent.model.useCanonicalDisplay)"
                )
                applyMode(to: terminalView)
                lastMode = parent.model.mode
                lastInputEnabled = parent.model.isInputEnabled
                lastUseCanonicalDisplay = parent.model.useCanonicalDisplay
                lastObserverDimensions = parent.model.observerDimensions
            }

            if forceFullReload || lastResetVersion != parent.model.resetVersion {
                resetTerminalView(terminalView)
                lastResetVersion = parent.model.resetVersion
                lastRenderedChunkCount = 0
                lastBootstrapToken = -1
            }

            if parent.model.useCanonicalDisplay,
               forceFullReload || lastBootstrapToken != parent.model.bootstrapToken {
                SentritsDebugTrace.log(
                    "ios.focus",
                    "swiftterm.bootstrap",
                    "token=\(parent.model.bootstrapToken) chunks=\(parent.model.bootstrapChunksBase64.count) summary=\(summarizeBase64Chunks(parent.model.bootstrapChunksBase64))"
                )
                resetTerminalView(terminalView)
                for chunk in parent.model.bootstrapChunksBase64 {
                    feed(base64Chunk: chunk, to: terminalView)
                }
                lastBootstrapToken = parent.model.bootstrapToken
                lastRenderedChunkCount = 0
                return
            }

            if parent.model.useCanonicalDisplay {
                return
            }

            guard parent.model.outputChunksBase64.count > lastRenderedChunkCount else { return }
            let newChunks = Array(parent.model.outputChunksBase64[lastRenderedChunkCount...])
            if parent.model.mode == .focused && parent.model.isInputEnabled {
                SentritsDebugTrace.log(
                    "ios.focus",
                    "swiftterm.append",
                    "chunks=\(newChunks.count) summary=\(summarizeBase64Chunks(newChunks))"
                )
            }
            for chunk in newChunks {
                feed(base64Chunk: chunk, to: terminalView)
            }
            lastRenderedChunkCount = parent.model.outputChunksBase64.count
        }

        @MainActor
        private func applyMode(to terminalView: TerminalView) {
            let swiftTermView = terminalView as? SentritsSwiftTermView
            swiftTermView?.preserveViewportAnchor()
            if let resize = parent.model.observerDimensions {
                terminalView.getTerminal().resize(cols: resize.cols, rows: resize.rows)
            }
            DispatchQueue.main.async {
                if self.parent.model.isInputEnabled {
                    _ = terminalView.becomeFirstResponder()
                } else {
                    _ = terminalView.resignFirstResponder()
                }
                swiftTermView?.restoreViewportAfterTerminalUpdate()
            }
        }

        @MainActor
        private func resetTerminalView(_ terminalView: TerminalView) {
            let swiftTermView = terminalView as? SentritsSwiftTermView
            swiftTermView?.preserveViewportAnchor()
            terminalView.getTerminal().resetToInitialState()
            if let resize = parent.model.observerDimensions {
                terminalView.getTerminal().resize(cols: resize.cols, rows: resize.rows)
            }
            terminalView.setNeedsDisplay()
            swiftTermView?.restoreViewportAfterTerminalUpdate()
        }

        @MainActor
        private func feed(base64Chunk: String, to terminalView: TerminalView) {
            guard let data = Data(base64Encoded: base64Chunk) else { return }
            let swiftTermView = terminalView as? SentritsSwiftTermView
            swiftTermView?.preserveViewportAnchor()
            terminalView.feed(byteArray: Array(data)[...])
            terminalView.setNeedsDisplay()
            swiftTermView?.restoreViewportAfterTerminalUpdate()
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            let onResize = parent.callbacks.onResize
            DispatchQueue.main.async {
                onResize(TerminalResize(cols: newCols, rows: newRows))
            }
        }

        func setTerminalTitle(source: TerminalView, title: String) {}

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            let payload = String(decoding: Array(data), as: UTF8.self)
            let onInput = parent.callbacks.onInput
            DispatchQueue.main.async {
                onInput(payload)
            }
        }

        func scrolled(source: TerminalView, position: Double) {}

        func requestOpenLink(source: TerminalView, link: String, params: [String : String]) {}

        func clipboardCopy(source: TerminalView, content: Data) {}

        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
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
                    "token=\(parent.model.bootstrapToken) chunks=\(parent.model.bootstrapChunksBase64.count) summary=\(summarizeBase64Chunks(parent.model.bootstrapChunksBase64))"
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
            if parent.model.mode == .focused && parent.model.isInputEnabled {
                SentritsDebugTrace.log(
                    "ios.focus",
                    "renderer.append",
                    "chunks=\(newChunks.count) summary=\(summarizeBase64Chunks(newChunks))"
                )
            }
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
