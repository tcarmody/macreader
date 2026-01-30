import SwiftUI

/// Chat section for article Q&A and summary refinement
struct ArticleChatSection: View {
    let article: ArticleDetail
    let fontSize: ArticleFontSize
    let lineSpacing: ArticleLineSpacing
    let appTypeface: AppTypeface

    @EnvironmentObject var appState: AppState
    @State private var isExpanded: Bool = false
    @State private var messages: [ChatMessage] = []
    @State private var hasChat: Bool = false
    @State private var inputText: String = ""
    @State private var isLoading: Bool = false
    @State private var isSending: Bool = false
    @State private var error: String?
    @State private var showClearConfirmation: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header - always visible, toggles expansion
            headerButton

            // Expandable content
            if isExpanded {
                VStack(spacing: 0) {
                    Divider()
                        .padding(.horizontal)

                    // Messages area
                    messagesArea
                        .frame(height: 200)

                    Divider()
                        .padding(.horizontal)

                    // Input area
                    inputArea
                }
            }
        }
        .background(Color.blue.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.blue.opacity(0.2), lineWidth: 1)
        )
        .task {
            await loadChatHistory()
        }
        .onChange(of: article.id) { _, _ in
            // Reset state when article changes
            isExpanded = false
            messages = []
            hasChat = false
            inputText = ""
            error = nil
            Task {
                await loadChatHistory()
            }
        }
        .alert("Clear Chat History?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                Task {
                    await clearChat()
                }
            }
        } message: {
            Text("This will delete all messages in this conversation. This action cannot be undone.")
        }
    }

    // MARK: - Header

    private var headerButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack {
                Label("Chat About This Article", systemImage: "message")
                    .font(appTypeface.font(size: fontSize.bodyFontSize, weight: .semibold))
                    .foregroundStyle(.blue)

                if hasChat {
                    Text("\(messages.count) messages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }

                Spacer()

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Messages Area

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if isLoading {
                    loadingView
                } else if messages.isEmpty {
                    emptyView
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { message in
                            messageRow(message)
                        }

                        // Sending indicator
                        if isSending {
                            sendingIndicator
                        }

                        // Scroll anchor
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding()
                }
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: isSending) { _, _ in
                withAnimation {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .scaleEffect(0.8)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "message")
                .font(.largeTitle)
                .foregroundStyle(.secondary.opacity(0.5))
            Text("No messages yet")
                .foregroundStyle(.secondary)
            Text("Ask questions or request summary changes")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func messageRow(_ message: ChatMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isAssistant {
                // Assistant avatar
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .frame(width: 24, height: 24)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(message.content)
                        .font(appTypeface.font(size: fontSize.bodyFontSize - 1))
                        .lineSpacing(fontSize.bodyFontSize * (lineSpacing.multiplier - 1) * 0.5)
                        .textSelection(.enabled)

                    HStack(spacing: 6) {
                        Text(message.timeDisplay)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        if let model = message.modelUsed {
                            Text(model)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Spacer(minLength: 40)
            } else {
                // User message - align right
                Spacer(minLength: 40)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(message.content)
                        .font(appTypeface.font(size: fontSize.bodyFontSize - 1))
                        .lineSpacing(fontSize.bodyFontSize * (lineSpacing.multiplier - 1) * 0.5)
                        .textSelection(.enabled)

                    Text(message.timeDisplay)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(10)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // User avatar
                Image(systemName: "person.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24, height: 24)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(Circle())
            }
        }
    }

    private var sendingIndicator: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(.blue)
                .frame(width: 24, height: 24)
                .background(Color.blue.opacity(0.1))
                .clipShape(Circle())

            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                Text("Thinking...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Spacer()
        }
    }

    // MARK: - Input Area

    private var inputArea: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("Ask a question or request summary changes...", text: $inputText)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .disabled(isSending)
                    .onSubmit {
                        Task {
                            await sendMessage()
                        }
                    }

                Button {
                    Task {
                        await sendMessage()
                    }
                } label: {
                    if isSending {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isSending)

                if hasChat {
                    Button {
                        showClearConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .help("Clear chat history")
                }
            }

            if let error = error {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
        .padding()
    }

    // MARK: - Actions

    private func loadChatHistory() async {
        isLoading = true
        error = nil

        do {
            let response = try await appState.apiClient.getChatHistory(articleId: article.id)
            messages = response.messages
            hasChat = response.hasChat
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    private func sendMessage() async {
        let trimmedMessage = inputText.trimmingCharacters(in: .whitespaces)
        guard !trimmedMessage.isEmpty else { return }

        // Clear input immediately for better UX
        let messageToSend = trimmedMessage
        inputText = ""
        error = nil
        isSending = true

        do {
            _ = try await appState.apiClient.sendChatMessage(
                articleId: article.id,
                message: messageToSend
            )

            // Reload full history to get both user message and response
            let historyResponse = try await appState.apiClient.getChatHistory(articleId: article.id)
            messages = historyResponse.messages
            hasChat = true
        } catch {
            // Restore the message so user can retry
            inputText = messageToSend
            self.error = error.localizedDescription
        }

        isSending = false
    }

    private func clearChat() async {
        do {
            _ = try await appState.apiClient.clearChatHistory(articleId: article.id)
            messages = []
            hasChat = false
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#Preview {
    ArticleChatSection(
        article: ArticleDetail(
            id: 1,
            feedId: 1,
            url: URL(string: "https://example.com")!,
            sourceUrl: nil,
            title: "Test Article",
            content: "Some content",
            summaryShort: "Short summary",
            summaryFull: "Full summary of the article content.",
            keyPoints: ["Point 1", "Point 2"],
            isRead: false,
            isBookmarked: false,
            publishedAt: Date(),
            createdAt: Date(),
            author: nil,
            readingTimeMinutes: 5,
            wordCountValue: nil,
            featuredImage: nil,
            hasCodeBlocks: nil,
            siteName: nil,
            relatedLinks: nil,
            relatedLinksError: nil
        ),
        fontSize: .medium,
        lineSpacing: .normal,
        appTypeface: .system
    )
    .environmentObject(AppState())
    .frame(width: 500, height: 400)
    .padding()
}
