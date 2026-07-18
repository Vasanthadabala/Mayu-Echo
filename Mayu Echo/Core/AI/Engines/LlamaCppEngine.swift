import Foundation

actor LlamaCppEngine: LLMEngine {
    nonisolated let name = "llama.cpp"

    private var loadedModel: LLMModel?
    private var generationTask: Task<Void, Never>?
    private var generationID: UUID?

    func availableModels() async throws -> [LLMModel] {
        LLMModel.defaultLlamaCppModels
    }

    func load(model: LLMModel) async throws {
        guard model.provider == .llamaCpp else {
            throw LLMEngineError.unsupportedModel(model.displayName)
        }

        guard let localPath = model.localPath,
              FileManager.default.fileExists(atPath: localPath),
              localPath.lowercased().hasSuffix(".gguf") else {
            throw LLMEngineError.modelNotDownloaded("\(model.displayName) GGUF")
        }

        loadedModel = model
    }

    func unload(model: LLMModel) async throws {
        guard loadedModel?.id == model.id else {
            return
        }

        loadedModel = nil
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
            do {
                try await load(model: model)
                throw LLMEngineError.dependencyMissing("llama.cpp runtime is not linked yet.")
            } catch {
                stream.continuation.finish(throwing: error)
            }

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
}
