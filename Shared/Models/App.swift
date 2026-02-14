import SwiftData
import Foundation

@Model
final class App {
    var id: String
    var name: String
    var hdrSupported: Bool = false
    var hidden: Bool = false

    var host: Host?

    init(
        id: String = "",
        name: String = "",
        host: Host? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
    }

    // MARK: - Populate from AppInfo (Swift networking)

    func updateFromAppInfo(_ info: AppInfo) {
        id = info.id
        name = info.name
        hdrSupported = info.hdrSupported
    }
}
