import Foundation
import AppKit
import UniformTypeIdentifiers

// MARK: - Library Operations
extension AppState {

    func loadLibraryItems() async {
        do {
            let response = try await apiClient.getLibraryItems()
            libraryItems = response.items
            libraryItemCount = response.total
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadLibraryItemDetail(for item: LibraryItem) async {
        do {
            selectedLibraryItemDetail = try await apiClient.getLibraryItem(id: item.id)

            if settings.markReadOnOpen && !item.isRead {
                try await markLibraryItemRead(itemId: item.id)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func addURLToLibrary(url: String, title: String? = nil, autoSummarize: Bool = false) async throws {
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
    }

    func deleteLibraryItem(itemId: Int) async throws {
        try await apiClient.deleteLibraryItem(id: itemId)

        libraryItems.removeAll { $0.id == itemId }
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
        if selectedLibraryItemDetail?.id == itemId {
            selectedLibraryItemDetail?.isRead = isRead
        }
    }

    func toggleLibraryItemBookmark(itemId: Int) async throws {
        let result = try await apiClient.toggleLibraryItemBookmark(id: itemId)

        if let index = libraryItems.firstIndex(where: { $0.id == itemId }) {
            libraryItems[index].isBookmarked = result.isBookmarked
        }
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

    func selectLibrary() {
        showLibrary = true
        // Don't change selectedFilter - it triggers onChange handler which interferes
        // with library mode. The filter is separate from library view.
        selectedArticle = nil
        selectedArticleDetail = nil
        Task {
            await loadLibraryItems()
        }
    }

    func deselectLibrary() {
        showLibrary = false
        selectedLibraryItem = nil
        selectedLibraryItemDetail = nil
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
