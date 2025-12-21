import Foundation
import AppKit

/// Service for fetching and caching website favicons
actor FaviconService {
    static let shared = FaviconService()

    /// In-memory cache of favicon images
    private var cache: [String: NSImage] = [:]

    /// URLs currently being fetched (to avoid duplicate requests)
    private var inFlightRequests: Set<String> = []

    private init() {}

    /// Get favicon for a feed URL, fetching if necessary
    /// - Parameter feedURL: The feed URL to get favicon for
    /// - Returns: The favicon image, or nil if not available
    func favicon(for feedURL: URL) async -> NSImage? {
        // Extract the host from the URL
        guard let host = feedURL.host else { return nil }

        // Check cache first
        if let cached = cache[host] {
            return cached
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
                cache[host] = image
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

    /// Clear the favicon cache
    func clearCache() {
        cache.removeAll()
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
}
