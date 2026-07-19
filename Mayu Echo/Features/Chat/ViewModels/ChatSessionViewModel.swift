import Foundation
import Combine
import SwiftData

/// A model-proposed action (file edit or shell command) awaiting the user's decision.
enum PendingToolProposal: Identifiable {
    case edit(ProjectFileEditProposal)
    case command(ProjectCommandProposal)

    var id: UUID {
        switch self {
        case .edit(let proposal): return proposal.id
        case .command(let proposal): return proposal.id
        }
    }

    var toolCallID: String {
        switch self {
        case .edit(let proposal): return proposal.toolCallID
        case .command(let proposal): return proposal.toolCallID
        }
    }
}

/// State captured while the agentic loop is paused waiting on the user to approve or
/// reject one or more proposed actions.
private struct PendingAgentTurn {
    let assistantID: LLMMessage.ID
    /// Original request messages plus the assistant's tool-call message and every
    /// tool result resolved so far in this batch.
    var baseMessages: [LLMMessage]
    let model: LLMModel
    let options: LLMGenerationOptions
    let projectContext: ProjectAgentContext
    let toolsEnabled: Bool
    let iteration: Int
    var proposals: [PendingToolProposal]
}

@MainActor
final class ChatSessionViewModel: ObservableObject {
    /// A file edit's content growing live as the model streams it, shown before the
    /// tool call finishes and the real (accept/reject) proposal card appears.
    struct LiveEditPreview: Identifiable {
        let id = UUID()
        let path: String?
        let content: String
    }

    @Published private(set) var messages: [LLMMessage] = []
    @Published private(set) var isGenerating = false
    @Published private(set) var availableModels: [LLMModel]
    @Published var selectedModel: LLMModel
    @Published var generationOptions = LLMGenerationOptions()
    /// How autonomously proposed edits/commands are applied (Manual / Accept edits / Auto).
    @Published var agentMode: AgentMode = .manual
    /// File edits and shell commands proposed by the model that are awaiting approval.
    @Published private(set) var pendingProposals: [PendingToolProposal] = []
    /// The in-progress edit_file content, updated live as it streams in.
    @Published private(set) var liveEditPreview: LiveEditPreview?

    private let engine: LocalAIEngineRouter
    private let downloader: HuggingFaceModelDownloader
    private let terminalRunner = TerminalCommandRunner()
    private var includeProjectContext = true
    private var projectContextTokenBudget = LLMModel.defaultWorkingContextLength
    private var allowTerminalCommands = true
    private var requireTerminalConfirmation = true
    private var streamTask: Task<Void, Never>?
    private var modelContext: ModelContext?
    private var activeItem: Item?
    private var activeItemID: PersistentIdentifier?
    private var persistedMessages: [LLMMessage.ID: ChatMessageRecord] = [:]
    private var currentAssistantMessageID: LLMMessage.ID?
    private var pendingTurn: PendingAgentTurn?
    private let maxToolLoopIterations = 8

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

