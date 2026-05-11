import Foundation

nonisolated struct LLMModel: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var displayName: String
    var provider: Provider
    var repository: String
    var localPath: String?
    var contextLength: Int
    var isDownloaded: Bool
    var isRecommendedForCoding: Bool

    init(
        id: String,
        displayName: String,
        provider: Provider = .mlx,
        repository: String,
        localPath: String? = nil,
        contextLength: Int = 0,
        isDownloaded: Bool = false,
        isRecommendedForCoding: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.provider = provider
        self.repository = repository
        self.localPath = localPath
        self.contextLength = contextLength
        self.isDownloaded = isDownloaded
        self.isRecommendedForCoding = isRecommendedForCoding
    }

    enum Provider: String, Codable, Hashable, Sendable {
        case mlx = "MLX"
    }
}

nonisolated extension LLMModel {
    static let defaultWorkingContextLength = 32_768

    var workingContextLength: Int {
        guard contextLength > 0 else {
            return Self.defaultWorkingContextLength
        }

        return min(contextLength, Self.defaultWorkingContextLength)
    }

    static let qwen25Coder7BInstruct4Bit = LLMModel(
        id: "qwen25-coder-7b-instruct-4bit",
        displayName: "Qwen2.5 Coder 7B Instruct 4-bit",
        repository: "mlx-community/Qwen2.5-Coder-7B-Instruct-4bit",
        isRecommendedForCoding: true
    )

    static let qwen25Coder14BInstruct4Bit = LLMModel(
        id: "qwen25-coder-14b-instruct-4bit",
        displayName: "Qwen2.5 Coder 14B Instruct 4-bit",
        repository: "mlx-community/Qwen2.5-Coder-14B-Instruct-4bit",
        isRecommendedForCoding: true
    )

    static let defaultMLXModels: [LLMModel] = [
        .qwen25Coder7BInstruct4Bit,
        .qwen25Coder14BInstruct4Bit
    ]

    static func customHuggingFaceModel(repository: String) -> LLMModel {
        let normalizedRepository = repository.trimmingCharacters(in: .whitespacesAndNewlines)
        let slug = normalizedRepository.split(separator: "/").last.map(String.init) ?? normalizedRepository
        let displayName = slug
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")

        return LLMModel(
            id: "hf-\(normalizedRepository.stableModelIDComponent)",
            displayName: displayName,
            repository: normalizedRepository,
            isRecommendedForCoding: normalizedRepository.lowercased().isCodingModelRepository
        )
    }
}

nonisolated enum LLMModelCatalog {
    private static let customModelsStorageKey = "mayu.customHuggingFaceModels.v1"

    static var allModels: [LLMModel] {
        mergedModels(defaults: LLMModel.defaultMLXModels, custom: customModels())
    }

    static func customModels() -> [LLMModel] {
        guard let data = UserDefaults.standard.data(forKey: customModelsStorageKey),
              let models = try? JSONDecoder().decode([LLMModel].self, from: data) else {
            return []
        }

        return models
    }

    static func saveCustomModels(_ models: [LLMModel]) {
        guard let data = try? JSONEncoder().encode(models) else {
            return
        }

        UserDefaults.standard.set(data, forKey: customModelsStorageKey)
    }

    static func repository(fromHuggingFaceInput input: String) throws -> String {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedInput.isEmpty else {
            throw HuggingFaceModelReferenceError.emptyInput
        }

        if let repository = repositoryFromURL(trimmedInput) {
            return repository
        }

        if isRepositoryID(trimmedInput) {
            return normalizedRepository(trimmedInput)
        }

        throw HuggingFaceModelReferenceError.invalidInput
    }

    static func mergedModels(defaults: [LLMModel], custom: [LLMModel]) -> [LLMModel] {
        var seenIDs = Set<String>()
        var merged: [LLMModel] = []

        for model in defaults + custom where seenIDs.insert(model.id).inserted {
            merged.append(model)
        }

        return merged
    }

    private static func repositoryFromURL(_ input: String) -> String? {
        let rawURL = input.contains("://") ? input : "https://\(input)"

        guard let components = URLComponents(string: rawURL),
              let host = components.host?.lowercased(),
              host == "huggingface.co" || host == "www.huggingface.co" || host == "hf.co" else {
            return nil
        }

        var pathComponents = components.path
            .split(separator: "/")
            .map(String.init)

        if pathComponents.first == "api", pathComponents.dropFirst().first == "models" {
            pathComponents.removeFirst(2)
        }

        guard pathComponents.count >= 2 else {
            return nil
        }

        let owner = pathComponents[0]
        let model = pathComponents[1]
        return normalizedRepository("\(owner)/\(model)")
    }

    private static func isRepositoryID(_ input: String) -> Bool {
        let components = input.split(separator: "/")
        guard components.count == 2 else {
            return false
        }

        return components.allSatisfy { component in
            !component.isEmpty && !component.contains(" ") && !component.contains(":")
        }
    }

    private static func normalizedRepository(_ repository: String) -> String {
        repository
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

nonisolated enum HuggingFaceModelReferenceError: LocalizedError {
    case emptyInput
    case invalidInput

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Paste a Hugging Face model URL or repository id."
        case .invalidInput:
            return "Use a Hugging Face model URL like https://huggingface.co/mlx-community/Qwen2.5-Coder-7B-Instruct-4bit."
        }
    }
}

private nonisolated extension String {
    var stableModelIDComponent: String {
        lowercased()
            .map { character -> Character in
                character.isLetter || character.isNumber ? character : "-"
            }
            .reduce(into: "") { partialResult, character in
                if character == "-", partialResult.last == "-" {
                    return
                }

                partialResult.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    var isCodingModelRepository: Bool {
        contains("coder") ||
        contains("code") ||
        contains("codestral") ||
        contains("starcoder") ||
        contains("deepseek-coder")
    }
}
