import Foundation

extension String {
    /// Convert straight quotes to typographically correct smart quotes.
    /// Handles double quotes, single quotes, and apostrophes.
    ///
    /// Unicode characters used:
    /// - \u{201C} = " (left double quote)
    /// - \u{201D} = " (right double quote)
    /// - \u{2018} = ' (left single quote)
    /// - \u{2019} = ' (right single quote / apostrophe)
    var smartQuotes: String {
        var result = self

        // Double quotes: opening after whitespace/start, closing before whitespace/end/punctuation
        // Opening double quote (after whitespace or at start)
        result = result.replacingOccurrences(
            of: #"(^|[\s\(])\""#,
            with: "$1\u{201C}",
            options: .regularExpression
        )
        // Closing double quote (before whitespace, punctuation, or at end)
        result = result.replacingOccurrences(
            of: #"\"([\s\)\.,;:!?\-]|$)"#,
            with: "\u{201D}$1",
            options: .regularExpression
        )
        // Any remaining straight double quotes become closing quotes
        result = result.replacingOccurrences(of: "\"", with: "\u{201D}")

        // Single quotes / apostrophes
        // Apostrophe within words (don't, it's, '90s)
        result = result.replacingOccurrences(
            of: #"(\w)'(\w)"#,
            with: "$1\u{2019}$2",
            options: .regularExpression
        )
        // Apostrophe at start of word for contractions like 'twas, '90s
        result = result.replacingOccurrences(
            of: #"(^|[\s\(])'(\w)"#,
            with: "$1\u{2019}$2",
            options: .regularExpression
        )
        // Opening single quote (after whitespace or at start, followed by non-space)
        result = result.replacingOccurrences(
            of: #"(^|[\s\(])'"#,
            with: "$1\u{2018}",
            options: .regularExpression
        )
        // Closing single quote (before whitespace, punctuation, or at end)
        result = result.replacingOccurrences(
            of: #"'([\s\)\.,;:!?\-]|$)"#,
            with: "\u{2019}$1",
            options: .regularExpression
        )
        // Any remaining straight single quotes become closing quotes (apostrophes)
        result = result.replacingOccurrences(of: "'", with: "\u{2019}")

        return result
    }
}
