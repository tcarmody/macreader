import SwiftUI

/// Left sidebar: feeds and filters with multi-select support
struct FeedListView: View {
    @EnvironmentObject var appState: AppState
    @State private var showDeleteConfirmation = false
    @State private var feedsToDelete: [Int] = []
    @State private var showNewCategorySheet = false
    @State private var feedsForNewCategory: [Int] = []
    @State private var categoryToRename: String?
    @State private var categoryToDelete: String?
    @State private var dropTargetCategory: String? = nil  // nil means uncategorized, empty string means no target

    var body: some View {
        List(selection: $appState.selectedFilter) {
            // Library section
            Section {
                LibrarySidebarRow(isSelected: appState.showLibrary, count: appState.libraryItemCount)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appState.selectLibrary()
                    }
            }

            // Newsletters section - right below Library
            if !appState.newsletterFeeds.isEmpty {
                Section {
                    if !appState.collapsedCategories.contains("Newsletters") {
                        ForEach(appState.newsletterFeeds) { feed in
                            newsletterFeedRow(for: feed)
                        }
                    }
                } header: {
                    NewsletterHeader(
                        feedCount: appState.newsletterFeeds.count,
                        unreadCount: appState.newsletterUnreadCount,
                        isCollapsed: appState.collapsedCategories.contains("Newsletters"),
                        onToggle: { appState.toggleCategoryCollapsed("Newsletters") }
                    )
                }
                .collapsible(false)
            }

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

                FilterRow(filter: .today, count: appState.todayArticleCount)

                FilterRow(filter: .bookmarked, count: nil)

                FilterRow(filter: .summarized, count: nil)

                FilterRow(filter: .unsummarized, count: nil)
            }

