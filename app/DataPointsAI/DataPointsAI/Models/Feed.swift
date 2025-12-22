import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Feed model (matches FeedResponse from API)
struct Feed: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    let url: URL
    var name: String
    var category: String?
    var unreadCount: Int
    let lastFetched: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case url
        case name
        case category
        case unreadCount = "unread_count"
        case lastFetched = "last_fetched"
    }
}

// MARK: - Drag and Drop Support

/// Custom UTType for feed drag and drop
extension UTType {
    static let feedTransfer = UTType(exportedAs: "com.datapointsai.feed-transfer")
}

/// Transferable data for dragging feeds between categories
struct FeedTransfer: Codable, Transferable {
    let feedIds: [Int]

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .feedTransfer)
    }
}

/// Filter options for article list
enum ArticleFilter: Hashable, Codable {
    case all
    case unread
    case today
    case bookmarked
    case summarized
    case unsummarized
    case feed(Int)

    // Custom coding for the associated value case
    private enum CodingKeys: String, CodingKey {
        case type, feedId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "all": self = .all
        case "unread": self = .unread
        case "today": self = .today
        case "bookmarked": self = .bookmarked
        case "summarized": self = .summarized
        case "unsummarized": self = .unsummarized
        case "feed":
            let feedId = try container.decode(Int.self, forKey: .feedId)
            self = .feed(feedId)
        default: self = .all
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .all: try container.encode("all", forKey: .type)
        case .unread: try container.encode("unread", forKey: .type)
        case .today: try container.encode("today", forKey: .type)
        case .bookmarked: try container.encode("bookmarked", forKey: .type)
        case .summarized: try container.encode("summarized", forKey: .type)
        case .unsummarized: try container.encode("unsummarized", forKey: .type)
        case .feed(let feedId):
            try container.encode("feed", forKey: .type)
            try container.encode(feedId, forKey: .feedId)
        }
    }

    var displayName: String {
        switch self {
        case .all: return "All Articles"
        case .unread: return "Unread"
        case .today: return "Today"
        case .bookmarked: return "Saved"
        case .summarized: return "Summarized"
        case .unsummarized: return "Unsummarized"
        case .feed: return "Feed"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "tray.full"
        case .unread: return "circle.fill"
        case .today: return "sun.max.fill"
        case .bookmarked: return "star.fill"
        case .summarized: return "sparkles"
        case .unsummarized: return "sparkles.rectangle.stack"
        case .feed: return "dot.radiowaves.up.forward"
        }
    }
}

/// LLM provider options
enum LLMProvider: String, Codable, CaseIterable, Sendable {
    case anthropic = "anthropic"
    case openai = "openai"
    case google = "google"

    var label: String {
        switch self {
        case .anthropic: return "Anthropic Claude"
        case .openai: return "OpenAI GPT"
        case .google: return "Google Gemini"
        }
    }

    var description: String {
        switch self {
        case .anthropic: return "Claude models with prompt caching for lower costs"
        case .openai: return "GPT models from OpenAI"
        case .google: return "Gemini models with large context windows"
        }
    }

    /// Available model tiers for this provider
    var modelOptions: [(value: String, label: String, description: String)] {
        switch self {
        case .anthropic:
            return [
                ("haiku", "Haiku (Faster)", "Fast and cost-effective for simple articles"),
                ("sonnet", "Sonnet (Smarter)", "Better quality for complex content")
            ]
        case .openai:
            return [
                ("fast", "GPT-5.2 Mini (Faster)", "Fast and cost-effective"),
                ("standard", "GPT-5.2 (Smarter)", "Higher quality summaries")
            ]
        case .google:
            return [
                ("flash", "Gemini Flash (Faster)", "Fast with large context"),
                ("pro", "Gemini Pro (Smarter)", "Best quality from Google")
            ]
        }
    }
}

/// Application settings (matches SettingsResponse from API)
struct AppSettings: Codable, Sendable {
    var refreshIntervalMinutes: Int
    var autoSummarize: Bool
    var markReadOnOpen: Bool
    var defaultModel: String
    var llmProvider: LLMProvider

    // Client-side only settings (not synced with backend)
    var notificationsEnabled: Bool = true

    // Appearance settings (client-side only)
    var articleFontSize: ArticleFontSize = .medium
    var articleLineSpacing: ArticleLineSpacing = .normal
    var listDensity: ListDensity = .comfortable
    var appTypeface: AppTypeface = .system
    var contentTypeface: ContentTypeface = .system

