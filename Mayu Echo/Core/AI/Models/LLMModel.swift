import Foundation

nonisolated struct LLMModel: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var displayName: String
    var provider: Provider
    var repository: String
    var localPath: String?
    var contextLength: Int
    var isDownloaded: Bool
    var isLoaded: Bool
    var isRecommendedForCoding: Bool
    var statusDescription: String?
    var apiProviderConfigID: String?

    init(
        id: String,
        displayName: String,
        provider: Provider = .mlx,
        repository: String,
        localPath: String? = nil,
        contextLength: Int = 0,
        isDownloaded: Bool = false,
        isLoaded: Bool = false,
        isRecommendedForCoding: Bool = false,
        statusDescription: String? = nil,
        apiProviderConfigID: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.provider = provider
        self.repository = repository
        self.localPath = localPath
        self.contextLength = contextLength
        self.isDownloaded = isDownloaded
        self.isLoaded = isLoaded
        self.isRecommendedForCoding = isRecommendedForCoding
        self.statusDescription = statusDescription
        self.apiProviderConfigID = apiProviderConfigID
    }

    enum Provider: String, Codable, CaseIterable, Hashable, Sendable {
        case mlx = "MLX"
        case llamaCpp = "llama.cpp"
        case api = "API"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case provider
        case repository
        case localPath
        case contextLength
        case isDownloaded
        case isLoaded
        case isRecommendedForCoding
        case statusDescription
        case apiProviderConfigID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        provider = try container.decodeIfPresent(Provider.self, forKey: .provider) ?? .mlx
        repository = try container.decode(String.self, forKey: .repository)
        localPath = try container.decodeIfPresent(String.self, forKey: .localPath)
        contextLength = try container.decodeIfPresent(Int.self, forKey: .contextLength) ?? 0
        isDownloaded = try container.decodeIfPresent(Bool.self, forKey: .isDownloaded) ?? false
        isLoaded = try container.decodeIfPresent(Bool.self, forKey: .isLoaded) ?? false
        isRecommendedForCoding = try container.decodeIfPresent(Bool.self, forKey: .isRecommendedForCoding) ?? false
        statusDescription = try container.decodeIfPresent(String.self, forKey: .statusDescription)
        apiProviderConfigID = try container.decodeIfPresent(String.self, forKey: .apiProviderConfigID)
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

    static let llamaCppLlama32 = LLMModel(
        id: "llamacpp-llama-3-2-3b-instruct-gguf",
        displayName: "Llama 3.2 3B Instruct GGUF",
        provider: .llamaCpp,
        repository: "bartowski/Llama-3.2-3B-Instruct-GGUF",
        contextLength: 131_072,
        isRecommendedForCoding: false
    )

    static let llamaCppQwen25Coder = LLMModel(
        id: "llamacpp-qwen2-5-coder-7b-instruct-gguf",
        displayName: "Qwen2.5 Coder 7B Instruct GGUF",
        provider: .llamaCpp,
        repository: "bartowski/Qwen2.5-Coder-7B-Instruct-GGUF",
        contextLength: 32_768,
        isRecommendedForCoding: true
    )

    static let defaultLlamaCppModels: [LLMModel] = [
        .llamaCppLlama32,
        .llamaCppQwen25Coder
    ]

    static let defaultManagedModels: [LLMModel] = defaultMLXModels + defaultLlamaCppModels

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

    static func customLlamaCppModel(name: String, localPath: String? = nil) -> LLMModel {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        return LLMModel(
            id: "llamacpp-\(trimmedName.stableModelIDComponent)",
            displayName: trimmedName.displayModelName,
            provider: .llamaCpp,
            repository: trimmedName,
            localPath: localPath,
            isDownloaded: localPath != nil,
            isRecommendedForCoding: trimmedName.lowercased().isCodingModelRepository
        )
    }
}

nonisolated enum LLMModelCatalog {
    private static let customModelsStorageKey = "mayu.customHuggingFaceModels.v1"

    static var allModels: [LLMModel] {
        mergedModels(
            defaults: LLMModel.defaultManagedModels,
            custom: customModels() + APIProviderCatalog.allModels
        )
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

    var displayModelName: String {
        split(separator: "/").last.map(String.init) ?? self
    }
}
