import SwiftUI

/// Row for a newsletter feed with mail icon
struct NewsletterFeedRow: View {
    let feed: Feed
    var isSelected: Bool = false

    var body: some View {
        Label {
            HStack(spacing: 6) {
                Text(feed.name)
                    .lineLimit(1)

                Spacer()

                if feed.unreadCount > 0 {
                    Text("\(feed.unreadCount)")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange)
                        .clipShape(Capsule())
                }
            }
        } icon: {
            Image(systemName: "envelope.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 14))
        }
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(4)
    }
}
