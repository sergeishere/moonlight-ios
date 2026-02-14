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

    /// Starts polling a host by trying each known address.
    /// Stops automatically after `maxConsecutiveFailures` consecutive failures.
    func startPolling(
        addresses: [String],
        serverCert: Data?,
        onResult: @MainActor @Sendable @escaping (PollResult) -> Void,
        onStoppedByFailures: @MainActor @Sendable @escaping () -> Void
    ) {
        stopPolling()

        pollingTask = Task { [addresses, serverCert] in
            var consecutiveFailures = 0

            while !Task.isCancelled {
                if let result = await Self.poll(
                    addresses: addresses,
                    serverCert: serverCert
                ) {
                    consecutiveFailures = 0
                    await onResult(result)
                } else {
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
        serverCert: Data?
    ) async -> PollResult? {
        // Sort: LAN addresses first for fastest response
        let sorted = addresses.sorted { lhs, _ in
            AddressUtils.isLANAddress(lhs)
        }

        for address in sorted {
            if Task.isCancelled { return nil }

            let (addr, port) = AddressUtils.parseAddressAndPort(address)
            let isLAN = AddressUtils.isLANAddress(address)
            let timeout = isLAN ? MoonlightClient.lanTimeout : MoonlightClient.wanTimeout

            let client = MoonlightClient(
                address: addr,
                port: port,
                httpsPort: 0,
                serverCert: serverCert
            )

            let start = ContinuousClock.now
            do {
                let serverInfo = try await client.getServerInfo(timeout: timeout)
                let elapsed = ContinuousClock.now - start
                let net = isLAN ? "LAN" : "WAN"
                log.debug("Poll \(address) [\(net) \(timeout, format: .fixed(precision: 1))s] -> OK in \(elapsed)")
                return PollResult(serverInfo: serverInfo, activeAddress: address)
            } catch {
                let elapsed = ContinuousClock.now - start
                log.debug(
                    "Poll \(address) [\(isLAN ? "LAN" : "WAN")] -> FAIL in \(elapsed): \(error.localizedDescription)"
                )
                continue
            }
        }

        return nil
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
}
