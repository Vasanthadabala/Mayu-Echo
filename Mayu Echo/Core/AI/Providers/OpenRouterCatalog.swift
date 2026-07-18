import Foundation

// MARK: - OpenRouter free model descriptor

nonisolated struct OpenRouterFreeModel: Identifiable, Sendable {
    let id: String           // e.g. "qwen/qwen3-coder:free"
    let displayName: String  // Human-readable label shown in the picker
    let contextLength: Int   // Token context window
    let description: String  // Short one-liner for the picker subtitle

    /// Converts this descriptor into the `APIProviderConfig` format used by
    /// the existing persistence and networking layers.
    func asProviderConfig(name: String? = nil) -> APIProviderConfig {
        APIProviderConfig.openRouter(modelID: id, name: name ?? displayName)
    }
}

// MARK: - Catalog

nonisolated enum OpenRouterCatalog {
    static let baseURL = "https://openrouter.ai/api/v1"

    // MARK: Curated static list (works offline, shown while live fetch is in-flight)

    static let curatedFreeModels: [OpenRouterFreeModel] = [
        OpenRouterFreeModel(
            id: "qwen/qwen3-coder:free",
            displayName: "Qwen3 Coder",
            contextLength: 32_768,
            description: "Alibaba's code-optimised Qwen3 model · free tier"
        ),
        OpenRouterFreeModel(
            id: "qwen/qwen3-235b-a22b:free",
            displayName: "Qwen3 235B A22B",
            contextLength: 32_768,
            description: "Alibaba Qwen3 MoE flagship · free tier"
        ),
        OpenRouterFreeModel(
            id: "meta-llama/llama-3.3-70b-instruct:free",
            displayName: "Llama 3.3 70B Instruct",
            contextLength: 131_072,
            description: "Meta's latest open Llama 70B · free tier"
        ),
        OpenRouterFreeModel(
            id: "meta-llama/llama-3.1-8b-instruct:free",
            displayName: "Llama 3.1 8B Instruct",
            contextLength: 131_072,
            description: "Compact and fast Meta Llama 8B · free tier"
        ),
        OpenRouterFreeModel(
            id: "mistralai/mistral-7b-instruct:free",
            displayName: "Mistral 7B Instruct",
            contextLength: 32_768,
            description: "Mistral AI general-purpose 7B · free tier"
        ),
        OpenRouterFreeModel(
            id: "mistralai/mistral-nemo:free",
            displayName: "Mistral Nemo",
            contextLength: 128_000,
            description: "Mistral Nemo 12B with long context · free tier"
        ),
        OpenRouterFreeModel(
            id: "deepseek/deepseek-r1:free",
            displayName: "DeepSeek R1",
            contextLength: 65_536,
            description: "DeepSeek reasoning model · free tier"
        ),
        OpenRouterFreeModel(
            id: "deepseek/deepseek-chat-v3-0324:free",
            displayName: "DeepSeek Chat V3",
            contextLength: 65_536,
            description: "DeepSeek V3 latest chat model · free tier"
        ),
        OpenRouterFreeModel(
            id: "google/gemma-3-27b-it:free",
            displayName: "Gemma 3 27B",
            contextLength: 131_072,
            description: "Google Gemma 3 instruction-tuned · free tier"
        ),
        OpenRouterFreeModel(
            id: "microsoft/phi-3-mini-128k-instruct:free",
            displayName: "Phi-3 Mini 128K",
            contextLength: 128_000,
            description: "Microsoft Phi-3 Mini with 128K context · free tier"
        ),
    ]

    // MARK: Live fetch

    /// Fetches the full model list from OpenRouter and returns only free models
    /// (those whose `pricing.prompt` equals `"0"`).  Falls back to
    /// `curatedFreeModels` on any error.
    static func fetchFreeModels() async -> [OpenRouterFreeModel] {
        guard let url = URL(string: "\(baseURL)/models") else {
            return curatedFreeModels
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data)

            let free = decoded.data.compactMap { raw -> OpenRouterFreeModel? in
                guard raw.pricing?.prompt == "0" else { return nil }
                return OpenRouterFreeModel(
                    id: raw.id,
                    displayName: raw.name ?? raw.id,
                    contextLength: raw.contextLength ?? 0,
                    description: raw.description ?? "Free model via OpenRouter"
                )
            }
            .sorted { $0.displayName < $1.displayName }

            return free.isEmpty ? curatedFreeModels : free
        } catch {
            return curatedFreeModels
        }
    }
}

// MARK: - Decodable helpers for /api/v1/models

private struct OpenRouterModelsResponse: Decodable {
    let data: [OpenRouterRawModel]
}

private struct OpenRouterRawModel: Decodable {
    let id: String
    let name: String?
    let description: String?
    let contextLength: Int?
    let pricing: OpenRouterPricing?

    private enum CodingKeys: String, CodingKey {
        case id, name, description
        case contextLength = "context_length"
        case pricing
    }
}

private struct OpenRouterPricing: Decodable {
    let prompt: String?
    let completion: String?
}
