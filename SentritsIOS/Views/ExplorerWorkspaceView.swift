import SwiftUI

struct ExplorerWorkspaceView: View {
    @ObservedObject var explorerStore: ExplorerWorkspaceStore
    @ObservedObject var notificationPreferences: NotificationPreferencesStore
    @ObservedObject var activityStore: ActivityLogStore
    let onFocusSession: (String, UUID) -> Void
    @State private var draftGroupName = ""
    @State private var isCreateGroupPresented = false

    var body: some View {
        ZStack {
            explorerBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    titleRow
                    heroPanel
                    groupStrip
                    content
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await explorerStore.syncConnectedHosts()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isCreateGroupPresented) {
            createGroupSheet
                .presentationDetents([.height(240)])
        }
        .alert("Explorer Error", isPresented: Binding(
            get: { explorerStore.errorMessage != nil },
            set: { if !$0 { explorerStore.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(explorerStore.errorMessage ?? "")
        }
    }

    private var explorerBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Color("ExplorerBackground"), Color("ExplorerBackgroundAlt")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color("ExplorerAccent").opacity(0.12),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 28,
                endRadius: 360
            )
        }
    }

    private var heroPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text("Connected sessions stay here. Focus one when you need the larger terminal.")
                    .font(.subheadline)
                    .foregroundStyle(Color("ExplorerMuted"))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    isCreateGroupPresented = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color("ExplorerHighlight"))
                .accessibilityLabel("Create group")
            }

            HStack(spacing: 10) {
                explorerMetric(value: "\(explorerStore.sessions.count)", label: "Connected")
                explorerMetric(value: "\(max(0, explorerStore.groupTabs.count - 1))", label: "Groups")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color("ExplorerPanel"))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }

    private var titleRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Explorer")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.94))

            Text("Focused live sessions for control and supervision.")
                .font(.subheadline)
                .foregroundStyle(Color("ExplorerMuted"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var groupStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(explorerStore.groupTabs, id: \.self) { tag in
                    Button {
                        explorerStore.selectGroup(tag)
                    } label: {
                        Text(tag == "all" ? "All" : "#\(tag)")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(explorerStore.selectedGroupTag == tag ? Color("ExplorerAccent") : Color("ExplorerPanelSoft"))
                            .foregroundStyle(explorerStore.selectedGroupTag == tag ? Color("ExplorerBackground") : Color("ExplorerText"))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        let sessionKeys = notificationSessionKeys(for: tag)

                        Button {
                            setNotifications(subscribed: true, for: tag)
                        } label: {
                            Label("All", systemImage: "bell")
                        }
                        .disabled(sessionKeys.isEmpty)

                        Button(role: .destructive) {
                            setNotifications(subscribed: false, for: tag)
                        } label: {
                            Label("All", systemImage: "bell.slash")
                        }
                        .disabled(sessionKeys.isEmpty)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if explorerStore.visibleSessions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("No connected sessions match this group.")
                    .font(.headline)
                    .foregroundStyle(Color("ExplorerText"))
                Text("Connect a session from Inventory. All always shows every connected session.")
                    .font(.subheadline)
                    .foregroundStyle(Color("ExplorerMuted"))
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color("ExplorerPanelSoft"))
            .clipShape(RoundedRectangle(cornerRadius: 24))
        } else {
            LazyVStack(spacing: 16) {
                ForEach(explorerStore.visibleSessions, id: \.session.sessionId) { sessionViewModel in
                    sessionTile(for: sessionViewModel)
                }
            }
        }
    }

    private func sessionTile(for sessionViewModel: SessionViewModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    
                    HStack(spacing: 8) {
                        Text(sessionViewModel.session.displayTitle)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(Color("ExplorerText"))
                        
                        Spacer()
                        
                        Button(role: .destructive) {
                            Task { await explorerStore.stop(sessionViewModel) }
                        } label: {
                            Image(systemName: "stop.fill")
                                .font(.caption.weight(.bold))
                                .frame(width: 28, height: 24)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.red)
                        .disabled(sessionViewModel.session.isEnded)
                        .accessibilityLabel("Stop")

                        Button {
                            explorerStore.disconnect(sessionViewModel)
                        } label: {
                            Image(systemName: "bolt.slash")
                                .font(.caption.weight(.bold))
                                .frame(width: 28, height: 24)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.gray)
                        .disabled(sessionViewModel.session.isEnded)
                        .accessibilityLabel("Disconnect")

                        Button {
                            onFocusSession(sessionViewModel.session.sessionId, sessionViewModel.host.id)
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.caption.weight(.bold))
                                .frame(width: 28, height: 24)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(Color("ExplorerAccent"))
                    }
                    
                    HStack{
                        VStack(alignment: .leading) {
                            Text(sessionViewModel.host.displayLabel)
                                .font(.footnote)
                                .foregroundStyle(Color("ExplorerMuted"))
                            Text(sessionViewModel.session.workspaceRoot)
                                .font(.footnote)
                                .foregroundStyle(Color("ExplorerMuted"))
                                .lineLimit(1)
                            
                        }
                        Spacer()
                        Button {
                            toggleNotificationSubscription(for: sessionViewModel)
                        } label: {
                            Image(systemName: notificationPreferences.isSubscribed(sessionKey: sessionViewModel.session.notificationKey(hostID: sessionViewModel.host.id)) ? "bell.fill" : "bell.slash")
                                .font(.caption.weight(.bold))
                                .frame(width: 28, height: 24)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(notificationPreferences.isSubscribed(sessionKey: sessionViewModel.session.notificationKey(hostID: sessionViewModel.host.id)) ? Color("ExplorerAccent") : .gray)
                        .accessibilityLabel("Toggle notifications")
                    }
                }
            }

            TerminalTextView(
                terminal: sessionViewModel.terminal,
                mode: .preview,
                isInputEnabled: false,
                useCanonicalDisplay: false,
                bootstrapChunksBase64: [],
                bootstrapToken: 0,
                observerDimensions: sessionViewModel.observerTerminalDimensions,
                onInput: { _ in },
                onResize: { _ in }
            )
            .frame(height: 218)
            .padding(.horizontal, -10)

            HStack(spacing: 8) {
                explorerTag(SessionBadgeSupport.normalizedLabel(sessionViewModel.session.status), tone: SessionBadgeSupport.sessionTone(for: sessionViewModel.session.status))
                explorerTag(SessionBadgeSupport.normalizedLabel(sessionViewModel.session.supervisionStateLabel), tone: SessionBadgeSupport.supervisionTone(for: sessionViewModel.session))
                explorerTag(SessionBadgeSupport.normalizedLabel(SessionBadgeSupport.socketLabel(for: sessionViewModel.socketState)), tone: SessionBadgeSupport.socketTone(for: sessionViewModel.socketState))
                explorerTag(SessionBadgeSupport.normalizedLabel(sessionViewModel.session.controllerKind), tone: sessionViewModel.canSendInput ? Color.green : Color.orange)
                if let branch = sessionViewModel.primaryGitBranch, !branch.isEmpty {
                    explorerTag(branch, tone: Color("ExplorerAccent").opacity(0.8))
                }
            }

            HStack(spacing: 8) {
                if explorerStore.selectedGroupTag != "all",
                   !sessionViewModel.session.normalizedGroupTags.contains(explorerStore.selectedGroupTag) {
                    Button("Add To Group") {
                        Task { await explorerStore.addSelectedGroup(to: sessionViewModel) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color("ExplorerHighlight").opacity(0.92))
                    .controlSize(.small)
                }

                Menu("Groups") {
                    ForEach(explorerStore.availableGroups(for: sessionViewModel), id: \.self) { tag in
                        Button("Add #\(tag)") {
                            Task { await explorerStore.addGroup(tag, to: sessionViewModel) }
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("ExplorerPanelSoft"))
                .controlSize(.small)

                Spacer()

                if !sessionViewModel.session.groupTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(sessionViewModel.session.groupTags, id: \.self) { tag in
                                Button {
                                    Task { await explorerStore.removeGroup(tag, from: sessionViewModel) }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text("#\(tag)")
                                            .dynamicBadgeFont(weight: .medium)
                                        Image(systemName: "minus.circle.fill")
                                            .font(.caption2)
                                    }
                                    .frame(width: 60)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(Color("ExplorerPanelSoft"))
                                    .foregroundStyle(Color("ExplorerText"))
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color("ExplorerPanel"))
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 26))
    }

    private func toggleNotificationSubscription(for sessionViewModel: SessionViewModel) {
        let sessionKey = sessionViewModel.session.notificationKey(hostID: sessionViewModel.host.id)
        let willSubscribe = !notificationPreferences.isSubscribed(sessionKey: sessionKey)
        notificationPreferences.setSubscription(sessionKey: sessionKey, subscribed: willSubscribe)
        activityStore.record(
            category: .inventory,
            title: willSubscribe ? "Subscribed to session notifications" : "Muted session notifications",
            message: "\(sessionViewModel.session.displayTitle) on \(sessionViewModel.host.displayLabel)",
            host: sessionViewModel.host,
            sessionID: sessionViewModel.session.sessionId
        )
    }

    private func notificationSessionKeys(for groupTag: String) -> [String] {
        let sessions: [SessionViewModel]
        if groupTag == "all" {
            sessions = explorerStore.sessions
        } else {
            sessions = explorerStore.sessions.filter { $0.session.normalizedGroupTags.contains(groupTag) }
        }
        return sessions.map { $0.session.notificationKey(hostID: $0.host.id) }
    }

    private func setNotifications(subscribed: Bool, for groupTag: String) {
        let sessions: [SessionViewModel]
        if groupTag == "all" {
            sessions = explorerStore.sessions
        } else {
            sessions = explorerStore.sessions.filter { $0.session.normalizedGroupTags.contains(groupTag) }
        }
        let sessionKeys = sessions.map { $0.session.notificationKey(hostID: $0.host.id) }
        guard !sessionKeys.isEmpty else { return }

        notificationPreferences.setSubscriptions(sessionKeys: sessionKeys, subscribed: subscribed)

        let groupLabel = groupTag == "all" ? "All" : "#\(groupTag)"
        activityStore.record(
            category: .inventory,
            title: subscribed ? "Subscribed group notifications" : "Muted group notifications",
            message: "\(groupLabel) (\(sessions.count) sessions)",
            hostLabel: "Explorer"
        )
    }

    private var createGroupSheet: some View {
        NavigationStack {
            Form {
                Section("New Group") {
                    TextField("group-name", text: $draftGroupName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Create Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        draftGroupName = ""
                        isCreateGroupPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        explorerStore.createGroup(named: draftGroupName)
                        draftGroupName = ""
                        isCreateGroupPresented = false
                    }
                    .disabled(SessionSummary.normalizeGroupTag(draftGroupName).isEmpty)
                }
            }
        }
    }

    private func explorerMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Color("ExplorerText"))
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color("ExplorerMuted"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color("ExplorerPanelSoft"))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func explorerTag(_ text: String, tone: Color) -> some View {
        SessionCapsuleBadge(text: text, tone: tone, width: 40)
    }
}

#Preview("Explorer") {
    let context = PreviewAppContext.make()
    NavigationStack {
        ExplorerWorkspaceView(
            explorerStore: context.explorerStore,
            notificationPreferences: context.notificationPreferences,
            activityStore: context.activityStore,
            onFocusSession: { _, _ in }
        )
    }
}
