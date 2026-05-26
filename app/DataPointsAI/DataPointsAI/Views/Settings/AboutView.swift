import SwiftUI

/// About tab
struct AboutView: View {
    var llmProvider: LLMProvider

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "newspaper.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)

            Text("Data Points AI")
                .font(.title)
                .fontWeight(.bold)

            Text("Version 2.0.0")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()
                .padding(.vertical)

            Text("An AI-powered RSS reader for macOS.")
                .multilineTextAlignment(.center)

            Text("Summaries powered by \(llmProvider.label)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
    }
}
