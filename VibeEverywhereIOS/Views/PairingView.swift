import SwiftUI

struct PairingView: View {
    @ObservedObject var hostsStore: HostsStore
    let tokenStore: TokenStore
    @ObservedObject var activityStore: ActivityLogStore

    @StateObject private var connectViewModel = ConnectViewModel()

    var body: some View {
        ZStack {
            background

            ScrollView {
                VStack(spacing: 18) {
                    headerCard
                    discoveryCard
                    manualAddCard
                    savedDevicesCard
                    selectedHostCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("Pairing")
        .navigationBarTitleDisplayMode(.large)
        .task {
            hostsStore.startDiscovery()
        }
        .onDisappear {
            hostsStore.stopDiscovery()
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.06, blue: 0.08),
                Color(red: 0.12, green: 0.10, blue: 0.09),
                Color(red: 0.20, green: 0.14, blue: 0.11)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color(red: 0.89, green: 0.68, blue: 0.43).opacity(0.10))
                .frame(width: 220, height: 220)
                .blur(radius: 24)
                .offset(x: 70, y: -40)
        }
    }

    private var headerCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Native discovery and host trust")
                    .font(.system(size: 30, weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
                Text("Broadcast listeners surface nearby hosts live. Manual verify remains available when broadcast is unavailable.")
                    .font(.body)
                    .foregroundStyle(Color.white.opacity(0.72))
                if let discoveryStatus = hostsStore.discoveryStatus {
                    Text(discoveryStatus)
                        .font(.footnote)
                        .foregroundStyle(Color(red: 0.93, green: 0.82, blue: 0.64))
                }
            }
        }
    }

