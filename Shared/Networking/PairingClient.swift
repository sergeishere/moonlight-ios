import Foundation

enum PairingClient {

    /// Performs the 5-phase pairing handshake and returns the server certificate in DER format.
    /// - Parameters:
    ///   - client: HTTP client (without server cert) for phases 1-4
    ///   - httpsClientFactory: Creates an HTTPS client with the new server cert for phase 5
    ///   - pin: 4-digit PIN displayed to the user
    static func pair(
        client: MoonlightClient,
        httpsClientFactory: @Sendable (Data) -> MoonlightClient,
        pin: String
    ) async throws -> Data {
        let crypto = CryptoManager()
        guard let clientCert = CryptoManager.readCertFromFile() else {
            throw PairingError.failed("Client certificate not found")
        }

        // Phase 1: Get server certificate and derive AES key
        let salt = generateRandomBytes(count: 16)
        let phase1 = try await getServerCertificate(
            client: client,
            crypto: crypto,
            salt: salt,
            clientCert: clientCert,
            pin: pin
        )

        let ctx = PairingContext(
            client: client,
            crypto: crypto,
            aesKey: phase1.aesKey
        )

        // Phase 2: Client challenge
        let phase2 = try await performClientChallenge(context: ctx)

        // Phase 3: Challenge response and verification
        let clientSecret = generateRandomBytes(count: 16)
        try await respondToChallenge(
            context: ctx,
            challengeResult: phase2,
            clientCert: clientCert,
            clientSecret: clientSecret,
            pemBytes: phase1.pemBytes
        )

        // Phase 4: Client secret
        try await sendClientSecret(context: ctx, clientSecret: clientSecret)

        // Phase 5: Pair challenge (over HTTPS with new cert)
        try await verifyPairChallenge(
            client: client,
            httpsClientFactory: httpsClientFactory,
            derCertBytes: phase1.derCertBytes
        )

        return phase1.derCertBytes
    }

    // MARK: - Supporting Types

    private struct PairingContext {
        let client: MoonlightClient
        let crypto: CryptoManager
        let aesKey: Data
    }

    private struct ChallengeResult {
        let randomChallenge: Data
        let serverResponse: Data
        let serverChallenge: Data
    }

    // MARK: - Pairing Phases

    /// Phase 1: Exchange salt and get server certificate.
    private static func getServerCertificate(
        client: MoonlightClient,
        crypto: CryptoManager,
        salt: Data,
        clientCert: Data,
        pin: String
    ) async throws -> (pemBytes: Data, derCertBytes: Data, aesKey: Data) {
        let pairData = try await client.pairGetServerCert(salt: salt, clientCert: clientCert)
        let pairResponse = try ServerResponse<StartPairingResponse>(from: pairData)

        guard pairResponse.isStatusOk, pairResponse.content.paired == 1 else {
            throw PairingError.failed("Pairing was declined by the target.")
        }

        let plainCertHex = pairResponse.content.plainCert
        guard !plainCertHex.isEmpty else {
            throw PairingError.failed("Another pairing attempt is already in progress.")
        }

        let pemBytes = AddressUtils.hexToBytes(plainCertHex)
        guard let derCertBytes = CryptoManager.pemToDer(pemBytes) else {
            throw PairingError.failed("Failed to parse server certificate")
        }

        let saltedPIN = salt + Data(pin.utf8)
        let aesKey = crypto.createAESKeyFromSaltSHA256(saltedPIN)

        return (pemBytes, derCertBytes, aesKey)
    }

    /// Phase 2: Send client challenge and decrypt server response.
    private static func performClientChallenge(
        context: PairingContext
    ) async throws -> ChallengeResult {
        let hashLength = 32
        let randomChallenge = generateRandomBytes(count: 16)
        let encryptedChallenge = context.crypto.aesEncrypt(randomChallenge, withKey: context.aesKey)

        let challengeData = try await context.client.pairClientChallenge(encryptedChallenge)
        let challengeResponse = try ServerResponse<ServerChallengeResponse>(from: challengeData)

        guard challengeResponse.isStatusOk,
              !challengeResponse.content.challengeResponse.isEmpty else {
            throw PairingError.failed("Pairing stage #2 failed")
        }

        let encServerChallengeResp = AddressUtils.hexToBytes(
            challengeResponse.content.challengeResponse
        )
        let decServerChallengeResp = context.crypto.aesDecrypt(
            encServerChallengeResp,
            withKey: context.aesKey
        )

        let serverResponse = Data(decServerChallengeResp.prefix(hashLength))
        let serverChallenge = decServerChallengeResp.subdata(in: hashLength..<(hashLength + 16))

        return ChallengeResult(
            randomChallenge: randomChallenge,
            serverResponse: serverResponse,
            serverChallenge: serverChallenge
        )
    }

