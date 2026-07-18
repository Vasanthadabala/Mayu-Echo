import SwiftUI
import AppKit
import SwiftData

struct ChatDetailView: View {
    private static let scrollCoordinateSpace = "chat-detail-scroll"
    private static let bottomAnchorID = "chat-detail-bottom-anchor"

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appSettings: AppSettings
    let item: Item?
    var ensureChat: (() -> Item?)?
    @StateObject private var viewModel = ChatSessionViewModel()
    @State private var message = ""
    @State private var isAtLatestMessage = true
    @State private var editingPromptID: LLMMessage.ID?
    @State private var editingPromptDraft = ""
    @State private var isRightPanelVisible = false
    @State private var lastProjectChangeCount = 0
    @StateObject private var projectChanges = ProjectChangesViewModel()

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                chatColumn

                if isRightPanelVisible {
                    Divider()
                        .background(Color.mayuBorder)

                    ProjectChangesReviewPanel(
                        snapshot: projectChanges.snapshot,
                        isLoading: projectChanges.isLoading,
                        isVisible: $isRightPanelVisible,
                        refresh: projectChanges.refresh
                    )
                        .frame(width: rightPanelWidth(for: proxy.size.width))
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .background(Color.mayuChatBackground)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                chatTitleControl
            }

            ToolbarItem(placement: .primaryAction) {
                splitViewControl
            }
        }
        .onAppear {
            viewModel.configure(item: item, modelContext: modelContext)
            viewModel.apply(settings: appSettings)
            projectChanges.configure(projectPath: activeProjectPath)
        }
        .onChange(of: item?.title) {
            viewModel.configure(item: item, modelContext: modelContext)
        }
        .onChange(of: item?.persistentModelID) {
            viewModel.configure(item: item, modelContext: modelContext)
            viewModel.apply(settings: appSettings)
            projectChanges.configure(projectPath: activeProjectPath)
            lastProjectChangeCount = projectChanges.snapshot.changeCount
        }
        .onChange(of: appSettingsSignature) {
            viewModel.apply(settings: appSettings)
        }
        .onChange(of: appSettings.generationOptions) {
            viewModel.generationOptions = appSettings.generationOptions
        }
        .onChange(of: viewModel.selectedModel) {
            // Only write back genuine (composer-driven) selection changes. When the change
            // originated from `apply(settings:)`, appSettings already holds this id, so
            // skipping avoids a settings -> viewModel -> settings loop that fought engine switches.
            guard appSettings.selectedModelID != viewModel.selectedModel.id else {
                return
            }

            appSettings.selectModel(viewModel.selectedModel)
        }
        .onChange(of: viewModel.generationOptions) {
            appSettings.generationOptions = viewModel.generationOptions
        }
        .onChange(of: projectChanges.snapshot.changeCount) {
            handleProjectChangeCount()
        }
        .animation(.easeInOut(duration: 0.18), value: isRightPanelVisible)
    }

    private func sendMessage() {
        let outgoingMessage = message
        message = ""

        if let targetChat = ensureChat?() ?? item {
            viewModel.configure(item: targetChat, modelContext: modelContext)
        }

        viewModel.send(outgoingMessage)
        isAtLatestMessage = true
    }

    private func handleProjectChangeCount() {
        let changeCount = projectChanges.snapshot.changeCount

        if lastProjectChangeCount == 0 && changeCount > 0 {
            isRightPanelVisible = true
        }

        lastProjectChangeCount = changeCount
    }

    private var chatTitleControl: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.mayuAccentSoft)
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.mayuStrongBorder.opacity(0.5), lineWidth: 1)
                    }

                Image(systemName: activeProjectPath == nil ? "bubble.left.and.bubble.right" : "folder")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.mayuAccent)
            }
            .frame(width: 24, height: 24)

            Text(chatTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 200, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.mayuPanelBackground.opacity(0.7))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.mayuBorder.opacity(0.6), lineWidth: 1)
                }
        }
    }

    private var splitViewControl: some View {
        Button {
            isRightPanelVisible.toggle()
        } label: {
            Image(systemName: "sidebar.right")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isRightPanelVisible ? .primary : .secondary)
                .frame(width: 36, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var chatColumn: some View {
        VStack(spacing: 0) {
            chatSurface

            if projectChanges.snapshot.hasChanges {
                ProjectChangesSummaryBar(
                    snapshot: projectChanges.snapshot,
                    reviewAction: {
                        isRightPanelVisible = true
                    }
                )
                .frame(maxWidth: 980)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 34)
                .padding(.bottom, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            MessageComposer(
                message: $message,
                selectedModel: $viewModel.selectedModel,
                availableModels: viewModel.availableModels,
                generationOptions: $viewModel.generationOptions,
                contextUsage: contextUsage,
                isGenerating: viewModel.isGenerating,
                sendMessage: sendMessage,
                stopGeneration: viewModel.cancel
            )
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 34)
            .padding(.top, projectChanges.snapshot.hasChanges ? 10 : 16)
            .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func rightPanelWidth(for availableWidth: CGFloat) -> CGFloat {
        min(max(availableWidth * 0.42, 420), 780)
    }

    private var chatSurface: some View {
        GeometryReader { viewportProxy in
            ScrollViewReader { scrollProxy in
                ZStack(alignment: .bottom) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if viewModel.messages.isEmpty {
                                EmptyChatState(
                                    model: viewModel.selectedModel,
                                    projectName: activeProjectPath.map { URL(fileURLWithPath: $0).lastPathComponent }
                                )
                                    .frame(maxWidth: .infinity, minHeight: 420, alignment: .center)
                            }

                            ForEach(viewModel.messages) { message in
                                ChatMessageBubble(
                                    message: message,
                                    canEditPrompt: message.id == latestUserMessageID,
                                    isEditingPrompt: message.id == editingPromptID,
                                    editingPromptDraft: $editingPromptDraft,
                                    beginEditingPrompt: beginEditingPrompt,
                                    savePromptEdit: savePromptEdit,
                                    cancelPromptEdit: cancelPromptEdit
                                )
                            }

                            Color.clear
                                .frame(height: 1)
                                .id(Self.bottomAnchorID)
                                .background {
                                    GeometryReader { bottomProxy in
                                        Color.clear.preference(
                                            key: ChatBottomAnchorPreferenceKey.self,
                                            value: bottomProxy.frame(in: .named(Self.scrollCoordinateSpace)).maxY
                                        )
                                    }
                                }
                        }
                        .padding(.horizontal, 34)
                        .padding(.vertical, 40)
                        .frame(maxWidth: 980, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .coordinateSpace(name: Self.scrollCoordinateSpace)
                    .onPreferenceChange(ChatBottomAnchorPreferenceKey.self) { bottomY in
                        updateLatestVisibility(bottomY: bottomY, viewportHeight: viewportProxy.size.height)
                    }

                    if shouldShowJumpToLatestButton {
                        jumpToLatestButton(scrollProxy: scrollProxy)
                            .transition(.scale(scale: 0.92).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.16), value: shouldShowJumpToLatestButton)
                .onAppear {
                    scrollToLatest(using: scrollProxy, animated: false)
                }
                .onChange(of: viewModel.messages.count) {
                    scrollToLatest(using: scrollProxy, animated: true)
                }
                .onChange(of: item?.persistentModelID) {
                    isAtLatestMessage = true
                    scrollToLatest(using: scrollProxy, animated: false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var shouldShowJumpToLatestButton: Bool {
        !isAtLatestMessage && !viewModel.messages.isEmpty
    }

    private func jumpToLatestButton(scrollProxy: ScrollViewProxy) -> some View {
        Button {
            scrollToLatest(using: scrollProxy, animated: true)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 12, weight: .bold))

                Text("Jump to latest")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background {
                Capsule()
                    .fill(Color.mayuPanelBackground)
                    .overlay {
                        Capsule()
                            .stroke(Color.mayuStrongBorder.opacity(0.6), lineWidth: 1)
                    }
            }
            .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 20)
    }

    private func updateLatestVisibility(bottomY: CGFloat, viewportHeight: CGFloat) {
        let distanceFromBottom = bottomY - viewportHeight
        let isNearBottom = distanceFromBottom <= 72

        guard isAtLatestMessage != isNearBottom else {
            return
        }

        isAtLatestMessage = isNearBottom
    }

    private func scrollToLatest(using scrollProxy: ScrollViewProxy, animated: Bool) {
        DispatchQueue.main.async {
            let scrollAction = {
                scrollProxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                isAtLatestMessage = true
            }

            if animated {
                withAnimation(.easeOut(duration: 0.18), scrollAction)
            } else {
                scrollAction()
            }
        }
    }

    private var chatTitle: String {
        item?.title ?? "New chat"
    }

    private var activeProjectPath: String? {
        if item?.isProject == true {
            return item?.projectPath
        }

        return item?.parentProjectPath
    }

    private var latestUserMessageID: LLMMessage.ID? {
        viewModel.messages.last { message in
            message.role == .user
        }?.id
    }

    private var contextUsage: ContextWindowUsage {
        let usedTokens = (viewModel.messages.map(\.content) + [message]).reduce(0) { partialResult, content in
            partialResult + estimatedTokenCount(in: content)
        }

        return ContextWindowUsage(
            usedTokens: usedTokens,
            maxTokens: viewModel.selectedModel.workingContextLength
        )
    }

    private var appSettingsSignature: String {
        [
            appSettings.preferredProvider.rawValue,
            appSettings.selectedModelID ?? "",
            "\(appSettings.includeProjectContext)",
            "\(appSettings.contextTokenBudget)",
            "\(appSettings.allowTerminalCommands)"
        ].joined(separator: "|")
    }

    private func estimatedTokenCount(in text: String) -> Int {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return 0
        }

        return max(1, Int(ceil(Double(trimmedText.count) / 4.0)))
    }

    private func beginEditingPrompt(_ prompt: LLMMessage) {
        editingPromptID = prompt.id
        editingPromptDraft = prompt.content
    }

    private func savePromptEdit() {
        guard let editingPromptID else {
            return
        }

        guard !editingPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        guard viewModel.updateUserMessageAndRegenerate(id: editingPromptID, content: editingPromptDraft) else {
            return
        }

        isAtLatestMessage = true
        cancelPromptEdit()
    }

    private func cancelPromptEdit() {
        editingPromptID = nil
        editingPromptDraft = ""
    }
}

private struct ChatMessageBubble: View {
    let message: LLMMessage
    let canEditPrompt: Bool
    let isEditingPrompt: Bool
    @Binding var editingPromptDraft: String
    let beginEditingPrompt: (LLMMessage) -> Void
    let savePromptEdit: () -> Void
    let cancelPromptEdit: () -> Void
    @State private var isCopied = false

    var body: some View {
        if isUserMessage {
            userPrompt
            .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            assistantMessage
        }
    }

    private var userPrompt: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack {
                Spacer(minLength: 120)

                if isEditingPrompt {
                    InlinePromptEditor(text: $editingPromptDraft)
                } else {
                    userMessage
                }
            }

            HStack(spacing: 14) {
                if isEditingPrompt {
                    Button(action: cancelPromptEdit) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Cancel edit")

                    Button(action: savePromptEdit) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Save edit")
                } else {
                    Button(action: copyPrompt) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Copy prompt")

                    if canEditPrompt {
                        Button {
                            beginEditingPrompt(message)
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 14, weight: .medium))
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Edit prompt")
                    }
                }
            }
            .foregroundStyle(.secondary)
            .padding(.trailing, 10)
        }
    }

    private var userMessage: some View {
        Text(displayContent)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .lineSpacing(4)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: 640, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.mayuUserBubble)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.mayuStrongBorder.opacity(0.4), lineWidth: 1)
                    }
            }
            .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }

    private var assistantMessage: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar chip
            ZStack {
                Circle()
                    .fill(Color.mayuAccentSoft)
                    .overlay {
                        Circle()
                            .stroke(Color.mayuBorder.opacity(0.5), lineWidth: 1)
                    }

                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.mayuAccent)
            }
            .frame(width: 28, height: 28)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(ChatMessageSegment.parse(displayContent)) { segment in
                    switch segment {
                    case .prose(_, let text):
                        AssistantProseView(text: text)
                    case .code(_, let language, let body):
                        CodeBlockCard(language: language, code: body)
                    }
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
        }
        .padding(.trailing, 60)
    }

    private var displayContent: String {
        message.content.isEmpty ? "Thinking..." : message.content
    }

    private var isUserMessage: Bool {
        message.role == .user
    }

    private func copyPrompt() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        isCopied = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            isCopied = false
        }
    }
}