    private var discoveryCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader("Active Discovery", detail: "\(hostsStore.discoveredHosts.count) live")
                if hostsStore.discoveredHosts.isEmpty {
                    Text("Waiting for UDP broadcasts on port 18087.")
                        .foregroundStyle(Color.white.opacity(0.62))
                } else {
                    ForEach(hostsStore.discoveredHosts) { host in
                        Button {
                            hostsStore.selectDiscoveredHost(host)
                            activityStore.record(
                                category: .system,
                                title: "Discovered host selected",
                                message: "Inspecting \(host.displayName) from live discovery.",
                                hostLabel: host.displayName
                            )
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(host.displayName)
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                    Text(host.endpoint.displayAddress)
                                        .font(.subheadline)
                                        .foregroundStyle(Color.white.opacity(0.62))
                                    Text(host.identity.protocolVersion ?? "protocol unknown")
                                        .font(.caption)
                                        .foregroundStyle(Color.white.opacity(0.45))
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 5) {
                                    statusChip(hostsStore.hostState(for: host))
                                    Text(host.age < 2 ? "just now" : "\(Int(host.age))s ago")
                                        .font(.caption)
                                        .foregroundStyle(Color.white.opacity(0.52))
                                }
                            }
                            .padding(14)
                            .background(cardRowBackground)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var manualAddCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader("Manual Add / Verify", detail: "Fallback")

                TextField("Alias (optional)", text: $connectViewModel.hostAlias)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(cardRowBackground)
                    .foregroundStyle(.white)

                TextField("Host or IP", text: $connectViewModel.hostAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(cardRowBackground)
                    .foregroundStyle(.white)

                HStack(spacing: 12) {
                    TextField("Port", text: $connectViewModel.port)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(cardRowBackground)
                        .foregroundStyle(.white)

                    Toggle("TLS", isOn: $connectViewModel.useTLS)
                        .toggleStyle(.switch)
                        .foregroundStyle(.white)
                }

                Toggle("Allow self-signed certificate", isOn: $connectViewModel.allowSelfSignedTLS)
                    .toggleStyle(.switch)
                    .foregroundStyle(Color.white.opacity(0.85))

                Button {
                    guard let endpoint = connectViewModel.makeEndpoint() else { return }
                    Task {
                        await hostsStore.verifyManualHost(endpoint: endpoint, alias: connectViewModel.alias)
                        switch hostsStore.verificationState {
                        case .idle:
                            if let selectedHost = hostsStore.selectedHost {
                                activityStore.record(
                                    category: .system,
                                    title: "Manual host verified",
                                    message: "Verified \(selectedHost.host.displayLabel) and loaded host details.",
                                    hostLabel: selectedHost.host.displayLabel
                                )
                            }
                        case let .failed(message):
                            activityStore.record(
                                severity: .warning,
                                category: .system,
                                title: "Manual host verification failed",
                                message: message,
                                hostLabel: endpoint.displayAddress
                            )
                        case .verifying:
                            break
                        }
                    }
                } label: {
                    HStack {
                        switch hostsStore.verificationState {
                        case .verifying:
                            ProgressView()
                        default:
                            Image(systemName: "checkmark.shield")
                        }
                        Text("Verify Host")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.84, green: 0.63, blue: 0.39))
                    .foregroundStyle(Color.black.opacity(0.82))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(hostsStore.verificationState == .verifying)

                if case let .failed(message) = hostsStore.verificationState {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Color(red: 1, green: 0.72, blue: 0.68))
                }
            }
        }
    }

    private var savedDevicesCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader("Saved Devices", detail: "\(hostsStore.savedHosts.count)")
                if hostsStore.savedHosts.isEmpty {
                    Text("Approved or manually saved hosts appear here.")
                        .foregroundStyle(Color.white.opacity(0.62))
                } else {
                    ForEach(Array(hostsStore.savedHosts.enumerated()), id: \.element.id) { index, host in
                        HStack(alignment: .top, spacing: 12) {
                            Button {
                                connectViewModel.populate(from: host)
                                hostsStore.selectSavedHost(host)
                                activityStore.record(
                                    category: .system,
                                    title: "Saved host selected",
                                    message: "Loaded the saved host into the pairing detail view.",
                                    hostLabel: host.displayLabel
                                )
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(host.displayLabel)
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                    Text(host.secondaryLabel)
                                        .font(.subheadline)
                                        .foregroundStyle(Color.white.opacity(0.62))
                                }
                                Spacer()
                                statusChip(hostsStore.token(for: host) == nil ? "Saved" : "Paired")
                            }
                            .buttonStyle(.plain)

                            Button(role: .destructive) {
                                hostsStore.removeSavedHosts(at: IndexSet(integer: index))
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(Color.white.opacity(0.68))
                                    .padding(10)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(14)
                        .background(cardRowBackground)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var selectedHostCard: some View {
        if let selectedHost = hostsStore.selectedHost {
            card {
                VStack(alignment: .leading, spacing: 14) {
                    sectionHeader("Selected Host Detail", detail: selectedHost.isSaved ? "saved" : "transient")

                    VStack(alignment: .leading, spacing: 6) {
                        Text(selectedHost.host.displayLabel)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(selectedHost.host.detailLabel)
                            .foregroundStyle(Color.white.opacity(0.62))
                    }

                    detailRow("Host ID", value: selectedHost.host.hostId ?? selectedHost.hostInfo?.hostId ?? "Unknown")
                    detailRow("Display Name", value: selectedHost.hostInfo?.displayName ?? selectedHost.host.displayName)
                    detailRow("TLS", value: selectedHost.host.useTLS ? "enabled" : "disabled")
                    detailRow("Token", value: selectedHost.hasToken ? "saved" : "not saved")
                    if let version = selectedHost.hostInfo?.version {
                        detailRow("Version", value: version)
                    }
                    if let capabilities = selectedHost.hostInfo?.capabilities, !capabilities.isEmpty {
                        detailRow("Capabilities", value: capabilities.joined(separator: ", "))
                    }
                    if let protocolVersion = selectedHost.discovery?.protocolVersion {
                        detailRow("Protocol", value: protocolVersion)
                    }
                    if let lastSeenAt = selectedHost.lastSeenAt {
                        detailRow("Last Seen", value: lastSeenAt.formatted(date: .omitted, time: .standard))
                    }

                    if !selectedHost.isSaved {
                        Button("Save Device") {
                            hostsStore.saveSelectedHost(alias: connectViewModel.alias)
                            activityStore.record(
                                category: .system,
                                title: "Host saved",
                                message: "Saved the selected host for future access.",
                                hostLabel: selectedHost.host.displayLabel
                            )
                        }
                        .buttonStyle(ActionButtonStyle(fill: Color.white.opacity(0.10)))
                    }

                    PairingRequestSection(
                        host: selectedHost.host,
                        tokenStore: tokenStore,
                        activityStore: activityStore,
                        alias: connectViewModel.alias,
                        onPaired: {
                            hostsStore.markSelectedHostPaired(alias: connectViewModel.alias)
                            activityStore.record(
                                category: .pairing,
                                title: "Host trusted",
                                message: "Promoted the selected host into saved trusted devices.",
                                hostLabel: selectedHost.host.displayLabel
                            )
                        }
                    )
                }
            }
        } else {
            card {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("Selected Host Detail", detail: "none")
                    Text("Select a discovered or saved device to inspect identity and start pairing.")
                        .foregroundStyle(Color.white.opacity(0.62))
                }
            }
        }
    }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        HStack {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
            Text(detail.uppercased())
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.42))
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(Color.white.opacity(0.52))
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.white)
        }
        .font(.subheadline)
    }

    private func statusChip(_ label: String) -> some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(red: 0.84, green: 0.63, blue: 0.39).opacity(0.18))
            .foregroundStyle(Color(red: 0.96, green: 0.84, blue: 0.67))
            .clipShape(Capsule())
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
    }

    private var cardRowBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.06))
    }
}

