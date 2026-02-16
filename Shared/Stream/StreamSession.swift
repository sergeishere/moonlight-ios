import Foundation

final class StreamSession: @unchecked Sendable {
    let config: StreamConfiguration
    private(set) var connection: MoonlightConnection?
    private let delegate: any StreamConnectionDelegate

    #if os(visionOS)
    private let videoRenderer: AVSampleBufferVideoRenderer
    #else
    private let frameQueue: FrameQueue
    #endif

    #if os(visionOS)
    init(config: StreamConfiguration, videoRenderer: AVSampleBufferVideoRenderer, delegate: any StreamConnectionDelegate) {
        self.config = config
        self.videoRenderer = videoRenderer
        self.delegate = delegate
        config.riKey = Utils.randomBytes(16)
        config.riKeyId = Int32(arc4random())
    }
    #else
    init(config: StreamConfiguration, frameQueue: FrameQueue, delegate: any StreamConnectionDelegate) {
        self.config = config
        self.frameQueue = frameQueue
        self.delegate = delegate
        config.riKey = Utils.randomBytes(16)
        config.riKeyId = Int32(arc4random())
    }
    #endif

    func start() {
        StreamCallbackRouter.shared.delegate = delegate

        Task {
            do {
                try await launchOrResume()
            } catch {
                delegate.launchFailed(error.localizedDescription)
            }
        }
    }

    func stop() {
        connection?.terminate()
    }

    // MARK: - Private

    private func launchOrResume() async throws {
        CryptoManager.generateKeyPairUsingSSL()

        let host = config.host ?? ""
        let (address, port) = AddressUtils.parseAddressAndPort(host)
        let client = MoonlightClient(
            address: address,
            port: port,
            httpsPort: config.httpsPort,
            serverCert: config.serverCert
        )

        // Fetch server info if not pre-filled
        if config.appVersion == nil {
            let info = try await client.getServerInfo()
            guard info.pairStatus == 1 else {
                throw StreamSessionError.notPaired
            }
            config.appVersion = info.appVersion
            config.gfeVersion = info.gfeVersion
            config.isResume = info.currentGame != "0"
        }

        // Launch or resume via HTTP
        let verb = config.isResume ? "resume" : "launch"
        try await client.launchOrResume(verb: verb, config: config)

        // Create VideoDecoder and MoonlightConnection on main thread
        await MainActor.run {
            #if os(visionOS)
            let decoder = VideoDecoder(
                callbacks: delegate,
                sampleBufferVideoRenderer: videoRenderer,
                streamAspectRatio: Float(config.width) / Float(config.height),
                useFramePacing: config.useFramePacing
            )
            #else
            let decoder = VideoDecoder(
                callbacks: delegate,
                frameQueue: frameQueue,
                streamAspectRatio: Float(config.width) / Float(config.height)
            )
            #endif

            let conn = MoonlightConnection(config: config, renderer: decoder)
            self.connection = conn

            DispatchQueue.global(qos: .userInitiated).async {
                conn.start()
            }
        }
    }
}

enum StreamSessionError: LocalizedError {
    case notPaired
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .notPaired: "Device not paired to PC"
        case .launchFailed(let msg): msg
        }
    }
}
