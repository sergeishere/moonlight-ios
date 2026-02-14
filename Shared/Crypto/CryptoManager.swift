import Foundation
import CryptoKit
import CommonCrypto
import Security
import SwiftASN1

@objc class CryptoManager: NSObject {

    // MARK: - Key Pair Generation

    @objc static func generateKeyPairUsingSSL() {
        struct Once { nonisolated(unsafe) static var token = false }
        guard !Once.token else { return }
        Once.token = true

        guard !keyPairExists() else { return }

        Log.log("Generating Certificate... ", level: .info)
        do {
            let credentials = try CertificateGenerator.generate()

            writeCryptoObject("client.crt", data: credentials.certificatePEM)
            writeCryptoObject("client.key", data: credentials.privateKeyPEM)
            // No PKCS12 needed — identity stored in Keychain

            Log.log("Certificate created", level: .info)
        } catch {
            Log.log("Certificate generation failed: \(error)", level: .error)
        }
    }

    // MARK: - File I/O

    @objc static func readCertFromFile() -> Data? {
        return readCryptoObject("client.crt")
    }

    @objc static func readKeyFromFile() -> Data? {
        return readCryptoObject("client.key")
    }

    @objc static func readP12FromFile() -> Data? {
        return readCryptoObject("client.p12")
    }

    // MARK: - Hashing

    @objc func createAESKeyFromSaltSHA1(_ saltedPIN: Data) -> Data {
        return sha1HashData(saltedPIN).prefix(16)
    }

    @objc func createAESKeyFromSaltSHA256(_ saltedPIN: Data) -> Data {
        return sha256HashData(saltedPIN).prefix(16)
    }

    @objc(SHA1HashData:)
    func sha1HashData(_ data: Data) -> Data {
        let digest = Insecure.SHA1.hash(data: data)
        return Data(digest)
    }

    @objc(SHA256HashData:)
    func sha256HashData(_ data: Data) -> Data {
        let digest = SHA256.hash(data: data)
        return Data(digest)
    }

    // MARK: - AES-128-ECB Encrypt/Decrypt

    @objc func aesEncrypt(_ data: Data, withKey key: Data) -> Data {
        return aesECB(data, key: key, operation: CCOperation(kCCEncrypt))
    }

    @objc func aesDecrypt(_ data: Data, withKey key: Data) -> Data {
        return aesECB(data, key: key, operation: CCOperation(kCCDecrypt))
    }

    private func aesECB(_ data: Data, key: Data, operation: CCOperation) -> Data {
        var outLength: size_t = 0
        var outData = Data(count: data.count)

        let status = outData.withUnsafeMutableBytes { outPtr in
            data.withUnsafeBytes { inPtr in
                key.withUnsafeBytes { keyPtr in
                    guard let keyBase = keyPtr.baseAddress,
                          let inBase = inPtr.baseAddress,
                          let outBase = outPtr.baseAddress else {
                        return CCCryptorStatus(kCCParamError)
                    }
                    return CCCrypt(
                        operation,
                        CCAlgorithm(kCCAlgorithmAES128),
                        CCOptions(kCCOptionECBMode),
                        keyBase,
                        key.count,
                        nil,
                        inBase,
                        data.count,
                        outBase,
                        data.count,
                        &outLength
                    )
                }
            }
        }

        assert(status == kCCSuccess)
        assert(outLength == data.count)
        return outData
    }

    // MARK: - PEM to DER conversion

    @objc static func pemToDer(_ pemCertBytes: Data) -> Data? {
        guard let pemString = String(data: pemCertBytes, encoding: .utf8) else {
            return nil
        }

        // Strip PEM headers and decode base64
        let lines = pemString.components(separatedBy: "\n")
        let base64Lines = lines.filter { line in
            !line.hasPrefix("-----") && !line.isEmpty
        }
        let base64String = base64Lines.joined()

        return Data(base64Encoded: base64String)
    }

    // MARK: - Signature extraction from X.509 certificate

    @objc static func getSignatureFromCert(_ cert: Data) -> Data? {
        // cert is PEM — convert to DER first
        guard let derData = pemToDer(cert) else {
            Log.log("Unable to convert PEM to DER", level: .error)
            return nil
        }

        return extractSignatureFromDER(derData)
    }

    /// Parse X.509 DER certificate and extract the signatureValue field.
    /// X.509 structure: SEQUENCE { tbsCertificate, signatureAlgorithm, signatureValue BIT STRING }
    private static func extractSignatureFromDER(_ derData: Data) -> Data? {
        do {
            let node = try DER.parse(Array(derData))

            // X.509 is a SEQUENCE of 3 elements
            let sequence = node.sequence ?? []
            guard sequence.count >= 3 else {
                Log.log("Invalid X.509 structure", level: .error)
                return nil
            }

            // The third element is the signatureValue (BIT STRING)
            let signatureNode = sequence[2]
            guard let bitStringBytes = signatureNode.bitString else {
                Log.log("Failed to parse signatureValue as BIT STRING", level: .error)
                return nil
            }

            return Data(bitStringBytes.bytes)
        } catch {
            Log.log("Failed to parse DER: \(error)", level: .error)
            return nil
        }
    }

