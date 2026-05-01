import Foundation
import SwiftUI

extension String {
    /// Returns the string as an AttributedString with bare URLs converted into clickable
    /// links. Trailing sentence punctuation (`.,!?;:)]`) is excluded from the link target
    /// since it's almost always part of the surrounding sentence rather than the URL.
    func autoLinked(linkColor: Color = .accentColor) -> AttributedString {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let nsString = self as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let matches = detector?.matches(in: self, range: fullRange) ?? []

        guard !matches.isEmpty else {
            return AttributedString(self)
        }

        var result = AttributedString()
        var cursor = 0
        let trailing: Set<Character> = [".", ",", "!", "?", ";", ":", ")", "]"]

        for match in matches {
            let range = match.range
            if range.location > cursor {
                let pre = nsString.substring(with: NSRange(location: cursor, length: range.location - cursor))
                result += AttributedString(pre)
            }
            var matched = nsString.substring(with: range)
            var tail = ""
            while let last = matched.last, trailing.contains(last) {
                tail = String(last) + tail
                matched.removeLast()
            }
            var linkPart = AttributedString(matched)
            if let url = URL(string: matched) {
                linkPart.link = url
                linkPart.foregroundColor = linkColor
                linkPart.underlineStyle = .single
            }
            result += linkPart
            if !tail.isEmpty {
                result += AttributedString(tail)
            }
            cursor = range.location + range.length
        }
        if cursor < nsString.length {
            let suffix = nsString.substring(with: NSRange(location: cursor, length: nsString.length - cursor))
            result += AttributedString(suffix)
        }
        return result
    }
}
