import SwiftUI

struct APIProviderDraft: Identifiable {
    var id: String
    var name: String
    var baseURL: String
    var format: APIProviderFormat
    var modelID: String
    var apiKey: String
    var isNew: Bool
}

struct APIProviderRow: View {
    let config: APIProviderConfig
    let editAction: () -> Void
    let deleteAction: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(config.name)
                        .font(.system(size: 14, weight: .semibold))

                    // OpenRouter gets a distinct teal badge; others use accent
                    if config.isOpenRouter {
                        Text("OpenRouter")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.mayuAccent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.mayuAccent.opacity(0.12))
                            .clipShape(Capsule())
                    } else {
                        Text(config.format.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.mayuAccent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.mayuAccentSoft)
                            .clipShape(Capsule())
                    }
                }

                Text("\(config.modelID) · \(config.normalizedBaseURL)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                Button(action: editAction) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.mayuElevatedBackground)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: deleteAction) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.mayuWarning)
                        .frame(width: 28, height: 28)
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.mayuWarning.opacity(0.10))
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .opacity(isHovered ? 1 : 0.6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}

struct APIProviderEditorSheet: View {
    @State var draft: APIProviderDraft
    let onSave: (APIProviderDraft) -> Void
    let onCancel: () -> Void
    @State private var isKeyVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(draft.isNew ? "Add API connection" : "Edit API connection")
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 14) {
                labeledField("Name", text: $draft.name, placeholder: "Company Gateway")

                VStack(alignment: .leading, spacing: 6) {
                    Text("Format")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Picker("", selection: $draft.format) {
                        ForEach(APIProviderFormat.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                labeledField("Base URL", text: $draft.baseURL, placeholder: "https://llm.company.com/v1", monospaced: true)
                labeledField("Model ID", text: $draft.modelID, placeholder: "gpt-4o, claude-sonnet-4-5, ...", monospaced: true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("API Key")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Group {
                            if isKeyVisible {
                                TextField("sk-...", text: $draft.apiKey)
                            } else {
                                SecureField("sk-...", text: $draft.apiKey)
                            }
                        }
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))

                        Button(action: { isKeyVisible.toggle() }) {
                            Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.mayuElevatedBackground)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.mayuBorder.opacity(0.6), lineWidth: 1)
                            }
                    }

                    Text("Stored in the macOS Keychain, never in plain text.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            HStack {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: { onSave(draft) }) {
                    Text("Save")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isValid ? Color.mayuOnAccent : .secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background {
                            Capsule().fill(isValid ? Color.mayuAccentSolid : Color.secondary.opacity(0.15))
                        }
                }
                .buttonStyle(.plain)
                .disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(Color.mayuPanelBackground)
    }

    private var isValid: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draft.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draft.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func labeledField(_ label: String, text: Binding<String>, placeholder: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: monospaced ? .monospaced : .default))
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.mayuElevatedBackground)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.mayuBorder.opacity(0.6), lineWidth: 1)
                        }
                }
        }
    }
}

// MARK: - OpenRouter Setup Sheet

struct OpenRouterSetupSheet: View {
    let onSave: (APIProviderDraft) -> Void
    let onCancel: () -> Void

    @State private var apiKey: String = ""
    @State private var isKeyVisible: Bool = false
    @State private var selectedModel: OpenRouterFreeModel? = OpenRouterCatalog.curatedFreeModels.first
    @State private var models: [OpenRouterFreeModel] = OpenRouterCatalog.curatedFreeModels
    @State private var isLoadingModels: Bool = false
    @State private var connectionName: String = "OpenRouter"

    private var isValid: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedModel != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.mayuAccent.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "globe.americas.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.mayuAccent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Add OpenRouter Connection")
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                    Text("Access 400+ models · free tier available")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 14) {

                // Connection name
                labeledField("Connection name", text: $connectionName, placeholder: "OpenRouter")

                // API key
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("API Key")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Link("Get a free key →", destination: URL(string: "https://openrouter.ai/keys")!)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.mayuAccent)
                    }

                    HStack(spacing: 8) {
                        Group {
                            if isKeyVisible {
                                TextField("sk-or-v1-...", text: $apiKey)
                            } else {
                                SecureField("sk-or-v1-...", text: $apiKey)
                            }
                        }
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))

                        Button(action: { isKeyVisible.toggle() }) {
                            Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.mayuElevatedBackground)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.mayuBorder.opacity(0.6), lineWidth: 1)
                            }
                    }

                    Text("Stored in the macOS Keychain, never in plain text.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                // Model picker
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Free model")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        if isLoadingModels {
                            HStack(spacing: 5) {
                                ProgressView().controlSize(.mini)
                                Text("Fetching live list…")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                        } else {
                            Button("Refresh") {
                                Task { await refreshModels() }
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.mayuAccent)
                            .buttonStyle(.plain)
                        }
                    }

                    Menu {
                        ForEach(models) { model in
                            Button {
                                selectedModel = model
                            } label: {
                                if selectedModel?.id == model.id {
                                    Label(model.displayName, systemImage: "checkmark")
                                } else {
                                    Text(model.displayName)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selectedModel?.displayName ?? "Choose a model")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(selectedModel == nil ? .secondary : .primary)
                                if let model = selectedModel {
                                    Text(model.description)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.mayuElevatedBackground)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.mayuBorder.opacity(0.6), lineWidth: 1)
                                }
                        }
                    }
                    .menuStyle(.borderlessButton)

                    if let model = selectedModel {
                        HStack(spacing: 6) {
                            Image(systemName: "text.page")
                                .font(.system(size: 10))
                            Text("Context: \(model.contextLength == 0 ? "—" : "\(model.contextLength / 1_000)K tokens")")
                            Text("·")
                            Image(systemName: "tag")
                                .font(.system(size: 10))
                            Text("Model ID: \(model.id)")
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    }
                }

                // Info note
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.mayuAccent)
                        .padding(.top, 1)
                    Text("Free models on OpenRouter may have rate limits. The base URL is pre-filled automatically.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.mayuAccent.opacity(0.07))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.mayuAccent.opacity(0.2), lineWidth: 1)
                        }
                }
            }

            Divider()

            HStack {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: saveOpenRouter) {
                    Text("Add Connection")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isValid ? Color.mayuOnAccent : .secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background {
                            Capsule().fill(isValid ? Color.mayuAccent : Color.secondary.opacity(0.15))
                        }
                }
                .buttonStyle(.plain)
                .disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(Color.mayuPanelBackground)
        .task {
            await refreshModels()
        }
    }

    // MARK: Private helpers

    @MainActor
    private func refreshModels() async {
        isLoadingModels = true
        defer { isLoadingModels = false }
        let fetched = await OpenRouterCatalog.fetchFreeModels()
        models = fetched
        // Keep the current selection valid; default to first if it disappeared
        if let current = selectedModel, !fetched.contains(where: { $0.id == current.id }) {
            selectedModel = fetched.first
        } else if selectedModel == nil {
            selectedModel = fetched.first
        }
    }

    private func saveOpenRouter() {
        guard let model = selectedModel else { return }

        let trimmedName = connectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmedName.isEmpty ? model.displayName : trimmedName

        let draft = APIProviderDraft(
            id: UUID().uuidString,
            name: displayName,
            baseURL: OpenRouterCatalog.baseURL,
            format: .openAICompatible,
            modelID: model.id,
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            isNew: true
        )

        onSave(draft)
    }

    private func labeledField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.mayuElevatedBackground)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.mayuBorder.opacity(0.6), lineWidth: 1)
                        }
                }
        }
    }
}