    // MARK: - Signature Verification

    @objc func verifySignature(_ data: Data, withSignature signature: Data, andCert cert: Data) -> Bool {
        // cert is PEM
        guard let derCert = Self.pemToDer(cert) else {
            Log.log("Unable to parse certificate for verification", level: .error)
            return false
        }

        guard let secCert = SecCertificateCreateWithData(nil, derCert as CFData) else {
            Log.log("Unable to create SecCertificate", level: .error)
            return false
        }

        guard let pubKey = SecCertificateCopyKey(secCert) else {
            Log.log("Unable to extract public key from certificate", level: .error)
            return false
        }

        var error: Unmanaged<CFError>?
        let result = SecKeyVerifySignature(
            pubKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            data as CFData,
            signature as CFData,
            &error
        )

        if !result {
            Log.log("Signature verification failed: \(error?.takeRetainedValue().localizedDescription ?? "unknown")", level: .error)
        }

        return result
    }

    // MARK: - Signing

    @objc func signData(_ data: Data, withKey key: Data) -> Data? {
        // key is PEM
        guard let secKey = Self.pemKeyToSecKey(key) else {
            Log.log("Unable to parse private key for signing", level: .error)
            return nil
        }

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            secKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            data as CFData,
            &error
        ) else {
            Log.log("Signing failed: \(error?.takeRetainedValue().localizedDescription ?? "unknown")", level: .error)
            return nil
        }

        return signature as Data
    }

    // MARK: - Private Helpers

    private static func pemKeyToSecKey(_ pemData: Data) -> SecKey? {
        guard let pemString = String(data: pemData, encoding: .utf8) else {
            return nil
        }

        let lines = pemString.components(separatedBy: "\n")
        let base64Lines = lines.filter { line in
            !line.hasPrefix("-----") && !line.isEmpty
        }
        let base64String = base64Lines.joined()

        guard let derData = Data(base64Encoded: base64String) else {
            return nil
        }

        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 2048
        ]

        var error: Unmanaged<CFError>?
        return SecKeyCreateWithData(derData as CFData, attrs as CFDictionary, &error)
    }

    // MARK: - Keychain Identity (for Obj-C access)

    @objc static func getIdentityFromKeychain() -> SecIdentity? {
        return CertificateGenerator.getIdentityFromKeychain()
    }

    @objc static func migratePKCS12ToKeychain(_ p12Data: Data, password: String) -> Bool {
        return CertificateGenerator.migratePKCS12ToKeychain(p12Data, password: password)
    }

    // MARK: - Internal Helpers

    private static func keyPairExists() -> Bool {
        let keyExists = readCryptoObject("client.key") != nil
        let certExists = readCryptoObject("client.crt") != nil
        // Also check Keychain
        let keychainExists = CertificateGenerator.getIdentityFromKeychain() != nil
        return (keyExists && certExists) || keychainExists
    }

    private static func readCryptoObject(_ item: String) -> Data? {
        #if os(tvOS)
        return UserDefaults.standard.data(forKey: item)
        #else
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        let documentsDirectory = paths[0]
        let file = (documentsDirectory as NSString).appendingPathComponent(item)
        return try? Data(contentsOf: URL(fileURLWithPath: file))
        #endif
    }

    private static func writeCryptoObject(_ item: String, data: Data) {
        #if os(tvOS)
        UserDefaults.standard.set(data, forKey: item)
        #else
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        let documentsDirectory = paths[0]
        let file = (documentsDirectory as NSString).appendingPathComponent(item)
        try? data.write(to: URL(fileURLWithPath: file), options: .atomic)
        #endif
    }
}

// MARK: - DER Parsing Helpers

private extension ASN1Node {
    /// Attempt to parse this node as a SEQUENCE, returning child nodes.
    var sequence: [ASN1Node]? {
        guard case .constructed(let nodes) = self.content else {
            return nil
        }
        return Array(nodes)
    }

    /// Attempt to parse this node as a BIT STRING.
    var bitString: ASN1BitString? {
        return try? ASN1BitString(derEncoded: self)
    }
}

// MARK: - Logging Bridge

private enum Log {
    enum Level: String {
        case info = "I"
        case error = "E"
        case warning = "W"
    }

    static func log(_ message: String, level: Level) {
        NSLog("[%@] %@", level.rawValue, message)
    }
}
