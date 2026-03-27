import SwiftUI

struct InventoryView: View {
    @ObservedObject var hostsStore: SavedHostsStore
    let tokenStore: TokenStore

    @StateObject private var store: InventoryStore
    @State private var createSheetHost: SavedHost?
    @State private var focusedSession: InventoryFocusedSession?
    @State private var inventoryError: String?

    init(hostsStore: SavedHostsStore, tokenStore: TokenStore) {
        self.hostsStore = hostsStore
        self.tokenStore = tokenStore
        _store = StateObject(wrappedValue: InventoryStore(hostsStore: hostsStore, tokenStore: tokenStore))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                inventoryBackground

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        summaryPanel
                        controlsRow
                        sectionList
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 20)
                    .padding(.bottom, 120)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Inventory")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if store.isRefreshing {
                        ProgressView()
                            .tint(inventoryAccent)
                    }
                }
            }
            .task {
                await store.refresh()
            }
            .refreshable {
                await store.refresh()
            }
            .onChange(of: hostsStore.hosts) {
                Task { await store.refresh() }
            }
            .sheet(item: $createSheetHost) { host in
                CreateSessionSheet(host: host) { input in
                    do {
                        let created = try await store.createSession(hostID: host.id, input: input)
                        if let token = tokenStore.token(for: host.tokenKey) {
                            focusedSession = InventoryFocusedSession(host: host, token: token, session: created)
                        }
                    } catch {
                        inventoryError = error.localizedDescription
                    }
                }
            }
            .sheet(item: $focusedSession) { focused in
                NavigationStack {
                    SessionDetailView(host: focused.host, token: focused.token, session: focused.session)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Disconnect") {
                                    focusedSession = nil
                                }
                            }
                        }
                }
            }
            .alert("Inventory Error", isPresented: Binding(
                get: { inventoryError != nil },
                set: { isPresented in
                    if !isPresented {
                        inventoryError = nil
                    }
                }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(inventoryError ?? "")
            }
        }
    }

    private var summaryPanel: some View {
        let sectionCount = store.sections.count
        let sessionCount = store.sections.reduce(0) { $0 + $1.sessions.count }
        let liveCount = store.sections.reduce(0) { partial, section in
            partial + section.sessions.filter { !$0.isEnded }.count
        }

        return VStack(alignment: .leading, spacing: 16) {
            Text("Device inventory")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.94))

            Text("Sessions are grouped by paired device. Create and stop them from here, then open focused control when needed.")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.68))

            HStack(spacing: 12) {
                inventoryMetric(title: "Devices", value: "\(sectionCount)")
                inventoryMetric(title: "Sessions", value: "\(sessionCount)")
                inventoryMetric(title: "Live", value: "\(liveCount)")
            }
        }
        .padding(22)
        .background(panelBackground.opacity(0.92))
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(inventoryAccent.opacity(0.28))
                .frame(width: 140, height: 140)
                .blur(radius: 32)
                .offset(x: 30, y: -40)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var controlsRow: some View {
        HStack {
            Toggle(isOn: $store.showStoppedSessions) {
                Text("Show ended sessions")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.78))
            }
            .tint(inventoryAccent)

            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var sectionList: some View {
        VStack(spacing: 18) {
            if store.sections.isEmpty {
                emptyInventoryPanel
            } else {
                ForEach(store.sections) { section in
                    deviceSection(section)
                }
            }
        }
    }

    private var emptyInventoryPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No saved devices yet")
                .font(.headline)
                .foregroundStyle(Color.white.opacity(0.9))
            Text("Pair a device first to load its runtime sessions here.")
                .foregroundStyle(Color.white.opacity(0.66))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(panelBackground.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func deviceSection(_ section: InventoryDeviceSection) -> some View {
        let visibleSessions = store.visibleSessions(for: section)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.host.name.isEmpty ? section.host.address : section.host.name)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.92))
                    Text("\(section.host.address):\(section.host.port)")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.54))
                    if let displayName = section.hostInfo?.displayName,
                       !displayName.isEmpty,
                       displayName != section.host.name {
                        Text(displayName)
                            .font(.caption)
                            .foregroundStyle(inventoryAccent.opacity(0.92))
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Text("\(visibleSessions.count) visible")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())

                    Button {
                        createSheetHost = section.host
                    } label: {
                        Label("New Session", systemImage: "plus")
                            .font(.footnote.weight(.bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(inventoryAccent)
                    .disabled(section.token == nil || store.isBusy(hostID: section.host.id))
                }
            }

            if let errorMessage = section.errorMessage {
                inventoryMessage(errorMessage, color: .red.opacity(0.84))
            } else if section.token == nil {
                inventoryMessage("Pair this device before loading or creating sessions.", color: Color.white.opacity(0.62))
            } else if visibleSessions.isEmpty {
                inventoryMessage("No sessions for this device.", color: Color.white.opacity(0.62))
            }

            ForEach(visibleSessions) { session in
                sessionCard(section: section, session: session)
            }
        }
        .padding(20)
        .background(panelBackground.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(inventoryAccent)
                .frame(width: 5, height: 36)
                .padding(.leading, 8)
                .padding(.top, 18)
        }
    }

    private func sessionCard(section: InventoryDeviceSection, session: SessionSummary) -> some View {
        let isFocused = focusedSession?.session.id == session.id

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.displayTitle)
                        .font(.headline)
                        .foregroundStyle(Color.white.opacity(0.92))
                    Text(session.sessionId)
                        .font(.caption2.monospaced())
                        .foregroundStyle(Color.white.opacity(0.48))
                    Text(session.workspaceRoot)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.58))
                        .lineLimit(2)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    statusBadge(session.inventoryStateLabel, color: statusColor(for: session))
                    if let attention = session.attentionState, attention != "none" {
                        statusBadge(attention, color: attentionColor(for: session))
                    }
                }
            }

            HStack(spacing: 8) {
                detailChip(session.provider.uppercased(), tint: inventoryAccent)
                detailChip("control \(session.controllerKind)", tint: controllerColor(session.controllerKind))
                if let attached = session.attachedClientCount, attached > 0 {
                    detailChip("\(attached) attached", tint: .blue.opacity(0.85))
                }
            }

            HStack(spacing: 8) {
                if let branch = session.gitBranch, !branch.isEmpty {
                    detailChip(branch, tint: session.gitDirty == true ? .orange.opacity(0.9) : .white.opacity(0.55))
                }
                if let fileChanges = session.recentFileChangeCount, fileChanges > 0 {
                    detailChip("+\(fileChanges) files", tint: .yellow.opacity(0.85))
                } else {
                    detailChip("files steady", tint: .white.opacity(0.45))
                }
            }

            if !session.groupTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(session.groupTags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.white.opacity(0.7))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    if isFocused {
                        focusedSession = nil
                    } else if let token = section.token {
                        focusedSession = InventoryFocusedSession(host: section.host, token: token, session: session)
                    }
                } label: {
                    Label(isFocused ? "Disconnect" : "Connect", systemImage: isFocused ? "bolt.slash" : "terminal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(isFocused ? .gray.opacity(0.7) : inventoryAccent)
                .disabled(section.token == nil)

                Button(role: .destructive) {
                    Task {
                        do {
                            try await store.stopSession(hostID: section.host.id, sessionID: session.sessionId)
                            if focusedSession?.session.id == session.id {
                                focusedSession = nil
                            }
                        } catch {
                            inventoryError = error.localizedDescription
                        }
                    }
                } label: {
                    if store.isBusy(sessionID: session.sessionId) {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Stop", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .tint(.red.opacity(0.9))
                .disabled(section.token == nil || store.isBusy(sessionID: session.sessionId))
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func inventoryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.92))
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.white.opacity(0.52))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func inventoryMessage(_ message: String, color: Color) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func detailChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }

    private func statusBadge(_ text: String, color: Color) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    private func statusColor(for session: SessionSummary) -> Color {
        switch session.inventoryStateLabel.lowercased() {
        case "live", "running", "attached", "starting":
            return inventoryAccent
        case "archived":
            return .orange.opacity(0.92)
        default:
            return .gray.opacity(0.82)
        }
    }

    private func attentionColor(for session: SessionSummary) -> Color {
        switch session.attentionState?.lowercased() {
        case "needs_review":
            return .orange.opacity(0.92)
        case "urgent":
            return .red.opacity(0.92)
        default:
            return .yellow.opacity(0.9)
        }
    }

    private func controllerColor(_ kind: String) -> Color {
        switch kind.lowercased() {
        case "remote":
            return .green.opacity(0.92)
        case "observer":
            return .blue.opacity(0.92)
        default:
            return .white.opacity(0.55)
        }
    }

    private var inventoryBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.05, blue: 0.06),
                Color(red: 0.07, green: 0.09, blue: 0.10),
                Color(red: 0.10, green: 0.12, blue: 0.14)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(inventoryAccent.opacity(0.20))
                .frame(width: 220, height: 220)
                .blur(radius: 50)
                .offset(x: 90, y: -20)
        }
        .ignoresSafeArea()
    }

    private var panelBackground: Color {
        Color(red: 0.12, green: 0.15, blue: 0.17)
    }

    private var inventoryAccent: Color {
        Color(red: 0.74, green: 0.81, blue: 0.54)
    }
}

private struct InventoryFocusedSession: Identifiable, Equatable {
    let host: SavedHost
    let token: String
    let session: SessionSummary

    var id: String { "\(host.id.uuidString)-\(session.id)" }
}

private struct CreateSessionSheet: View {
    let host: SavedHost
    let onSubmit: (CreateSessionInput) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var input = CreateSessionInput()
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Device") {
                    Text(host.displayLabel)
                    Text(host.useTLS ? "HTTPS / WSS" : "HTTP / WS")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Session") {
                    TextField("Workspace path", text: $input.workspaceRoot)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Title", text: $input.title)
                    Picker("Provider", selection: $input.provider) {
                        ForEach(SessionProvider.allCases) { provider in
                            Text(provider.label).tag(provider)
                        }
                    }
                    TextField("Group tags (comma separated)", text: $input.groupTagsText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("New Session")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        Task {
                            isSubmitting = true
                            await onSubmit(input)
                            isSubmitting = false
                            dismiss()
                        }
                    }
                    .disabled(isSubmitting || input.normalizedWorkspaceRoot.isEmpty)
                }
            }
        }
    }
}
