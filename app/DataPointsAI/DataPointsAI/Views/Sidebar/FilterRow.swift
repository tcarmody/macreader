import SwiftUI

/// Row for filter options
struct FilterRow: View {
    let filter: ArticleFilter
    let count: Int?

    var body: some View {
        Label {
            HStack {
                Text(filter.displayName)
                Spacer()
                if let count = count, count > 0 {
                    Text("\(count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
        } icon: {
            Image(systemName: filter.systemImage)
                .foregroundStyle(filter == .unread ? .blue : .secondary)
        }
        .tag(filter)
    }
}
