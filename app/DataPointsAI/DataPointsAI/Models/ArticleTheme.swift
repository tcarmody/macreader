import Foundation
import SwiftUI
import AppKit

/// Article reading theme options
enum ArticleTheme: String, Codable, CaseIterable, Sendable {
    case auto = "auto"
    case light = "light"
    case dark = "dark"
    case sepia = "sepia"
    case paper = "paper"
    case night = "night"

    var label: String {
        switch self {
        case .auto: return "Auto (System)"
        case .light: return "Light"
        case .dark: return "Dark"
        case .sepia: return "Sepia"
        case .paper: return "Paper"
        case .night: return "Night"
        }
    }

    var description: String {
        switch self {
        case .auto: return "Follows system appearance"
        case .light: return "Bright white background"
        case .dark: return "Dark gray background"
        case .sepia: return "Warm, easy on the eyes"
        case .paper: return "Off-white like aged paper"
        case .night: return "Pure black for OLED displays"
        }
    }

    /// Preview colors for the theme picker
    var previewBackground: String {
        switch self {
        case .auto: return "linear-gradient(135deg, #ffffff 50%, #1a1a1a 50%)"
        case .light: return "#ffffff"
        case .dark: return "#1e1e1e"
        case .sepia: return "#f4ecd8"
        case .paper: return "#f5f5f0"
        case .night: return "#000000"
        }
    }

    var previewText: String {
        switch self {
        case .auto, .light, .paper: return "#333333"
        case .dark: return "#e0e0e0"
        case .sepia: return "#5b4636"
        case .night: return "#b0b0b0"
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
                        --bg-color: #1e1e1e;
                        --text-color: #e0e0e0;
                        --secondary-color: #a0a0a0;
                        --link-color: #6cb6ff;
                        --code-bg: rgba(255, 255, 255, 0.1);
                        --border-color: rgba(255, 255, 255, 0.15);
                        --blockquote-color: #a0a0a0;
                    }
                }
                @media (prefers-color-scheme: light) {
                    body {
                        --bg-color: #ffffff;
                        --text-color: #333333;
                        --secondary-color: #666666;
                        --link-color: #0066cc;
                        --code-bg: rgba(0, 0, 0, 0.05);
                        --border-color: rgba(0, 0, 0, 0.1);
                        --blockquote-color: #666666;
                    }
                }
            """
        case .light:
            return """
                :root {
                    color-scheme: light;
                }
                body {
                    --bg-color: #ffffff;
                    --text-color: #333333;
                    --secondary-color: #666666;
                    --link-color: #0066cc;
                    --code-bg: rgba(0, 0, 0, 0.05);
                    --border-color: rgba(0, 0, 0, 0.1);
                    --blockquote-color: #666666;
                }
            """
        case .dark:
            return """
                :root {
                    color-scheme: dark;
                }
                body {
                    --bg-color: #1e1e1e;
                    --text-color: #e0e0e0;
                    --secondary-color: #a0a0a0;
                    --link-color: #6cb6ff;
                    --code-bg: rgba(255, 255, 255, 0.1);
                    --border-color: rgba(255, 255, 255, 0.15);
                    --blockquote-color: #a0a0a0;
                }
            """
        case .sepia:
            return """
                :root {
                    color-scheme: light;
                }
                body {
                    --bg-color: #f4ecd8;
                    --text-color: #5b4636;
                    --secondary-color: #7a6455;
                    --link-color: #8b4513;
                    --code-bg: rgba(139, 69, 19, 0.1);
                    --border-color: rgba(139, 69, 19, 0.2);
                    --blockquote-color: #7a6455;
                }
            """
        case .paper:
            return """
                :root {
                    color-scheme: light;
                }
                body {
                    --bg-color: #f5f5f0;
                    --text-color: #333333;
                    --secondary-color: #555555;
                    --link-color: #2c5aa0;
                    --code-bg: rgba(0, 0, 0, 0.05);
                    --border-color: rgba(0, 0, 0, 0.12);
                    --blockquote-color: #555555;
                }
            """
        case .night:
            return """
                :root {
                    color-scheme: dark;
                }
                body {
                    --bg-color: #000000;
                    --text-color: #b0b0b0;
                    --secondary-color: #707070;
                    --link-color: #5a9fd4;
                    --code-bg: rgba(255, 255, 255, 0.08);
                    --border-color: rgba(255, 255, 255, 0.1);
                    --blockquote-color: #707070;
                }
            """
        }
    }

    /// SwiftUI background color for the theme
    var backgroundColor: Color {
        switch self {
        case .auto:
            return Color(NSColor.textBackgroundColor)
        case .light:
            return Color.white
        case .dark:
            return Color(red: 0.118, green: 0.118, blue: 0.118)
        case .sepia:
            return Color(red: 0.957, green: 0.925, blue: 0.847)
        case .paper:
            return Color(red: 0.961, green: 0.961, blue: 0.941)
        case .night:
            return Color.black
        }
    }

    /// SwiftUI text color for the theme
    var textColor: Color {
        switch self {
        case .auto:
            return Color(NSColor.textColor)
        case .light, .paper:
            return Color(red: 0.2, green: 0.2, blue: 0.2)
        case .dark:
            return Color(red: 0.878, green: 0.878, blue: 0.878)
        case .sepia:
            return Color(red: 0.357, green: 0.275, blue: 0.212)
        case .night:
            return Color(red: 0.69, green: 0.69, blue: 0.69)
        }
    }

    /// SwiftUI secondary text color for the theme
    var secondaryTextColor: Color {
        switch self {
        case .auto:
            return Color(NSColor.secondaryLabelColor)
        case .light, .paper:
            return Color(red: 0.4, green: 0.4, blue: 0.4)
        case .dark:
            return Color(red: 0.627, green: 0.627, blue: 0.627)
        case .sepia:
            return Color(red: 0.478, green: 0.392, blue: 0.333)
        case .night:
            return Color(red: 0.439, green: 0.439, blue: 0.439)
        }
    }

    /// SwiftUI accent/link color for the theme
    var accentColor: Color {
        switch self {
        case .auto:
            return Color.accentColor
        case .light:
            return Color(red: 0, green: 0.4, blue: 0.8)
        case .dark:
            return Color(red: 0.424, green: 0.714, blue: 1.0)
        case .sepia:
            return Color(red: 0.545, green: 0.271, blue: 0.075)
        case .paper:
            return Color(red: 0.173, green: 0.353, blue: 0.627)
        case .night:
            return Color(red: 0.353, green: 0.624, blue: 0.831)
        }
    }
}