private struct EmptyChatState: View {
    let model: LLMModel
    var projectName: String?

    private let suggestions: [(icon: String, title: String, subtitle: String, tint: Color)] = [
        (
            "terminal", "Run a command", "Execute shell commands in your project",
            Color(red: 0.757, green: 0.376, blue: 0.239)
        ),
        (
            "doc.text.magnifyingglass", "Review changes", "Inspect recent git diffs",
            Color(red: 0.267, green: 0.498, blue: 0.220)
        ),
        (
            "lightbulb", "Ask anything", "Explain code, suggest refactors",
            Color(red: 0.749, green: 0.573, blue: 0.157)
        ),
        (
            "arrow.triangle.2.circlepath", "Iterate", "Edit and regenerate responses",
            Color(red: 0.522, green: 0.400, blue: 0.573)
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 18) {
                // Logo
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.mayuAccentSoft)
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.mayuStrongBorder.opacity(0.5), lineWidth: 1)
                        }

                    Image(systemName: "sparkles")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Color.mayuAccent)
                }
                .frame(width: 72, height: 72)
                .shadow(color: Color.mayuAccent.opacity(0.15), radius: 20)

                VStack(spacing: 6) {
                    if let projectName {
                        Text("What should we build in \(projectName)?")
                            .font(.system(size: 26, weight: .semibold, design: .serif))
                            .foregroundStyle(.primary)
                            .tracking(-0.2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 480)
                    } else {
                        Text("Mayu Echo")
                            .font(.system(size: 30, weight: .semibold, design: .serif))
                            .foregroundStyle(.primary)
                            .tracking(-0.2)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: providerIcon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(model.provider.rawValue)
                        Text("·")
                        Text(model.displayName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 320)
                }
            }

            // Suggestion chips
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 10
            ) {
                ForEach(suggestions, id: \.title) { suggestion in
                    SuggestionChip(icon: suggestion.icon, title: suggestion.title, subtitle: suggestion.subtitle, tint: suggestion.tint)
                }
            }
            .frame(maxWidth: 560)
            .padding(.top, 40)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var providerIcon: String {
        switch model.provider {
        case .mlx: return "apple.logo"
        case .llamaCpp: return "memorychip"
        case .api: return "network"
        }
    }
}

