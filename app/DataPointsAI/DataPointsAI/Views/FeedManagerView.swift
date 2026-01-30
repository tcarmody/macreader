import SwiftUI
import UniformTypeIdentifiers

/// Comprehensive feed management view
struct FeedManagerView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""
    @State private var selectedFeedIds: Set<Int> = []
    @State private var editingFeedId: Int?
    @State private var editingName: String = ""
    @State private var showingImportOPML = false
    @State private var showingAddFeed = false
    @State private var sortOrder: FeedSortOrder = .name
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var showingDeleteConfirmation = false

    private var filteredFeeds: [Feed] {
        var feeds = appState.feeds.filter { !$0.url.absoluteString.hasPrefix("newsletter://") }

        if !searchText.isEmpty {
            feeds = feeds.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                ($0.category?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                $0.url.absoluteString.localizedCaseInsensitiveContains(searchText)
            }
        }

        switch sortOrder {
        case .name:
            feeds.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .category:
            feeds.sort {
                let cat1 = $0.category ?? ""
                let cat2 = $1.category ?? ""
                if cat1 != cat2 { return cat1 < cat2 }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .status:
            feeds.sort {
                let status1 = $0.healthStatus.sortPriority
                let status2 = $1.healthStatus.sortPriority
                if status1 != status2 { return status1 < status2 }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .lastFetched:
            feeds.sort {
                let date1 = $0.lastFetched ?? .distantPast
                let date2 = $1.lastFetched ?? .distantPast
                return date1 > date2
            }
        }

        return feeds
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Feed Manager")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            // Toolbar
            HStack(spacing: 12) {
                // Add Feed
                Button {
                    showingAddFeed = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .help("Add new feed")

                // Delete Selected
                Button {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selectedFeedIds.isEmpty)
                .help("Delete selected feeds")

                // Refresh Selected
                Button {
                    refreshSelectedFeeds()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(selectedFeedIds.isEmpty)
                .help("Refresh selected feeds")

                Divider()
                    .frame(height: 20)

                // Import OPML
                Button {
                    showingImportOPML = true
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .help("Import feeds from OPML file")

                // Export OPML
                Button {
                    exportOPML()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(isExporting)
                .help("Export feeds to OPML file")

                Spacer()

                // Sort options
                Picker("Sort", selection: $sortOrder) {
                    ForEach(FeedSortOrder.allCases, id: \.self) { order in
                        Text(order.label).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)

                // Search
                TextField("Search feeds...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Feed table
            if filteredFeeds.isEmpty {
                ContentUnavailableView {
                    Label("No Feeds", systemImage: "dot.radiowaves.up.forward")
                } description: {
                    if searchText.isEmpty {
                        Text("Add feeds to get started")
                    } else {
                        Text("No feeds match your search")
                    }
                } actions: {
                    if searchText.isEmpty {
                        Button("Add Feed") {
                            showingAddFeed = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                feedTable
            }

            // Footer with selection info
            if !selectedFeedIds.isEmpty {
                Divider()
                HStack {
                    Text("\(selectedFeedIds.count) feed\(selectedFeedIds.count == 1 ? "" : "s") selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Select All") {
                        selectedFeedIds = Set(filteredFeeds.map(\.id))
                    }
                    .font(.caption)

                    Button("Deselect All") {
                        selectedFeedIds.removeAll()
                    }
                    .font(.caption)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
        .frame(minWidth: 800, idealWidth: 900, minHeight: 500, idealHeight: 600)
        .sheet(isPresented: $showingImportOPML) {
            ImportOPMLView()
        }
        .sheet(isPresented: $showingAddFeed) {
            AddFeedView()
        }
        .alert("Delete Feeds", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteSelectedFeeds()
            }
        } message: {
            Text("Are you sure you want to delete \(selectedFeedIds.count) feed\(selectedFeedIds.count == 1 ? "" : "s")? This action cannot be undone.")
        }
        .alert("Export Error", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK") { exportError = nil }
        } message: {
            if let error = exportError {
                Text(error)
            }
        }
    }

    private var feedTable: some View {
        Table(filteredFeeds, selection: $selectedFeedIds) {
            // Checkbox column (implicit with selection)

            TableColumn("Name") { feed in
                feedNameCell(for: feed)
            }
            .width(min: 150, ideal: 250)

            TableColumn("Category") { feed in
                categoryCell(for: feed)
            }
            .width(min: 100, ideal: 150)

            TableColumn("Status") { feed in
                FeedHealthBadge(status: feed.healthStatus)
            }
            .width(80)

            TableColumn("Last Fetched") { feed in
                if let date = feed.lastFetched {
                    Text(date, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Never")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .width(min: 80, ideal: 120)

            TableColumn("URL") { feed in
                Text(feed.url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(feed.url.absoluteString)
            }
            .width(min: 100, ideal: 200)

            TableColumn("Actions") { feed in
                HStack(spacing: 4) {
                    Button {
                        editingFeedId = feed.id
                        editingName = feed.name
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                    .help("Edit feed name")

                    Button {
                        copyFeedURL(feed)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .help("Copy feed URL")

                    Button {
                        refreshFeed(feed)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("Refresh feed")
                }
            }
            .width(80)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .sheet(item: Binding(
            get: { editingFeedId.flatMap { id in filteredFeeds.first { $0.id == id } } },
            set: { _ in editingFeedId = nil }
        )) { feed in
            EditFeedSheet(feed: feed)
        }
    }

    @ViewBuilder
    private func feedNameCell(for feed: Feed) -> some View {
        HStack(spacing: 8) {
            FaviconView(url: feed.url, size: 16)

            Text(feed.name)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func categoryCell(for feed: Feed) -> some View {
        Menu {
            Button("None") {
                updateCategory(for: feed, to: nil)
            }

            Divider()

            ForEach(appState.categories, id: \.self) { category in
                Button(category) {
                    updateCategory(for: feed, to: category)
                }
            }

            Divider()

            Button("New Category...") {
                // Could show a sheet to create new category
            }
        } label: {
            HStack {
                Text(feed.category ?? "None")
                    .foregroundStyle(feed.category == nil ? .tertiary : .primary)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Actions

    private func deleteSelectedFeeds() {
        let idsToDelete = Array(selectedFeedIds)
        Task {
            do {
                try await appState.bulkDeleteFeeds(feedIds: idsToDelete)
                selectedFeedIds.removeAll()
            } catch {
                print("Failed to delete feeds: \(error)")
            }
        }
    }

    private func refreshSelectedFeeds() {
        for feedId in selectedFeedIds {
            Task {
                do {
                    try await appState.apiClient.refreshFeed(id: feedId)
                } catch {
                    print("Failed to refresh feed \(feedId): \(error)")
                }
            }
        }
    }

    private func refreshFeed(_ feed: Feed) {
        Task {
            do {
                try await appState.apiClient.refreshFeed(id: feed.id)
            } catch {
                print("Failed to refresh feed: \(error)")
            }
        }
    }

    private func copyFeedURL(_ feed: Feed) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(feed.url.absoluteString, forType: .string)
    }

    private func updateCategory(for feed: Feed, to category: String?) {
        Task {
            do {
                try await appState.updateFeed(feedId: feed.id, category: category ?? "")
            } catch {
                print("Failed to update category: \(error)")
            }
        }
    }

    private func exportOPML() {
        isExporting = true

        Task {
            do {
                let opmlContent = try await appState.exportOPML()

                // Show save panel
                await MainActor.run {
                    let savePanel = NSSavePanel()
                    savePanel.allowedContentTypes = [UTType(filenameExtension: "opml") ?? .xml]
                    savePanel.nameFieldStringValue = "Data Points Feeds.opml"
                    savePanel.title = "Export Feeds"
                    savePanel.message = "Choose where to save your feeds"

                    if savePanel.runModal() == .OK, let url = savePanel.url {
                        do {
                            try opmlContent.write(to: url, atomically: true, encoding: .utf8)
                        } catch {
                            exportError = "Failed to save file: \(error.localizedDescription)"
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    exportError = error.localizedDescription
                }
            }

            await MainActor.run {
                isExporting = false
            }
        }
    }
}

// MARK: - Supporting Types

enum FeedSortOrder: String, CaseIterable {
    case name = "name"
    case category = "category"
    case status = "status"
    case lastFetched = "lastFetched"

    var label: String {
        switch self {
        case .name: return "Name"
        case .category: return "Category"
        case .status: return "Status"
        case .lastFetched: return "Last Fetched"
        }
    }
}

extension FeedHealthStatus {
    var sortPriority: Int {
        switch self {
        case .error: return 0
        case .neverFetched: return 1
        case .stale: return 2
        case .healthy: return 3
        }
    }
}

// MARK: - Feed Health Badge

struct FeedHealthBadge: View {
    let status: FeedHealthStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(statusLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .help(status.description)
    }

    private var statusColor: Color {
        switch status {
        case .healthy: return .green
        case .stale: return .yellow
        case .error: return .red
        case .neverFetched: return .gray
        }
    }

    private var statusLabel: String {
        switch status {
        case .healthy: return "OK"
        case .stale: return "Stale"
        case .error: return "Error"
        case .neverFetched: return "New"
        }
    }
}

// MARK: - Edit Feed Sheet

struct EditFeedSheet: View {
    let feed: Feed
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var selectedCategory: String?
    @State private var newCategory: String = ""
    @State private var showingNewCategory = false
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Feed")
                .font(.headline)

            // Feed URL (read-only)
            VStack(alignment: .leading, spacing: 4) {
                Text("URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text(feed.url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(feed.url.absoluteString, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .help("Copy URL")
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Feed name
            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Feed Name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            // Category picker
            VStack(alignment: .leading, spacing: 4) {
                Text("Category")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Category", selection: $selectedCategory) {
                    Text("None").tag(nil as String?)
                    Divider()
                    ForEach(appState.categories, id: \.self) { category in
                        Text(category).tag(category as String?)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            // Health status
            HStack {
                Text("Status:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                FeedHealthBadge(status: feed.healthStatus)

                Spacer()
            }

            Spacer()

            // Buttons
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
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400, height: 350)
        .onAppear {
            name = feed.name
            selectedCategory = feed.category
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        isSaving = true
        Task {
            do {
                // Update name if changed
                if trimmedName != feed.name {
                    try await appState.updateFeed(feedId: feed.id, name: trimmedName)
                }

                // Update category if changed
                if selectedCategory != feed.category {
                    try await appState.updateFeed(feedId: feed.id, category: selectedCategory ?? "")
                }

                dismiss()
            } catch {
                print("Failed to update feed: \(error)")
            }
            isSaving = false
        }
    }
}

#Preview {
    FeedManagerView()
        .environmentObject(AppState())
}
