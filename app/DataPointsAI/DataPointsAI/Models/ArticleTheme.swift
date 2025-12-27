import Foundation
import SwiftUI
import AppKit

/// Article reading theme options
enum ArticleTheme: String, Codable, CaseIterable, Sendable {
    case auto = "auto"
    case manuscript = "manuscript"
    case noir = "noir"
    case ember = "ember"
    case forest = "forest"
    case ocean = "ocean"
    case midnight = "midnight"

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .manuscript: return "Manuscript"
        case .noir: return "Noir"
        case .ember: return "Ember"
        case .forest: return "Forest"
        case .ocean: return "Ocean"
        case .midnight: return "Midnight"
        }
    }

    var description: String {
        switch self {
        case .auto: return "Follows system appearance"
        case .manuscript: return "Warm cream with rich brown ink"
        case .noir: return "High contrast black and white"
        case .ember: return "Deep charcoal with warm orange accents"
        case .forest: return "Soft sage with deep green tones"
        case .ocean: return "Cool slate with teal highlights"
        case .midnight: return "Deep navy with golden accents"
        }
    }

    /// CSS styles for the theme
    var cssStyles: String {
        switch self {
        case .auto:
            return """
                :root {
                    color-scheme: light dark;
                }
                @media (prefers-color-scheme: dark) {
                    body {
                        --bg-color: #1a1a1a;
                        --text-color: #e8e8e8;
                        --secondary-color: #999999;
                        --link-color: #6cb6ff;
                        --code-bg: rgba(255, 255, 255, 0.08);
                        --border-color: rgba(255, 255, 255, 0.12);
                        --blockquote-border: #4a4a4a;
                        --blockquote-color: #aaaaaa;
                    }
                }
                @media (prefers-color-scheme: light) {
                    body {
                        --bg-color: #faf9f7;
                        --text-color: #1a1a1a;
                        --secondary-color: #555555;
                        --link-color: #0055aa;
                        --code-bg: rgba(0, 0, 0, 0.04);
                        --border-color: rgba(0, 0, 0, 0.08);
                        --blockquote-border: #cccccc;
                        --blockquote-color: #666666;
                    }
                }
            """

        case .manuscript:
            // Warm, literary feel - like reading on aged paper
            return """
                :root { color-scheme: light; }
                body {
                    --bg-color: #f8f4e9;
                    --text-color: #2c2416;
                    --secondary-color: #5c5040;
                    --link-color: #8b4000;
                    --code-bg: rgba(60, 40, 20, 0.06);
                    --border-color: rgba(60, 40, 20, 0.15);
                    --blockquote-border: #c4a882;
                    --blockquote-color: #6b5d4d;
                }
            """

        case .noir:
            // Stark, dramatic - pure black with crisp white
            return """
                :root { color-scheme: dark; }
                body {
                    --bg-color: #000000;
                    --text-color: #ffffff;
                    --secondary-color: #888888;
                    --link-color: #ffffff;
                    --code-bg: rgba(255, 255, 255, 0.06);
                    --border-color: rgba(255, 255, 255, 0.2);
                    --blockquote-border: #555555;
                    --blockquote-color: #aaaaaa;
                }
            """

        case .ember:
            // Dark with warm accent colors - cozy fireplace feel
            return """
                :root { color-scheme: dark; }
                body {
                    --bg-color: #1c1917;
                    --text-color: #faf5f0;
                    --secondary-color: #a8a29e;
                    --link-color: #f97316;
                    --code-bg: rgba(249, 115, 22, 0.1);
                    --border-color: rgba(168, 162, 158, 0.2);
                    --blockquote-border: #78716c;
                    --blockquote-color: #d6d3d1;
                }
            """

        case .forest:
            // Calming green tones - natural and restful
            return """
                :root { color-scheme: light; }
                body {
                    --bg-color: #f0f4f1;
                    --text-color: #1a2e1a;
                    --secondary-color: #4a5f4a;
                    --link-color: #2d6a4f;
                    --code-bg: rgba(45, 106, 79, 0.08);
                    --border-color: rgba(45, 106, 79, 0.15);
                    --blockquote-border: #74a892;
                    --blockquote-color: #3d5a4c;
                }
            """

        case .ocean:
            // Cool blue-gray tones - clean and focused
            return """
                :root { color-scheme: light; }
                body {
                    --bg-color: #f4f7fa;
                    --text-color: #0f172a;
                    --secondary-color: #475569;
                    --link-color: #0891b2;
                    --code-bg: rgba(8, 145, 178, 0.06);
                    --border-color: rgba(71, 85, 105, 0.15);
                    --blockquote-border: #7dd3fc;
                    --blockquote-color: #334155;
                }
            """

        case .midnight:
            // Deep blue with gold accents - elegant night reading
            return """
                :root { color-scheme: dark; }
                body {
                    --bg-color: #0c1222;
                    --text-color: #e2e8f0;
                    --secondary-color: #94a3b8;
                    --link-color: #fbbf24;
                    --code-bg: rgba(251, 191, 36, 0.08);
                    --border-color: rgba(148, 163, 184, 0.15);
                    --blockquote-border: #475569;
                    --blockquote-color: #cbd5e1;
                }
            """
        }
    }

    /// SwiftUI background color for the theme
    var backgroundColor: Color {
        switch self {
        case .auto:
            return Color(NSColor.textBackgroundColor)
        case .manuscript:
            return Color(red: 0.973, green: 0.957, blue: 0.914)
        case .noir:
            return Color.black
        case .ember:
            return Color(red: 0.110, green: 0.098, blue: 0.090)
        case .forest:
            return Color(red: 0.941, green: 0.957, blue: 0.945)
        case .ocean:
            return Color(red: 0.957, green: 0.969, blue: 0.980)
        case .midnight:
            return Color(red: 0.047, green: 0.071, blue: 0.133)
        }
    }

    /// SwiftUI text color for the theme
    var textColor: Color {
        switch self {
        case .auto:
            return Color(NSColor.textColor)
        case .manuscript:
            return Color(red: 0.173, green: 0.141, blue: 0.086)
        case .noir:
            return Color.white
        case .ember:
            return Color(red: 0.980, green: 0.961, blue: 0.941)
        case .forest:
            return Color(red: 0.102, green: 0.180, blue: 0.102)
        case .ocean:
            return Color(red: 0.059, green: 0.090, blue: 0.165)
        case .midnight:
            return Color(red: 0.886, green: 0.910, blue: 0.941)
        }
    }

    /// SwiftUI secondary text color for the theme
    var secondaryTextColor: Color {
        switch self {
        case .auto:
            return Color(NSColor.secondaryLabelColor)
        case .manuscript:
            return Color(red: 0.361, green: 0.314, blue: 0.251)
        case .noir:
            return Color(red: 0.533, green: 0.533, blue: 0.533)
        case .ember:
            return Color(red: 0.659, green: 0.635, blue: 0.620)
        case .forest:
            return Color(red: 0.290, green: 0.373, blue: 0.290)
        case .ocean:
            return Color(red: 0.278, green: 0.333, blue: 0.416)
        case .midnight:
            return Color(red: 0.580, green: 0.639, blue: 0.722)
        }
    }

    /// SwiftUI accent/link color for the theme
    var accentColor: Color {
        switch self {
        case .auto:
            return Color.accentColor
        case .manuscript:
            return Color(red: 0.545, green: 0.251, blue: 0.0)
        case .noir:
            return Color.white
        case .ember:
            return Color(red: 0.976, green: 0.451, blue: 0.086)
        case .forest:
            return Color(red: 0.176, green: 0.416, blue: 0.310)
        case .ocean:
            return Color(red: 0.031, green: 0.569, blue: 0.698)
        case .midnight:
            return Color(red: 0.984, green: 0.749, blue: 0.141)
        }
    }
}