            // Group feeds by category
            ForEach(appState.feedsByCategory, id: \.category) { group in
                if let category = group.category {
                    // Categorized feeds section
                    Section {
                        if !appState.collapsedCategories.contains(category) {
                            ForEach(group.feeds) { feed in
                                feedRow(for: feed)
                            }
                        }
                    } header: {
                        CategoryHeader(
                            category: category,
                            feedCount: group.feeds.count,
                            unreadCount: group.feeds.reduce(0) { $0 + $1.unreadCount },
                            isCollapsed: appState.collapsedCategories.contains(category),
                            onToggle: { appState.toggleCategoryCollapsed(category) },
                            isDropTarget: dropTargetCategory == category
                        )
                        .dropDestination(for: FeedTransfer.self) { items, _ in
                            handleDrop(items: items, toCategory: category)
                        } isTargeted: { isTargeted in
                            dropTargetCategory = isTargeted ? category : nil
                        }
                        .contextMenu {
                            categoryContextMenu(for: category)
                        }
                    }
                    .collapsible(false)
                } else {
                    // Uncategorized feeds section
                    Section {
                        ForEach(group.feeds) { feed in
                            feedRow(for: feed)
                        }
                    } header: {
                        UncategorizedHeader(isDropTarget: dropTargetCategory == "")
                            .dropDestination(for: FeedTransfer.self) { items, _ in
                                handleDrop(items: items, toCategory: nil)
                            } isTargeted: { isTargeted in
                                dropTargetCategory = isTargeted ? "" : nil
                            }
                    }
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

                    Divider()

                    Button {
                        DispatchQueue.main.async {
                            appState.showFeedManager = true
                        }
                    } label: {
                        Label("Manage Feeds...", systemImage: "slider.horizontal.3")
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
        .onChange(of: appState.selectedFilter) { oldValue, newValue in
            // Only react to actual filter changes
            guard oldValue != newValue else { return }

            // If library is showing and user selects a different filter, deselect library
            if appState.showLibrary {
                appState.deselectLibrary()
            }

            // Reload articles for the new filter
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
        .sheet(isPresented: $showNewCategorySheet) {
            NewCategorySheet(feedIds: feedsForNewCategory) {
                feedsForNewCategory = []
            }
        }
        .sheet(item: $categoryToRename) { category in
            RenameCategorySheet(category: category)
        }
        .alert("Delete Folder?", isPresented: .init(
            get: { categoryToDelete != nil },
            set: { if !$0 { categoryToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                categoryToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let category = categoryToDelete {
                    Task {
                        try? await appState.deleteCategory(category)
                    }
                }
                categoryToDelete = nil
            }
        } message: {
            if let category = categoryToDelete {
                Text("Are you sure you want to delete the folder \"\(category)\"? The feeds will be moved to uncategorized.")
            }
        }
        .safeAreaInset(edge: .bottom) {
            ServerStatusIndicator()
        }
    }

    @ViewBuilder
    private func feedRow(for feed: Feed) -> some View {
        let isInSelection = appState.selectedFeedIds.contains(feed.id)
        let feedIdsToTransfer = isInSelection && !appState.selectedFeedIds.isEmpty
            ? Array(appState.selectedFeedIds)
            : [feed.id]

        FeedRow(feed: feed, isSelected: isInSelection)
            .tag(ArticleFilter.feed(feed.id))
            .draggable(FeedTransfer(feedIds: feedIdsToTransfer)) {
                // Drag preview
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc")
                    Text(feedIdsToTransfer.count == 1 ? feed.name : "\(feedIdsToTransfer.count) feeds")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.regularMaterial)
                .cornerRadius(6)
            }
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

    @ViewBuilder
    private func newsletterFeedRow(for feed: Feed) -> some View {
        NewsletterFeedRow(feed: feed, isSelected: appState.selectedFilter == .feed(feed.id))
            .tag(ArticleFilter.feed(feed.id))
            .contextMenu {
                newsletterFeedContextMenu(for: feed)
            }
            .onTapGesture(count: 1) {
                appState.selectedFilter = .feed(feed.id)
            }
    }

    @ViewBuilder
    private func newsletterFeedContextMenu(for feed: Feed) -> some View {
        Button {
            Task {
                try? await appState.markFeedRead(feedId: feed.id)
            }
        } label: {
            Label("Mark All as Read", systemImage: "checkmark.circle")
        }

        Divider()

        Button {
            appState.feedBeingEdited = feed
        } label: {
            Label("Rename...", systemImage: "pencil")
        }
    }

    @ViewBuilder
    private func categoryContextMenu(for category: String) -> some View {
        Button {
            categoryToRename = category
        } label: {
            Label("Rename Folder...", systemImage: "pencil")
        }

        Divider()

        Button(role: .destructive) {
            categoryToDelete = category
        } label: {
            Label("Delete Folder", systemImage: "trash")
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

    /// Handle dropping feeds onto a category
    private func handleDrop(items: [FeedTransfer], toCategory category: String?) -> Bool {
        guard let transfer = items.first else { return false }

        Task {
            for feedId in transfer.feedIds {
                try? await appState.moveFeedToCategory(feedId: feedId, category: category)
            }
        }

        return true
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

        Divider()

        // Move to folder submenu
        Menu {
            Button {
                Task {
                    for feedId in effectiveIds {
                        try? await appState.moveFeedToCategory(feedId: feedId, category: nil)
                    }
                }
            } label: {
                Label("Uncategorized", systemImage: feed.category == nil ? "checkmark" : "")
            }

            if !appState.categories.isEmpty {
                Divider()

                ForEach(appState.categories, id: \.self) { category in
                    Button {
                        Task {
                            for feedId in effectiveIds {
                                try? await appState.moveFeedToCategory(feedId: feedId, category: category)
                            }
                        }
                    } label: {
                        Label(category, systemImage: feed.category == category ? "checkmark" : "")
                    }
                }
            }

            Divider()

            Button {
                feedsForNewCategory = effectiveIds
                showNewCategorySheet = true
            } label: {
                Label("New Folder...", systemImage: "folder.badge.plus")
            }
        } label: {
            Label("Move to Folder", systemImage: "folder")
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

// MARK: - Preview

#Preview {
    FeedListView()
        .environmentObject(AppState())
        .frame(width: 250)
}
