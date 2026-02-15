import Foundation

@Observable
@MainActor
final class PairingService {
    var isPairing = false
    var currentPin = ""
    var isWebViewPairing = false
    var webViewURL: URL?

    func pair(host: Host) async throws -> Data {
        // Check if already paired
        let preClient = MoonlightClient(host: host)
        do {
            let serverInfo = try await preClient.getServerInfo()
            if serverInfo.isPaired {
                throw PairingError.alreadyPaired
            }
        } catch let error as PairingError {
            throw error
        } catch {
            // Continue with pairing even if serverInfo check fails
        }

        #if os(tvOS)
        return try await pairWithPin(host: host)
        #else
        if host.isAstrumServer {
            return try await pairWithWebView(host: host)
        } else {
            return try await pairWithPin(host: host)
        }
        #endif
    }

    func cancelPairing() {
        isPairing = false
        isWebViewPairing = false
        webViewURL = nil
        currentPin = ""
    }

    // MARK: - PIN Pairing (standard Sunshine/GFE)

    private func pairWithPin(host: Host) async throws -> Data {
        let pin = PairingClient.generatePin()
        isPairing = true
        currentPin = pin

        defer {
            isPairing = false
            currentPin = ""
        }

        return try await performPairingHandshake(host: host, pin: pin)
    }

    // MARK: - WebView Pairing (Astrum servers)

    private func pairWithWebView(host: Host) async throws -> Data {
        let pin = PairingClient.generatePin()

        let (address, port) = host.bestAddress.map { AddressUtils.parseAddressAndPort($0) } ?? ("", 47989)
        let configPort = port + 1

        guard let url = URL(string: "https://\(address):\(configPort)/pair-webview#pin=\(pin)") else {
            throw PairingError.failed("Failed to construct WebView pairing URL")
        }

        isWebViewPairing = true
        webViewURL = url

        defer {
            isWebViewPairing = false
            webViewURL = nil
        }

        return try await performPairingHandshake(host: host, pin: pin)
    }

    // MARK: - Shared Handshake

    private func performPairingHandshake(host: Host, pin: String) async throws -> Data {
        let (address, port) = host.bestAddress.map { AddressUtils.parseAddressAndPort($0) } ?? ("", 47989)
        let httpsPort = host.httpsPort != 0 ? host.httpsPort : 47984

        let pairingClient = MoonlightClient(
            address: address,
            port: port,
            httpsPort: httpsPort,
            serverCert: nil
        )

        let serverCert = try await PairingClient.pair(
            client: pairingClient,
            httpsClientFactory: { cert in
                MoonlightClient(
                    address: address,
                    port: port,
                    httpsPort: httpsPort,
                    serverCert: cert
                )
            },
            pin: pin
        )

        return serverCert
    }
}

enum PairingError: LocalizedError {
    case failed(String)
    case cancelled
    case alreadyPaired

    var errorDescription: String? {
        switch self {
        case .failed(let message): message
        case .cancelled: "Pairing cancelled"
        case .alreadyPaired: "Already paired"
        }
    }
}
