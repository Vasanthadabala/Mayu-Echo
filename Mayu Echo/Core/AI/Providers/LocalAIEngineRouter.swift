import Foundation

actor LocalAIEngineRouter: LLMEngine {
    nonisolated let name = "Local AI"

    private let mlxEngine: MLXEngine
    private let llamaCppEngine: LlamaCppEngine
    private let remoteAPIEngine: RemoteAPIEngine

    init(
        mlxEngine: MLXEngine = MLXEngine(),
        llamaCppEngine: LlamaCppEngine = LlamaCppEngine(),
        remoteAPIEngine: RemoteAPIEngine = RemoteAPIEngine()
    ) {
        self.mlxEngine = mlxEngine
        self.llamaCppEngine = llamaCppEngine
        self.remoteAPIEngine = remoteAPIEngine
    }

    func availableModels() async throws -> [LLMModel] {
        let mlxModels = (try? await mlxEngine.availableModels()) ?? []
        let llamaCppModels = (try? await llamaCppEngine.availableModels()) ?? []
        let apiModels = (try? await remoteAPIEngine.availableModels()) ?? []

        return LLMModelCatalog.mergedModels(
            defaults: mlxModels + llamaCppModels + apiModels,
            custom: LLMModelCatalog.customModels()
        )
    }

    func load(model: LLMModel) async throws {
        try await engine(for: model.provider).load(model: model)
    }

    func unload(model: LLMModel) async throws {
        switch model.provider {
        case .mlx, .api:
            break
        case .llamaCpp:
            try await llamaCppEngine.unload(model: model)
        }
    }

    func download(model: LLMModel, progress: (@Sendable (Double) async -> Void)? = nil) async throws {
        switch model.provider {
        case .mlx, .api:
            throw LLMEngineError.unsupportedModel(model.displayName)
        case .llamaCpp:
            throw LLMEngineError.dependencyMissing("llama.cpp model download is not implemented yet. Add a local GGUF model file.")
        }
    }

    func streamChat(
        messages: [LLMMessage],
        model: LLMModel,
        options: LLMGenerationOptions,
        toolsEnabled: Bool
    ) async -> AsyncThrowingStream<LLMStreamEvent, Error> {
        await engine(for: model.provider).streamChat(
            messages: messages,
            model: model,
            options: options,
            toolsEnabled: toolsEnabled
        )
    }

    func cancel() async {
        await mlxEngine.cancel()
        await llamaCppEngine.cancel()
        await remoteAPIEngine.cancel()
    }

    private func engine(for provider: LLMModel.Provider) -> any LLMEngine {
        switch provider {
        case .mlx:
            return mlxEngine
        case .llamaCpp:
            return llamaCppEngine
        case .api:
            return remoteAPIEngine
        }
    }
}
