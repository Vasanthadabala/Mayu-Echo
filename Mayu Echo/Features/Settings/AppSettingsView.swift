import SwiftUI

struct AppSettingsView: View {
    @EnvironmentObject private var appSettings: AppSettings
    let availableModels: [LLMModel]
    let backAction: () -> Void
    @State private var selectedCategory: SettingsCategory = .general
    @State private var searchText = ""
    @State private var apiProviderConfigs: [APIProviderConfig] = APIProviderCatalog.all()
    @State private var editingConnection: APIProviderDraft?
    @State private var showingOpenRouterSetup: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar

            Divider()
                .background(Color.mayuBorder)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text(selectedCategory.title)
                        .font(.system(size: 26, weight: .semibold, design: .serif))
                        .padding(.top, 56)

                    selectedContent
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 72)
                .padding(.bottom, 56)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.mayuChatBackground)
        }
        .background(Color.mayuSidebarBackground)
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button(action: backAction) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 12, weight: .bold))
                    Text("Back")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(Color.mayuElevatedBackground)
                        .overlay {
                            Capsule()
                                .stroke(Color.mayuBorder.opacity(0.6), lineWidth: 1)
                        }
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 20)

            SidebarSearchField(text: $searchText)

            VStack(alignment: .leading, spacing: 16) {
                SettingsCategoryGroup(title: "LOCAL AI") {
                    categoryRows([.general, .models, .providers, .apiProviders, .generation, .context])
                }

                SettingsCategoryGroup(title: "SYSTEM") {
                    categoryRows([.storage, .runtime, .privacy, .appearance])
                }

                SettingsCategoryGroup(title: "WORKSPACE") {
                    categoryRows([.developerTools, .shortcuts])
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(width: 270)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.mayuSidebarBackground)
    }

    @ViewBuilder
    private func categoryRows(_ categories: [SettingsCategory]) -> some View {
        ForEach(filtered(categories), id: \.self) { category in
            SettingsCategoryRow(
                category: category,
                isSelected: selectedCategory == category
            ) {
                selectedCategory = category
            }
        }
    }

    private func filtered(_ categories: [SettingsCategory]) -> [SettingsCategory] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return categories
        }

        return categories.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedCategory {
        case .general:
            generalSettings
        case .models:
            modelSettings
        case .providers:
            providerSettings
        case .apiProviders:
            apiProvidersSettings
        case .generation:
            generationSettings
        case .context:
            contextSettings
        case .storage:
            storageSettings
        case .runtime:
            runtimeSettings
        case .privacy:
            privacySettings
        case .appearance:
            appearanceSettings
        case .developerTools:
            developerToolSettings
        case .shortcuts:
            shortcutSettings
        }
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 26) {
            SettingsOptionGroup(title: "Default local model", subtitle: "Choose the engine and model Mayu Echo should run first") {
                SettingsPanel {
                    ProviderPickerRow(selection: providerBinding)
                    Divider()
                    if downloadedProviderModels.isEmpty {
                        ReadOnlySettingRow(title: "Default model", subtitle: appSettings.preferredProvider.rawValue, value: "No models available")
                    } else {
                        ModelPickerRow(
                            providerName: appSettings.preferredProvider.rawValue,
                            selectedModelName: selectedModelName,
                            selection: modelBinding,
                            models: downloadedProviderModels
                        )
                    }
                }
            }

            SettingsOptionGroup(title: "Session defaults") {
                SettingsPanel {
                    ReadOnlySettingRow(title: "Local inference", subtitle: "Responses run on this Mac.", value: "On")
                    ReadOnlySettingRow(title: "Current model", subtitle: "Used when a new chat starts.", value: selectedModelName)
                    ReadOnlySettingRow(title: "Default context", subtitle: "Project context limit for new requests.", value: "\(appSettings.contextTokenBudget) tokens")
                }
            }
        }
    }

    private var modelSettings: some View {
        VStack(alignment: .leading, spacing: 26) {
            SettingsOptionGroup(title: "Download policy", subtitle: "Control how Mayu Echo handles local model files") {
                SettingsPanel {
                    ToggleSettingRow(title: "Prefer downloaded models", subtitle: "Show on-device models before model catalog entries.", isOn: $appSettings.preferDownloadedModels)
                    ToggleSettingRow(title: "Confirm before downloads", subtitle: "Ask before downloading multi-GB model files.", isOn: $appSettings.confirmBeforeDownloads)
                }
            }

            SettingsOptionGroup(title: "Model library", subtitle: "Where model files live and how they are recognized") {
                SettingsPanel {
                    ReadOnlySettingRow(title: "MLX library", subtitle: "Downloaded Hugging Face MLX model folders.", value: "Application Support")
                    ReadOnlySettingRow(title: "GGUF library", subtitle: "llama.cpp model files added locally.", value: "Local files")
                    ReadOnlySettingRow(title: "Custom models", subtitle: "User-added Hugging Face repositories.", value: "Enabled")
                    ReadOnlySettingRow(title: "Delete order", subtitle: "Delete downloaded files before removing a model card.", value: "Files first")
                }
            }
        }
    }

    private var providerSettings: some View {
        VStack(alignment: .leading, spacing: 26) {
            SettingsOptionGroup(title: "Active engine", subtitle: "Choose the runtime used by the default model") {
                SettingsPanel {
                    ProviderPickerRow(selection: providerBinding)
                }
            }

            SettingsOptionGroup(title: "Engine capabilities") {
                SettingsPanel {
                    ReadOnlySettingRow(
                        title: selectedEngineCapability.title,
                        subtitle: selectedEngineCapability.subtitle,
                        value: selectedEngineCapability.value
                    )
                    ReadOnlySettingRow(title: "Streaming", subtitle: "Tokens appear while the selected engine generates.", value: "On")
                    ReadOnlySettingRow(title: "Cancellation", subtitle: "Stop active local generation from the composer.", value: "On")
                }
            }

            SettingsOptionGroup(title: "Compatibility") {
                SettingsPanel {
                    ReadOnlySettingRow(
                        title: selectedEngineCompatibility.title,
                        subtitle: selectedEngineCompatibility.subtitle,
                        value: selectedEngineCompatibility.value
                    )
                }
            }
        }
    }

    private var selectedEngineCapability: (title: String, subtitle: String, value: String) {
        switch appSettings.preferredProvider {
        case .mlx:
            return ("MLX", "Apple Silicon runtime for MLX-format models.", "Ready")
        case .llamaCpp:
            return ("llama.cpp", "Native GGUF runtime for broad quantized model support.", "Ready")
        case .api:
            return ("API", "Chat through a private or company-hosted API connection.", "Ready")
        }
    }

    private var selectedEngineCompatibility: (title: String, subtitle: String, value: String) {
        switch appSettings.preferredProvider {
        case .mlx:
            return ("MLX models", "Optimized folders with weights and tokenizer files.", "Safetensors")
        case .llamaCpp:
            return ("llama.cpp models", "Single-file quantized model format.", "GGUF")
        case .api:
            return ("API connections", "OpenAI-compatible and Anthropic-compatible endpoints.", "See API Providers")
        }
    }

    private var apiProvidersSettings: some View {
        VStack(alignment: .leading, spacing: 26) {
            SettingsOptionGroup(
                title: "API connections",
                subtitle: "Point Mayu Echo at a private or company-hosted LLM API instead of running models locally. Keys are stored in the macOS Keychain."
            ) {
                if apiProviderConfigs.isEmpty {
                    SettingsPanel {
                        ReadOnlySettingRow(title: "No connections yet", subtitle: "Add one to chat through a private API.", value: "")
                    }
                } else {
                    SettingsPanel {
                        ForEach(Array(apiProviderConfigs.enumerated()), id: \.element.id) { index, config in
                            if index > 0 {
                                Divider()
                            }

                            APIProviderRow(
                                config: config,
                                editAction: { beginEditingConnection(config) },
                                deleteAction: { deleteConnection(config) }
                            )
                        }
                    }
                }

                // OpenRouter quick-add card
                Button(action: { showingOpenRouterSetup = true }) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.mayuAccent.opacity(0.15))
                                .frame(width: 28, height: 28)
                            Image(systemName: "globe.americas.fill")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.mayuAccent)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Add OpenRouter")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text("Free models, guided setup")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.mayuPanelBackground)
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.mayuAccent.opacity(0.25), lineWidth: 1)
                            }
                    }
                }
                .buttonStyle(.plain)

                Button(action: beginAddingConnection) {
                    Label("Add custom connection", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.mayuOnAccent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background {
                            Capsule().fill(Color.mayuAccentSolid)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(item: $editingConnection) { draft in
            APIProviderEditorSheet(
                draft: draft,
                onSave: saveConnection,
                onCancel: { editingConnection = nil }
            )
        }
        .sheet(isPresented: $showingOpenRouterSetup) {
            OpenRouterSetupSheet(
                onSave: { draft in
                    saveConnection(draft)
                    showingOpenRouterSetup = false
                },
                onCancel: { showingOpenRouterSetup = false }
            )
        }
    }

    private func beginAddingConnection() {
        editingConnection = APIProviderDraft(
            id: UUID().uuidString,
            name: "",
            baseURL: "",
            format: .openAICompatible,
            modelID: "",
            apiKey: "",
            isNew: true
        )
    }

    private func beginEditingConnection(_ config: APIProviderConfig) {
        editingConnection = APIProviderDraft(
            id: config.id,
            name: config.name,
            baseURL: config.baseURL,
            format: config.format,
            modelID: config.modelID,
            apiKey: APIProviderCatalog.apiKey(for: config) ?? "",
            isNew: false
        )
    }

    private func saveConnection(_ draft: APIProviderDraft) {
        let config = APIProviderConfig(
            id: draft.id,
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: draft.baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            format: draft.format,
            modelID: draft.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        APIProviderCatalog.upsert(config, apiKey: draft.apiKey)
        editingConnection = nil
        apiProviderConfigs = APIProviderCatalog.all()
    }

    private func deleteConnection(_ config: APIProviderConfig) {
        APIProviderCatalog.remove(config)
        apiProviderConfigs = APIProviderCatalog.all()
    }

    private var generationSettings: some View {
        SettingsOptionGroup(title: "Response tuning", subtitle: "Tune quality, creativity, and response length") {
            SettingsPanel {
                PickerSettingRow(title: "Intelligence", subtitle: "Controls detail and response budget", value: appSettings.generationOptions.intelligence.rawValue) {
                    Picker("", selection: intelligenceBinding) {
                        ForEach(LLMGenerationOptions.Intelligence.allCases, id: \.self) { intelligence in
                            Text(intelligence.rawValue)
                                .tag(intelligence)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }

                StepperSettingRow(title: "Max response tokens", value: maxTokensBinding, range: 512...12_288, step: 512)
                SliderSettingRow(title: "Temperature", value: temperatureBinding, range: 0...1, formattedValue: String(format: "%.2f", appSettings.generationOptions.temperature))
                SliderSettingRow(title: "Top P", value: topPBinding, range: 0.1...1, formattedValue: String(format: "%.2f", appSettings.generationOptions.topP))
            }
        }
    }

    private var contextSettings: some View {
        VStack(alignment: .leading, spacing: 26) {
            SettingsOptionGroup(title: "Project context", subtitle: "Control what local models receive from your workspace") {
                SettingsPanel {
                    ToggleSettingRow(title: "Include project context", subtitle: "Add relevant files and snippets to chat requests.", isOn: $appSettings.includeProjectContext)
                    StepperSettingRow(title: "Context token budget", value: $appSettings.contextTokenBudget, range: 4_096...65_536, step: 4_096)
                    ToggleSettingRow(title: "Include Git changes", subtitle: "Send current changed files and diffs when available.", isOn: $appSettings.includeGitChanges)
                }
            }

            SettingsOptionGroup(title: "Context safety") {
                SettingsPanel {
                    ReadOnlySettingRow(title: "Large files", subtitle: "Very large files should be summarized before sending.", value: "Summarize")
                    ReadOnlySettingRow(title: "Binary files", subtitle: "Images, archives, and binaries stay out of text context.", value: "Excluded")
                }
            }
        }
    }

    private var storageSettings: some View {
        SettingsOptionGroup(title: "Local storage", subtitle: "Manage model files and local cache behavior") {
            SettingsPanel {
                ToggleSettingRow(title: "Confirm before downloads", subtitle: "Avoid accidental multi-GB model downloads.", isOn: $appSettings.confirmBeforeDownloads)
                ReadOnlySettingRow(title: "MLX download location", subtitle: "Where Mayu Echo stores downloaded MLX models.", value: "Application Support")
                ReadOnlySettingRow(title: "GGUF model files", subtitle: "llama.cpp models are stored as local .gguf files.", value: "Local")
            }
        }
    }

    private var runtimeSettings: some View {
        SettingsOptionGroup(title: "Runtime behavior", subtitle: "Tune memory and startup behavior for local inference") {
            SettingsPanel {
                ToggleSettingRow(title: "Auto-load selected model", subtitle: "Load the selected model when a response starts.", isOn: $appSettings.autoLoadSelectedModel)
                ToggleSettingRow(title: "Keep model loaded", subtitle: "Keep the model in memory after generation when supported.", isOn: $appSettings.keepModelLoaded)
                ReadOnlySettingRow(title: "Streaming responses", subtitle: "Show tokens as they arrive from the local engine.", value: "On")
                ReadOnlySettingRow(title: "Cancellation", subtitle: "Stop active local generation from the composer.", value: "On")
            }
        }
    }

    private var privacySettings: some View {
        VStack(alignment: .leading, spacing: 26) {
            SettingsOptionGroup(title: "Privacy", subtitle: "Keep local model usage private by default") {
                SettingsPanel {
                    ToggleSettingRow(title: "Reduce local logging", subtitle: "Avoid writing prompt and response details to logs.", isOn: $appSettings.reduceLocalLogging)
                    ReadOnlySettingRow(title: "Cloud inference", subtitle: "Mayu Echo runs models locally.", value: "Off")
                    ReadOnlySettingRow(title: "Prompt storage", subtitle: "Chats are stored locally by SwiftData.", value: "Local")
                }
            }

            SettingsOptionGroup(title: "Workspace access") {
                SettingsPanel {
                    ToggleSettingRow(title: "Include project context", subtitle: "Allow selected workspace content in local prompts.", isOn: $appSettings.includeProjectContext)
                    ToggleSettingRow(title: "Include Git changes", subtitle: "Allow changed files and diffs in local prompts.", isOn: $appSettings.includeGitChanges)
                }
            }
        }
    }

    private var appearanceSettings: some View {
        SettingsOptionGroup(title: "Interface") {
            SettingsPanel {
                PickerSettingRow(title: "Color mode", subtitle: "Choose system, dark, or light appearance", value: appSettings.colorScheme.rawValue) {
                    Picker("", selection: $appSettings.colorScheme) {
                        ForEach(AppColorScheme.allCases) { scheme in
                            Text(scheme.rawValue)
                                .tag(scheme)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }
                ToggleSettingRow(title: "Compact sidebar", subtitle: "Use tighter chat and project rows.", isOn: .constant(true))
                ToggleSettingRow(title: "Reduce visual effects", subtitle: "Use simpler shadows and surfaces.", isOn: .constant(true))
            }
        }
    }

    private var developerToolSettings: some View {
        SettingsOptionGroup(title: "Developer tools", subtitle: "Controls for coding workflows with local models") {
            SettingsPanel {
                ToggleSettingRow(title: "Allow terminal commands", subtitle: "Enable /terminal and $ command prompts in chat.", isOn: $appSettings.allowTerminalCommands)
                ToggleSettingRow(title: "Confirm terminal commands", subtitle: "Ask before running generated or typed terminal commands.", isOn: $appSettings.requireTerminalConfirmation)
                ToggleSettingRow(title: "Include Git changes", subtitle: "Let the assistant reason over current file changes.", isOn: $appSettings.includeGitChanges)
                ReadOnlySettingRow(title: "Project review panel", subtitle: "Show changed files after local model actions.", value: "On")
            }
        }
    }

    private var shortcutSettings: some View {
        SettingsOptionGroup(title: "Keyboard shortcuts") {
            SettingsPanel {
                ReadOnlySettingRow(title: "Open settings", subtitle: "Show local LLM settings.", value: "⌘,")
                ReadOnlySettingRow(title: "Send message", subtitle: "Submit the current prompt.", value: "Return")
                ReadOnlySettingRow(title: "New line", subtitle: "Insert a line break in the composer.", value: "⇧ Return")
            }
        }
    }

    private var providerModels: [LLMModel] {
        availableModels.filter { $0.provider == appSettings.preferredProvider }
    }

    private var downloadedProviderModels: [LLMModel] {
        providerModels.filter(\.isDownloaded)
    }

    private var selectedModelName: String {
        guard let model = appSettings.selectedModel(in: availableModels), model.isDownloaded else {
            return "No models available"
        }

        return model.displayName
    }

    private var providerBinding: Binding<LLMModel.Provider> {
        Binding {
            appSettings.preferredProvider
        } set: { provider in
            appSettings.selectProvider(provider, availableModels: availableModels)
        }
    }

    private var modelBinding: Binding<LLMModel.ID> {
        Binding {
            let currentModel = appSettings.selectedModel(in: availableModels)

            if let currentModel, downloadedProviderModels.contains(where: { $0.id == currentModel.id }) {
                return currentModel.id
            }

            return downloadedProviderModels.first?.id ?? ""
        } set: { modelID in
            guard let model = availableModels.first(where: { $0.id == modelID }) else {
                return
            }

            appSettings.selectModel(model)
        }
    }

    private var intelligenceBinding: Binding<LLMGenerationOptions.Intelligence> {
        Binding {
            appSettings.generationOptions.intelligence
        } set: { intelligence in
            appSettings.generationOptions.applyIntelligencePreset(intelligence)
        }
    }

    private var maxTokensBinding: Binding<Int> {
        Binding {
            appSettings.generationOptions.maxTokens
        } set: { maxTokens in
            appSettings.generationOptions.maxTokens = maxTokens
        }
    }

    private var temperatureBinding: Binding<Double> {
        Binding {
            appSettings.generationOptions.temperature
        } set: { temperature in
            appSettings.generationOptions.temperature = temperature
        }
    }

    private var topPBinding: Binding<Double> {
        Binding {
            appSettings.generationOptions.topP
        } set: { topP in
            appSettings.generationOptions.topP = topP
        }
    }
}

private enum SettingsCategory: CaseIterable, Hashable {
    case general
    case models
    case providers
    case apiProviders
    case generation
    case context
    case storage
    case runtime
    case privacy
    case appearance
    case developerTools
    case shortcuts

    var title: String {
        switch self {
        case .general: return "General"
        case .models: return "Models"
        case .providers: return "Engines"
        case .apiProviders: return "API Providers"
        case .generation: return "Generation"
        case .context: return "Context"
        case .storage: return "Storage"
        case .runtime: return "Runtime"
        case .privacy: return "Privacy"
        case .appearance: return "Appearance"
        case .developerTools: return "Developer tools"
        case .shortcuts: return "Shortcuts"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .models: return "cpu"
        case .providers: return "point.3.connected.trianglepath.dotted"
        case .apiProviders: return "network"
        case .generation: return "slider.horizontal.3"
        case .context: return "text.page"
        case .storage: return "internaldrive"
        case .runtime: return "memorychip"
        case .privacy: return "lock.shield"
        case .appearance: return "sun.max"
        case .developerTools: return "terminal"
        case .shortcuts: return "keyboard"
        }
    }
}

private struct SettingsCategoryGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.quaternary)
                .tracking(0.6)
                .padding(.horizontal, 10)

            VStack(alignment: .leading, spacing: 2) {
                content
            }
        }
    }
}

private struct SettingsCategoryRow: View {
    let category: SettingsCategory
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? Color.mayuAccentSoft : Color.mayuPanelBackground.opacity(0.6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(Color.mayuBorder.opacity(isSelected ? 0.5 : 0.3), lineWidth: 1)
                        }

                    Image(systemName: category.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.mayuAccent : .secondary)
                }
                .frame(width: 26, height: 26)
                .animation(.easeInOut(duration: 0.15), value: isSelected)

                Text(category.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.mayuSelection : (isHovered ? Color.mayuSelection.opacity(0.55) : .clear))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : (isHovered ? .primary : .secondary))
        .animation(.easeInOut(duration: 0.12), value: isSelected)
        .animation(.easeInOut(duration: 0.1), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

private struct SettingsOptionGroup<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            content
        }
    }
}

