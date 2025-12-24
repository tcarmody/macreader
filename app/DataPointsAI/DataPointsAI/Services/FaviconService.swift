import Foundation
import AppKit

/// Service for fetching and caching website favicons
/// Caches favicons both in memory and on disk for persistence across app launches
actor FaviconService {
    static let shared = FaviconService()

    /// In-memory cache of favicon images
    private var cache: [String: NSImage] = [:]

    /// URLs currently being fetched (to avoid duplicate requests)
    private var inFlightRequests: Set<String> = []

    /// Disk cache directory
    private let cacheDirectory: URL

    /// Maximum age for cached favicons (7 days)
    private let maxCacheAge: TimeInterval = 7 * 24 * 60 * 60

    private init() {
        // Create cache directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheDirectory = appSupport.appendingPathComponent("DataPointsAI/FaviconCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // Clean up old cache entries in the background
        Task {
            await cleanupOldCache()
        }
    }

    /// Get favicon for a feed URL, fetching if necessary
    /// - Parameter feedURL: The feed URL to get favicon for
    /// - Returns: The favicon image, or nil if not available
    func favicon(for feedURL: URL) async -> NSImage? {
        // Extract the host from the URL
        guard let host = feedURL.host else { return nil }

        // Check memory cache first
        if let cached = cache[host] {
            return cached
        }

        // Check disk cache
        if let diskCached = loadFromDisk(host: host) {
            cache[host] = diskCached
            return diskCached
        }

        // Check if already fetching
        if inFlightRequests.contains(host) {
            return nil
        }

        // Start fetching
        inFlightRequests.insert(host)
        defer { inFlightRequests.remove(host) }

        // Try multiple favicon sources
        let faviconURLs = [
            // Google's favicon service (most reliable)
            "https://www.google.com/s2/favicons?domain=\(host)&sz=64",
            // DuckDuckGo's favicon service
            "https://icons.duckduckgo.com/ip3/\(host).ico",
            // Direct favicon.ico
            "https://\(host)/favicon.ico",
            // Apple touch icon
            "https://\(host)/apple-touch-icon.png"
        ]

        for urlString in faviconURLs {
            guard let url = URL(string: urlString) else { continue }

            if let image = await fetchImage(from: url) {
                // Save to both memory and disk cache
                cache[host] = image
                saveToDisk(image: image, host: host)
                return image
            }
        }

        return nil
    }

    /// Fetch an image from a URL
    private func fetchImage(from url: URL) async -> NSImage? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            // Check for valid response
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            // Try to create image from data
            guard let image = NSImage(data: data) else {
                return nil
            }

            // Ensure it's a reasonable size
            if image.size.width >= 8 && image.size.height >= 8 {
                return image
            }

            return nil
        } catch {
            return nil
        }
    }

    /// Clear the favicon cache (both memory and disk)
    func clearCache() {
        cache.removeAll()
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// Prefetch favicons for a list of feed URLs
    func prefetch(feedURLs: [URL]) async {
        await withTaskGroup(of: Void.self) { group in
            for url in feedURLs {
                group.addTask {
                    _ = await self.favicon(for: url)
                }
            }
        }
    }

    // MARK: - Disk Cache

    /// Generate a safe filename from a host
    private func cacheFilePath(for host: String) -> URL {
        // Use a sanitized version of the host as filename
        let safeHost = host.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return cacheDirectory.appendingPathComponent("favicon_\(safeHost).png")
    }

    /// Save favicon to disk cache
    private func saveToDisk(image: NSImage, host: String) {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return
        }

        let path = cacheFilePath(for: host)
        try? pngData.write(to: path)
    }

    /// Load favicon from disk cache
    private func loadFromDisk(host: String) -> NSImage? {
        let path = cacheFilePath(for: host)

        // Check if file exists and is not too old
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path.path),
              let modDate = attributes[.modificationDate] as? Date,
              Date().timeIntervalSince(modDate) < maxCacheAge else {
            return nil
        }

        return NSImage(contentsOf: path)
    }

    /// Clean up old cache entries
    private func cleanupOldCache() async {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        let cutoffDate = Date().addingTimeInterval(-maxCacheAge)

        for fileURL in contents {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                  let modDate = attributes[.modificationDate] as? Date,
                  modDate < cutoffDate else {
                continue
            }

            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}
