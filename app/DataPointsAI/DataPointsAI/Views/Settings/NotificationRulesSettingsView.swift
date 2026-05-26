import SwiftUI

/// Notification Rules settings tab
struct NotificationRulesSettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var notificationService = NotificationService.shared

    @State private var rules: [APIClient.NotificationRule] = []
    @State private var history: [APIClient.NotificationHistoryEntry] = []
    @State private var isLoading = true
    @State private var isLoadingHistory = false
    @State private var showAddRuleSheet = false
    @State private var editingRule: APIClient.NotificationRule?
    @State private var showHistory = false

    // New rule form state
    @State private var newRuleName = ""
    @State private var newRuleKeyword = ""
    @State private var newRuleAuthor = ""
    @State private var newRuleFeedId: Int?
    @State private var newRulePriority = "normal"

    var body: some View {
        Form {
            Section {
                if !notificationService.isAuthorized {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        VStack(alignment: .leading) {
                            Text("Notifications are disabled")
                                .fontWeight(.medium)
                            Text("Enable notifications in System Settings to use smart notification rules.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Open Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .font(.caption)
                    }
                }
            }

            Section {
                if isLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading rules...")
                            .foregroundStyle(.secondary)
                    }
                } else if rules.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No notification rules yet")
                            .foregroundStyle(.secondary)
                        Text("Create rules to get notified about specific keywords, authors, or feeds.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(rules) { rule in
                        NotificationRuleRow(
                            rule: rule,
                            onToggle: { toggleRule(rule) },
                            onEdit: { editingRule = rule },
                            onDelete: { deleteRule(rule) }
                        )
                    }
                }

                Button {
                    resetNewRuleForm()
                    showAddRuleSheet = true
                } label: {
                    Label("Add Rule", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Notification Rules")
            } footer: {
                Text("Rules are evaluated when new articles arrive. Matching articles trigger notifications based on priority.")
            }

            Section {
                DisclosureGroup("Recent Notifications", isExpanded: $showHistory) {
                    if isLoadingHistory {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading...")
                                .foregroundStyle(.secondary)
                        }
                    } else if history.isEmpty {
                        Text("No recent notifications")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(history.prefix(10)) { entry in
                            NotificationHistoryRow(entry: entry, onOpen: {
                                openArticle(entry.articleId)
                            })
                        }

                        if !history.isEmpty {
                            Button("Dismiss All") {
                                dismissAllNotifications()
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .onChange(of: showHistory) { _, isExpanded in
                    if isExpanded {
                        Task {
                            await loadHistory()
                        }
                    }
                }
            } header: {
                Text("History")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("High Priority", systemImage: "bell.badge.fill")
                        .foregroundStyle(.red)
                    Text("Urgent notifications that break through Focus modes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Normal Priority", systemImage: "bell.fill")
                        .foregroundStyle(.blue)
                    Text("Standard notifications grouped by app")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Low Priority", systemImage: "bell")
                        .foregroundStyle(.gray)
                    Text("Silent notifications in Notification Center only")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Priority Levels")
            }
        }
        .formStyle(.grouped)
        .task {
            await loadRules()
            await notificationService.checkAuthorizationStatus()
        }
        .sheet(isPresented: $showAddRuleSheet) {
            addRuleSheet
        }
        .sheet(item: $editingRule) { rule in
            editRuleSheet(rule: rule)
        }
    }

    private var addRuleSheet: some View {
        VStack(spacing: 20) {
            Text("New Notification Rule")
                .font(.headline)

            Form {
                TextField("Rule name", text: $newRuleName)

                Section {
                    TextField("Keyword (optional)", text: $newRuleKeyword)
                    TextField("Author (optional)", text: $newRuleAuthor)

                    Picker("Feed (optional)", selection: $newRuleFeedId) {
                        Text("All feeds").tag(nil as Int?)
                        ForEach(appState.feeds, id: \.id) { feed in
                            Text(feed.name).tag(feed.id as Int?)
                        }
                    }
                } header: {
                    Text("Filters (at least one required)")
                }

                Picker("Priority", selection: $newRulePriority) {
                    Text("High").tag("high")
                    Text("Normal").tag("normal")
                    Text("Low").tag("low")
                }
            }
            .frame(height: 250)

            HStack {
                Button("Cancel") {
                    showAddRuleSheet = false
                }
                .keyboardShortcut(.escape)

                Button("Create") {
                    createRule()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(newRuleName.isEmpty || (newRuleKeyword.isEmpty && newRuleAuthor.isEmpty && newRuleFeedId == nil))
            }
        }
        .padding(30)
        .frame(width: 400)
    }

    @ViewBuilder
    private func editRuleSheet(rule: APIClient.NotificationRule) -> some View {
        EditNotificationRuleSheet(
            rule: rule,
            feeds: appState.feeds,
            onSave: { updatedRule in
                Task {
                    await updateRule(updatedRule)
                }
            },
            onCancel: { editingRule = nil }
        )
    }

    private func loadRules() async {
        do {
            let fetchedRules = try await appState.apiClient.getNotificationRules()
            await MainActor.run {
                rules = fetchedRules
                isLoading = false
            }
        } catch {
            await MainActor.run {
                isLoading = false
            }
            print("Failed to load notification rules: \(error)")
        }
    }

    private func resetNewRuleForm() {
        newRuleName = ""
        newRuleKeyword = ""
        newRuleAuthor = ""
        newRuleFeedId = nil
        newRulePriority = "normal"
    }

    private func createRule() {
        Task {
            do {
                let rule = try await appState.apiClient.createNotificationRule(
                    name: newRuleName,
                    feedId: newRuleFeedId,
                    keyword: newRuleKeyword.isEmpty ? nil : newRuleKeyword,
                    author: newRuleAuthor.isEmpty ? nil : newRuleAuthor,
                    priority: newRulePriority
                )
                await MainActor.run {
                    rules.insert(rule, at: 0)
                    showAddRuleSheet = false
                }
            } catch {
                print("Failed to create rule: \(error)")
            }
        }
    }

    private func toggleRule(_ rule: APIClient.NotificationRule) {
        Task {
            do {
                let updated = try await appState.apiClient.updateNotificationRule(
                    id: rule.id,
                    enabled: !rule.enabled
                )
                await MainActor.run {
                    if let index = rules.firstIndex(where: { $0.id == rule.id }) {
                        rules[index] = updated
                    }
                }
            } catch {
                print("Failed to toggle rule: \(error)")
            }
        }
    }

    private func updateRule(_ update: (id: Int, name: String?, keyword: String?, author: String?, feedId: Int?, clearFeed: Bool, priority: String?)) async {
        do {
            let updated = try await appState.apiClient.updateNotificationRule(
                id: update.id,
                name: update.name,
                feedId: update.feedId,
                clearFeed: update.clearFeed,
                keyword: update.keyword,
                clearKeyword: update.keyword == nil,
                author: update.author,
                clearAuthor: update.author == nil,
                priority: update.priority
            )
            await MainActor.run {
                if let index = rules.firstIndex(where: { $0.id == update.id }) {
                    rules[index] = updated
                }
                editingRule = nil
            }
        } catch {
            print("Failed to update rule: \(error)")
        }
    }

    private func deleteRule(_ rule: APIClient.NotificationRule) {
        Task {
            do {
                try await appState.apiClient.deleteNotificationRule(id: rule.id)
                await MainActor.run {
                    rules.removeAll { $0.id == rule.id }
                }
            } catch {
                print("Failed to delete rule: \(error)")
            }
        }
    }

    private func loadHistory() async {
        isLoadingHistory = true
        do {
            let fetchedHistory = try await appState.apiClient.getNotificationHistory()
            await MainActor.run {
                history = fetchedHistory
                isLoadingHistory = false
            }
        } catch {
            await MainActor.run {
                isLoadingHistory = false
            }
            print("Failed to load notification history: \(error)")
        }
    }

    private func dismissAllNotifications() {
        Task {
            do {
                try await appState.apiClient.dismissAllNotifications()
                await MainActor.run {
                    history.removeAll()
                }
            } catch {
                print("Failed to dismiss notifications: \(error)")
            }
        }
    }

    private func openArticle(_ articleId: Int) {
        // Select the article to navigate to it
        appState.selectedArticleIds = [articleId]
    }
}

/// Row for notification history entry
struct NotificationHistoryRow: View {
    let entry: APIClient.NotificationHistoryEntry
    let onOpen: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.articleTitle ?? "Unknown Article")
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let ruleName = entry.ruleName {
                        Label(ruleName, systemImage: "bell")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(formatDate(entry.notifiedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: onOpen) {
                Image(systemName: "arrow.right.circle")
            }
            .buttonStyle(.borderless)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// Row for a notification rule
struct NotificationRuleRow: View {
    let rule: APIClient.NotificationRule
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(rule.name)
                        .fontWeight(.medium)
                    priorityBadge
                }

                HStack(spacing: 8) {
                    if let keyword = rule.keyword {
                        Label(keyword, systemImage: "magnifyingglass")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let author = rule.author {
                        Label(author, systemImage: "person")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let feedName = rule.feedName {
                        Label(feedName, systemImage: "newspaper")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Toggle("", isOn: .init(
                get: { rule.enabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private var priorityBadge: some View {
        switch rule.priority {
        case "high":
            Image(systemName: "bell.badge.fill")
                .foregroundStyle(.red)
                .font(.caption)
        case "low":
            Image(systemName: "bell")
                .foregroundStyle(.gray)
                .font(.caption)
        default:
            Image(systemName: "bell.fill")
                .foregroundStyle(.blue)
                .font(.caption)
        }
    }
}

/// Sheet for editing a notification rule
struct EditNotificationRuleSheet: View {
    let rule: APIClient.NotificationRule
    let feeds: [Feed]
    let onSave: ((id: Int, name: String?, keyword: String?, author: String?, feedId: Int?, clearFeed: Bool, priority: String?)) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var keyword: String
    @State private var author: String
    @State private var feedId: Int?
    @State private var priority: String

    init(rule: APIClient.NotificationRule, feeds: [Feed], onSave: @escaping ((id: Int, name: String?, keyword: String?, author: String?, feedId: Int?, clearFeed: Bool, priority: String?)) -> Void, onCancel: @escaping () -> Void) {
        self.rule = rule
        self.feeds = feeds
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: rule.name)
        _keyword = State(initialValue: rule.keyword ?? "")
        _author = State(initialValue: rule.author ?? "")
        _feedId = State(initialValue: rule.feedId)
        _priority = State(initialValue: rule.priority)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Notification Rule")
                .font(.headline)

            Form {
                TextField("Rule name", text: $name)

                Section {
                    TextField("Keyword", text: $keyword)
                    TextField("Author", text: $author)

                    Picker("Feed", selection: $feedId) {
                        Text("All feeds").tag(nil as Int?)
                        ForEach(feeds, id: \.id) { feed in
                            Text(feed.name).tag(feed.id as Int?)
                        }
                    }
                } header: {
                    Text("Filters")
                }

                Picker("Priority", selection: $priority) {
                    Text("High").tag("high")
                    Text("Normal").tag("normal")
                    Text("Low").tag("low")
                }
            }
            .frame(height: 250)

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape)

                Button("Save") {
                    onSave((
                        id: rule.id,
                        name: name != rule.name ? name : nil,
                        keyword: keyword.isEmpty ? nil : keyword,
                        author: author.isEmpty ? nil : author,
                        feedId: feedId,
                        clearFeed: feedId == nil && rule.feedId != nil,
                        priority: priority != rule.priority ? priority : nil
                    ))
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
        }
        .padding(30)
        .frame(width: 400)
    }
}