    enum CodingKeys: String, CodingKey {
        case refreshIntervalMinutes = "refresh_interval_minutes"
        case autoSummarize = "auto_summarize"
        case markReadOnOpen = "mark_read_on_open"
        case defaultModel = "default_model"
        case llmProvider = "llm_provider"
        // Client-side settings are not sent to/from API
    }

    static let `default` = AppSettings(
        refreshIntervalMinutes: 30,
        autoSummarize: false,
        markReadOnOpen: true,
        defaultModel: "haiku",
        llmProvider: .anthropic,
        notificationsEnabled: true,
        articleFontSize: .medium,
        articleLineSpacing: .normal,
        listDensity: .comfortable,
        appTypeface: .system,
        contentTypeface: .system
    )
}

/// Font size options for article content
enum ArticleFontSize: String, Codable, CaseIterable, Sendable {
    case small = "small"
    case medium = "medium"
    case large = "large"
    case extraLarge = "extra_large"

    var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        }
    }

    var bodyFontSize: CGFloat {
        switch self {
        case .small: return 13
        case .medium: return 15
        case .large: return 17
        case .extraLarge: return 20
        }
    }

    var titleFontSize: CGFloat {
        switch self {
        case .small: return 18
        case .medium: return 22
        case .large: return 26
        case .extraLarge: return 30
        }
    }
}

/// Line spacing options for article content
enum ArticleLineSpacing: String, Codable, CaseIterable, Sendable {
    case compact = "compact"
    case normal = "normal"
    case relaxed = "relaxed"

    var label: String {
        switch self {
        case .compact: return "Compact"
        case .normal: return "Normal"
        case .relaxed: return "Relaxed"
        }
    }

    var multiplier: CGFloat {
        switch self {
        case .compact: return 1.2
        case .normal: return 1.5
        case .relaxed: return 1.8
        }
    }
}

/// List density options for article list
enum ListDensity: String, Codable, CaseIterable, Sendable {
    case compact = "compact"
    case comfortable = "comfortable"
    case spacious = "spacious"

    var label: String {
        switch self {
        case .compact: return "Compact"
        case .comfortable: return "Comfortable"
        case .spacious: return "Spacious"
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .compact: return 4
        case .comfortable: return 8
        case .spacious: return 12
        }
    }

    var showSummaryPreview: Bool {
        switch self {
        case .compact: return false
        case .comfortable, .spacious: return true
        }
    }
}

/// Typeface options for the application UI
enum AppTypeface: String, Codable, CaseIterable, Sendable {
    // Sans-serif
    case system = "system"
    case helveticaNeue = "helvetica_neue"
    case avenir = "avenir"
    case avenirNext = "avenir_next"
    // Serif
    case newYork = "new_york"
    case georgia = "georgia"
    case palatino = "palatino"
    case charter = "charter"
    case iowan = "iowan"
    case baskerville = "baskerville"
    // Other
    case americanTypewriter = "american_typewriter"
    case sfMono = "sf_mono"

    var label: String {
        switch self {
        case .system: return "System (San Francisco)"
        case .helveticaNeue: return "Helvetica Neue"
        case .avenir: return "Avenir"
        case .avenirNext: return "Avenir Next"
        case .newYork: return "New York"
        case .georgia: return "Georgia"
        case .palatino: return "Palatino"
        case .charter: return "Charter"
        case .iowan: return "Iowan Old Style"
        case .baskerville: return "Baskerville"
        case .americanTypewriter: return "American Typewriter"
        case .sfMono: return "SF Mono"
        }
    }

    /// Returns the SwiftUI Font.Design for system fonts, or nil for custom fonts
    var fontDesign: Font.Design? {
        switch self {
        case .system: return .default
        case .newYork: return .serif
        case .sfMono: return .monospaced
        default: return nil
        }
    }

    /// Returns the font family name for custom fonts
    var fontFamily: String? {
        switch self {
        case .system, .newYork, .sfMono: return nil
        case .helveticaNeue: return "Helvetica Neue"
        case .avenir: return "Avenir"
        case .avenirNext: return "Avenir Next"
        case .georgia: return "Georgia"
        case .palatino: return "Palatino"
        case .charter: return "Charter"
        case .iowan: return "Iowan Old Style"
        case .baskerville: return "Baskerville"
        case .americanTypewriter: return "American Typewriter"
        }
    }

