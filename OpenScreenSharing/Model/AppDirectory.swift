import Foundation
import os

nonisolated enum AppDirectory {
    #if os(macOS)
    #if UNSIGNED_BUILD
    // Without a team-signed app group entitlement macOS denies access to the group container.
    static let group = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(Bundle.main.bundleIdentifier!, isDirectory: true)
    #else
    static let group = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as! String)!
    #endif
    static let caches: URL = {
        var caches = group.appendingPathComponent("Library/Caches", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try caches.setResourceValues(values)
        } catch {
            StorageNotice.logger.error("exclude caches from backup: \(error, privacy: .public)")
        }
        return caches
    }()
    #else
    static let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    #endif

    static func cacheSize() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: caches, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else {
            return 0
        }
        var size: Int64 = 0
        for case let url as URL in enumerator {
            size += Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        return size
    }

    static func clearCaches() throws {
        for item in try FileManager.default.contentsOfDirectory(at: caches, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: item)
        }
    }
}
