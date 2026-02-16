import Foundation
import os

private let log = Logger(subsystem: "com.moonlight-stream", category: "Poller")

actor HostPoller {

    private static let pollInterval: Duration = .seconds(3)
    private static let maxConsecutiveFailures = 5

    private var pollingTask: Task<Void, Never>?

    struct PollResult: Sendable {
        let serverInfo: ServerInfo
        let activeAddress: String
    }

    enum PollOutcome: Sendable {
        case success(PollResult)
        case authFailure
        case unreachable
    }

    /// Starts polling a host by trying each known address.
    /// Stops automatically after `maxConsecutiveFailures` consecutive failures.
    func startPolling(
        addresses: [String],
        httpsPort: UInt16,
        serverCert: Data?,
        onResult: @MainActor @Sendable @escaping (PollResult) -> Void,
        onAuthFailure: @MainActor @Sendable @escaping () -> Void,
        onStoppedByFailures: @MainActor @Sendable @escaping () -> Void
    ) {
        stopPolling()

        pollingTask = Task { [addresses, httpsPort, serverCert] in
            var consecutiveFailures = 0

            while !Task.isCancelled {
                let outcome = await Self.poll(
                    addresses: addresses,
                    httpsPort: httpsPort,
                    serverCert: serverCert
                )

                switch outcome {
                case .success(let result):
                    consecutiveFailures = 0
                    await onResult(result)
                case .authFailure:
                    log.error("Auth failure — stopping poller")
                    await onAuthFailure()
                    return
                case .unreachable:
                    consecutiveFailures += 1
                    if consecutiveFailures >= Self.maxConsecutiveFailures {
                        log.info("Poller stopped: \(Self.maxConsecutiveFailures) consecutive failures")
                        await onStoppedByFailures()
                        return
                    }
                }

                guard !Task.isCancelled else { break }

                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Performs a single poll attempt across all addresses.
    /// Tries LAN addresses first (fast timeout), then WAN.
    static func poll(
        addresses: [String],
        httpsPort: UInt16 = 0,
        serverCert: Data?
    ) async -> PollOutcome {
        // Sort: LAN addresses first for fastest response
        let sorted = addresses.sorted { lhs, _ in
            AddressUtils.isLANAddress(lhs)
        }

        var hadAuthFailure = false

        for address in sorted {
            if Task.isCancelled { return .unreachable }

            let (addr, port) = AddressUtils.parseAddressAndPort(address)
            let isLAN = AddressUtils.isLANAddress(address)
            let timeout = isLAN ? MoonlightClient.lanTimeout : MoonlightClient.wanTimeout

            let client = MoonlightClient(
                address: addr,
                port: port,
                httpsPort: httpsPort,
                serverCert: serverCert
            )

            let start = ContinuousClock.now
            do {
                let serverInfo = try await client.getServerInfo(timeout: timeout)
                let elapsed = ContinuousClock.now - start
                let net = isLAN ? "LAN" : "WAN"
                log.debug("Poll \(address) [\(net) \(timeout, format: .fixed(precision: 1))s] -> OK in \(elapsed)")
                return .success(PollResult(serverInfo: serverInfo, activeAddress: address))
            } catch {
                let elapsed = ContinuousClock.now - start
                log.debug(
                    "Poll \(address) [\(isLAN ? "LAN" : "WAN")] -> FAIL in \(elapsed): \(error.localizedDescription)"
                )
                if isAuthFailure(error) {
                    hadAuthFailure = true
                }
                continue
            }
        }

        return hadAuthFailure ? .authFailure : .unreachable
    }

    /// Single poll attempt (for initial check or manual add).
    static func discoverOnce(address: String) async throws -> (ServerInfo, String) {
        let (addr, port) = AddressUtils.parseAddressAndPort(address)
        let client = MoonlightClient(
            address: addr,
            port: port,
            httpsPort: 0,
            serverCert: nil
        )

        let serverInfo = try await client.getServerInfo()
        return (serverInfo, address)
    }

    private static func isAuthFailure(_ error: Error) -> Bool {
        if case ServerResponseError.serverError(let code, _) = error, code == 401 {
            return true
        }
        return false
    }
}
