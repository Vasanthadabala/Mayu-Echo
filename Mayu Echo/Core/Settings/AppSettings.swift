import Foundation
import Combine
import SwiftUI

enum AppColorScheme: String, CaseIterable, Identifiable {
    case system = "System"
    case dark = "Dark"
    case light = "Light"

    var id: String {
        rawValue
    }

    var swiftUIColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .dark:
            return .dark
        case .light:
            return .light
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let preferredProvider = "mayu.settings.preferredProvider.v1"
        static let selectedModelID = "mayu.settings.selectedModelID.v1"
        static let generationOptions = "mayu.settings.generationOptions.v1"
        static let autoLoadSelectedModel = "mayu.settings.autoLoadSelectedModel.v1"
        static let keepModelLoaded = "mayu.settings.keepModelLoaded.v1"
        static let preferDownloadedModels = "mayu.settings.preferDownloadedModels.v1"
        static let confirmBeforeDownloads = "mayu.settings.confirmBeforeDownloads.v1"
        static let includeProjectContext = "mayu.settings.includeProjectContext.v1"
        static let contextTokenBudget = "mayu.settings.contextTokenBudget.v1"
        static let includeGitChanges = "mayu.settings.includeGitChanges.v1"
        static let allowTerminalCommands = "mayu.settings.allowTerminalCommands.v1"
        static let requireTerminalConfirmation = "mayu.settings.requireTerminalConfirmation.v1"
        static let reduceLocalLogging = "mayu.settings.reduceLocalLogging.v1"
        static let colorScheme = "mayu.settings.colorScheme.v1"
    }

    @Published var preferredProvider: LLMModel.Provider {
        didSet {
            UserDefaults.standard.set(preferredProvider.rawValue, forKey: Key.preferredProvider)
        }
    }

    @Published var selectedModelID: LLMModel.ID? {
        didSet {
            UserDefaults.standard.set(selectedModelID, forKey: Key.selectedModelID)
        }
    }

    @Published var generationOptions: LLMGenerationOptions {
        didSet {
            saveGenerationOptions()
        }
    }

    @Published var autoLoadSelectedModel: Bool {
        didSet {
            UserDefaults.standard.set(autoLoadSelectedModel, forKey: Key.autoLoadSelectedModel)
        }
    }

    @Published var keepModelLoaded: Bool {
        didSet {
            UserDefaults.standard.set(keepModelLoaded, forKey: Key.keepModelLoaded)
        }
    }

    @Published var preferDownloadedModels: Bool {
        didSet {
            UserDefaults.standard.set(preferDownloadedModels, forKey: Key.preferDownloadedModels)
        }
    }

    @Published var confirmBeforeDownloads: Bool {
        didSet {
            UserDefaults.standard.set(confirmBeforeDownloads, forKey: Key.confirmBeforeDownloads)
        }
    }

    @Published var includeProjectContext: Bool {
        didSet {
            UserDefaults.standard.set(includeProjectContext, forKey: Key.includeProjectContext)
        }
    }

    @Published var contextTokenBudget: Int {
        didSet {
            UserDefaults.standard.set(contextTokenBudget, forKey: Key.contextTokenBudget)
        }
    }

    @Published var includeGitChanges: Bool {
        didSet {
            UserDefaults.standard.set(includeGitChanges, forKey: Key.includeGitChanges)
        }
    }

    @Published var allowTerminalCommands: Bool {
        didSet {
            UserDefaults.standard.set(allowTerminalCommands, forKey: Key.allowTerminalCommands)
        }
    }

    @Published var requireTerminalConfirmation: Bool {
        didSet {
            UserDefaults.standard.set(requireTerminalConfirmation, forKey: Key.requireTerminalConfirmation)
        }
    }

    @Published var reduceLocalLogging: Bool {
        didSet {
            UserDefaults.standard.set(reduceLocalLogging, forKey: Key.reduceLocalLogging)
        }
    }

    @Published var colorScheme: AppColorScheme {
        didSet {
            UserDefaults.standard.set(colorScheme.rawValue, forKey: Key.colorScheme)
        }
    }

    init(defaults: UserDefaults = .standard) {
        if let providerValue = defaults.string(forKey: Key.preferredProvider),
           let provider = LLMModel.Provider(rawValue: providerValue) {
            preferredProvider = provider
        } else {
            preferredProvider = .mlx
        }

        selectedModelID = defaults.string(forKey: Key.selectedModelID)

        if let data = defaults.data(forKey: Key.generationOptions),
           let options = try? JSONDecoder().decode(LLMGenerationOptions.self, from: data) {
            generationOptions = options
        } else {
            generationOptions = LLMGenerationOptions()
        }

        autoLoadSelectedModel = defaults.object(forKey: Key.autoLoadSelectedModel) as? Bool ?? true
        keepModelLoaded = defaults.object(forKey: Key.keepModelLoaded) as? Bool ?? true
        preferDownloadedModels = defaults.object(forKey: Key.preferDownloadedModels) as? Bool ?? true
        confirmBeforeDownloads = defaults.object(forKey: Key.confirmBeforeDownloads) as? Bool ?? true
        includeProjectContext = defaults.object(forKey: Key.includeProjectContext) as? Bool ?? true
        contextTokenBudget = defaults.object(forKey: Key.contextTokenBudget) as? Int ?? 32_768
        includeGitChanges = defaults.object(forKey: Key.includeGitChanges) as? Bool ?? true
        allowTerminalCommands = defaults.object(forKey: Key.allowTerminalCommands) as? Bool ?? true
        requireTerminalConfirmation = defaults.object(forKey: Key.requireTerminalConfirmation) as? Bool ?? true
        reduceLocalLogging = defaults.object(forKey: Key.reduceLocalLogging) as? Bool ?? true
        colorScheme = defaults.string(forKey: Key.colorScheme).flatMap(AppColorScheme.init(rawValue:)) ?? .system
    }

    func selectProvider(_ provider: LLMModel.Provider, availableModels: [LLMModel]) {
        preferredProvider = provider

        // Resolve the *exact* current selection (not the provider-based fallback, which
        // would already match `provider` now that it's set and hide a stale selection).
        let currentModel = selectedModelID.flatMap { id in
            availableModels.first { $0.id == id }
        }

        guard currentModel?.provider != provider else {
            return
        }

        selectedModelID = availableModels.first { $0.provider == provider }?.id
    }

    func selectModel(_ model: LLMModel) {
        preferredProvider = model.provider
        selectedModelID = model.id
    }

    func selectedModel(in models: [LLMModel]) -> LLMModel? {
        if let selectedModelID,
           let model = models.first(where: { $0.id == selectedModelID }) {
            return model
        }

        return models.first { $0.provider == preferredProvider } ?? models.first
    }

    private func saveGenerationOptions() {
        guard let data = try? JSONEncoder().encode(generationOptions) else {
            return
        }

        UserDefaults.standard.set(data, forKey: Key.generationOptions)
    }
}
