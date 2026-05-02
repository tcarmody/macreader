import SwiftUI

/// Row for filter options
struct FilterRow: View {
    let filter: ArticleFilter
    let count: Int?
    /// When true, the count is treated as an unread/attention number (blue badge).
    /// When false (default), the count is treated as a neutral total (gray badge).
    var usesUnreadBadge: Bool = false

    var body: some View {
        Label {
            HStack {
                Text(filter.displayName)
                Spacer()
                if let count = count, count > 0 {
                    if usesUnreadBadge {
                        Text("\(count)")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    } else {
                        Text("\(count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
            }
        } icon: {
            Image(systemName: filter.systemImage)
                .foregroundStyle(filter == .unread ? .blue : .secondary)
        }
        .tag(filter)
    }
}
