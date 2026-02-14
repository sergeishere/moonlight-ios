import Foundation

final class MoonlightClient: Sendable {

    private let baseHTTPURL: String
    private let baseHTTPSURL: String?
    private let uniqueId: String
    private let deviceName: String
    private let session: URLSession
    private let sslDelegate: SSLPinningDelegate

    static let lanTimeout: TimeInterval = 0.5
    static let wanTimeout: TimeInterval = 2
    static let normalTimeout: TimeInterval = 5
    private static let longTimeout: TimeInterval = 60
    private static let extraLongTimeout: TimeInterval = 180

    init(address: String, port: UInt16, httpsPort: UInt16, serverCert: Data?) {
        let urlSafe = AddressUtils.urlSafeAddress(address)
        self.baseHTTPURL = "http://\(urlSafe):\(port)"
        if httpsPort != 0 {
            self.baseHTTPSURL = "https://\(urlSafe):\(httpsPort)"
        } else {
            self.baseHTTPSURL = nil
        }
        self.uniqueId = IdManager.getUniqueId()
        self.deviceName = "roth"
        self.sslDelegate = SSLPinningDelegate(serverCert: serverCert)
        self.session = URLSession(
            configuration: .ephemeral,
            delegate: sslDelegate,
            delegateQueue: nil
        )
    }

    convenience init(host: Host) {
        let (address, port) = host.bestAddress.map { AddressUtils.parseAddressAndPort($0) } ?? ("", 47989)
        self.init(
            address: address,
            port: port,
            httpsPort: host.httpsPort,
            serverCert: host.serverCert
        )
    }

    deinit {
        session.invalidateAndCancel()
    }

    // MARK: - Server Info

    func getServerInfo(timeout: TimeInterval? = nil) async throws -> ServerInfo {
        let timeout = timeout ?? Self.normalTimeout

        // Try HTTPS first if available, then fall back to HTTP
        if let httpsURL = baseHTTPSURL {
            let url = "\(httpsURL)/serverinfo?uniqueid=\(uniqueId)"
            do {
                return try await fetchAndDecode(url: url, timeout: timeout)
            } catch {
                // Fall back to HTTP on certificate trust failure
                if (error as NSError).code == NSURLErrorServerCertificateUntrusted {
                    let httpURL = "\(baseHTTPURL)/serverinfo?uniqueid=\(uniqueId)"
                    return try await fetchAndDecode(url: httpURL, timeout: timeout)
                }
                throw error
            }
        }

        // HTTP-only (pre-pairing)
        let url = "\(baseHTTPURL)/serverinfo?uniqueid=\(uniqueId)"
        return try await fetchAndDecode(url: url, timeout: timeout)
    }

    // MARK: - App List

    func getAppList() async throws -> [AppInfo] {
        guard let httpsURL = baseHTTPSURL else {
            throw MoonlightClientError.httpsNotAvailable
        }

        let url = "\(httpsURL)/applist?uniqueid=\(uniqueId)"

        // Retry up to 5 times
        var lastError: Error?
        for attempt in 0..<5 {
            do {
                let apps: [AppInfo] = try await fetchAndDecode(url: url, timeout: Self.normalTimeout)
                return apps
            } catch {
                lastError = error
                if attempt < 4 {
                    try await Task.sleep(for: .seconds(1))
                }
            }
        }
        throw lastError ?? MoonlightClientError.unknown
    }

    // MARK: - Quit App

    func quitApp() async throws {
        guard let httpsURL = baseHTTPSURL else {
            throw MoonlightClientError.httpsNotAvailable
        }

        let url = "\(httpsURL)/cancel?uniqueid=\(uniqueId)"
        try await fetchAndValidate(url: url, timeout: Self.longTimeout)
    }

    // MARK: - Launch / Resume

