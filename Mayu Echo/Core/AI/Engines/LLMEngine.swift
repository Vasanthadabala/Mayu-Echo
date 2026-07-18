import Foundation

nonisolated protocol LLMEngine: Sendable {
    var name: String { get }

    func availableModels() async throws -> [LLMModel]

    func load(model: LLMModel) async throws

    func streamChat(
        messages: [LLMMessage],
        model: LLMModel,
        options: LLMGenerationOptions
    ) async -> AsyncThrowingStream<LLMStreamEvent, Error>

    func cancel() async
}

enum LLMStreamEvent: Sendable, Hashable {
    case token(String)
    case completed
}

enum LLMEngineError: LocalizedError, Sendable {
    case emptyPrompt
    case invalidEndpoint(String)
    case invalidModelDirectory(String)
    case modelNotLoaded
    case modelNotDownloaded(String)
    case dependencyMissing(String)
    case providerUnavailable(String)
    case unsupportedModel(String)

    var errorDescription: String? {
        switch self {
        case .emptyPrompt:
            return "Add a message before running the model."
        case .invalidEndpoint(let endpoint):
            return "The local provider endpoint is invalid: \(endpoint)"
        case .invalidModelDirectory(let path):
            return "The local model folder is incomplete: \(path)"
        case .modelNotLoaded:
            return "No local model is loaded."
        case .modelNotDownloaded(let model):
            return "\(model) is not downloaded yet."
        case .dependencyMissing(let dependency):
            return "\(dependency) is not linked yet."
        case .providerUnavailable(let provider):
            return "\(provider) is not reachable. Make sure its local server is running."
        case .unsupportedModel(let model):
            return "\(model) is not supported by this engine."
        }
    }
}