private struct SuggestionChip: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.14))

                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHovered ? Color.mayuElevatedBackground : Color.mayuPanelBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isHovered ? Color.mayuStrongBorder.opacity(0.7) : Color.mayuBorder.opacity(0.55), lineWidth: 1)
                }
        }
        .shadow(color: .black.opacity(isHovered ? 0.07 : 0), radius: 8, y: 3)
        .scaleEffect(isHovered ? 1.01 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

private struct InlinePromptEditor: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 15))
            .foregroundStyle(.primary)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: 620, minHeight: 96, maxHeight: 220, alignment: .leading)
            .background(Color.mayuUserBubble)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .focused($isFocused)
            .onAppear {
                isFocused = true
            }
    }
}

private struct AssistantProseView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(AssistantProseElement.parse(text)) { element in
                switch element.kind {
                case .heading:
                    AssistantHeading(text: element.text)
                case .bullet:
                    AssistantBullet(text: element.text)
                case .numbered(let number):
                    AssistantNumberedStep(number: number, text: element.text)
                case .paragraph:
                    Text(element.text)
                        .font(.system(size: 15, weight: .regular))
                        .lineSpacing(5)
                        .foregroundStyle(.primary.opacity(0.9))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AssistantHeading: View {
    let text: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.mayuAccent)
                .frame(width: 3, height: 20)

            Text(text)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .tracking(-0.2)
        }
        .padding(.top, 10)
        .padding(.bottom, 2)
    }
}

