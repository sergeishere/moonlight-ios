import UIKit
import os

private let log = Logger(subsystem: "com.moonlight", category: "BoxArt")

actor BoxArtCache {
    static let shared = BoxArtCache()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let cacheDirectory: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = caches.appendingPathComponent("boxart", isDirectory: true)
        memoryCache.countLimit = 200
        log.debug("Cache directory: \(self.cacheDirectory.path)")
    }

    func image(hostUUID: String, appId: String) -> UIImage? {
        let key = "\(hostUUID)/\(appId)" as NSString

        if let cached = memoryCache.object(forKey: key) {
            log.debug("[\(appId)] memory cache hit")
            return cached
        }

        let fileURL = fileURL(hostUUID: hostUUID, appId: appId)
        guard let data = try? Data(contentsOf: fileURL) else {
            log.debug("[\(appId)] no disk cache at \(fileURL.lastPathComponent)")
            return nil
        }
        guard let image = UIImage(data: data) else {
            log.warning("[\(appId)] disk cache corrupt, \(data.count) bytes")
            return nil
        }

        log.debug("[\(appId)] disk cache hit, \(data.count) bytes")
        memoryCache.setObject(image, forKey: key)
        return image
    }

    func store(_ data: Data, hostUUID: String, appId: String) {
        guard let image = UIImage(data: data) else {
            log.warning("[\(appId)] store failed: invalid image data, \(data.count) bytes")
            return
        }

        let key = "\(hostUUID)/\(appId)" as NSString
        memoryCache.setObject(image, forKey: key)

        let fileURL = fileURL(hostUUID: hostUUID, appId: appId)
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL)
            log.info("[\(appId)] stored \(data.count) bytes to disk")
        } catch {
            log.error("[\(appId)] disk write failed: \(error.localizedDescription)")
        }
    }

    private func fileURL(hostUUID: String, appId: String) -> URL {
        cacheDirectory
            .appendingPathComponent(hostUUID, isDirectory: true)
            .appendingPathComponent("\(appId).png")
    }
}
