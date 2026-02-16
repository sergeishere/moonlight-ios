import Foundation

final class StreamCallbackRouter: @unchecked Sendable {
    static let shared = StreamCallbackRouter()

    weak var delegate: (any StreamConnectionDelegate)?
    weak var videoDecoder: VideoDecoder?

    private init() {}
}
