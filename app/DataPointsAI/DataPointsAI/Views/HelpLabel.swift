import SwiftUI

extension View {
    /// Sets both `.help` (sighted hover tooltip) and `.accessibilityLabel`
    /// (VoiceOver) to the same text. Required pairing per MACUX.md
    /// §Accessibility — icon-only controls otherwise read as "Button"
    /// to VoiceOver users.
    func helpLabel(_ text: LocalizedStringKey) -> some View {
        self.help(text).accessibilityLabel(text)
    }

    func helpLabel<S: StringProtocol>(_ text: S) -> some View {
        self.help(text).accessibilityLabel(Text(text))
    }
}