    func launchOrResume(
        verb: String,
        config: StreamConfiguration
    ) async throws {
        guard let httpsURL = baseHTTPSURL else {
            throw MoonlightClientError.httpsNotAvailable
        }

        // FPS hack: FPS > 60 causes SOPS to default to 720p60, force to 0
        // unless it's Sunshine (negative version)
        let fps: Int32
        if config.frameRate > 60 && !(config.appVersion?.contains(".-") ?? false) {
            fps = 0
        } else {
            fps = config.frameRate
        }

        let riKeyHex = config.riKey.map { AddressUtils.bytesToHex($0) } ?? ""
        let videoFormatMask10Bit: Int32 = 0x2200
        let hdrParam: String
        if (config.supportedVideoFormats & videoFormatMask10Bit) != 0 {
            hdrParam = "&hdrMode=1&clientHdrCapVersion=0&clientHdrCapSupportedFlagsInUint32=0" +
                "&clientHdrCapMetaDataId=NV_STATIC_METADATA_TYPE_1" +
                "&clientHdrCapDisplayData=0x0x0x0x0x0x0x0x0x0x0"
        } else {
            hdrParam = ""
        }

        let queryParams = String(cString: LiGetLaunchUrlQueryParameters())

        // Replicate C macro: SURROUNDAUDIOINFO_FROM_AUDIO_CONFIGURATION
        // = (channelMask << 16) | channelCount
        let audioConfig = config.audioConfiguration
        let channelMask = Int(audioConfig >> 16) & 0xFFFF
        let channelCount = Int(audioConfig) & 0xFFFF
        let surroundInfo = (channelMask << 16) | channelCount

        var url = "\(httpsURL)/\(verb)?uniqueid=\(uniqueId)"
        url += "&appid=\(config.appID ?? "")"
        url += "&mode=\(config.width)x\(config.height)x\(fps)"
        url += "&additionalStates=1"
        url += "&sops=\(config.optimizeGameSettings ? 1 : 0)"
        url += "&rikey=\(riKeyHex)&rikeyid=\(config.riKeyId)"
        url += hdrParam
        url += "&localAudioPlayMode=\(config.playAudioOnPC ? 1 : 0)"
        url += "&surroundAudioInfo=\(surroundInfo)"
        url += "&remoteControllersBitmap=\(config.gamepadMask)"
        url += "&gcmap=\(config.gamepadMask)"
        url += "&gcpersist=\(!config.multiController ? 1 : 0)"
        url += queryParams

        try await fetchAndValidate(url: url, timeout: Self.longTimeout)
    }

    // MARK: - App Asset

    func getAppAsset(appId: String) async throws -> Data {
        guard let httpsURL = baseHTTPSURL else {
            throw MoonlightClientError.httpsNotAvailable
        }

        let url = "\(httpsURL)/appasset?uniqueid=\(uniqueId)&appid=\(appId)&AssetType=2&AssetIdx=0"
        let request = try makeRequest(url: url, timeout: Self.normalTimeout)
        let (data, response) = try await session.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        guard httpResponse?.statusCode == 200 else {
            throw MoonlightClientError.httpError(httpResponse?.statusCode ?? 0)
        }
        return data
    }

    // MARK: - Pairing Endpoints (HTTP)

    func pairGetServerCert(salt: Data, clientCert: Data) async throws -> Data {
        let url = "\(baseHTTPURL)/pair?uniqueid=\(uniqueId)&devicename=\(deviceName)" +
            "&updateState=1&phrase=getservercert" +
            "&salt=\(AddressUtils.bytesToHex(salt))" +
            "&clientcert=\(AddressUtils.bytesToHex(clientCert))"
        return try await fetchRaw(url: url, timeout: Self.extraLongTimeout)
    }

    func pairClientChallenge(_ encryptedChallenge: Data) async throws -> Data {
        let url = "\(baseHTTPURL)/pair?uniqueid=\(uniqueId)&devicename=\(deviceName)" +
            "&updateState=1&clientchallenge=\(AddressUtils.bytesToHex(encryptedChallenge))"
        return try await fetchRaw(url: url, timeout: Self.normalTimeout)
    }

