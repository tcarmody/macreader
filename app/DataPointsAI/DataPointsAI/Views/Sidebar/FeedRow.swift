import SwiftUI

/// Row for a feed with selection indicator and favicon
struct FeedRow: View {
    let feed: Feed
    var isSelected: Bool = false

    var body: some View {
        Label {
            HStack(spacing: 6) {
                Text(feed.name)
                    .lineLimit(1)

                // Health status indicator (only show if not healthy)
                if feed.healthStatus != .healthy {
                    Image(systemName: feed.healthStatus.iconName)
                        .font(.caption2)
                        .foregroundStyle(healthStatusColor)
                        .help(feed.healthStatus.description)
                }

                Spacer()

                if feed.unreadCount > 0 {
                    Text("\(feed.unreadCount)")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .clipShape(Capsule())
                }
            }
        } icon: {
            FeedFaviconView(feed: feed, isSelected: isSelected, size: 16)
        }
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(4)
    }

    private var healthStatusColor: Color {
        switch feed.healthStatus {
        case .healthy: return .green
        case .stale: return .yellow
        case .error: return .red
        case .neverFetched: return .gray
        }
    }
}
