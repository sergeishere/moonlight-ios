import Foundation

struct AppInfo: Decodable {
    let id: String
    let name: String
    let hdrSupported: Bool
    let installPath: String?

    enum CodingKeys: String, CodingKey {
        case name = "AppTitle"
        case id = "ID"
        case hdrSupported = "IsHdrSupported"
        case installPath = "AppInstallPath"
    }
}
