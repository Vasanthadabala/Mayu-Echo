import SwiftUI
import AppKit
import SwiftData

struct ChatDetailView: View {
    private static let scrollCoordinateSpace = "chat-detail-scroll"
    private static let bottomAnchorID = "chat-detail-bottom-anchor"

    @Environment(\.modelContext) private var modelContext
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
            projectChanges.configure(projectPath: activeProjectPath)
        }
        .onChange(of: item?.title) {
            viewModel.configure(item: item, modelContext: modelContext)
        }
        .onChange(of: item?.persistentModelID) {
            viewModel.configure(item: item, modelContext: modelContext)
            projectChanges.configure(projectPath: activeProjectPath)
            lastProjectChangeCount = projectChanges.snapshot.changeCount
        }
        .onChange(of: projectChanges.snapshot.changeCount) {
            let changeCount = projectChanges.snapshot.changeCount

            if lastProjectChangeCount == 0 && changeCount > 0 {
                isRightPanelVisible = true
            }

            lastProjectChangeCount = changeCount
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

    private var chatTitleControl: some View {
        HStack(spacing: 10) {
            Text(chatTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth:120)
            
            Button(action: {}) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
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
            Image(systemName: "arrow.down")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 38, height: 38)
                .background(Color.mayuSelection)
                .overlay {
                    Circle()
                        .stroke(Color.mayuBorder, lineWidth: 1)
                }
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 18)
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
            .font(.system(size: 15))
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: 620, alignment: .leading)
            .background(Color.mayuUserBubble)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var assistantMessage: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(ChatMessageSegment.parse(displayContent)) { segment in
                switch segment {
                case .prose(_, let text):
                    Text(text)
                        .font(.system(size: 15))
                        .lineSpacing(3)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                case .code(_, let language, let body):
                    CodeBlockCard(language: language, code: body)
                }
            }
        }
        .frame(maxWidth: 760, alignment: .leading)
        .padding(.trailing, 88)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(language.lowercased())
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: copyCode) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 24)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code.isEmpty ? " " : code)
                    .font(.system(size: 14, design: .monospaced))
                    .lineSpacing(5)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: 720, alignment: .leading)
        .background(Color.mayuCodeBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.mayuBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        copied = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
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