private struct AssistantBullet: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Color.mayuAccent.opacity(0.75))
                .frame(width: 4, height: 4)
                .padding(.top, 8)

            Text(text)
                .font(.system(size: 15, weight: .regular))
                .lineSpacing(4)
                .foregroundStyle(.primary.opacity(0.88))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 12)
    }
}

private struct AssistantNumberedStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.mayuOnAccent)
                .frame(width: 20, height: 20)
                .background {
                    Circle().fill(Color.mayuAccentSolid)
                }

            Text(text)
                .font(.system(size: 15, weight: .regular))
                .lineSpacing(4)
                .foregroundStyle(.primary.opacity(0.88))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 8)
    }
}

private struct AssistantProseElement: Identifiable {
    enum Kind {
        case heading
        case bullet
        case numbered(Int)
        case paragraph
    }

    let id = UUID()
    let kind: Kind
    let text: String

    static func parse(_ text: String) -> [AssistantProseElement] {
        var elements: [AssistantProseElement] = []
        var paragraphLines: [String] = []

        func flushParagraph() {
            let paragraph = paragraphLines
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            paragraphLines.removeAll()

            guard !paragraph.isEmpty else {
                return
            }

            elements.append(AssistantProseElement(kind: .paragraph, text: cleanInlineMarkdown(paragraph)))
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !line.isEmpty else {
                flushParagraph()
                continue
            }

            if let heading = headingText(from: line) {
                flushParagraph()
                elements.append(AssistantProseElement(kind: .heading, text: cleanInlineMarkdown(heading)))
            } else if let bullet = bulletText(from: line) {
                flushParagraph()
                elements.append(AssistantProseElement(kind: .bullet, text: cleanInlineMarkdown(bullet)))
            } else if let numbered = numberedText(from: line) {
                flushParagraph()
                elements.append(AssistantProseElement(kind: .numbered(numbered.number), text: cleanInlineMarkdown(numbered.text)))
            } else {
                paragraphLines.append(line)
            }
        }

        flushParagraph()

        if elements.isEmpty {
            return [AssistantProseElement(kind: .paragraph, text: cleanInlineMarkdown(text))]
        }

        return elements
    }

