import Foundation
import LLM

actor LlamaCppEngine: LLMEngine {
    nonisolated let name = "llama.cpp"

    private var llm: LLM?
    private var loadedModelID: String?
    private var generationTask: Task<Void, Never>?
    private var generationID: UUID?
    private let downloader = HuggingFaceModelDownloader()

    func availableModels() async throws -> [LLMModel] {
        LLMModel.defaultLlamaCppModels.map { downloader.ggufModelWithLocalStatus($0) }
    }

    func load(model: LLMModel) async throws {
        guard model.provider == .llamaCpp else {
            throw LLMEngineError.unsupportedModel(model.displayName)
        }

        if loadedModelID == model.id, llm != nil {
            return
        }

        let resolved = downloader.ggufModelWithLocalStatus(model)

        guard let localPath = resolved.localPath ?? model.localPath,
              FileManager.default.fileExists(atPath: localPath),
              localPath.lowercased().hasSuffix(".gguf") else {
            throw LLMEngineError.modelNotDownloaded("\(model.displayName) GGUF")
        }

        // Model loading is heavy and synchronous (mmap + metadata); confine it to the actor.
        guard let instance = LLM(
            from: URL(fileURLWithPath: localPath),
            maxTokenCount: Int32(clampedContextLength(for: resolved))
        ) else {
            throw LLMEngineError.invalidModelDirectory(localPath)
        }

        llm = instance
        loadedModelID = model.id
    }

    func unload(model: LLMModel) async throws {
        guard loadedModelID == model.id else {
            return
        }

        llm?.stop()
        llm = nil
        loadedModelID = nil
    }

    func streamChat(
        messages: [LLMMessage],
        model: LLMModel,
        options: LLMGenerationOptions,
        toolsEnabled: Bool
    ) async -> AsyncThrowingStream<LLMStreamEvent, Error> {
        // toolsEnabled ignored — llama.cpp tool-calling isn't implemented yet.
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
        llm?.stop()
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

            guard let llm else {
                throw LLMEngineError.modelNotLoaded
            }

            let systemPrompt = messages.first { $0.role == .system }?.content
            let conversation = messages.filter { $0.role != .system }

            guard let lastMessage = conversation.last else {
                throw LLMEngineError.emptyPrompt
            }

            let history: [Chat] = conversation.dropLast().map { message in
                (message.role == .assistant ? Role.bot : Role.user, message.content)
            }

            llm.template = template(for: model, systemPrompt: systemPrompt)
            llm.history = history
            llm.temp = Float(options.temperature)
            llm.topP = Float(options.topP)

            await llm.respond(to: lastMessage.content) { tokenStream in
                var accumulated = ""

                for await delta in tokenStream {
                    if Task.isCancelled {
                        break
                    }

                    continuation.yield(.token(delta))
                    accumulated += delta
                }

                return accumulated
            }

            continuation.yield(.completed)
            continuation.finish()
        } catch {
            guard !Task.isCancelled else {
                return
            }

            continuation.finish(throwing: error)
        }
    }

    private func template(for model: LLMModel, systemPrompt: String?) -> Template {
        let identifier = model.repository.lowercased()

        if identifier.contains("llama-3") || identifier.contains("llama3") {
            return .llama(systemPrompt)
        }

        if identifier.contains("gemma") {
            return .gemma
        }

        if identifier.contains("mistral") {
            return .mistral
        }

        // Qwen, DeepSeek-Coder and most modern instruct GGUFs use the ChatML format.
        return .chatML(systemPrompt)
    }

    private func clampedContextLength(for model: LLMModel) -> Int {
        let requested = model.contextLength > 0 ? model.contextLength : LLMModel.defaultWorkingContextLength
        return min(max(requested, 2_048), 8_192)
    }
}
