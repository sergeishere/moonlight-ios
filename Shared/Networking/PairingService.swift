import Foundation

@Observable
@MainActor
final class PairingService {
    var isPairing = false
    var currentPin = ""

    func pair(host: Host) async throws -> Data {
        let pin = PairingClient.generatePin()
        isPairing = true
        currentPin = pin

        defer {
            isPairing = false
            currentPin = ""
        }

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

        let (address, port) = host.bestAddress.map { AddressUtils.parseAddressAndPort($0) } ?? ("", 47989)
        let httpsPort = host.httpsPort != 0 ? host.httpsPort : 47984

        // HTTP client for phases 1-4 (no server cert)
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

    func cancelPairing() {
        isPairing = false
        currentPin = ""
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
