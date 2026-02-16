import Foundation
import os

private let log = Logger(subsystem: "com.moonlight", category: "HostConnection")

final class HostConnectionService: Sendable {

    enum FetchResult {
        case success([AppInfo])
        case authFailure
        case error
    }

    @MainActor
    func fetchServerInfo(for host: Host) async -> Bool {
        let client = MoonlightClient(host: host)

        do {
            let serverInfo = try await client.getServerInfo()
            host.updateFromServerInfo(serverInfo)
            return true
        } catch {
            if case ServerResponseError.serverError(let code, _) = error, code == 401 {
                log.error("fetchServerInfo auth failed (401) for \(host.name)")
                host.serverCert = nil
                host.pairState = PairState.unpaired.rawValue
            }
            host.state = HostState.offline.rawValue
            return false
        }
    }

    @MainActor
    func fetchAppList(for host: Host) async -> FetchResult {
        let client = MoonlightClient(host: host)

        do {
            let apps = try await client.getAppList()
            return .success(apps)
        } catch let error as ServerResponseError {
            if case .serverError(let code, _) = error, code == 401 {
                log.error("App list auth failed (401) — host needs re-pairing")
                return .authFailure
            }
            log.error("App list fetch failed: \(error.localizedDescription)")
            return .error
        } catch {
            log.error("App list fetch failed: \(error.localizedDescription)")
            return .error
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
