import Foundation
import Security
import os

private let log = Logger(subsystem: "com.moonlight", category: "SSL")

final class SSLPinningDelegate: NSObject, URLSessionDelegate, Sendable {

    private let serverCertData: Data?

    init(serverCert: Data?) {
        self.serverCertData = serverCert
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {

        let authMethod = challenge.protectionSpace.authenticationMethod

        if authMethod == NSURLAuthenticationMethodServerTrust {
            return handleServerTrust(challenge)
        } else if authMethod == NSURLAuthenticationMethodClientCertificate {
            return handleClientCertificate()
        }

        return (.performDefaultHandling, nil)
    }

    // MARK: - Server Trust

    private func handleServerTrust(
        _ challenge: URLAuthenticationChallenge
    ) -> (URLSession.AuthChallengeDisposition, URLCredential?) {

        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            return (.performDefaultHandling, nil)
        }

        guard let certData = serverCertData else {
            // No pinned cert — allow for HTTP-only or pre-pairing requests
            return (.performDefaultHandling, nil)
        }

        // Use modern API: SecTrustCopyCertificateChain (replaces deprecated SecTrustGetCertificateAtIndex)
        guard let certChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
              let firstCert = certChain.first else {
            return (.performDefaultHandling, nil)
        }

        let actualCertData = SecCertificateCopyData(firstCert) as Data
        guard actualCertData == certData else {
            return (.performDefaultHandling, nil)
        }

        return (.useCredential, URLCredential(trust: serverTrust))
    }

    // MARK: - Client Certificate

    private func handleClientCertificate() -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard let identity = CryptoManager.getIdentityFromKeychain() else {
            log.error("No client identity in keychain")
            return (.cancelAuthenticationChallenge, nil)
        }
        return makeClientCredential(identity: identity)
    }

    private func makeClientCredential(
        identity: SecIdentity
    ) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        var certificate: SecCertificate?
        SecIdentityCopyCertificate(identity, &certificate)

        let certs = certificate.map { [$0 as Any] } ?? []
        let credential = URLCredential(
            identity: identity,
            certificates: certs,
            persistence: .permanent
        )
        return (.useCredential, credential)
    }
}