    func pairServerChallengeResp(_ encryptedResponse: Data) async throws -> Data {
        let url = "\(baseHTTPURL)/pair?uniqueid=\(uniqueId)&devicename=\(deviceName)" +
            "&updateState=1&serverchallengeresp=\(AddressUtils.bytesToHex(encryptedResponse))"
        return try await fetchRaw(url: url, timeout: Self.normalTimeout)
    }

    func pairClientSecret(_ clientSecret: String) async throws -> Data {
        let url = "\(baseHTTPURL)/pair?uniqueid=\(uniqueId)&devicename=\(deviceName)" +
            "&updateState=1&clientpairingsecret=\(clientSecret)"
        return try await fetchRaw(url: url, timeout: Self.normalTimeout)
    }

    func pairChallenge() async throws -> Data {
        guard let httpsURL = baseHTTPSURL else {
            throw MoonlightClientError.httpsNotAvailable
        }
        let url = "\(httpsURL)/pair?uniqueid=\(uniqueId)&devicename=\(deviceName)" +
            "&updateState=1&phrase=pairchallenge"
        return try await fetchRaw(url: url, timeout: Self.normalTimeout)
    }

    func unpair() async throws {
        let url = "\(baseHTTPURL)/unpair?uniqueid=\(uniqueId)"
        _ = try await fetchRaw(url: url, timeout: Self.normalTimeout)
    }

    // MARK: - Private Helpers

    // urlQueryAllowed doesn't include [ and ], which breaks IPv6 URLs like http://[fdec::1]:47989/
    private static let urlAllowedCharacters: CharacterSet = {
        var chars = CharacterSet.urlQueryAllowed
        chars.insert(charactersIn: "[]")
        return chars
    }()

    private func makeRequest(url: String, timeout: TimeInterval) throws -> URLRequest {
        guard let encoded = url.addingPercentEncoding(withAllowedCharacters: Self.urlAllowedCharacters),
              let parsedURL = URL(string: encoded) else {
            throw MoonlightClientError.invalidURL(url)
        }
        var request = URLRequest(url: parsedURL)
        request.timeoutInterval = timeout
        return request
    }

    private func fetchRaw(url: String, timeout: TimeInterval) async throws -> Data {
        let request = try makeRequest(url: url, timeout: timeout)
        let (data, _) = try await session.data(for: request)
        return fixXmlEncoding(data)
    }

    private func fetchAndDecode<T: Decodable>(url: String, timeout: TimeInterval) async throws -> T {
        let data = try await fetchRaw(url: url, timeout: timeout)
        let response = try ServerResponse<T>(from: data)
        guard response.isStatusOk else {
            throw ServerResponseError.serverError(response.statusCode, response.statusMessage)
        }
        return response.content
    }

    private func fetchAndValidate(url: String, timeout: TimeInterval) async throws {
        let data = try await fetchRaw(url: url, timeout: timeout)
        let response = try ServerResponse<EmptyContent>(from: data)
        guard response.isStatusOk else {
            throw ServerResponseError.serverError(response.statusCode, response.statusMessage)
        }
    }

    private func fixXmlEncoding(_ data: Data) -> Data {
        guard let string = String(data: data, encoding: .utf8) else { return data }
        let fixed = string.replacingOccurrences(of: "UTF-16", with: "UTF-8", options: .caseInsensitive)
        return Data(fixed.utf8)
    }
}

// Empty decodable for responses we don't need content from
private struct EmptyContent: Decodable {}

enum MoonlightClientError: LocalizedError {
    case httpsNotAvailable
    case invalidURL(String)
    case httpError(Int)
    case unknown

    var errorDescription: String? {
        switch self {
        case .httpsNotAvailable:
            "HTTPS not available (host may not be paired)"
        case .invalidURL(let url):
            "Invalid URL: \(url)"
        case .httpError(let code):
            "HTTP error: \(code)"
        case .unknown:
            "Unknown error"
        }
    }
}
