import Foundation

nonisolated enum APIProviderFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case openAICompatible = "OpenAI-compatible"
    case anthropicCompatible = "Anthropic-compatible"

    var id: String { rawValue }
}

nonisolated struct APIProviderConfig: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var name: String
    var baseURL: String
    var format: APIProviderFormat
    var modelID: String

    init(
        id: String = UUID().uuidString,
        name: String,
        baseURL: String,
        format: APIProviderFormat,
        modelID: String
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.format = format
        self.modelID = modelID
    }

    var normalizedBaseURL: String {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)

        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }

        return trimmed
    }

    var llmModelID: String {
        "api-\(id)"
    }

    var asLLMModel: LLMModel {
        LLMModel(
            id: llmModelID,
            displayName: name,
            provider: .api,
            repository: modelID,
            isDownloaded: true,
            isRecommendedForCoding: false,
            statusDescription: format.rawValue,
            apiProviderConfigID: id
        )
    }
}

// MARK: - OpenRouter convenience factory

nonisolated extension APIProviderConfig {
    /// Creates a pre-filled `APIProviderConfig` pointed at OpenRouter's
    /// OpenAI-compatible endpoint.  The caller only needs to supply a
    /// model identifier (e.g. `"qwen/qwen3-coder:free"`) and an optional
    /// human-readable display name.
    static func openRouter(modelID: String, name: String? = nil) -> APIProviderConfig {
        APIProviderConfig(
            name: name ?? modelID,
            baseURL: OpenRouterCatalog.baseURL,
            format: .openAICompatible,
            modelID: modelID
        )
    }

    /// Returns `true` when this config targets OpenRouter.
    var isOpenRouter: Bool {
        normalizedBaseURL.contains("openrouter.ai")
    }
}

nonisolated enum APIProviderCatalog {
    private static let storageKey = "mayu.apiProviderConfigs.v1"

    /// Posted on the main queue whenever the catalog changes (add, edit, or delete).
    /// Observers can use this to refresh their available-model lists.
    static let didChange = Notification.Name("APIProviderCatalog.didChange")

    static func all() -> [APIProviderConfig] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let configs = try? JSONDecoder().decode([APIProviderConfig].self, from: data) else {
            return []
        }

        return configs
    }

    static var allModels: [LLMModel] {
        all().map(\.asLLMModel)
    }

    static func config(withID id: String) -> APIProviderConfig? {
        all().first { $0.id == id }
    }

    @discardableResult
    static func upsert(_ config: APIProviderConfig, apiKey: String?) -> APIProviderConfig {
        var configs = all()

        if let index = configs.firstIndex(where: { $0.id == config.id }) {
            configs[index] = config
        } else {
            configs.append(config)
        }

        save(configs)

        if let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            KeychainStore.save(apiKey, forAccount: config.id)
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: didChange, object: nil)
        }

        return config
    }

    static func remove(_ config: APIProviderConfig) {
        var configs = all()
        configs.removeAll { $0.id == config.id }
        save(configs)
        KeychainStore.delete(forAccount: config.id)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    static func apiKey(for config: APIProviderConfig) -> String? {
        KeychainStore.read(forAccount: config.id)
    }

    private static func save(_ configs: [APIProviderConfig]) {
        guard let data = try? JSONEncoder().encode(configs) else {
            return
        }

        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
