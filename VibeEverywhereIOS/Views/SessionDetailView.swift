import SwiftUI

struct SessionDetailView: View {
    @ObservedObject var viewModel: SessionViewModel
    let autoActivate: Bool
    let onClose: (() -> Void)?
    let onSessionEnded: (() -> Void)?
    @State private var isContextPanelPresented = false
    @State private var isPromptEditorPresented = false
    @State private var keyPageIndex = 0
    @State private var promptEditorDragOffset: CGFloat = 0
    @Environment(\.dismiss) private var dismiss

    init(
        viewModel: SessionViewModel,
        autoActivate: Bool = true,
        onClose: (() -> Void)? = nil,
        onSessionEnded: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.autoActivate = autoActivate
        self.onClose = onClose
        self.onSessionEnded = onSessionEnded
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            focusedBackground
                .ignoresSafeArea()

            VStack(spacing: layout.verticalSpacing) {
                headerBar
                    .frame(height: layout.headerHeight, alignment: .top)
                    .padding(.horizontal, layout.outerPadding)
                    .padding(.top, layout.topPadding)

                terminalPanel
                    .layoutPriority(1)
                    .padding(.horizontal, layout.terminalHorizontalPadding)

                modeBar
                    .frame(height: layout.modeBarHeight)
                    .padding(.horizontal, layout.outerPadding)
                    .padding(.bottom, layout.bottomPadding)

                inputBar
                    .frame(height: layout.inputBarHeight)
                    .padding(.horizontal, layout.outerPadding)
                    .padding(.bottom, layout.bottomPadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if isContextPanelPresented {
                Color.black.opacity(0.24)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                            isContextPanelPresented = false
                        }
                    }
                    .zIndex(1)

                contextPanel
                    .frame(width: 320)
                    .padding(.trailing, 10)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(2)
            }

            if isPromptEditorPresented {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        closePromptEditor()
                    }
                    .zIndex(3)

                promptEditorPanel
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                    .offset(y: promptEditorDragOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                guard value.translation.height > 0 else { return }
                                promptEditorDragOffset = value.translation.height
                            }
                            .onEnded { value in
                                if value.translation.height > 120 {
                                    closePromptEditor()
                                } else {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                                        promptEditorDragOffset = 0
                                    }
                                }
                            }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(4)
            }
        }
        .navigationTitle(viewModel.session.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard autoActivate else { return }
            await viewModel.activate()
        }
        .onChange(of: viewModel.session.isEnded) { _, isEnded in
            guard isEnded else { return }
            onSessionEnded?()
            dismiss()
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: isContextPanelPresented)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    onClose?()
                    dismiss()
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                }
            }
        }
    }

    private let layout = FocusedLayoutMetrics()

    private var focusedBackground: some View {
        LinearGradient(
            colors: [Color("FocusedBackgroundTop"), Color("FocusedBackgroundBottom")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            RadialGradient(
                colors: [Color("FocusedAccent").opacity(0.14), .clear],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 360
            )
        )
    }

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                compactStatusBadge(normalizedBadgeLabel(viewModel.session.status), tone: sessionStatusColor(viewModel.session.status))
                compactStatusBadge(normalizedBadgeLabel(viewModel.session.supervisionStateLabel), tone: supervisionColor(viewModel.session))
                compactStatusBadge(normalizedBadgeLabel(socketLabel(viewModel.socketState)), tone: socketColor(viewModel.socketState))
                compactStatusBadge(normalizedBadgeLabel(viewModel.session.controllerKind), tone: viewModel.canSendInput ? .green : .orange)

                Spacer(minLength: 8)

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                        isContextPanelPresented.toggle()
                    }
                } label: {
                    Image(systemName: isContextPanelPresented ? "sidebar.trailing" : "sidebar.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color("FocusedText"))
                        .frame(width: 32, height: 32)
                        .background(Color("FocusedPanelSoft").opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .frame(height: 32)

            Text(viewModel.session.workspaceRoot)
                .font(.caption)
                .foregroundStyle(Color("FocusedMuted"))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(height: 16, alignment: .leading)
        }
    }

    private var terminalPanel: some View {
        ZStack {
            TerminalTextView(
                terminal: viewModel.terminal,
                mode: .focused,
                isInputEnabled: viewModel.canSendInput,
                onInput: { data in
                    Task { await viewModel.sendTerminalInput(data) }
                },
                onResize: { resize in
                    Task { await viewModel.sendResizeIfChanged(resize) }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            if !viewModel.terminal.hasContent {
                Text("Waiting for terminal output...")
                    .font(.footnote)
                    .foregroundStyle(Color("FocusedMuted"))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 12)
    }

    private var modeBar: some View {
        HStack(spacing: 12) {
            modeIndicator(
                title: viewModel.canSendInput ? "You have control" : "Observer Mode",
                detail: viewModel.canSendInput ? "Direct terminal input is live" : "You are watching this session",
                tone: viewModel.canSendInput ? Color("FocusedActive") : Color("FocusedMuted")
            )

            Spacer(minLength: 4)

            if viewModel.canSendInput {
                Button("Release") {
                    Task { await viewModel.releaseControl() }
                }
                .font(.system(size: 12, weight: Font.Weight.bold))
                .buttonStyle(.bordered)
                .tint(Color("FocusedAccent"))
                .frame(height: 24)

                Button(role: .destructive) {
                    Task { await viewModel.stopSession() }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .font(.system(size: 12, weight: Font.Weight.bold))
                .buttonStyle(.borderedProminent)
                .tint(Color.red.opacity(0.9))
                .frame(height: 24)
            } else {
                Button("Request Control") {
                    Task { await viewModel.requestControl() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("FocusedAccent"))
                .frame(height: 24)
            }
        }
        .frame(height: 60)
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
        .background(Color("FocusedGlass"))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var inputBar: some View {
        HStack(alignment: .center, spacing: 5) {
            
            directionalKeyCluster
            .frame(width: 140, height: 76)
            
            VStack(){
                HStack(alignment: .top, spacing: 10) {
                    
                    pageIndicator
                        .frame(width: 12, height: 76)
                    
                    verticalKeyPager
                        .frame(maxWidth: .infinity)
                        .frame(height: 76)
                }
                .padding(.top, -10)

                Button {
                    guard viewModel.canSendInput else { return }
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                        isPromptEditorPresented = true
                        promptEditorDragOffset = 0
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Prompt Editor")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(viewModel.canSendInput ? "Compose multiline prompt" : "Request control to compose")
                            .font(.caption)
                            .foregroundStyle(Color("FocusedMuted"))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .background(Color("FocusedPanelSoft").opacity(0.92))
                    .foregroundStyle(viewModel.canSendInput ? Color("FocusedText") : Color("FocusedMuted"))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canSendInput)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color("FocusedGlass"))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var pageIndicator: some View {
        VStack(spacing: 6) {
            ForEach(0..<2, id: \.self) { index in
                Capsule()
                    .fill(index == keyPageIndex ? Color("FocusedAccent") : Color.white.opacity(0.14))
                    .frame(width: 6, height: index == keyPageIndex ? 18 : 8)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var verticalKeyPager: some View {
        GeometryReader { proxy in
            TabView(selection: $keyPageIndex) {
                expandedKeyGrid
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .rotationEffect(.degrees(90))
                    .tag(0)
                
                primaryKeyGrid
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .rotationEffect(.degrees(90))
                    .tag(1)
            }
            .frame(width: proxy.size.height, height: proxy.size.width)
            .rotationEffect(.degrees(-90), anchor: .topLeading)
            .offset(x: 0, y: proxy.size.height)
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }

    private var directionalKeyCluster: some View {
        let columns = Array(repeating: GridItem(.fixed(34), spacing: 15), count: 3)
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(directionalKeys, id: \.label) { key in
                Button {
                    Task { await viewModel.sendTerminalInput(key.payload) }
                } label: {
                    Image(systemName: key.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 16, height: 30)
                }
                .frame(height: 40)
                .buttonStyle(.bordered)
                .tint(Color("FocusedControlKey"))
                .disabled(!viewModel.canSendInput)
            }
        }
    }

    private var primaryKeyGrid: some View {
        let rows = Array(repeating: GridItem(.fixed(34), spacing: 0), count: 2)
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: rows, spacing: 8) {
                keyButtons(for: primaryControlKeys)
            }
            .padding(.vertical, 4)
        }
    }

    private var expandedKeyGrid: some View {
        let rows = Array(repeating: GridItem(.fixed(34), spacing: 0), count: 2)
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: rows, spacing: 8) {
                keyButtons(for: expandedControlKeys)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func keyButtons(for keys: [TerminalControlKey]) -> some View {
        ForEach(keys, id: \.label) { key in
            Button {
                handleControlKeyTap(key)
            } label: {
                Text(key.label)
                    .font(.caption.weight(.semibold))
                    .frame(minWidth: 44)
                    .frame(height: 15)
            }
            .buttonStyle(.bordered)
            .tint(Color("FocusedControlKey"))
            .frame(height: 24)
            .disabled(!viewModel.canSendInput && key.payload != "__MORE__")
        }
    }

    private func handleControlKeyTap(_ key: TerminalControlKey) {
        if key.payload == "__MORE__" {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                keyPageIndex = 1
            }
            return
        }

        Task { await viewModel.sendTerminalInput(key.payload) }
    }

    private var promptEditorPanel: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Prompt Editor")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color("FocusedText"))
                    Text("Compose multiline input, then send it to the terminal.")
                        .font(.footnote)
                        .foregroundStyle(Color("FocusedMuted"))
                }

                Spacer()

                Button {
                    closePromptEditor()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color("FocusedMuted"))
                        .frame(width: 28, height: 28)
                        .background(Color("FocusedPanelSoft").opacity(0.9))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            TextEditor(text: $viewModel.inputText)
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 220, maxHeight: 280)
                .background(Color("FocusedPanelSoft").opacity(0.92))
                .foregroundStyle(Color("FocusedText"))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            HStack(spacing: 10) {
                Button("Clear") {
                    viewModel.inputText = ""
                }
                .buttonStyle(.bordered)
                .tint(Color("FocusedAccent"))

                Button("Close") {
                    closePromptEditor()
                }
                .buttonStyle(.bordered)
                .tint(Color("FocusedMuted"))

                Button("Send") {
                    Task {
                        await viewModel.sendInput()
                        closePromptEditor()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("FocusedAccent"))
                .disabled(!viewModel.canSendInput || viewModel.inputText.isEmpty)
            }
        }
        .padding(18)
        .background(.ultraThinMaterial)
        .background(Color("FocusedPanel").opacity(0.96))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 22, x: 0, y: 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func closePromptEditor() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            isPromptEditorPresented = false
            promptEditorDragOffset = 0
        }
    }

    private var contextPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Context")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color("FocusedText"))

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                        isContextPanelPresented = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color("FocusedMuted"))
                        .frame(width: 28, height: 28)
                        .background(Color("FocusedPanelSoft").opacity(0.9))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            contextSection(title: "Project Path") {
                Text(viewModel.session.workspaceRoot)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Color("FocusedText"))
                    .textSelection(.enabled)
            }

            contextSection(title: "Git Status") {
                Text(gitSummary)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Color("FocusedText"))
            }

            contextSection(title: "Recent Files") {
                VStack(alignment: .leading, spacing: 8) {
                    if viewModel.hasRecentFiles {
                        ForEach(Array(viewModel.recentFiles.prefix(5)), id: \.self) { file in
                            Text(file)
                                .font(.footnote)
                                .foregroundStyle(Color("FocusedText"))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    } else {
                        Text("No recent files yet.")
                            .font(.footnote)
                            .foregroundStyle(Color("FocusedMuted"))
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(.ultraThinMaterial)
        .background(Color("FocusedPanel").opacity(0.92))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.24), radius: 20, x: -6, y: 8)
    }

    private var gitSummary: String {
        let branch = viewModel.primaryGitBranch ?? "unknown branch"
        let modified = viewModel.session.gitModifiedCount ?? viewModel.snapshot?.git?.modifiedCount ?? 0
        let staged = viewModel.session.gitStagedCount ?? viewModel.snapshot?.git?.stagedCount ?? 0
        let untracked = viewModel.session.gitUntrackedCount ?? viewModel.snapshot?.git?.untrackedCount ?? 0
        return "\(branch)\n\(modified) modified\n\(staged) staged\n\(untracked) untracked"
    }

    private func modeIndicator(title: String, detail: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tone.opacity(0.95))
                .lineLimit(1)

            Text(detail)
                .font(.caption2)
                .foregroundStyle(Color("FocusedMuted"))
                .lineLimit(1)
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func contextSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color("FocusedMuted"))
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color("FocusedPanelSoft").opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func socketLabel(_ state: SessionSocket.ConnectionState) -> String {
        switch state {
        case .idle:
            return "idle"
        case .connecting:
            return "connecting"
        case .connected:
            return "connected"
        case let .disconnected(reason):
            return reason ?? "disconnected"
        }
    }

    private func sessionStatusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "running", "attached", "starting", "awaitinginput":
            return .green
        case "exited":
            return .gray
        case "error":
            return .red
        default:
            return .orange
        }
    }

    private func socketColor(_ state: SessionSocket.ConnectionState) -> Color {
        switch state {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .idle, .disconnected:
            return .gray
        }
    }

    private func supervisionColor(_ session: SessionSummary) -> Color {
        switch session.supervisionStateLabel.lowercased() {
        case "active":
            return .green
        case "stopped":
            return .gray
        default:
            return .orange
        }
    }

    private func compactStatusBadge(_ text: String, tone: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tone)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(tone.opacity(0.18))
            .clipShape(Capsule())
    }

    private func normalizedBadgeLabel(_ text: String) -> String {
        if text.lowercased() == text {
            return text.capitalized
        }
        return text
    }

    private var directionalKeys: [TerminalControlKey] {
        [
            .init(label: "Enter", payload: "\r", systemImage: "return.left"),
            .init(label: "Up", payload: "\u{1B}[A", systemImage: "arrow.up"),
            .init(label: "Backspace", payload: "\u{08}", systemImage: "delete.left"),
            .init(label: "Left", payload: "\u{1B}[D", systemImage: "arrow.left"),
            .init(label: "Down", payload: "\u{1B}[B", systemImage: "arrow.down"),
            .init(label: "Right", payload: "\u{1B}[C", systemImage: "arrow.right")
        ]
    }

    private var primaryControlKeys: [TerminalControlKey] {
        [
            .init(label: "Ctrl+C", payload: "\u{03}", systemImage: ""),
            .init(label: "Esc", payload: "\u{1B}", systemImage: ""),
            .init(label: "Tab", payload: "\t", systemImage: ""),
            .init(label: "Home", payload: "\u{1B}[H", systemImage: ""),
            .init(label: "End", payload: "\u{1B}[F", systemImage: ""),
            .init(label: "Del", payload: "\u{7F}", systemImage: "")
            ,
            .init(label: "PgUp", payload: "\u{1B}[5~", systemImage: ""),
            .init(label: "PgDn", payload: "\u{1B}[6~", systemImage: ""),
            .init(label: "More", payload: "__MORE__", systemImage: "")
        ]
    }

    private var expandedControlKeys: [TerminalControlKey] {
        [
            .init(label: "Ctrl+D", payload: "\u{04}", systemImage: ""),
            .init(label: "Ctrl+L", payload: "\u{0C}", systemImage: ""),
            .init(label: "Ctrl+Z", payload: "\u{1A}", systemImage: ""),
            .init(label: "F1", payload: "\u{1B}OP", systemImage: ""),
            .init(label: "F2", payload: "\u{1B}OQ", systemImage: ""),
            .init(label: "F3", payload: "\u{1B}OR", systemImage: ""),
            .init(label: "F4", payload: "\u{1B}OS", systemImage: ""),
            .init(label: "F5", payload: "\u{1B}[15~", systemImage: ""),
            .init(label: "F6", payload: "\u{1B}[17~", systemImage: ""),
            .init(label: "F7", payload: "\u{1B}[18~", systemImage: ""),
            .init(label: "F8", payload: "\u{1B}[19~", systemImage: ""),
            .init(label: "F9", payload: "\u{1B}[20~", systemImage: ""),
            .init(label: "F10", payload: "\u{1B}[21~", systemImage: ""),
            .init(label: "F11", payload: "\u{1B}[23~", systemImage: ""),
            .init(label: "F12", payload: "\u{1B}[24~", systemImage: "")
        ]
    }
}

private struct FocusedLayoutMetrics {
    let outerPadding: CGFloat = 14
    let terminalHorizontalPadding: CGFloat = 2
    let topPadding: CGFloat = 10
    let bottomPadding: CGFloat = 10
    let verticalSpacing: CGFloat = 10
    let headerHeight: CGFloat = 58
    let modeBarHeight: CGFloat = 68
    let inputBarHeight: CGFloat = 118
}

private struct TerminalControlKey {
    let label: String
    let payload: String
    let systemImage: String
}

#Preview("Focused Session") {
    let context = PreviewAppContext.make()
    NavigationStack {
        SessionDetailView(viewModel: context.focusedSessionViewModel, autoActivate: false)
    }
}
