import Foundation
import Combine
import SwiftData

@MainActor
final class ChatSessionViewModel: ObservableObject {
    @Published private(set) var messages: [LLMMessage] = []
    @Published private(set) var isGenerating = false
    @Published private(set) var availableModels: [LLMModel]
    @Published var selectedModel: LLMModel
    @Published var generationOptions = LLMGenerationOptions()

    private let engine: LocalAIEngineRouter
    private let downloader: HuggingFaceModelDownloader
    private let terminalRunner = TerminalCommandRunner()
    private var includeProjectContext = true
    private var projectContextTokenBudget = LLMModel.defaultWorkingContextLength
    private var allowTerminalCommands = true
    private var streamTask: Task<Void, Never>?
    private var modelContext: ModelContext?
    private var activeItem: Item?
    private var activeItemID: PersistentIdentifier?
    private var persistedMessages: [LLMMessage.ID: ChatMessageRecord] = [:]
    private var currentAssistantMessageID: LLMMessage.ID?

    init(engine: LocalAIEngineRouter? = nil, downloader: HuggingFaceModelDownloader? = nil) {
        let resolvedDownloader = downloader ?? HuggingFaceModelDownloader()
        let resolvedModels = LLMModelCatalog.allModels.map {
            Self.resolvedModel($0, downloader: resolvedDownloader)
        }

        self.engine = engine ?? LocalAIEngineRouter()
        self.downloader = resolvedDownloader
        self.availableModels = resolvedModels
        self.selectedModel = resolvedModels.first ?? LLMModel.qwen25Coder7BInstruct4Bit
    }

    func configure(item: Item?, modelContext: ModelContext) {
        self.modelContext = modelContext
        refreshAvailableModels()

        if activeItemID == item?.persistentModelID {
            activeItem = item

            if !isGenerating && messages.isEmpty && item != nil {
                loadSavedMessages()
            }

            return
        }

        cancel()
        activeItem = item
        activeItemID = item?.persistentModelID
        loadSavedMessages()
    }

    func send(_ text: String) {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isGenerating else {
            return
        }

        if allowTerminalCommands, let terminalCommand = terminalCommand(from: prompt) {
            runTerminalCommand(userPrompt: prompt, command: terminalCommand)
            return
        }

        let userMessage = LLMMessage(role: .user, content: prompt)
        let assistantMessage = LLMMessage(role: .assistant, content: "")
        let chatMessages = messages + [userMessage]

        messages.append(userMessage)
        messages.append(assistantMessage)
        persist(userMessage)
        persist(assistantMessage)
        updateActiveChatMetadata(with: prompt)
        saveContext()

        streamAssistantResponse(
            chatMessages: chatMessages,
            assistantID: assistantMessage.id
        )
    }

    private func runTerminalCommand(userPrompt: String, command: String) {
        let userMessage = LLMMessage(role: .user, content: userPrompt)
        let toolMessage = LLMMessage(
            role: .tool,
            content: terminalRunningContent(command: command)
        )

        messages.append(userMessage)
        messages.append(toolMessage)
        persist(userMessage)
        persist(toolMessage)
        updateActiveChatMetadata(with: userPrompt)
        saveContext()

        isGenerating = true
        currentAssistantMessageID = toolMessage.id

        let projectPath = activeProjectPath
        let projectBookmarkData = activeProjectBookmarkData

        streamTask?.cancel()
        streamTask = Task { [weak self] in
            guard let self else {
                return
            }

            let result = await terminalRunner.run(
                command: command,
                workingDirectoryPath: projectPath,
                bookmarkData: projectBookmarkData
            )

            guard !Task.isCancelled else {
                return
            }

            replaceAssistantMessage(
                toolMessage.id,
                with: terminalResultContent(result)
            )
            currentAssistantMessageID = nil
            isGenerating = false
            saveContext()
        }
    }

    private func terminalCommand(from prompt: String) -> String? {
        let lowercasedPrompt = prompt.lowercased()
        let slashPrefixes = ["/terminal ", "/term "]

        for prefix in slashPrefixes where lowercasedPrompt.hasPrefix(prefix) {
            let command = prompt.dropFirst(prefix.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return command.isEmpty ? nil : command
        }

        guard prompt.hasPrefix("$ ") else {
            return nil
        }

        let command = prompt.dropFirst(2)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return command.isEmpty ? nil : command
    }

    private func terminalRunningContent(command: String) -> String {
        """
        Running terminal command:

        ```bash
        $ \(escapedFenceContent(command))
        ```
        """
    }

    private func terminalResultContent(_ result: TerminalCommandResult) -> String {
        """
        Terminal command finished with exit code \(result.exitCode) in \(formattedDuration(result.duration)).

        Working directory: `\(result.workingDirectoryPath)`

        ```bash
        $ \(escapedFenceContent(result.command))
        ```

        ```text
        \(escapedFenceContent(result.combinedOutput))
        ```
        """
    }

    private func escapedFenceContent(_ text: String) -> String {
        text.replacingOccurrences(of: "```", with: "`\u{200B}``")
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return "\(Int((duration * 1_000).rounded()))ms"
        }

        return String(format: "%.1fs", duration)
    }

