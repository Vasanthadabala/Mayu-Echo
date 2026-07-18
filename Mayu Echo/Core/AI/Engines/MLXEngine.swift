import Foundation
import MLXLLM
import MLXLMCommon

actor MLXEngine: LLMEngine {
    nonisolated let name = "MLX"

    private var loadedModel: LLMModel?
    private var loadedContainer: ModelContainer?
    private var generationTask: Task<Void, Never>?
    private var generationID: UUID?
    private let downloader = HuggingFaceModelDownloader()
    private let tokenizerLoader = HuggingFaceTokenizerLoader()

    func availableModels() async throws -> [LLMModel] {
        LLMModelCatalog.allModels
            .filter { $0.provider == .mlx }
            .map { downloader.modelWithLocalStatus($0) }
    }

    func load(model: LLMModel) async throws {
        guard model.provider == .mlx else {
            throw LLMEngineError.unsupportedModel(model.displayName)
        }

        if loadedModel?.id == model.id, loadedContainer != nil {
            return
        }

        let localDirectory = try localDirectory(for: model)
        try validateModelDirectory(localDirectory)

        let container = try await LLMModelFactory.shared.loadContainer(
            from: localDirectory,
            using: tokenizerLoader
        )

        var loaded = downloader.modelWithLocalStatus(model)
        loaded.localPath = localDirectory.path
        loaded.isDownloaded = true

        loadedModel = loaded
        loadedContainer = container
    }

    func streamChat(
        messages: [LLMMessage],
        model: LLMModel,
        options: LLMGenerationOptions
    ) async -> AsyncThrowingStream<LLMStreamEvent, Error> {
        generationTask?.cancel()

        let generationID = UUID()
        let stream = AsyncThrowingStream<LLMStreamEvent, Error>.makeStream(of: LLMStreamEvent.self)
        let task = Task {
            await runGeneration(
                messages: messages,
                model: model,
                options: options,
                continuation: stream.continuation
            )
            clearGenerationTask(id: generationID)
        }

        self.generationID = generationID
        generationTask = task
        stream.continuation.onTermination = { @Sendable _ in
            task.cancel()
        }

        return stream.stream
    }

    func cancel() async {
        generationTask?.cancel()
        generationTask = nil
        generationID = nil
    }

    private func clearGenerationTask(id: UUID) {
        guard generationID == id else {
            return
        }

        generationTask = nil
        generationID = nil
    }

    private func runGeneration(
        messages: [LLMMessage],
        model: LLMModel,
        options: LLMGenerationOptions,
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation
    ) async {
        do {
            try await load(model: model)
            guard let loadedContainer else {
                throw LLMEngineError.modelNotLoaded
            }

            let request = try makeChatRequest(from: messages)
            let session = ChatSession(
                loadedContainer,
                history: request.history,
                generateParameters: options.mlxGenerateParameters
            )

            for try await token in session.streamResponse(
                to: request.prompt,
                role: request.role,
                images: [],
                videos: []
            ) {
                guard !Task.isCancelled else {
                    return
                }

                continuation.yield(.token(token))
            }

            continuation.yield(.completed)
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    private func localDirectory(for model: LLMModel) throws -> URL {
        if let localPath = model.localPath, FileManager.default.fileExists(atPath: localPath) {
            return URL(fileURLWithPath: localPath, isDirectory: true)
        }

        let resolved = downloader.modelWithLocalStatus(model)
        if let localPath = resolved.localPath, FileManager.default.fileExists(atPath: localPath) {
            return URL(fileURLWithPath: localPath, isDirectory: true)
        }

        throw LLMEngineError.modelNotDownloaded(model.displayName)
    }

    private func validateModelDirectory(_ directory: URL) throws {
        let fileManager = FileManager.default
        let configURL = directory.appendingPathComponent("config.json")
        let tokenizerURL = directory.appendingPathComponent("tokenizer.json")

        guard fileManager.fileExists(atPath: configURL.path),
              fileManager.fileExists(atPath: tokenizerURL.path),
              containsSafetensors(in: directory) else {
            throw LLMEngineError.invalidModelDirectory(directory.path)
        }
    }

    private func containsSafetensors(in directory: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return false
        }

        for case let url as URL in enumerator where url.pathExtension == "safetensors" {
            return true
        }

        return false
    }

    private func makeChatRequest(from messages: [LLMMessage]) throws -> ChatRequest {
        guard let promptMessage = messages.last else {
            throw LLMEngineError.emptyPrompt
        }

        let history = messages
            .dropLast()
            .compactMap(Self.chatMessage(from:))

        return ChatRequest(
            history: Array(history),
            prompt: promptMessage.content,
            role: Self.chatRole(from: promptMessage.role)
        )
    }

    private static func chatMessage(from message: LLMMessage) -> Chat.Message? {
        switch message.role {
        case .system:
            return .system(message.content)
        case .user:
            return .user(message.content)
        case .assistant:
            return .assistant(message.content)
        case .tool:
            return .tool(message.content)
        }
    }

    private static func chatRole(from role: LLMMessage.Role) -> Chat.Message.Role {
        switch role {
        case .system:
            return .system
        case .user:
            return .user
        case .assistant:
            return .assistant
        case .tool:
            return .tool
        }
    }
}

private nonisolated struct ChatRequest {
    let history: [Chat.Message]
    let prompt: String
    let role: Chat.Message.Role
}

private nonisolated extension LLMGenerationOptions {
    var mlxGenerateParameters: GenerateParameters {
        GenerateParameters(
            maxTokens: maxTokens,
            temperature: Float(temperature),
            topP: Float(topP),
            repetitionPenalty: Float(repetitionPenalty)
        )
    }
}
