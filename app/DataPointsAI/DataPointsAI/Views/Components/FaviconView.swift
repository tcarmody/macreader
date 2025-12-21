import SwiftUI

/// View that displays a website favicon with fallback
struct FaviconView: View {
    let url: URL
    let size: CGFloat

    @State private var favicon: NSImage?
    @State private var isLoading = true

    init(url: URL, size: CGFloat = 16) {
        self.url = url
        self.size = size
    }

    var body: some View {
        Group {
            if let favicon = favicon {
                Image(nsImage: favicon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            } else {
                // Fallback icon
                Image(systemName: "globe")
                    .font(.system(size: size * 0.75))
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
            }
        }
        .task {
            await loadFavicon()
        }
    }

    private func loadFavicon() async {
        isLoading = true
        favicon = await FaviconService.shared.favicon(for: url)
        isLoading = false
    }
}

/// Favicon view specifically for feeds with selection state
struct FeedFaviconView: View {
    let feed: Feed
    let isSelected: Bool
    let size: CGFloat

    @State private var favicon: NSImage?

    init(feed: Feed, isSelected: Bool, size: CGFloat = 16) {
        self.feed = feed
        self.isSelected = isSelected
        self.size = size
    }

    var body: some View {
        ZStack {
            if isSelected {
                // Show checkmark when selected for multi-select
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.system(size: size))
            } else if let favicon = favicon {
                // Show favicon
                Image(nsImage: favicon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            } else {
                // Fallback to RSS icon
                Image(systemName: "dot.radiowaves.up.forward")
                    .foregroundStyle(.orange)
                    .font(.system(size: size * 0.85))
            }
        }
        .frame(width: size, height: size)
        .task {
            await loadFavicon()
        }
    }

    private func loadFavicon() async {
        favicon = await FaviconService.shared.favicon(for: feed.url)
    }
}

#Preview {
    VStack(spacing: 20) {
        FaviconView(url: URL(string: "https://news.ycombinator.com")!, size: 32)
        FaviconView(url: URL(string: "https://arstechnica.com")!, size: 32)
        FaviconView(url: URL(string: "https://invalid-domain-12345.com")!, size: 32)
    }
    .padding()
}
