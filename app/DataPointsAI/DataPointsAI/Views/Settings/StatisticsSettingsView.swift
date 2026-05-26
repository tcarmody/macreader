import SwiftUI

/// Statistics settings tab
struct StatisticsSettingsView: View {
    @EnvironmentObject var appState: AppState

    @State private var stats: APIClient.ReadingStatsResponse?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedPeriodType: PeriodType = .rolling
    @State private var selectedPeriodValue: String = "30d"
    @State private var isClusteringTopics = false
    @State private var clusteringError: String?
    @State private var clusteringSuccess: String?

    enum PeriodType: String, CaseIterable {
        case rolling = "rolling"
        case calendar = "calendar"

        var label: String {
            switch self {
            case .rolling: return "Rolling Window"
            case .calendar: return "Calendar Period"
            }
        }
    }

    var periodOptions: [String] {
        switch selectedPeriodType {
        case .rolling:
            return ["7d", "30d", "90d"]
        case .calendar:
            return ["week", "month", "year"]
        }
    }

    var body: some View {
        Form {
            // Period Selector
            Section {
                Picker("Period Type", selection: $selectedPeriodType) {
                    ForEach(PeriodType.allCases, id: \.self) { type in
                        Text(type.label).tag(type)
                    }
                }
                .onChange(of: selectedPeriodType) { _, _ in
                    selectedPeriodValue = periodOptions.first ?? "30d"
                    Task { await loadStats() }
                }

                Picker("Time Period", selection: $selectedPeriodValue) {
                    ForEach(periodOptions, id: \.self) { option in
                        Text(formatPeriodLabel(option)).tag(option)
                    }
                }
                .onChange(of: selectedPeriodValue) { _, _ in
                    Task { await loadStats() }
                }
            } header: {
                Text("Time Period")
            }

            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading statistics...")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let error = loadError {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text(error)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let stats = stats {
                // Summarization Stats
                summarizationSection(stats.summarization)

                // Reading Stats
                readingSection(stats.reading)

                // Topic Stats
                topicSection(stats.topics)
            }

            // Topic Clustering Action
            Section {
                Button {
                    Task { await clusterTopics() }
                } label: {
                    if isClusteringTopics {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Analyzing topics...")
                        }
                    } else {
                        Label("Analyze Current Topics", systemImage: "sparkles")
                    }
                }
                .disabled(isClusteringTopics)

                if let error = clusteringError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if let success = clusteringSuccess {
                    Text(success)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            } header: {
                Text("Topic Analysis")
            } footer: {
                Text("Uses AI to group articles by topic and saves results for trend analysis.")
            }
        }
        .formStyle(.grouped)
        .task {
            await loadStats()
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func summarizationSection(_ stats: APIClient.SummarizationStats) -> some View {
        Section {
            StatRow(
                label: "Articles Summarized",
                value: "\(stats.summarizedArticles) of \(stats.totalArticles)",
                detail: String(format: "%.1f%%", stats.summarizationRate * 100)
            )

            StatRow(
                label: "Average per Day",
                value: String(format: "%.1f", stats.avgPerDay)
            )

            StatRow(
                label: "Average per Week",
                value: String(format: "%.1f", stats.avgPerWeek)
            )

            // Model breakdown
            if !stats.modelBreakdown.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model Usage")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    ForEach(Array(stats.modelBreakdown.keys.sorted()), id: \.self) { model in
                        HStack {
                            Text(formatModelName(model))
                            Spacer()
                            Text("\(stats.modelBreakdown[model] ?? 0)")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }
            }
        } header: {
            Label("Summarization", systemImage: "doc.text.magnifyingglass")
        }
    }

    @ViewBuilder
    private func readingSection(_ stats: APIClient.ReadingActivityStats) -> some View {
        Section {
            StatRow(
                label: "Articles Read",
                value: "\(stats.articlesRead)"
            )

            StatRow(
                label: "Total Reading Time",
                value: formatReadingTime(stats.totalReadingTimeMinutes)
            )

            StatRow(
                label: "Avg. per Article",
                value: String(format: "%.1f min", stats.avgReadingTimeMinutes)
            )

            StatRow(
                label: "Bookmarks Added",
                value: "\(stats.bookmarksAdded)"
            )

            // Top feeds by reading
            if !stats.readByFeed.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Most Read Feeds")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    ForEach(Array(stats.readByFeed.sorted { $0.value > $1.value }.prefix(5)), id: \.key) { feed, count in
                        HStack {
                            Text(feed)
                                .lineLimit(1)
                            Spacer()
                            Text("\(count) articles")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }
            }
        } header: {
            Label("Reading", systemImage: "book")
        }
    }

    @ViewBuilder
    private func topicSection(_ stats: APIClient.TopicStats) -> some View {
        Section {
            if stats.currentTopics.isEmpty && stats.mostCommon.isEmpty {
                Text("No topic data available. Run topic analysis to see trends.")
                    .foregroundStyle(.secondary)
            } else {
                // Current topics
                if !stats.currentTopics.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Current Topics")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        ForEach(stats.currentTopics.prefix(5), id: \.label) { topic in
                            HStack {
                                Text(topic.label)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(topic.count) articles")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                    }
                }

                // Most common topics (historical)
                if !stats.mostCommon.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Most Common Topics")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        ForEach(stats.mostCommon.prefix(5), id: \.label) { topic in
                            HStack {
                                Text(topic.label)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(topic.count) total")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                    }
                }
            }
        } header: {
            Label("Topics", systemImage: "tag")
        }
    }

    // MARK: - Helper Functions

    private func loadStats() async {
        isLoading = true
        loadError = nil

        do {
            let fetchedStats = try await appState.apiClient.getReadingStats(
                periodType: selectedPeriodType.rawValue,
                periodValue: selectedPeriodValue
            )
            await MainActor.run {
                stats = fetchedStats
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func clusterTopics() async {
        isClusteringTopics = true
        clusteringError = nil
        clusteringSuccess = nil

        do {
            let result = try await appState.apiClient.triggerTopicClustering()
            await MainActor.run {
                clusteringSuccess = "Found \(result.topics.count) topics across \(result.totalArticles) articles"
                isClusteringTopics = false
            }
            // Refresh stats to show new topics
            await loadStats()
        } catch {
            await MainActor.run {
                clusteringError = error.localizedDescription
                isClusteringTopics = false
            }
        }
    }

    private func formatPeriodLabel(_ value: String) -> String {
        switch value {
        case "7d": return "Last 7 days"
        case "30d": return "Last 30 days"
        case "90d": return "Last 90 days"
        case "week": return "This week"
        case "month": return "This month"
        case "year": return "This year"
        default: return value
        }
    }

    private func formatModelName(_ model: String) -> String {
        // Clean up model names for display
        model.replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: "gpt-", with: "GPT-")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private func formatReadingTime(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "\(hours)h"
            } else {
                return "\(hours)h \(remainingMinutes)m"
            }
        }
    }
}

/// Row displaying a statistic
struct StatRow: View {
    let label: String
    let value: String
    var detail: String? = nil

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            if let detail = detail {
                Text(detail)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            Text(value)
                .fontWeight(.medium)
        }
    }
}