private struct SettingsPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.mayuPanelBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.mayuBorder.opacity(0.6), lineWidth: 1)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct SelectableSettingCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isSelected ? Color.mayuAccent : .secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(isSelected ? Color.mayuSelection : Color.mayuPanelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.mayuBorder.opacity(0.55), lineWidth: 1)
        }
    }
}

private struct ProviderPickerRow: View {
    @Binding var selection: LLMModel.Provider

    var body: some View {
        HStack(spacing: 16) {
            Text("Engine")
                .font(.system(size: 14, weight: .medium))

            Spacer()

            Menu {
                ForEach(LLMModel.Provider.allCases, id: \.self) { provider in
                    Button {
                        selection = provider
                    } label: {
                        if selection == provider {
                            Label(provider.rawValue, systemImage: "checkmark")
                        } else {
                            Text(provider.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: selection.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                    Text(selection.rawValue)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct ModelPickerRow: View {
    let providerName: String
    let selectedModelName: String
    @Binding var selection: LLMModel.ID
    let models: [LLMModel]

    var body: some View {
        PickerSettingRow(
            title: "Default model",
            subtitle: providerName,
            value: selectedModelName
        ) {
            Menu {
                ForEach(models, id: \.id) { model in
                    Button {
                        selection = model.id
                    } label: {
                        if selection == model.id {
                            Label(model.displayName, systemImage: "checkmark")
                        } else {
                            Text(model.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selectedModelName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .menuStyle(.borderlessButton)
            .frame(width: 320, alignment: .trailing)
        }
    }
}

private struct ToggleSettingRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

private struct TextFieldSettingRow: View {
    let title: String
    let subtitle: String
    @Binding var text: String
    var isSecure = false

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Group {
                if isSecure {
                    SecureField("", text: $text)
                } else {
                    TextField("", text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 14, weight: .medium))
            .multilineTextAlignment(.trailing)
            .frame(width: 300)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

private struct ReadOnlySettingRow: View {
    let title: String
    let subtitle: String
    let value: String

    var body: some View {
        PickerSettingRow(title: title, subtitle: subtitle, value: value)
    }
}

private struct PickerSettingRow<Trailing: View>: View {
    let title: String
    let subtitle: String
    let value: String
    let trailing: Trailing

    init(title: String, subtitle: String, value: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.trailing = trailing()
    }

    init(title: String, subtitle: String, value: String) where Trailing == Text {
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.trailing = Text(value)
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            trailing
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

private struct StepperSettingRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        Stepper(value: $value, in: range, step: step) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Text("\(value)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

private struct SliderSettingRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let formattedValue: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Text(formattedValue)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Slider(value: $value, in: range)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

private extension LLMModel.Provider {
    var systemImage: String {
        switch self {
        case .mlx:
            return "apple.logo"
        case .llamaCpp:
            return "memorychip"
        case .api:
            return "network"
        }
    }
}