    @discardableResult
    func updateUserMessageAndRegenerate(id: LLMMessage.ID, content: String) -> Bool {
        let editedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !editedContent.isEmpty else {
            return false
        }

        if isGenerating {
            cancel()
        }

        guard let index = messages.firstIndex(where: { $0.id == id && $0.role == .user }) else {
            return false
        }

        messages[index].content = editedContent
        persistedMessages[id]?.content = editedContent
        removeMessages(after: index)
        activeItem?.timestamp = Date()

        let chatMessages = Array(messages.prefix(index + 1))
        let assistantMessage = LLMMessage(role: .assistant, content: "")
        messages.append(assistantMessage)
        persist(assistantMessage)
        saveContext()

        streamAssistantResponse(
            chatMessages: chatMessages,
            assistantID: assistantMessage.id
        )

        return true
    }

    private func streamAssistantResponse(
        chatMessages: [LLMMessage],
        assistantID: LLMMessage.ID
    ) {
        isGenerating = true

        currentAssistantMessageID = assistantID
        refreshAvailableModels()
        let model = selectedModel
        let options = generationOptions.resolvedForGeneration
        let projectPath = activeProjectPath
        let projectBookmarkData = activeProjectBookmarkData
        let contextTokenBudget = projectContextTokenBudget

        streamTask?.cancel()
        streamTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let requestMessages: [LLMMessage]

                if includeProjectContext {
                    requestMessages = await Task.detached(priority: .userInitiated) {
                        ProjectContextBuilder.requestMessages(
                            chatMessages: chatMessages,
                            projectPath: projectPath,
                            bookmarkData: projectBookmarkData,
                            intelligence: options.intelligence,
                            modelContextLength: min(model.workingContextLength, contextTokenBudget),
                            reservedResponseTokens: options.maxTokens
                        )
                    }.value
                } else {
                    requestMessages = chatMessages
                }

                let stream = await engine.streamChat(
                    messages: requestMessages,
                    model: model,
                    options: options
                )

                for try await event in stream {
                    guard !Task.isCancelled else {
                        return
                    }

                    switch event {
                    case .token(let token):
                        append(token, to: assistantID)
                    case .completed:
                        currentAssistantMessageID = nil
                        saveContext()
                        break
                    }
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                replaceAssistantMessage(
                    assistantID,
                    with: error.localizedDescription
                )
                currentAssistantMessageID = nil
                saveContext()
            }

            isGenerating = false
            saveContext()
        }
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil

        Task {
            await engine.cancel()
        }

