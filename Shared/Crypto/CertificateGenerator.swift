import Foundation
import Security
import X509
import SwiftASN1
import Crypto
import _CryptoExtras

enum CertificateGenerator {

    private static let keychainKeyTag = "com.moonlight-stream.client-key"
    private static let keychainCertLabel = "com.moonlight-stream.client-cert"

    struct GeneratedCredentials {
        let certificatePEM: Data
        let privateKeyPEM: Data
    }

    /// Generate RSA-2048 key pair and self-signed X.509 certificate.
    /// Saves PEM files via CryptoManager storage and stores in Keychain.
    static func generate() throws -> GeneratedCredentials {
        // 1. Generate RSA-2048 key
        let privateKey = try _RSA.Signing.PrivateKey(keySize: .bits2048)

        // 2. Create self-signed X.509 certificate
        let name = try DistinguishedName {
            CommonName("NVIDIA GameStream Client")
        }
        let now = Date()
        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(0),
            publicKey: .init(privateKey.publicKey),
            notValidBefore: now,
            notValidAfter: now.addingTimeInterval(20 * 365.25 * 24 * 3600),
            issuer: name,
            subject: name,
            signatureAlgorithm: .sha256WithRSAEncryption,
            extensions: Certificate.Extensions {},
            issuerPrivateKey: .init(privateKey)
        )

        // 3. Serialize certificate to DER then PEM
        var certSerializer = DER.Serializer()
        try certificate.serialize(into: &certSerializer)
        let certDER = Data(certSerializer.serializedBytes)

        let certBase64 = certDER.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        let certPEM = "-----BEGIN CERTIFICATE-----\n\(certBase64)\n-----END CERTIFICATE-----\n"
        let certPEMData = Data(certPEM.utf8)

        // 4. Serialize private key to DER then PEM
        let keyDER = privateKey.derRepresentation
        let keyBase64 = keyDER.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        let keyPEM = "-----BEGIN RSA PRIVATE KEY-----\n\(keyBase64)\n-----END RSA PRIVATE KEY-----\n"
        let keyPEMData = Data(keyPEM.utf8)

        // 5. Store in Keychain for TLS client authentication
        try storeInKeychain(certDER: certDER, keyDER: keyDER)

        return GeneratedCredentials(
            certificatePEM: certPEMData,
            privateKeyPEM: keyPEMData
        )
    }

    /// Store certificate + private key in the Keychain so SecIdentity can be obtained.
    private static func storeInKeychain(certDER: Data, keyDER: Data) throws {
        // Remove any existing items first
        removeFromKeychain()

        // Import the private key into Keychain
        let keyAttrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 2048
        ]

        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(keyDER as CFData, keyAttrs as CFDictionary, &error) else {
            if let cfError = error?.takeRetainedValue() {
                throw cfError
            }
            throw NSError(domain: "CertificateGenerator", code: -1)
        }

        let addKeyQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrApplicationTag as String: Data(keychainKeyTag.utf8),
            kSecValueRef as String: secKey,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let keyStatus = SecItemAdd(addKeyQuery as CFDictionary, nil)
        guard keyStatus == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(keyStatus))
        }

        // Import the certificate into Keychain
        guard let secCert = SecCertificateCreateWithData(nil, certDER as CFData) else {
            throw NSError(
                domain: "CertificateGenerator",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create SecCertificate"]
            )
        }

        let addCertQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: secCert,
            kSecAttrLabel as String: keychainCertLabel,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let certStatus = SecItemAdd(addCertQuery as CFDictionary, nil)
        guard certStatus == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(certStatus))
        }
    }

    /// Remove existing identity from Keychain.
    static func removeFromKeychain() {
        let deleteKeyQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: Data(keychainKeyTag.utf8)
        ]
        SecItemDelete(deleteKeyQuery as CFDictionary)

        let deleteCertQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: keychainCertLabel
        ]
        SecItemDelete(deleteCertQuery as CFDictionary)
    }

    /// Retrieve SecIdentity from Keychain.
    /// Returns nil if not found.
    static func getIdentityFromKeychain() -> SecIdentity? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrApplicationTag as String: Data(keychainKeyTag.utf8),
            kSecReturnRef as String: true
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let ref = result else { return nil }
        // CF types don't support conditional cast; API guarantees SecIdentity here
        // swiftlint:disable:next force_cast
        return (ref as! SecIdentity)
    }

    /// Migrate existing PKCS12 file data into Keychain.
    /// Used for backward compatibility with existing installations.
    static func migratePKCS12ToKeychain(_ p12Data: Data, password: String = "limelight") -> Bool {
        let options: [String: Any] = [kSecImportExportPassphrase as String: password]
        var items: CFArray?
        let status = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &items)

        guard status == errSecSuccess,
              let array = items as? [[String: Any]],
              let first = array.first else {
            return false
        }

        // The import already stores items in the Keychain,
        // but we need to tag them for later retrieval
        if let identity = first[kSecImportItemIdentity as String] {
            // CF types don't support conditional cast; API guarantees SecIdentity here
            // swiftlint:disable:next force_cast
            let secIdentity = identity as! SecIdentity

            // Extract the private key and re-add with our tag
            var privateKey: SecKey?
            if SecIdentityCopyPrivateKey(secIdentity, &privateKey) == errSecSuccess,
               let key = privateKey {
                let addKeyQuery: [String: Any] = [
                    kSecClass as String: kSecClassKey,
                    kSecAttrApplicationTag as String: Data(keychainKeyTag.utf8),
                    kSecValueRef as String: key,
                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
                ]
                SecItemDelete(addKeyQuery as CFDictionary)
                SecItemAdd(addKeyQuery as CFDictionary, nil)
            }

            // Extract the certificate and re-add with our label
            var certificate: SecCertificate?
            if SecIdentityCopyCertificate(secIdentity, &certificate) == errSecSuccess,
               let cert = certificate {
                let addCertQuery: [String: Any] = [
                    kSecClass as String: kSecClassCertificate,
                    kSecValueRef as String: cert,
                    kSecAttrLabel as String: keychainCertLabel,
                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
                ]
                SecItemDelete(addCertQuery as CFDictionary)
                SecItemAdd(addCertQuery as CFDictionary, nil)
            }

            return true
        }

        return false
    }
}
