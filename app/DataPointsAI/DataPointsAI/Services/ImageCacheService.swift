import Foundation
import AppKit
import CryptoKit

/// Service for caching images for offline viewing
@MainActor
final class ImageCacheService {
    static let shared = ImageCacheService()

    private let cacheDirectory: URL
    private let fileManager = FileManager.default
    private let session: URLSession

    /// Maximum cache size in bytes (100 MB)
    private let maxCacheSize: Int64 = 100 * 1024 * 1024

    /// Maximum age for cached images (30 days)
    private let maxCacheAge: TimeInterval = 30 * 24 * 60 * 60

    private init() {
        // Create cache directory in Application Support
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let oldCacheDir = appSupport.appendingPathComponent("DataPointsAI/ImageCache", isDirectory: true)
        cacheDirectory = appSupport.appendingPathComponent("Data Points AI/ImageCache", isDirectory: true)

        // Migrate old cache directory to new name if it exists
        if fileManager.fileExists(atPath: oldCacheDir.path) && !fileManager.fileExists(atPath: cacheDirectory.path) {
            let oldParent = appSupport.appendingPathComponent("DataPointsAI", isDirectory: true)
            let newParent = appSupport.appendingPathComponent("Data Points AI", isDirectory: true)
            try? fileManager.moveItem(at: oldParent, to: newParent)
            print("Migrated cache directory from 'DataPointsAI' to 'Data Points AI'")
        }

        // Create directory if it doesn't exist
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // Configure URL session with caching
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Cache all images found in HTML content
    /// - Parameter html: The HTML content to scan for images
    /// - Returns: Modified HTML with local file URLs for cached images
    func cacheImagesInContent(_ html: String) async -> String {
        let imageUrls = extractImageUrls(from: html)
        guard !imageUrls.isEmpty else { return html }

        var modifiedHtml = html

        // Cache images concurrently
        await withTaskGroup(of: (String, URL?).self) { group in
            for urlString in imageUrls {
                group.addTask {
                    if let url = URL(string: urlString) {
                        let localUrl = await self.cacheImage(from: url)
                        return (urlString, localUrl)
                    }
                    return (urlString, nil)
                }
            }

            for await (originalUrl, localUrl) in group {
                if let localUrl = localUrl {
                    modifiedHtml = modifiedHtml.replacingOccurrences(
                        of: originalUrl,
                        with: localUrl.absoluteString
                    )
                }
            }
        }

        return modifiedHtml
    }

    /// Cache a single image from URL
    /// - Parameter url: The remote URL of the image
    /// - Returns: Local file URL if cached successfully
    func cacheImage(from url: URL) async -> URL? {
        let cacheKey = cacheKeyForURL(url)
        let cachedFile = cacheDirectory.appendingPathComponent(cacheKey)

        // Check if already cached
        if fileManager.fileExists(atPath: cachedFile.path) {
            // Update access time to keep frequently used images longer
            try? fileManager.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: cachedFile.path
            )
            return cachedFile
        }

        // Download and cache
        do {
            let (data, response) = try await session.data(from: url)

            // Verify it's an image
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let mimeType = httpResponse.mimeType,
                  mimeType.hasPrefix("image/") else {
                return nil
            }

            // Save to cache
            try data.write(to: cachedFile)
            return cachedFile
        } catch {
            return nil
        }
    }

    /// Get cached image if available
    /// - Parameter url: The original remote URL
    /// - Returns: Local file URL if cached
    func getCachedImage(for url: URL) -> URL? {
        let cacheKey = cacheKeyForURL(url)
        let cachedFile = cacheDirectory.appendingPathComponent(cacheKey)

        if fileManager.fileExists(atPath: cachedFile.path) {
            return cachedFile
        }
        return nil
    }

    /// Check if image is cached
    func isCached(url: URL) -> Bool {
        let cacheKey = cacheKeyForURL(url)
        let cachedFile = cacheDirectory.appendingPathComponent(cacheKey)
        return fileManager.fileExists(atPath: cachedFile.path)
    }

    /// Clean up old cache entries
    func cleanupCache() async {
        let now = Date()

        guard let contents = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var filesToDelete: [URL] = []
        var totalSize: Int64 = 0
        var fileInfos: [(url: URL, date: Date, size: Int64)] = []

        // Gather file info
        for fileUrl in contents {
            guard let attrs = try? fileManager.attributesOfItem(atPath: fileUrl.path),
                  let modDate = attrs[.modificationDate] as? Date,
                  let size = attrs[.size] as? Int64 else {
                continue
            }

            // Mark old files for deletion
            if now.timeIntervalSince(modDate) > maxCacheAge {
                filesToDelete.append(fileUrl)
            } else {
                totalSize += size
                fileInfos.append((url: fileUrl, date: modDate, size: size))
            }
        }

        // If still over size limit, delete oldest files
        if totalSize > maxCacheSize {
            // Sort by modification date (oldest first)
            fileInfos.sort { $0.date < $1.date }

            for info in fileInfos {
                if totalSize <= maxCacheSize {
                    break
                }
                filesToDelete.append(info.url)
                totalSize -= info.size
            }
        }

        // Delete files
        for fileUrl in filesToDelete {
            try? fileManager.removeItem(at: fileUrl)
        }
    }

    /// Clear entire cache
    func clearCache() {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// Get current cache size in bytes
    func getCacheSize() -> Int64 {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var totalSize: Int64 = 0
        for fileUrl in contents {
            if let size = try? fileManager.attributesOfItem(atPath: fileUrl.path)[.size] as? Int64 {
                totalSize += size
            }
        }
        return totalSize
    }

    // MARK: - Private Helpers

    /// Generate a cache key from URL using SHA256 hash
    private func cacheKeyForURL(_ url: URL) -> String {
        let data = Data(url.absoluteString.utf8)
        let hash = SHA256.hash(data: data)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        // Preserve file extension if present
        let ext = url.pathExtension.isEmpty ? "img" : url.pathExtension
        return "\(hashString).\(ext)"
    }

    /// Extract image URLs from HTML content
    private func extractImageUrls(from html: String) -> [String] {
        var urls: [String] = []

        // Match src attributes in img tags
        let imgPattern = #"<img[^>]+src\s*=\s*[\"']([^\"']+)[\"']"#
        if let regex = try? NSRegularExpression(pattern: imgPattern, options: .caseInsensitive) {
            let range = NSRange(html.startIndex..., in: html)
            let matches = regex.matches(in: html, options: [], range: range)

            for match in matches {
                if let urlRange = Range(match.range(at: 1), in: html) {
                    let urlString = String(html[urlRange])
                    // Only cache http/https URLs
                    if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
                        urls.append(urlString)
                    }
                }
            }
        }

        // Also match srcset attributes
        let srcsetPattern = #"srcset\s*=\s*[\"']([^\"']+)[\"']"#
        if let regex = try? NSRegularExpression(pattern: srcsetPattern, options: .caseInsensitive) {
            let range = NSRange(html.startIndex..., in: html)
            let matches = regex.matches(in: html, options: [], range: range)

            for match in matches {
                if let srcsetRange = Range(match.range(at: 1), in: html) {
                    let srcset = String(html[srcsetRange])
                    // Parse srcset format: "url1 1x, url2 2x, ..."
                    let entries = srcset.split(separator: ",")
                    for entry in entries {
                        let parts = entry.trimmingCharacters(in: .whitespaces).split(separator: " ")
                        if let urlPart = parts.first {
                            let urlString = String(urlPart)
                            if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
                                urls.append(urlString)
                            }
                        }
                    }
                }
            }
        }

        return Array(Set(urls)) // Remove duplicates
    }
}