    /// The `/terminal` and `$ ` manual prefixes — a separate, always-immediate path from
    /// the model-invoked `run_terminal_command` tool below.
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
        let projectContext = projectPath.map {
            ProjectAgentContext(rootPath: $0, bookmarkData: projectBookmarkData)
        }
        // Tool-calling is implemented for the API engine only (OpenAI- and
        // Anthropic-compatible); local MLX/llama.cpp still get file-tree-only context.
        let toolsEnabled = projectContext != nil && model.provider == .api

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
                            reservedResponseTokens: options.maxTokens,
                            toolsEnabled: toolsEnabled
                        )
                    }.value
                } else {
                    requestMessages = chatMessages
                }

                try await self.runAgenticTurn(
                    requestMessages: requestMessages,
                    assistantID: assistantID,
                    model: model,
                    options: options,
                    toolsEnabled: toolsEnabled,
                    projectContext: projectContext,
                    iteration: 0
                )
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

            // Stay "generating" while paused on an approval — the composer should not
            // accept a new prompt mid-tool-call.
            if pendingTurn == nil {
                isGenerating = false
            }

            saveContext()
        }
    }

    /// One assistant turn: stream a response, and if the model requests tools, execute
    /// the safe ones automatically, pause for approval on file edits and (depending on
    /// settings) commands, then recurse with the tool results appended until the model
    /// returns a final answer or the loop cap is hit.
    private func runAgenticTurn(
        requestMessages: [LLMMessage],
        assistantID: LLMMessage.ID,
        model: LLMModel,
        options: LLMGenerationOptions,
        toolsEnabled: Bool,
        projectContext: ProjectAgentContext?,
        iteration: Int
    ) async throws {
        guard iteration < maxToolLoopIterations else {
            replaceAssistantMessage(assistantID, with: "Stopped after too many tool calls in a row.")
            currentAssistantMessageID = nil
            saveContext()
            return
        }

        let stream = await engine.streamChat(
            messages: requestMessages,
            model: model,
            options: options,
            toolsEnabled: toolsEnabled
        )

        var collectedToolCalls: [ToolCallRequest] = []

        for try await event in stream {
            guard !Task.isCancelled else {
                return
            }

            switch event {
            case .token(let token):
                append(token, to: assistantID)
            case .toolCallProgress(_, let name, let argumentsJSON):
                updateLiveEditPreview(name: name, argumentsJSON: argumentsJSON)
            case .toolCalls(let calls):
                collectedToolCalls = calls
            case .completed:
                break
            }
        }

        liveEditPreview = nil

        guard !collectedToolCalls.isEmpty, let projectContext else {
            currentAssistantMessageID = nil
            saveContext()
            return
        }

        setToolCalls(collectedToolCalls, on: assistantID)
        saveContext()

        var toolResultMessages: [LLMMessage] = []
        var proposalsNeedingApproval: [PendingToolProposal] = []

        for call in collectedToolCalls {
            let result = ProjectAgentTools.execute(
                name: call.name,
                argumentsJSON: call.argumentsJSON,
                toolCallID: call.id,
                context: projectContext
            )

            switch result {
            case .text(let text):
                appendToolResult(text, callID: call.id, name: call.name, into: &toolResultMessages)

            case .pendingEdit(let proposal):
                // Accept-edits / Auto modes write the file without asking; Manual pauses.
                if agentMode.autoApplyEdits {
                    let editResult = applyEditWithRecovery(proposal, context: projectContext)
                    appendEditToolResult(editResult, proposal: proposal, callID: call.id, name: call.name, into: &toolResultMessages)
                } else {
                    proposalsNeedingApproval.append(.edit(proposal))
                }

            case .pendingCommand(let proposal):
                if !allowTerminalCommands {
                    appendToolResult(
                        "Terminal commands are disabled in Settings.",
                        callID: call.id,
                        name: call.name,
                        into: &toolResultMessages
                    )
                } else if agentMode.autoRunCommands && !requireTerminalConfirmation {
                    // Auto mode runs commands immediately, unless the safety setting forces a prompt.
                    let commandResult = await terminalRunner.run(
                        command: proposal.command,
                        workingDirectoryPath: projectContext.rootPath,
                        bookmarkData: projectContext.bookmarkData
                    )
                    appendToolResult(
                        terminalResultContent(commandResult),
                        callID: call.id,
                        name: call.name,
                        into: &toolResultMessages
                    )
                } else {
                    proposalsNeedingApproval.append(.command(proposal))
                }
            }
        }

        saveContext()

        let assistantSnapshot = assistantMessageSnapshot(assistantID)

        if !proposalsNeedingApproval.isEmpty {
            pendingTurn = PendingAgentTurn(
                assistantID: assistantID,
                baseMessages: requestMessages + [assistantSnapshot] + toolResultMessages,
                model: model,
                options: options,
                projectContext: projectContext,
                toolsEnabled: toolsEnabled,
                iteration: iteration,
                proposals: proposalsNeedingApproval
            )
            pendingProposals.append(contentsOf: proposalsNeedingApproval)
            currentAssistantMessageID = nil
            return
        }

        let nextAssistantMessage = LLMMessage(role: .assistant, content: "")
        messages.append(nextAssistantMessage)
        persist(nextAssistantMessage)
        currentAssistantMessageID = nextAssistantMessage.id
        saveContext()

        try await runAgenticTurn(
            requestMessages: requestMessages + [assistantSnapshot] + toolResultMessages,
            assistantID: nextAssistantMessage.id,
            model: model,
            options: options,
            toolsEnabled: toolsEnabled,
            projectContext: projectContext,
            iteration: iteration + 1
        )
    }

    private func updateLiveEditPreview(name: String?, argumentsJSON: String) {
        let contentKey: String

        switch name {
        case "edit_file": contentKey = "content"
        case "str_replace": contentKey = "new_str"
        default: return
        }

        let path = ProjectAgentTools.partialStringValue(forKey: "path", inPartialJSON: argumentsJSON)
        let content = ProjectAgentTools.partialStringValue(forKey: contentKey, inPartialJSON: argumentsJSON) ?? ""
        liveEditPreview = LiveEditPreview(path: path, content: content)
    }

    private func appendToolResult(_ text: String, callID: String, name: String, into results: inout [LLMMessage]) {
        let toolMessage = LLMMessage(role: .tool, content: text, toolCallID: callID, toolName: name)
        messages.append(toolMessage)
        persist(toolMessage)
        results.append(toolMessage)
    }

    /// Same as `appendToolResult`, but for a resolved edit: on success, attaches the
    /// before/after content so the UI can offer a "Review" affordance after the fact.
    private func appendEditToolResult(
        _ text: String,
        proposal: ProjectFileEditProposal,
        callID: String,
        name: String,
        into results: inout [LLMMessage]
    ) {
        let succeeded = text == Self.editSuccessMessage
        let toolMessage = LLMMessage(
            role: .tool,
            content: text,
            toolCallID: callID,
            toolName: name,
            diffOriginalContent: succeeded ? proposal.originalContent : nil,
            diffProposedContent: succeeded ? proposal.proposedContent : nil,
            diffPath: succeeded ? proposal.path : nil
        )
        messages.append(toolMessage)
        persist(toolMessage)
        results.append(toolMessage)
    }

    private static let editSuccessMessage = "File written successfully."

    /// Writes an approved edit. If the write is denied because the folder's stored bookmark
    /// is read-only (created before the app had write access), re-requests folder access once
    /// and retries with the fresh read-write bookmark.
    private func applyEditWithRecovery(_ proposal: ProjectFileEditProposal, context: ProjectAgentContext) -> String {
        let result = ProjectAgentTools.applyEdit(proposal, context: context)

        guard case .permissionDenied = result else {
            return result.message
        }

        guard let freshBookmark = ProjectFolderAccess.reauthorize(projectPath: context.rootPath) else {
            return "The edit was not saved: Mayu Echo needs write access to this folder. Re-add the project folder in the sidebar to grant access, then try again."
        }

        persistRefreshedBookmark(freshBookmark, projectPath: context.rootPath)

        let retryContext = ProjectAgentContext(rootPath: context.rootPath, bookmarkData: freshBookmark)
        return ProjectAgentTools.applyEdit(proposal, context: retryContext).message
    }

    /// Stores a freshly minted read-write bookmark on every chat/project row that points at
    /// this folder, so later edits (and future chats) use the read-write bookmark.
    private func persistRefreshedBookmark(_ bookmark: Data, projectPath: String) {
        activeItem?.projectBookmarkData = bookmark

        if let modelContext {
            let descriptor = FetchDescriptor<Item>()
            if let items = try? modelContext.fetch(descriptor) {
                for item in items where item.projectPath == projectPath || item.parentProjectPath == projectPath {
                    item.projectBookmarkData = bookmark
                }
            }
        }

        saveContext()
    }

    /// Approves a proposed edit or command: applies it (writes the file, or runs the
    /// command) and resumes the agentic loop once every proposal in the batch is decided.
    func approve(_ proposal: PendingToolProposal) {
        Task { await resolveProposal(proposal, approved: true) }
    }

    /// Rejects a proposed edit or command: nothing happens, and the model is told so.
    func reject(_ proposal: PendingToolProposal) {
        Task { await resolveProposal(proposal, approved: false) }
    }

    private func resolveProposal(_ proposal: PendingToolProposal, approved: Bool) async {
        guard var turn = pendingTurn,
              let proposalIndex = turn.proposals.firstIndex(where: { $0.id == proposal.id }) else {
            return
        }

        turn.proposals.remove(at: proposalIndex)
        pendingProposals.removeAll { $0.id == proposal.id }

        let toolName: String
        let resultText: String
        var diffOriginalContent: String?
        var diffProposedContent: String?
        var diffPath: String?

        switch proposal {
        case .edit(let editProposal):
            toolName = "edit_file"
            if approved {
                resultText = applyEditWithRecovery(editProposal, context: turn.projectContext)
                if resultText == Self.editSuccessMessage {
                    diffOriginalContent = editProposal.originalContent
                    diffProposedContent = editProposal.proposedContent
                    diffPath = editProposal.path
                }
            } else {
                resultText = "The user rejected this change. The file was not modified."
            }

        case .command(let commandProposal):
            toolName = "run_terminal_command"
            if approved {
                let commandResult = await terminalRunner.run(
                    command: commandProposal.command,
                    workingDirectoryPath: turn.projectContext.rootPath,
                    bookmarkData: turn.projectContext.bookmarkData
                )
                resultText = terminalResultContent(commandResult)
            } else {
                resultText = "The user rejected running this command."
            }
        }

        let toolMessage = LLMMessage(
            role: .tool,
            content: resultText,
            toolCallID: proposal.toolCallID,
            toolName: toolName,
            diffOriginalContent: diffOriginalContent,
            diffProposedContent: diffProposedContent,
            diffPath: diffPath
        )
        messages.append(toolMessage)
        persist(toolMessage)
        turn.baseMessages.append(toolMessage)
        saveContext()

        guard turn.proposals.isEmpty else {
            pendingTurn = turn
            return
        }

        pendingTurn = nil
        isGenerating = true

        let nextAssistantMessage = LLMMessage(role: .assistant, content: "")
        messages.append(nextAssistantMessage)
        persist(nextAssistantMessage)
        currentAssistantMessageID = nextAssistantMessage.id
        saveContext()

        let model = turn.model
        let options = turn.options
        let projectContext = turn.projectContext
        let toolsEnabled = turn.toolsEnabled
        let nextIteration = turn.iteration + 1
        let baseMessages = turn.baseMessages

        streamTask?.cancel()
        streamTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                try await self.runAgenticTurn(
                    requestMessages: baseMessages,
                    assistantID: nextAssistantMessage.id,
                    model: model,
                    options: options,
                    toolsEnabled: toolsEnabled,
                    projectContext: projectContext,
                    iteration: nextIteration
                )
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                self.replaceAssistantMessage(nextAssistantMessage.id, with: error.localizedDescription)
                self.currentAssistantMessageID = nil
            }

            if self.pendingTurn == nil {
                self.isGenerating = false
            }

            self.saveContext()
        }
    }

    private func setToolCalls(_ toolCalls: [ToolCallRequest], on messageID: LLMMessage.ID) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }

        messages[index].toolCalls = toolCalls
        persistedMessages[messageID]?.update(from: messages[index])
    }

    private func assistantMessageSnapshot(_ id: LLMMessage.ID) -> LLMMessage {
        messages.first { $0.id == id } ?? LLMMessage(role: .assistant, content: "")
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        pendingTurn = nil
        pendingProposals = []
        liveEditPreview = nil

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
        requireTerminalConfirmation = settings.requireTerminalConfirmation
        agentMode = settings.agentMode

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
