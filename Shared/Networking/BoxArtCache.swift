import UIKit

actor BoxArtCache {
    static let shared = BoxArtCache()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let cacheDirectory: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = caches.appendingPathComponent("boxart", isDirectory: true)
        memoryCache.countLimit = 200
    }

    func image(hostUUID: String, appId: String) -> UIImage? {
        let key = "\(hostUUID)/\(appId)" as NSString

        if let cached = memoryCache.object(forKey: key) {
            return cached
        }

        let fileURL = fileURL(hostUUID: hostUUID, appId: appId)
        guard let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            return nil
        }

        memoryCache.setObject(image, forKey: key)
        return image
    }

    func store(_ data: Data, hostUUID: String, appId: String) {
        guard let image = UIImage(data: data) else { return }

        let key = "\(hostUUID)/\(appId)" as NSString
        memoryCache.setObject(image, forKey: key)

        let fileURL = fileURL(hostUUID: hostUUID, appId: appId)
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL)
    }

    private func fileURL(hostUUID: String, appId: String) -> URL {
        cacheDirectory
            .appendingPathComponent(hostUUID, isDirectory: true)
            .appendingPathComponent("\(appId).png")
    }
}