private struct PairingRequestSection: View {
    let host: SavedHost
    let tokenStore: TokenStore
    @ObservedObject var activityStore: ActivityLogStore
    let alias: String?
    let onPaired: () -> Void

    @StateObject private var viewModel: PairingViewModel

    init(host: SavedHost, tokenStore: TokenStore, activityStore: ActivityLogStore, alias: String?, onPaired: @escaping () -> Void) {
        self.host = host
        self.tokenStore = tokenStore
        self.activityStore = activityStore
        self.alias = alias
        self.onPaired = onPaired
        _viewModel = StateObject(wrappedValue: PairingViewModel(host: host, tokenStore: tokenStore, activityStore: activityStore))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pairing Request State")
                .font(.headline)
                .foregroundStyle(.white)

            switch viewModel.phase {
            case .idle:
                Button("Start Pairing") {
                    Task { await viewModel.start() }
                }
                .buttonStyle(ActionButtonStyle(fill: Color(red: 0.84, green: 0.63, blue: 0.39)))
            case .requesting:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Requesting pairing code from the host.")
                        .foregroundStyle(Color.white.opacity(0.72))
                }
            case let .waiting(response):
                VStack(alignment: .leading, spacing: 10) {
                    pairingValue("Pairing ID", value: response.pairingId)
                    pairingValue("Code", value: response.code)
                    pairingValue("Status", value: response.status)
                    Text("Approve this request in the host admin UI. Claim polling continues automatically.")
                        .font(.footnote)
                        .foregroundStyle(Color.white.opacity(0.62))
                    Button("Retry Claim Polling") {
                        viewModel.retryPolling()
                    }
                    .buttonStyle(ActionButtonStyle(fill: Color.white.opacity(0.10)))
                }
            case let .approved(deviceName):
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pairing approved.")
                        .foregroundStyle(Color(red: 0.75, green: 0.91, blue: 0.77))
                    if let deviceName {
                        Text("Trusted as \(deviceName).")
                            .foregroundStyle(Color.white.opacity(0.72))
                    }
                }
            case .rejected:
                retryState(message: "The host rejected this pairing request.")
            case .expired:
                retryState(message: "The pairing request expired before approval.")
            case let .failed(message):
                retryState(message: message)
            }
        }
        .onChange(of: isApproved) {
            if isApproved, tokenStore.token(for: host.tokenKey) != nil {
                onPaired()
            }
        }
        .id(host.tokenKey + (alias ?? ""))
    }

    private var isApproved: Bool {
        if case .approved = viewModel.phase {
            return true
        }
        return false
    }

    private func retryState(message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .foregroundStyle(Color(red: 1, green: 0.72, blue: 0.68))
            Button("Start New Pairing Request") {
                Task { await viewModel.start() }
            }
            .buttonStyle(ActionButtonStyle(fill: Color.white.opacity(0.10)))
        }
    }

    private func pairingValue(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Color.white.opacity(0.52))
            Spacer()
            Text(value)
                .foregroundStyle(.white)
                .textSelection(.enabled)
        }
        .font(.subheadline)
    }
}

private struct ActionButtonStyle: ButtonStyle {
    let fill: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(fill.opacity(configuration.isPressed ? 0.75 : 1))
            .foregroundStyle(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
