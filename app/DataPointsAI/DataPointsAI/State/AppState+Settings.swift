import Foundation

// MARK: - Settings Operations
extension AppState {

    func updateSettings(_ newSettings: AppSettings) async throws {
        let savedAppearance = (
            fontSize: newSettings.articleFontSize,
            lineSpacing: newSettings.articleLineSpacing,
            listDensity: newSettings.listDensity,
            notifications: newSettings.notificationsEnabled,
            appTypeface: newSettings.appTypeface,
            contentTypeface: newSettings.contentTypeface
        )

        var updatedSettings = try await apiClient.updateSettings(newSettings)

        updatedSettings.articleFontSize = savedAppearance.fontSize
        updatedSettings.articleLineSpacing = savedAppearance.lineSpacing
        updatedSettings.listDensity = savedAppearance.listDensity
        updatedSettings.notificationsEnabled = savedAppearance.notifications
        updatedSettings.appTypeface = savedAppearance.appTypeface
        updatedSettings.contentTypeface = savedAppearance.contentTypeface

        settings = updatedSettings
        saveLocalSettings()
    }

    internal func saveLocalSettings() {
        UserDefaults.standard.set(settings.articleFontSize.rawValue, forKey: "articleFontSize")
        UserDefaults.standard.set(settings.articleLineSpacing.rawValue, forKey: "articleLineSpacing")
        UserDefaults.standard.set(settings.listDensity.rawValue, forKey: "listDensity")
        UserDefaults.standard.set(settings.notificationsEnabled, forKey: "notificationsEnabled")
        UserDefaults.standard.set(settings.appTypeface.rawValue, forKey: "appTypeface")
        UserDefaults.standard.set(settings.contentTypeface.rawValue, forKey: "contentTypeface")
        UserDefaults.standard.set(settings.hideDuplicates, forKey: "hideDuplicates")
        UserDefaults.standard.set(settings.autoArchiveEnabled, forKey: "autoArchiveEnabled")
        UserDefaults.standard.set(settings.autoArchiveDays, forKey: "autoArchiveDays")
        UserDefaults.standard.set(settings.archiveKeepBookmarked, forKey: "archiveKeepBookmarked")
        UserDefaults.standard.set(settings.archiveKeepUnread, forKey: "archiveKeepUnread")
        saveWindowState()
    }

    func saveWindowState() {
        UserDefaults.standard.set(Array(collapsedCategories), forKey: "collapsedCategories")

        if let filterData = try? JSONEncoder().encode(selectedFilter) {
            UserDefaults.standard.set(filterData, forKey: "selectedFilter")
        }
    }

    internal func loadLocalSettings() {
        if let fontSizeRaw = UserDefaults.standard.string(forKey: "articleFontSize"),
           let fontSize = ArticleFontSize(rawValue: fontSizeRaw) {
            settings.articleFontSize = fontSize
        }
        if let lineSpacingRaw = UserDefaults.standard.string(forKey: "articleLineSpacing"),
           let lineSpacing = ArticleLineSpacing(rawValue: lineSpacingRaw) {
            settings.articleLineSpacing = lineSpacing
        }
        if let densityRaw = UserDefaults.standard.string(forKey: "listDensity"),
           let density = ListDensity(rawValue: densityRaw) {
            settings.listDensity = density
        }
        if UserDefaults.standard.object(forKey: "notificationsEnabled") != nil {
            settings.notificationsEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
        }
        if let appTypefaceRaw = UserDefaults.standard.string(forKey: "appTypeface"),
           let appTypeface = AppTypeface(rawValue: appTypefaceRaw) {
            settings.appTypeface = appTypeface
        }
        if let contentTypefaceRaw = UserDefaults.standard.string(forKey: "contentTypeface"),
           let contentTypeface = ContentTypeface(rawValue: contentTypefaceRaw) {
            settings.contentTypeface = contentTypeface
        }
        if UserDefaults.standard.object(forKey: "hideDuplicates") != nil {
            settings.hideDuplicates = UserDefaults.standard.bool(forKey: "hideDuplicates")
        }
        if UserDefaults.standard.object(forKey: "autoArchiveEnabled") != nil {
            settings.autoArchiveEnabled = UserDefaults.standard.bool(forKey: "autoArchiveEnabled")
        }
        if UserDefaults.standard.object(forKey: "autoArchiveDays") != nil {
            settings.autoArchiveDays = UserDefaults.standard.integer(forKey: "autoArchiveDays")
        }
        if UserDefaults.standard.object(forKey: "archiveKeepBookmarked") != nil {
            settings.archiveKeepBookmarked = UserDefaults.standard.bool(forKey: "archiveKeepBookmarked")
        }
        if UserDefaults.standard.object(forKey: "archiveKeepUnread") != nil {
            settings.archiveKeepUnread = UserDefaults.standard.bool(forKey: "archiveKeepUnread")
        }

        loadWindowState()
    }

    private func loadWindowState() {
        if let categories = UserDefaults.standard.stringArray(forKey: "collapsedCategories") {
            collapsedCategories = Set(categories)
        }

        if let filterData = UserDefaults.standard.data(forKey: "selectedFilter"),
           let filter = try? JSONDecoder().decode(ArticleFilter.self, from: filterData) {
            selectedFilter = filter
        }
    }

    // MARK: - Archive

    func archiveOldArticlesIfEnabled() async {
        guard settings.autoArchiveEnabled else { return }

        do {
            let result = try await apiClient.archiveOldArticles(
                days: settings.autoArchiveDays,
                keepBookmarked: settings.archiveKeepBookmarked,
                keepUnread: settings.archiveKeepUnread
            )

            if result.archivedCount > 0 {
                print("Archived \(result.archivedCount) old articles")
                await reloadArticles()
            }
        } catch {
            print("Failed to archive old articles: \(error)")
        }
    }
}
