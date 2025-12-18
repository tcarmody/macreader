import SwiftUI

/// Left sidebar: feeds and filters with multi-select support
struct FeedListView: View {
    @EnvironmentObject var appState: AppState
    @State private var showDeleteConfirmation = false
    @State private var feedsToDelete: [Int] = []

    var body: some View {
        List(selection: $appState.selectedFilter) {
            Section("Filters") {
                FilterRow(filter: .all, count: nil)
                    .contextMenu {
                        Button {
                            Task {
                                try? await appState.markAllRead()
                            }
                        } label: {
                            Label("Mark All as Read", systemImage: "checkmark.circle")
                        }
                    }

                FilterRow(filter: .unread, count: appState.totalUnreadCount)
                    .contextMenu {
                        Button {
                            Task {
                                try? await appState.markAllRead()
                            }
                        } label: {
                            Label("Mark All as Read", systemImage: "checkmark.circle")
                        }
                    }

                FilterRow(filter: .bookmarked, count: nil)
            }

            Section("Feeds") {
                ForEach(appState.feeds) { feed in
                    FeedRow(feed: feed, isSelected: appState.selectedFeedIds.contains(feed.id))
                        .tag(ArticleFilter.feed(feed.id))
                        .contextMenu {
                            feedContextMenu(for: feed)
                        }
                        .onTapGesture(count: 1) {
                            handleFeedTap(feed)
                        }
                        .gesture(
                            TapGesture(count: 1)
                                .modifiers(.command)
                                .onEnded { _ in
                                    toggleFeedSelection(feed.id)
                                }
                        )
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Feeds")
        .toolbar {
            ToolbarItemGroup {
                if !appState.selectedFeedIds.isEmpty {
                    Button(action: {
                        feedsToDelete = Array(appState.selectedFeedIds)
                        showDeleteConfirmation = true
                    }) {
                        Image(systemName: "trash")
                    }
                    .help("Delete Selected Feeds")

                    Button(action: {
                        appState.selectedFeedIds.removeAll()
                    }) {
                        Image(systemName: "xmark.circle")
                    }
                    .help("Clear Selection")
                }
            }

            ToolbarItem {
                Menu {
                    Button {
                        DispatchQueue.main.async {
                            appState.showAddFeed = true
                        }
                    } label: {
                        Label("Add Feed...", systemImage: "plus")
                    }

                    Button {
                        DispatchQueue.main.async {
                            appState.showImportOPML = true
                        }
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
        .alert("Delete Feeds?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                feedsToDelete = []
            }
            Button("Delete", role: .destructive) {
                let idsToDelete = feedsToDelete
                feedsToDelete = []
                appState.selectedFeedIds.removeAll()
                Task {
                    do {
                        try await appState.bulkDeleteFeeds(feedIds: idsToDelete)
                    } catch {
                        print("Failed to delete feeds: \(error)")
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete \(feedsToDelete.count) feed\(feedsToDelete.count == 1 ? "" : "s")? This will also delete all their articles.")
        }
        .sheet(item: $appState.feedBeingEdited) { feed in
            EditFeedView(feed: feed)
        }
    }

    private func handleFeedTap(_ feed: Feed) {
        if NSEvent.modifierFlags.contains(.command) {
            toggleFeedSelection(feed.id)
        } else if NSEvent.modifierFlags.contains(.shift) && !appState.selectedFeedIds.isEmpty {
            // Shift-click for range selection
            extendSelectionTo(feed.id)
        } else {
            appState.selectedFeedIds.removeAll()
            appState.selectedFilter = .feed(feed.id)
        }
    }

    private func toggleFeedSelection(_ feedId: Int) {
        if appState.selectedFeedIds.contains(feedId) {
            appState.selectedFeedIds.remove(feedId)
        } else {
            appState.selectedFeedIds.insert(feedId)
        }
    }

    private func extendSelectionTo(_ feedId: Int) {
        guard let lastSelected = appState.selectedFeedIds.first,
              let lastIndex = appState.feeds.firstIndex(where: { $0.id == lastSelected }),
              let newIndex = appState.feeds.firstIndex(where: { $0.id == feedId }) else {
            toggleFeedSelection(feedId)
            return
        }

        let range = min(lastIndex, newIndex)...max(lastIndex, newIndex)
        for i in range {
            appState.selectedFeedIds.insert(appState.feeds[i].id)
        }
    }

    @ViewBuilder
    private func feedContextMenu(for feed: Feed) -> some View {
        let hasSelection = !appState.selectedFeedIds.isEmpty
        let isInSelection = appState.selectedFeedIds.contains(feed.id)
        let effectiveIds = hasSelection && isInSelection ? Array(appState.selectedFeedIds) : [feed.id]
        let count = effectiveIds.count

        Button {
            Task {
                if count == 1 {
                    try? await appState.markFeedRead(feedId: feed.id)
                } else {
                    for feedId in effectiveIds {
                        try? await appState.markFeedRead(feedId: feedId)
                    }
                }
            }
        } label: {
            Label(count == 1 ? "Mark All as Read" : "Mark \(count) Feeds as Read", systemImage: "checkmark.circle")
        }

        Button {
            Task {
                try? await appState.refreshFeeds()
            }
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }

        if count == 1 {
            Divider()

            Button {
                appState.feedBeingEdited = feed
            } label: {
                Label("Rename...", systemImage: "pencil")
            }

            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(feed.url.absoluteString, forType: .string)
            } label: {
                Label("Copy Feed URL", systemImage: "link")
            }
        }

        Divider()

        Button(role: .destructive) {
            feedsToDelete = effectiveIds
            showDeleteConfirmation = true
        } label: {
            Label(count == 1 ? "Delete" : "Delete \(count) Feeds", systemImage: "trash")
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

/// Row for a feed with selection indicator
struct FeedRow: View {
    let feed: Feed
    var isSelected: Bool = false

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
            ZStack {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                } else {
                    Image(systemName: "dot.radiowaves.up.forward")
                        .foregroundStyle(.orange)
                }
            }
        }
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(4)
    }
}

/// Sheet for editing a feed's name
struct EditFeedView: View {
    let feed: Feed
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Rename Feed")
                .font(.headline)

            TextField("Feed Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.return)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            }
        }
        .padding()
        .frame(width: 350)
        .onAppear {
            name = feed.name
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        isSaving = true
        Task {
            do {
                try await appState.updateFeed(feedId: feed.id, name: trimmedName)
                dismiss()
            } catch {
                // Handle error - could show an alert
                print("Failed to update feed: \(error)")
            }
            isSaving = false
        }
    }
}

#Preview {
    FeedListView()
        .environmentObject(AppState())
        .frame(width: 250)
}
