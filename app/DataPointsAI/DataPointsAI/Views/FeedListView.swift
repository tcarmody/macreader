import SwiftUI

/// Left sidebar: feeds and filters
struct FeedListView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        List(selection: $appState.selectedFilter) {
            Section("Filters") {
                FilterRow(filter: .all, count: nil)
                FilterRow(filter: .unread, count: appState.totalUnreadCount)
                FilterRow(filter: .bookmarked, count: nil)
            }

            Section("Feeds") {
                ForEach(appState.feeds) { feed in
                    FeedRow(feed: feed)
                        .tag(ArticleFilter.feed(feed.id))
                        .contextMenu {
                            Button("Refresh") {
                                Task {
                                    try? await appState.refreshFeeds()
                                }
                            }

                            Divider()

                            Button("Delete", role: .destructive) {
                                Task {
                                    try? await appState.deleteFeed(feedId: feed.id)
                                }
                            }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Feeds")
        .toolbar {
            ToolbarItem {
                Menu {
                    Button {
                        appState.showAddFeed = true
                    } label: {
                        Label("Add Feed...", systemImage: "plus")
                    }

                    Button {
                        appState.showImportOPML = true
                    } label: {
                        Label("Import OPML...", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add Feed")
            }

            ToolbarItem {
                Button(action: {
                    Task {
                        try? await appState.refreshFeeds()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh Feeds")
                .disabled(appState.isLoading)
            }
        }
        .onChange(of: appState.selectedFilter) { _, _ in
            Task {
                await appState.reloadArticles()
            }
        }
    }
}

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

/// Row for a feed
struct FeedRow: View {
    let feed: Feed

    var body: some View {
        Label {
            HStack {
                Text(feed.name)
                    .lineLimit(1)
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
            Image(systemName: "dot.radiowaves.up.forward")
                .foregroundStyle(.orange)
        }
    }
}

#Preview {
    FeedListView()
        .environmentObject(AppState())
        .frame(width: 250)
}
