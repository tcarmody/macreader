import Foundation
import AppKit
import UniformTypeIdentifiers

// MARK: - Library Operations
extension AppState {

    func loadLibraryItems() async {
        let requestID = UUID()
        libraryLoadID = requestID
        isLoadingLibrary = true
        defer { if libraryLoadID == requestID { isLoadingLibrary = false } }
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            var items: [LibraryItem] = []
            var offset = 0
            while true {
                let response = try await apiClient.getLibraryItems(limit: 500, offset: offset,
                    search: query.count >= Self.minSearchQueryLength ? query : nil)
                guard !Task.isCancelled, libraryLoadID == requestID else { return }
                items.append(contentsOf: response.items)
                libraryItemCount = response.total
                if response.items.count < 500 { break }
                offset += response.items.count
            }
            libraryItems = items
            selectedLibraryItemIds.formIntersection(Set(visibleLibraryItems.map(\.id)))
        } catch {
            if !error.isCancellation && libraryLoadID == requestID { self.error = error.localizedDescription }
        }
    }

    func loadLibraryItemDetail(for item: LibraryItem) async {
        let requestID = UUID()
        libraryDetailLoadID = requestID
        selectedLibraryItem = item
        selectedLibraryItemIds = [item.id]
        selectedLibraryItemDetail = nil
        isLoadingLibraryDetail = true
        defer { if libraryDetailLoadID == requestID { isLoadingLibraryDetail = false } }
        do {
            let detail = try await apiClient.getLibraryItem(id: item.id)
            guard libraryDetailLoadID == requestID, selectedLibraryItem?.id == item.id,
                  showLibrary, !Task.isCancelled else { return }
            selectedLibraryItemDetail = detail

            if settings.markReadOnOpen && !item.isRead {
                try await markLibraryItemRead(itemId: item.id)
            }
        } catch {
            if libraryDetailLoadID == requestID && !error.isCancellation {
                selectedLibraryItem = nil
                self.error = error.localizedDescription
            }
        }
    }

    var visibleLibraryItems: [LibraryItem] {
        libraryItems.filter { libraryFilterType == nil || $0.type == libraryFilterType }
            .sorted { lhs, rhs in
                switch librarySortOption {
                case .newestFirst: return lhs.createdAt == rhs.createdAt ? lhs.id > rhs.id : lhs.createdAt > rhs.createdAt
                case .oldestFirst: return lhs.createdAt == rhs.createdAt ? lhs.id < rhs.id : lhs.createdAt < rhs.createdAt
                case .unreadFirst:
                    if lhs.isRead != rhs.isRead { return !lhs.isRead }
                    return lhs.createdAt == rhs.createdAt ? lhs.id > rhs.id : lhs.createdAt > rhs.createdAt
                case .titleAZ: return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
                case .titleZA: return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedDescending
                }
            }
    }

    func clearLibrarySelection() {
        libraryDetailLoadID = UUID()
        selectedLibraryItem = nil
        selectedLibraryItemDetail = nil
        isLoadingLibraryDetail = false
    }

    func setLibrarySelection(_ ids: Set<Int>) {
        selectedLibraryItemIds = ids
        guard ids.count == 1, let id = ids.first,
              let item = libraryItems.first(where: { $0.id == id }) else {
            clearLibrarySelection()
            return
        }
        guard selectedLibraryItem?.id != id else { return }
        Task {
            guard selectedLibraryItemIds == [item.id], showLibrary else { return }
            await loadLibraryItemDetail(for: item)
        }
    }

    func navigateLibrary(by step: Int) {
        let items = visibleLibraryItems
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selectedLibraryItem?.id }
        let index = min(max((current ?? (step > 0 ? -1 : items.count)) + step, 0), items.count - 1)
        setLibrarySelection([items[index].id])
    }

    func markLibraryItemsRead(ids: Set<Int>, isRead: Bool) async {
        do {
            for id in ids { try await markLibraryItemRead(itemId: id, isRead: isRead) }
        } catch { self.error = error.localizedDescription }
    }

    /// Returns true if the URL already existed in the database (and was bookmarked), false if newly added.
    @discardableResult
    func addURLToLibrary(url: String, title: String? = nil, autoSummarize: Bool = false) async throws -> Bool {
        let item = try await apiClient.addURLToLibrary(url: url, title: title, autoSummarize: autoSummarize)
        await loadLibraryItems()

        selectedLibraryItem = LibraryItem(
            id: item.id,
            url: item.url,
            title: item.title,
            summaryShort: item.summaryShort,
            isRead: item.isRead,
            isBookmarked: item.isBookmarked,
            contentType: item.contentType,
            fileName: item.fileName,
            createdAt: item.createdAt
        )
        selectedLibraryItemDetail = item
        selectedLibraryItemIds = [item.id]
        return item.alreadyExisted
    }

    func uploadFileToLibrary(data: Data, filename: String, title: String? = nil, autoSummarize: Bool = false) async throws {
        let item = try await apiClient.uploadFileToLibrary(data: data, filename: filename, title: title, autoSummarize: autoSummarize)
        await loadLibraryItems()

        selectedLibraryItem = LibraryItem(
            id: item.id,
            url: item.url,
            title: item.title,
            summaryShort: item.summaryShort,
            isRead: item.isRead,
            isBookmarked: item.isBookmarked,
            contentType: item.contentType,
            fileName: item.fileName,
            createdAt: item.createdAt
        )
        selectedLibraryItemDetail = item
        selectedLibraryItemIds = [item.id]
    }

    func deleteLibraryItem(itemId: Int) async throws {
        try await apiClient.deleteLibraryItem(id: itemId)

        libraryItems.removeAll { $0.id == itemId }
        selectedLibraryItemIds.remove(itemId)
        libraryItemCount = max(0, libraryItemCount - 1)

        if selectedLibraryItem?.id == itemId {
            selectedLibraryItem = nil
            selectedLibraryItemDetail = nil
        }
    }

    func markLibraryItemRead(itemId: Int, isRead: Bool = true) async throws {
        try await apiClient.markLibraryItemRead(id: itemId, isRead: isRead)

        if let index = libraryItems.firstIndex(where: { $0.id == itemId }) {
            libraryItems[index].isRead = isRead
        }
        if selectedLibraryItem?.id == itemId { selectedLibraryItem?.isRead = isRead }
        if selectedLibraryItemDetail?.id == itemId {
            selectedLibraryItemDetail?.isRead = isRead
        }
    }

    func toggleLibraryItemBookmark(itemId: Int) async throws {
        let result = try await apiClient.toggleLibraryItemBookmark(id: itemId)

        if let index = libraryItems.firstIndex(where: { $0.id == itemId }) {
            libraryItems[index].isBookmarked = result.isBookmarked
        }
        if selectedLibraryItem?.id == itemId { selectedLibraryItem?.isBookmarked = result.isBookmarked }
        if selectedLibraryItemDetail?.id == itemId {
            selectedLibraryItemDetail?.isBookmarked = result.isBookmarked
        }
    }

    func summarizeLibraryItem(itemId: Int) async throws {
        try await apiClient.summarizeLibraryItem(id: itemId)

        for _ in 0..<60 {
            try await Task.sleep(nanoseconds: 1_000_000_000)

            let detail = try await apiClient.getLibraryItem(id: itemId)
            if detail.summaryFull != nil {
                if selectedLibraryItemDetail?.id == itemId {
                    self.selectedLibraryItemDetail = detail
                }
                return
            }
        }

        let detail = try await apiClient.getLibraryItem(id: itemId)
        if selectedLibraryItemDetail?.id == itemId {
            self.selectedLibraryItemDetail = detail
        }
    }

    /// Send a library item to the Composer research workbench. Updates the local
    /// detail cache so the "In Composer" state is reflected immediately.
    func promoteLibraryItemToComposer(itemId: Int) async throws {
        _ = try await apiClient.promoteToComposer(articleId: itemId)
        let now = ISO8601DateFormatter().string(from: Date())
        if selectedLibraryItemDetail?.id == itemId {
            selectedLibraryItemDetail?.promotedToComposer = now
        }
    }

    func loadRelatedLinksForLibraryItem(itemId: Int) async {
        isLoadingRelated = true

        do {
            // Trigger related links fetch
            try await apiClient.findRelatedLinksForLibraryItem(id: itemId)

            // Poll for completion (wait for background task to finish - success or error)
            for _ in 0..<30 {  // Poll for up to 30 seconds
                try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second

                let detail = try await apiClient.getLibraryItem(id: itemId)
                // Stop polling when we get either results OR an error
                if detail.relatedLinks != nil || detail.relatedLinksError != nil {
                    if selectedLibraryItemDetail?.id == itemId {
                        selectedLibraryItemDetail = detail
                    }
                    isLoadingRelated = false
                    return
                }
            }

            // Timeout - fetch one more time to get current state
            let detail = try await apiClient.getLibraryItem(id: itemId)
            if selectedLibraryItemDetail?.id == itemId {
                selectedLibraryItemDetail = detail
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoadingRelated = false
    }

    func selectLibrary() {
        showLibrary = true
        selectedFilter = .library
        selectedArticle = nil
        selectedArticleDetail = nil
        selectedArticleIds.removeAll()
        pendingDetailTab = nil
        Task {
            await loadLibraryItems()
        }
    }

    func deselectLibrary() {
        showLibrary = false
        clearLibrarySelection()
        selectedLibraryItemIds.removeAll()
        if selectedFilter == .library { selectedFilter = .all }
    }

    // MARK: - File Operations

    /// Open file picker to add file to library
    func openFilePickerForLibrary() {
        let panel = NSOpenPanel()
        panel.title = "Add File to Library"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .pdf,
            .plainText,
            .html,
            UTType(filenameExtension: "docx") ?? .data,
            UTType(filenameExtension: "md") ?? .text
        ]

        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task { @MainActor in
                    do {
                        let data = try Data(contentsOf: url)
                        let filename = url.lastPathComponent
                        try await self.uploadFileToLibrary(
                            data: data,
                            filename: filename,
                            title: url.deletingPathExtension().lastPathComponent,
                            autoSummarize: false
                        )
                    } catch {
                        self.error = "Failed to add file: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    // MARK: - Copy & Share Operations

    /// Copy library item title to clipboard
    func copyLibraryItemTitle() {
        guard let item = selectedLibraryItem else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.title, forType: .string)
    }

    /// Copy library item summary to clipboard
    func copyLibraryItemSummary() {
        guard let detail = selectedLibraryItemDetail,
              let summary = detail.summaryFull ?? detail.summaryShort else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
    }

    /// Share library item using native macOS sharing
    func shareLibraryItem() {
        guard let item = selectedLibraryItem else { return }

        var items: [Any] = [item.url]

        if let detail = selectedLibraryItemDetail,
           let summary = detail.summaryFull ?? detail.summaryShort, !summary.isEmpty {
            let shareText = "\(item.title)\n\n\(summary)\n\n\(item.url.absoluteString)"
            items.append(shareText)
        }

        let picker = NSSharingServicePicker(items: items)

        if let window = NSApp.keyWindow,
           let contentView = window.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
    }
}
