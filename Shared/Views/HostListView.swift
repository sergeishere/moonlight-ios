import SwiftUI
import SwiftData
import AVFoundation

struct HostListView: View {
    @Environment(\.modelContext) private var modelContext
    @State var viewModel = HostListViewModel()

    @State private var showingAddHost = false
    @State private var showingSettings = false
    @State private var hostToDelete: Host?
    @State private var showDeleteConfirmation = false
    @State private var hostForInfo: Host?

    var body: some View {
        NavigationStack {
            Group {
                if let host = viewModel.selectedHost {
                    appGrid(for: host)
                } else {
                    hostGrid
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if let host = viewModel.selectedHost {
                        hostPicker(current: host)
                    } else {
                        Text("Moonlight")
                            .font(.headline)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if viewModel.selectedHost == nil {
                        Button("Add", systemImage: "plus") {
                            showingAddHost = true
                        }
                    }
                }
                ToolbarItem(placement: .navigation) {
                    Button("Settings", systemImage: "gearshape") {
                        showingSettings = true
                    }
                }
            }
        }
        .task {
            setupAndStartDiscovery()
            await viewModel.reconnectLastHost()
        }
        .onDisappear { viewModel.stopDiscovery() }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .fullScreenCover(isPresented: Binding(
            get: { viewModel.streamConfig != nil },
            set: { if !$0 { viewModel.endStream() } }
        )) {
            if let config = viewModel.streamConfig {
                StreamContainerView(config: config)
                    .ignoresSafeArea()
                    .statusBarHidden(true)
                    .persistentSystemOverlays(.hidden)
            }
        }
    }

    // MARK: - Host Picker

    @ViewBuilder
    private func hostPicker(current host: Host) -> some View {
        Menu {
            let otherHosts = viewModel.hosts.filter { $0.uuid != host.uuid && $0.isPaired }
            if !otherHosts.isEmpty {
                Section("Switch to") {
                    ForEach(otherHosts, id: \.uuid) { other in
                        Button(other.name) {
                            Task { await viewModel.selectHost(other) }
                        }
                    }
                }
            }
            Section {
                Button("Disconnect", role: .destructive) {
                    viewModel.disconnect()
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(host.name)
                    .font(.headline)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Host Grid

    private var hostGrid: some View {
        Group {
            if viewModel.hosts.isEmpty {
                ContentUnavailableView {
                    Label("No Computers Found", systemImage: "desktopcomputer.slash")
                } description: {
                    Text("Make sure your gaming PC is on and Sunshine or GeForce Experience is running.")
                } actions: {
                    Button("Add Manually") { showingAddHost = true }
                }
            } else {
                GeometryReader { geometry in
                    ScrollView(.horizontal) {
                        HStack(spacing: 20) {
                            ForEach(viewModel.hosts, id: \.uuid) { host in
                                Button {
                                    Task { await viewModel.selectHost(host) }
                                } label: {
                                    HostCardView(host: host)
                                }
                                .buttonStyle(.plain)
                                .disabled(!host.isOnline)
                                .contextMenu {
                                    hostContextMenu(for: host)
                                }
                            }
                        }
                        .frame(maxHeight: .infinity)
                    }
                    .contentMargins(.horizontal, (geometry.size.width - 195) / 2)
                    .scrollIndicators(.hidden)
                }
            }
        }
        .sheet(isPresented: $showingAddHost) {
            AddHostView { address in
                Task { await viewModel.addHost(address: address) }
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred.")
        }
        .confirmationDialog(
            "Delete Computer?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let hostToDelete {
                    viewModel.removeHost(hostToDelete)
                }
                hostToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                hostToDelete = nil
            }
        }
        .sheet(item: $hostForInfo) { host in
            HostInfoView(host: host)
        }
        .alert("Enter PIN", isPresented: Binding(
            get: { viewModel.pairingService.isPairing && !viewModel.pairingService.isWebViewPairing },
            set: { if !$0 { viewModel.pairingService.cancelPairing() } }
        )) {
            Button("Cancel", role: .cancel) {
                viewModel.pairingService.cancelPairing()
            }
        } message: {
            Text("Enter the following PIN on your host PC:\n\(viewModel.pairingService.currentPin)")
        }
        #if !os(tvOS)
        .sheet(isPresented: $viewModel.pairingService.isWebViewPairing) {
            if let url = viewModel.pairingService.webViewURL {
                PairingWebView(url: url, onCancel: {
                    viewModel.cancelWebViewPairing()
                })
            }
        }
        #endif
    }

    // MARK: - App Grid

    @ViewBuilder
    private func appGrid(for host: Host) -> some View {
        if viewModel.loadingApps {
            ProgressView("Loading apps...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.apps.isEmpty {
            ContentUnavailableView(
                "No Apps Found",
                systemImage: "app.dashed",
                description: Text("No applications found on \(host.name).")
            )
        } else {
            GeometryReader { geometry in
                ScrollView(.horizontal) {
                    HStack(spacing: 20) {
                        ForEach(viewModel.apps, id: \.id) { app in
                            Button {
                                launchStream(app: app)
                            } label: {
                                AppCardView(app: app, hostUUID: host.uuid)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                .contentMargins(.horizontal, (geometry.size.width - 195) / 2)
                .scrollIndicators(.hidden)
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func hostContextMenu(for host: Host) -> some View {
        Button {
            viewModel.wakeHost(host)
        } label: {
            Label("Wake PC", systemImage: "sun.horizon")
        }

        Button {
            hostForInfo = host
        } label: {
            Label("Info", systemImage: "info.circle")
        }

        if host.isPaired {
            Button(role: .destructive) {
                viewModel.unpairHost(host)
            } label: {
                Label("Unpair", systemImage: "link.badge.plus")
            }
        }

        Divider()

        Button(role: .destructive) {
            hostToDelete = host
            showDeleteConfirmation = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Streaming

    private func launchStream(app: App) {
        guard let host = viewModel.selectedHost else { return }
        let settings = allSettings.first ?? StreamSettings()
        viewModel.launchApp(app, host: host, settings: settings)
    }

    @Query private var allSettings: [StreamSettings]

    // MARK: - Helpers

    private func setupAndStartDiscovery() {
        viewModel.configure(modelContext: modelContext)
        viewModel.startDiscovery()
    }
}