    /// Phase 3: Send challenge response and verify server signature and challenge hash.
    private static func respondToChallenge(
        context: PairingContext,
        challengeResult: ChallengeResult,
        clientCert: Data,
        clientSecret: Data,
        pemBytes: Data
    ) async throws {
        guard let certSignature = CryptoManager.getSignatureFromCert(clientCert) else {
            throw PairingError.failed("Failed to get client certificate signature")
        }

        let hashInput = challengeResult.serverChallenge + certSignature + clientSecret
        let challengeRespHash = context.crypto.sha256HashData(hashInput)
        var paddedHash = Data(challengeRespHash)
        if paddedHash.count < 32 {
            paddedHash.append(Data(count: 32 - paddedHash.count))
        }

        let encrypted = context.crypto.aesEncrypt(paddedHash, withKey: context.aesKey)
        let secretData = try await context.client.pairServerChallengeResp(encrypted)
        let secretResponse = try ServerResponse<ServerSecretResponse>(from: secretData)

        guard secretResponse.isStatusOk else {
            throw PairingError.failed("Pairing stage #3 failed")
        }

        let serverSecretResp = AddressUtils.hexToBytes(secretResponse.content.pairingSecret)
        let serverSecret = serverSecretResp.prefix(16)
        let serverSignature = serverSecretResp.subdata(in: 16..<serverSecretResp.count)

        guard context.crypto.verifySignature(
            Data(serverSecret),
            withSignature: serverSignature,
            andCert: pemBytes
        ) else {
            throw PairingError.failed("Server certificate invalid")
        }

        guard let serverCertSignature = CryptoManager.getSignatureFromCert(pemBytes) else {
            throw PairingError.failed("Failed to get server certificate signature")
        }

        let verifyInput = challengeResult.randomChallenge + serverCertSignature + serverSecret
        let serverChallengeRespHash = context.crypto.sha256HashData(verifyInput)

        guard serverChallengeRespHash == challengeResult.serverResponse else {
            throw PairingError.failed("Incorrect PIN")
        }
    }

    /// Phase 4: Sign and send the client secret.
    private static func sendClientSecret(
        context: PairingContext,
        clientSecret: Data
    ) async throws {
        guard let keyData = CryptoManager.readKeyFromFile(),
              let signedSecret = context.crypto.signData(clientSecret, withKey: keyData) else {
            throw PairingError.failed("Failed to sign client secret")
        }

        let clientPairingSecret = clientSecret + signedSecret
        let clientSecretHex = AddressUtils.bytesToHex(clientPairingSecret)

        let clientSecretData = try await context.client.pairClientSecret(clientSecretHex)
        let clientSecretResp = try ServerResponse<PairChallengeResponse>(from: clientSecretData)

        guard clientSecretResp.isStatusOk, clientSecretResp.content.paired == 1 else {
            throw PairingError.failed("Pairing stage #4 failed")
        }
    }

    /// Phase 5: Verify the pairing over HTTPS using the new server certificate.
    private static func verifyPairChallenge(
        client: MoonlightClient,
        httpsClientFactory: @Sendable (Data) -> MoonlightClient,
        derCertBytes: Data
    ) async throws {
        let httpsClient = httpsClientFactory(derCertBytes)
        do {
            let pairChallengeData = try await httpsClient.pairChallenge()
            let pairChallengeResp = try ServerResponse<PairChallengeResponse>(
                from: pairChallengeData
            )

            guard pairChallengeResp.isStatusOk, pairChallengeResp.content.paired == 1 else {
                throw PairingError.failed("Pairing stage #5 failed")
            }
        } catch {
            try? await client.unpair()
            throw error
        }
    }

    static func generatePin() -> String {
        String(format: "%d%d%d%d",
               Int.random(in: 0...9),
               Int.random(in: 0...9),
               Int.random(in: 0...9),
               Int.random(in: 0...9))
    }

    private static func generateRandomBytes(count: Int) -> Data {
        var bytes = Data(count: count)
        bytes.withUnsafeMutableBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return }
            _ = SecRandomCopyBytes(kSecRandomDefault, count, baseAddress)
        }
        return bytes
    }
}