    private static func headingText(from line: String) -> String? {
        let hashCount = line.prefix { $0 == "#" }.count
        guard hashCount > 0, hashCount <= 6 else {
            return nil
        }

        let startIndex = line.index(line.startIndex, offsetBy: hashCount)
        guard startIndex < line.endIndex, line[startIndex].isWhitespace else {
            return nil
        }

        return String(line[startIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func bulletText(from line: String) -> String? {
        for marker in ["- ", "* ", "• "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }

        return nil
    }

    private static func numberedText(from line: String) -> (number: Int, text: String)? {
        guard let dotIndex = line.firstIndex(of: ".") else {
            return nil
        }

        let numberText = String(line[..<dotIndex])
        guard let number = Int(numberText) else {
            return nil
        }

        let contentStart = line.index(after: dotIndex)
        guard contentStart < line.endIndex, line[contentStart].isWhitespace else {
            return nil
        }

        let content = String(line[contentStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty ? nil : (number, content)
    }

    private static func cleanInlineMarkdown(_ text: String) -> String {
        text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum ChatMessageSegment: Identifiable {
    case prose(UUID, String)
    case code(UUID, language: String, body: String)

    var id: UUID {
        switch self {
        case .prose(let id, _), .code(let id, _, _):
            return id
        }
    }

    static func parse(_ content: String) -> [ChatMessageSegment] {
        var segments: [ChatMessageSegment] = []
        var remaining = content[...]

        func appendProse(_ text: String) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return
            }

            segments.append(.prose(UUID(), trimmed))
        }

        func appendCode(language: String, body: String) {
            let cleanedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanedBody = body.trimmingCharacters(in: .newlines)
            segments.append(.code(
                UUID(),
                language: cleanedLanguage.isEmpty ? "code" : cleanedLanguage,
                body: cleanedBody
            ))
        }

        while let openingRange = remaining.range(of: "```") {
            appendProse(String(remaining[..<openingRange.lowerBound]))
            remaining = remaining[openingRange.upperBound...]

            guard let lineBreak = remaining.range(of: "\n") else {
                appendCode(language: "", body: String(remaining))
                remaining = remaining[remaining.endIndex...]
                break
            }

            let language = String(remaining[..<lineBreak.lowerBound])
            remaining = remaining[lineBreak.upperBound...]

            if let closingRange = remaining.range(of: "```") {
                appendCode(
                    language: language,
                    body: String(remaining[..<closingRange.lowerBound])
                )
                remaining = remaining[closingRange.upperBound...]
            } else {
                appendCode(language: language, body: String(remaining))
                remaining = remaining[remaining.endIndex...]
                break
            }
        }

        appendProse(String(remaining))

        if segments.isEmpty {
            return [.prose(UUID(), content)]
        }

        return segments
    }
}

private struct CodeBlockCard: View {
    let language: String
    let code: String
    @State private var copied = false
    @State private var isHeaderHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    // Traffic-light dots
                    HStack(spacing: 5) {
                        Circle().fill(Color(red: 1.00, green: 0.373, blue: 0.341).opacity(0.8)).frame(width: 8, height: 8)
                        Circle().fill(Color(red: 0.996, green: 0.737, blue: 0.180).opacity(0.8)).frame(width: 8, height: 8)
                        Circle().fill(Color(red: 0.157, green: 0.784, blue: 0.251).opacity(0.8)).frame(width: 8, height: 8)
                    }

                    Rectangle()
                        .fill(Color.mayuBorder.opacity(0.6))
                        .frame(width: 1, height: 14)
                        .padding(.horizontal, 2)

                    Text(language.isEmpty ? "code" : language.lowercased())
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: copyCode) {
                    HStack(spacing: 5) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                        Text(copied ? "Copied" : "Copy")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(copied ? Color.mayuAccent : .secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background {
                        Capsule()
                            .fill(Color.mayuElevatedBackground)
                            .overlay {
                                Capsule()
                                    .stroke(Color.mayuBorder.opacity(0.6), lineWidth: 1)
                            }
                    }
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: copied)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                Rectangle()
                    .fill(Color.mayuElevatedBackground.opacity(0.6))
            }

            Rectangle()
                .fill(Color.mayuBorder.opacity(0.5))
                .frame(height: 1)

            // Code body
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code.isEmpty ? " " : code)
                    .font(.system(size: 13, design: .monospaced))
                    .lineSpacing(6)
                    .foregroundStyle(.primary.opacity(0.92))
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: 740, alignment: .leading)
        .background(Color.mayuCodeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.mayuBorder.opacity(0.6), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        copied = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copied = false
        }
    }
}

private struct ChatBottomAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
