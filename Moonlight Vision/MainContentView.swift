//

import SwiftUI
import os.log

struct MainContentView: View {
    
    @EnvironmentObject private var viewModel: MainViewModel
    
    @State private var selectedHost: TemporaryHost?
    
    @State private var addingHost = false
    @State private var isDeletingHost = false
    @State private var hostToDelete: TemporaryHost?
    @State private var newHostIp = ""
    
    var body: some View {
        TabView {
            splitView()
                .tabItem {
                    Label("Computers", systemImage: "desktopcomputer")
                }
                .task {
                    viewModel.loadSavedHosts()
                }
                .onAppear {
                    NotificationCenter.default.addObserver(
                        self,
                        selector: #selector(viewModel.beginRefresh),
                        name: UIApplication.didBecomeActiveNotification,
                        object: nil
                    )
                    viewModel.beginRefresh()
                }
                .onDisappear {
                    viewModel.stopRefresh()
                    NotificationCenter.default.removeObserver(self)
                }
            
            SettingsView(settings: $viewModel.streamSettings).tabItem {
                Label("Settings", systemImage: "gear")
            }
        }
    }
    
    private func splitView() -> some View {
        NavigationSplitView {
            List(viewModel.hosts, selection: $selectedHost) { host in
                NavigationLink(value: host) {
                    hostRow(for: host)
                }
            }
            .navigationTitle("Computers")
            .alert("Really delete?", isPresented: $isDeletingHost) {
                Button("Yes, delete it", role: .destructive) {
                    if let hostToDelete {
                        viewModel.removeHost(hostToDelete)
                        selectedHost = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    isDeletingHost = false
                    hostToDelete = nil
                }
            }
            .onChange(of: viewModel.hosts) {
                // If the hosts list changes and no host is selected,
                // try to select the first paired host automatically.
                if selectedHost == nil,
                   let firstHost = viewModel.hosts.first(where: { $0.pairState == .paired })
                {
                    selectedHost = firstHost
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Server", systemImage: "plus") {
                        addingHost = true
                    }.alert(
                        "Enter server",
                        isPresented: $addingHost
                    ) {
                        TextField("IP or Host", text: $newHostIp)
                        Button("Add") {
                            addingHost = false
                            viewModel.manuallyDiscoverHost(hostOrIp: newHostIp)
                        }
                        Button("Cancel", role: .cancel) {
                            addingHost = false
                        }
                    }.alert(
                        "Unable to add host",
                        isPresented: $viewModel.errorAddingHost
                    ) {
                        Button("Ok", role: .cancel) {
                            viewModel.errorAddingHost = true
                        }
                    } message: {
                        Text(viewModel.addHostErrorMessage)
                    }
                }
            }
        } detail: {
            if let selectedHost {
                ComputerView(host: selectedHost)
            }
        }
    }
    
    private func hostRow(for host: TemporaryHost) -> some View {
        VStack {
            Label(host.name,
                  systemImage: host.pairState == .paired ?
                  "desktopcomputer" : "lock.desktopcomputer")
            .foregroundColor(.primary)
        }.contextMenu {
            Button {
                viewModel.wakeHost(host)
            } label: {
                Label("Wake PC", systemImage: "sun.horizon")
            }
            Button(role: .destructive) {
                isDeletingHost = true
                hostToDelete = host
            } label: {
                Label("Delete PC", systemImage: "trash")
            }
        }
    }
}

#Preview {
    MainContentView().environmentObject(MainViewModel())
}
