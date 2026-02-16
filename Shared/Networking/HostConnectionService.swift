import Foundation

final class HostConnectionService: Sendable {

    @MainActor
    func fetchServerInfo(for host: Host) async -> Bool {
        let client = MoonlightClient(host: host)

        do {
            let serverInfo = try await client.getServerInfo()
            host.updateFromServerInfo(serverInfo)
            return true
        } catch {
            host.state = HostState.offline.rawValue
            return false
        }
    }

    @MainActor
    func fetchAppList(for host: Host) async -> [AppInfo] {
        let client = MoonlightClient(host: host)

        do {
            return try await client.getAppList()
        } catch {
            return []
        }
    }

    @MainActor
    func quitApp(on host: Host) async -> Bool {
        let client = MoonlightClient(host: host)

        do {
            try await client.quitApp()
            return true
        } catch {
            return false
        }
    }
}