        cleanupEmptyAssistantPlaceholder()
        isGenerating = false
        saveContext()
    }

    func reset() {
        cancel()
        messages = []
    }

    /// Refreshes only the available-model *list*. It deliberately never mutates
    /// `selectedModel`: the selection is owned solely by `apply(settings:)` (settings-driven)
    /// and the composer's picker (user-driven). Reassigning the selection here — especially
    /// from the async completion below — used to race with an in-flight provider switch and
    /// bounce the engine back to its previous value.
    func refreshAvailableModels() {
        availableModels = LLMModelCatalog.allModels.map {
            Self.resolvedModel($0, downloader: downloader)
        }

        Task { [weak self] in
            guard let self else {
                return
            }

            guard let providerModels = try? await engine.availableModels() else {
                return
            }

            let mergedModels = LLMModelCatalog.mergedModels(
                defaults: providerModels,
                custom: LLMModelCatalog.allModels.map {
                    Self.resolvedModel($0, downloader: self.downloader)
                }
            )

            guard !Task.isCancelled else {
                return
            }

            availableModels = mergedModels
        }
    }

    func apply(settings: AppSettings) {
        refreshAvailableModels()
        generationOptions = settings.generationOptions
        includeProjectContext = settings.includeProjectContext
        projectContextTokenBudget = settings.contextTokenBudget
        allowTerminalCommands = settings.allowTerminalCommands

        if let model = settings.selectedModel(in: availableModels) {
            selectedModel = model
        }
    }

    func updateUserMessage(id: LLMMessage.ID, content: String) {
        let editedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !editedContent.isEmpty else {
            return
        }

        guard let index = messages.firstIndex(where: { $0.id == id && $0.role == .user }) else {
            return
        }

        messages[index].content = editedContent
        persistedMessages[id]?.content = editedContent
        activeItem?.timestamp = Date()
        saveContext()
    }

    private func removeMessages(after index: Int) {
        let nextIndex = messages.index(after: index)
        guard nextIndex < messages.endIndex else {
            return
        }

        let removedMessages = messages[nextIndex...]

        for message in removedMessages {
            if let record = persistedMessages.removeValue(forKey: message.id) {
                modelContext?.delete(record)
            }
        }

        messages.removeSubrange(nextIndex...)
    }

    private func append(_ token: String, to messageID: LLMMessage.ID) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }

        messages[index].content += token
        persistedMessages[messageID]?.content += token
    }

    private func replaceAssistantMessage(_ messageID: LLMMessage.ID, with text: String) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }

        messages[index].content = text
        persistedMessages[messageID]?.content = text
    }

    private func cleanupEmptyAssistantPlaceholder() {
        guard let messageID = currentAssistantMessageID else {
            return
        }

        currentAssistantMessageID = nil

        guard let index = messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }

        guard messages[index].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        messages.remove(at: index)

        if let record = persistedMessages.removeValue(forKey: messageID) {
            modelContext?.delete(record)
        }
    }

    private func loadSavedMessages() {
        guard let activeItem else {
            messages = []
            persistedMessages = [:]
            return
        }

        let records = savedMessageRecords(for: activeItem)

        messages = records.map(\.message)
        persistedMessages = Dictionary(
            uniqueKeysWithValues: records.map { ($0.id, $0) }
        )
    }

    private func savedMessageRecords(for item: Item) -> [ChatMessageRecord] {
        let relationshipRecords = item.messages.sorted { lhs, rhs in
            lhs.createdAt < rhs.createdAt
        }

        guard let modelContext else {
            return relationshipRecords
        }

        do {
            let descriptor = FetchDescriptor<ChatMessageRecord>(
                sortBy: [SortDescriptor(\ChatMessageRecord.createdAt)]
            )
            let itemID = item.persistentModelID
            let fetchedRecords = try modelContext.fetch(descriptor).filter { record in
                record.chat?.persistentModelID == itemID
            }

            if !fetchedRecords.isEmpty || relationshipRecords.isEmpty {
                return fetchedRecords
            }
        } catch {
            assertionFailure("Failed to fetch chat messages: \(error.localizedDescription)")
        }

        return relationshipRecords
    }

    private func persist(_ message: LLMMessage) {
        guard let modelContext, let activeItem else {
            return
        }

        let record = ChatMessageRecord(message: message, chat: activeItem)
        modelContext.insert(record)
        persistedMessages[message.id] = record
    }

    private func updateActiveChatMetadata(with prompt: String) {
        guard let activeItem else {
            return
        }

        activeItem.timestamp = Date()

        if activeItem.title.hasPrefix("New chat") {
            activeItem.title = titlePreview(from: prompt)
        }
    }

    private func titlePreview(from prompt: String) -> String {
        let singleLinePrompt = prompt
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard singleLinePrompt.count > 48 else {
            return singleLinePrompt
        }

        let endIndex = singleLinePrompt.index(singleLinePrompt.startIndex, offsetBy: 48)
        return String(singleLinePrompt[..<endIndex]).trimmingCharacters(in: .whitespaces) + "..."
    }

    private var activeProjectPath: String? {
        if activeItem?.isProject == true {
            return activeItem?.projectPath
        }

        return activeItem?.parentProjectPath
    }

    private var activeProjectBookmarkData: Data? {
        activeItem?.projectBookmarkData
    }

    private func saveContext() {
        do {
            try modelContext?.save()
        } catch {
            assertionFailure("Failed to save chat messages: \(error.localizedDescription)")
        }
    }

    private static func resolvedModel(_ model: LLMModel, downloader: HuggingFaceModelDownloader) -> LLMModel {
        switch model.provider {
        case .mlx:
            return downloader.modelWithLocalStatus(model)
        case .llamaCpp:
            return downloader.ggufModelWithLocalStatus(model)
        case .api:
            return model
        }
    }
}
