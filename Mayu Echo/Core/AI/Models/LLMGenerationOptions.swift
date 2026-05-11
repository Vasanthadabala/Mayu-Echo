import Foundation

nonisolated struct LLMGenerationOptions: Codable, Hashable, Sendable {
    var temperature: Double
    var topP: Double
    var maxTokens: Int
    var repetitionPenalty: Double
    var intelligence: Intelligence

    init(
        temperature: Double = 0.2,
        topP: Double = 0.9,
        maxTokens: Int = 4_096,
        repetitionPenalty: Double = 1.05,
        intelligence: Intelligence = .medium
    ) {
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.repetitionPenalty = repetitionPenalty
        self.intelligence = intelligence
    }

    enum Intelligence: String, Codable, CaseIterable, Hashable, Sendable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
        case extraHigh = "Extra High"

        var generationPreset: GenerationPreset {
            switch self {
            case .low:
                return GenerationPreset(
                    temperature: 0.15,
                    topP: 0.85,
                    maxTokens: 1_024,
                    repetitionPenalty: 1.08
                )
            case .medium:
                return GenerationPreset(
                    temperature: 0.2,
                    topP: 0.9,
                    maxTokens: 4_096,
                    repetitionPenalty: 1.05
                )
            case .high:
                return GenerationPreset(
                    temperature: 0.18,
                    topP: 0.9,
                    maxTokens: 8_192,
                    repetitionPenalty: 1.05
                )
            case .extraHigh:
                return GenerationPreset(
                    temperature: 0.15,
                    topP: 0.92,
                    maxTokens: 12_288,
                    repetitionPenalty: 1.04
                )
            }
        }
    }

    mutating func applyIntelligencePreset(_ intelligence: Intelligence) {
        let preset = intelligence.generationPreset

        self.intelligence = intelligence
        temperature = preset.temperature
        topP = preset.topP
        maxTokens = preset.maxTokens
        repetitionPenalty = preset.repetitionPenalty
    }

    var resolvedForGeneration: LLMGenerationOptions {
        var options = self
        options.applyIntelligencePreset(intelligence)
        return options
    }
}

nonisolated struct GenerationPreset: Hashable, Sendable {
    let temperature: Double
    let topP: Double
    let maxTokens: Int
    let repetitionPenalty: Double
}
