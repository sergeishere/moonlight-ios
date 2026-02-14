import Foundation

enum PreferredCodec: Int, Codable, CaseIterable {
    case auto = 0
    case h264 = 1
    case hevc = 2
    case av1 = 3
}

enum OnScreenControlsLevel: Int, Codable, CaseIterable {
    case off = 0
    case auto = 1
    case simple = 2
    case full = 3
}
