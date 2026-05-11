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

    private let engine: MLXEngine
    private let downloader: HuggingFaceModelDownloader
    private var streamTask: Task<Void, Never>?
    private var modelContext: ModelContext?
    private var activeItem: Item?
    private var activeItemID: PersistentIdentifier?
    private var persistedMessages: [LLMMessage.ID: ChatMessageRecord] = [:]
    private var currentAssistantMessageID: LLMMessage.ID?

    init(engine: MLXEngine? = nil, downloader: HuggingFaceModelDownloader? = nil) {
        let resolvedDownloader = downloader ?? HuggingFaceModelDownloader()
        let resolvedModels = LLMModelCatalog.allModels.map {
            resolvedDownloader.modelWithLocalStatus($0)
        }

        self.engine = engine ?? MLXEngine()
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

        streamTask?.cancel()
        streamTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let requestMessages = await Task.detached(priority: .userInitiated) {
                    ProjectContextBuilder.requestMessages(
                        chatMessages: chatMessages,
                        projectPath: projectPath,
                        bookmarkData: projectBookmarkData,
                        intelligence: options.intelligence,
                        modelContextLength: model.workingContextLength,
                        reservedResponseTokens: options.maxTokens
                    )
                }.value

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

    func refreshAvailableModels() {
        let selectedModelID = selectedModel.id
        let resolvedModels = LLMModelCatalog.allModels.map {
            downloader.modelWithLocalStatus($0)
        }

        availableModels = resolvedModels

        if let resolvedSelection = resolvedModels.first(where: { $0.id == selectedModelID }) {
            selectedModel = resolvedSelection
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
}