    /// Creates a SwiftUI Font with this typeface
    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let family = fontFamily {
            // Use custom font family
            let weightSuffix: String
            switch weight {
            case .bold, .semibold, .heavy, .black:
                weightSuffix = "-Bold"
            case .light, .ultraLight, .thin:
                weightSuffix = "-Light"
            default:
                weightSuffix = ""
            }
            // Try the weighted variant first, fall back to base font
            if let _ = NSFont(name: family + weightSuffix, size: size) {
                return Font.custom(family + weightSuffix, size: size)
            }
            return Font.custom(family, size: size)
        } else if let design = fontDesign {
            return Font.system(size: size, weight: weight, design: design)
        } else {
            return Font.system(size: size, weight: weight)
        }
    }
}

/// Typeface options for HTML content view
enum ContentTypeface: String, Codable, CaseIterable, Sendable {
    // Sans-serif
    case system = "system"
    case helveticaNeue = "helvetica_neue"
    case avenir = "avenir"
    case avenirNext = "avenir_next"
    // Serif
    case serif = "serif"
    case georgia = "georgia"
    case palatino = "palatino"
    case charter = "charter"
    case iowan = "iowan"
    case baskerville = "baskerville"
    case times = "times"
    // Other
    case americanTypewriter = "american_typewriter"
    case menlo = "menlo"

    var label: String {
        switch self {
        case .system: return "System (San Francisco)"
        case .helveticaNeue: return "Helvetica Neue"
        case .avenir: return "Avenir"
        case .avenirNext: return "Avenir Next"
        case .serif: return "System Serif (New York)"
        case .georgia: return "Georgia"
        case .palatino: return "Palatino"
        case .charter: return "Charter"
        case .iowan: return "Iowan Old Style"
        case .baskerville: return "Baskerville"
        case .times: return "Times New Roman"
        case .americanTypewriter: return "American Typewriter"
        case .menlo: return "Menlo"
        }
    }

    /// Returns the CSS font-family value
    var cssFontFamily: String {
        switch self {
        case .system:
            return "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif"
        case .helveticaNeue:
            return "'Helvetica Neue', Helvetica, Arial, sans-serif"
        case .avenir:
            return "Avenir, 'Helvetica Neue', Helvetica, Arial, sans-serif"
        case .avenirNext:
            return "'Avenir Next', Avenir, 'Helvetica Neue', Helvetica, Arial, sans-serif"
        case .serif:
            return "'New York', 'Iowan Old Style', Georgia, serif"
        case .georgia:
            return "Georgia, 'Times New Roman', serif"
        case .palatino:
            return "Palatino, 'Palatino Linotype', 'Book Antiqua', serif"
        case .charter:
            return "Charter, Georgia, serif"
        case .iowan:
            return "'Iowan Old Style', Georgia, serif"
        case .baskerville:
            return "Baskerville, 'Baskerville Old Face', Georgia, serif"
        case .times:
            return "'Times New Roman', Times, serif"
        case .americanTypewriter:
            return "'American Typewriter', 'Courier New', Courier, monospace"
        case .menlo:
            return "Menlo, Monaco, 'SF Mono', 'Courier New', monospace"
        }
    }
}

/// API health status
struct APIStatus: Codable, Sendable {
    let status: String
    let version: String
    let summarizationEnabled: Bool
    let provider: String?

    enum CodingKeys: String, CodingKey {
        case status
        case version
        case summarizationEnabled = "summarization_enabled"
        case provider
    }

    var isHealthy: Bool { status == "ok" }
}

/// Server health status for UI display
enum ServerHealthStatus: Equatable {
    case unknown
    case healthy(summarizationEnabled: Bool)
    case unhealthy(error: String)
    case checking

    var isHealthy: Bool {
        if case .healthy = self { return true }
        return false
    }

    var statusText: String {
        switch self {
        case .unknown: return "Unknown"
        case .healthy(let summarizationEnabled):
            return summarizationEnabled ? "Connected" : "Connected (no API key)"
        case .unhealthy(let error): return "Error: \(error)"
        case .checking: return "Checking..."
        }
    }

    var statusColor: String {
        switch self {
        case .healthy(let summarizationEnabled):
            return summarizationEnabled ? "green" : "yellow"
        case .unhealthy: return "red"
        case .unknown, .checking: return "gray"
        }
    }
}

/// Statistics from the API
struct Stats: Codable, Sendable {
    let totalFeeds: Int
    let totalUnread: Int
    let refreshInProgress: Bool

    enum CodingKeys: String, CodingKey {
        case totalFeeds = "total_feeds"
        case totalUnread = "total_unread"
        case refreshInProgress = "refresh_in_progress"
    }
}
