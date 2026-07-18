import SwiftUI

struct AIModelsView: View {
    var backAction: () -> Void = {}
    @StateObject private var viewModel = AIModelsViewModel()
    @State private var huggingFaceInput = ""
    @State private var selectedProviderFilter: AIModelProviderFilter = .all

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                providerFilterBar
                addModelPanel

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Available Models")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("\(filteredModels.count)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.mayuPanelBackground)
                            .clipShape(Capsule())
                    }

                    ForEach(filteredModels) { model in
                        AIModelCard(
                            model: model,
                            state: viewModel.state(for: model),
                            isRemovable: viewModel.isCustomModel(model),
                            downloadAction: {
                                viewModel.download(model)
                            },
                            loadAction: {
                                viewModel.load(model)
                            },
                            unloadAction: {
                                viewModel.unload(model)
                            },
                            deleteAction: {
                                viewModel.deleteDownloadedModel(model)
                            },
                            removeAction: {
                                viewModel.removeCustomModel(model)
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 30)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.mayuChatBackground)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                backButton
            }
        }
        .onAppear {
            viewModel.refresh()
        }
    }

    private var backButton: some View {
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
    }

    private var addModelPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.mayuAccentSoft)
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.mayuBorder.opacity(0.5), lineWidth: 1)
                        }

                    Image(systemName: "link")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.mayuAccent)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Add Hugging Face Model")
                        .font(.system(size: 15, weight: .semibold))

                    Text("Paste a model URL or repo id to create a downloadable MLX model card.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 10) {
                TextField("https://huggingface.co/mlx-community/...", text: $huggingFaceInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .regular))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.mayuComposerBackground)
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.mayuBorder.opacity(0.6), lineWidth: 1)
                            }
                    }
                    .onSubmit(addCustomModel)

                Button(action: addCustomModel) {
                    Label("Add", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(trimmedHuggingFaceInput.isEmpty ? .secondary : Color.mayuOnAccent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(addButtonBackground)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(trimmedHuggingFaceInput.isEmpty)
                .animation(.easeInOut(duration: 0.15), value: trimmedHuggingFaceInput.isEmpty)
            }

            if let error = viewModel.addModelError {
                HStack(spacing: 7) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 12, weight: .semibold))
                    Text(error)
                        .font(.system(size: 12, weight: .regular))
                }
                .foregroundStyle(.secondary)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.mayuPanelBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.mayuBorder.opacity(0.55), lineWidth: 1)
                }
        }
    }

    private var providerFilterBar: some View {
        Picker("Engine", selection: $selectedProviderFilter) {
            ForEach(AIModelProviderFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 480)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.mayuAccentSoft)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.mayuStrongBorder.opacity(0.5), lineWidth: 1)
                    }

                Image(systemName: "cpu")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.mayuAccent)
            }
            .frame(width: 58, height: 58)
            .shadow(color: Color.mayuAccent.opacity(0.1), radius: 14)

            VStack(alignment: .leading, spacing: 5) {
                Text("AI Models")
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                    .tracking(-0.2)

                Text("Manage local MLX and llama.cpp models for coding assistance.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.bottom, 6)
    }

    private var trimmedHuggingFaceInput: String {
        huggingFaceInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var addButtonBackground: Color {
        trimmedHuggingFaceInput.isEmpty ? Color.secondary.opacity(0.12) : Color.mayuAccentSolid
    }

    private var filteredModels: [LLMModel] {
        let downloadableModels = viewModel.models.filter { $0.provider != .api }

        switch selectedProviderFilter {
        case .all:
            return downloadableModels
        case .provider(let provider):
            return downloadableModels.filter { $0.provider == provider }
        }
    }

    private func addCustomModel() {
        guard !trimmedHuggingFaceInput.isEmpty else {
            return
        }

        if viewModel.addModel(fromHuggingFaceInput: huggingFaceInput) {
            huggingFaceInput = ""
        }
    }
}

private enum AIModelProviderFilter: Hashable, Identifiable, CaseIterable {
    case all
    case provider(LLMModel.Provider)

    var id: String {
        title
    }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .provider(let provider):
            return provider.rawValue
        }
    }

    static let allCases: [AIModelProviderFilter] = [
        .all,
        .provider(.mlx),
        .provider(.llamaCpp)
    ]
}

private struct AIModelCard: View {
    let model: LLMModel
    let state: ModelDownloadState
    let isRemovable: Bool
    let downloadAction: () -> Void
    let loadAction: () -> Void
    let unloadAction: () -> Void
    let deleteAction: () -> Void
    let removeAction: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                ProviderIconBadge(provider: model.provider)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(model.displayName)
                            .font(.system(size: 17, weight: .semibold))
                            .tracking(-0.2)

                        if model.isRecommendedForCoding {
                            Text("Coding")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.mayuAccent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.mayuAccentSoft)
                                .clipShape(Capsule())
                        }
                    }

                    Text(model.repository)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 16)

                HStack(spacing: 8) {
                    Button(action: primaryModelAction) {
                        HStack(spacing: 7) {
                            if isBusy {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: buttonIcon)
                                    .font(.system(size: 12, weight: .semibold))
                            }

                            Text(primaryButtonTitle)
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(primaryButtonForeground)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(buttonBackground)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isPrimaryActionDisabled)

                    if state == .downloaded && model.supportsExplicitUnload && model.isLoaded {
                        Button(action: unloadAction) {
                            Image(systemName: "eject")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 32, height: 32)
                                .background(Color.secondary.opacity(0.10))
                                .clipShape(Circle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isBusy)
                        .help("Unload model")
                    }

                    if state == .downloaded && model.supportsDelete {
                        Button(role: .destructive, action: deleteAction) {
                            Image(systemName: "trash")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.mayuWarning)
                                .frame(width: 32, height: 32)
                                .background(Color.mayuWarning.opacity(0.10))
                                .clipShape(Circle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isBusy)
                        .help("Delete downloaded files")
                    }

                    if isRemovable && state != .downloaded {
                        Button(role: .destructive, action: removeAction) {
                            Label("Remove", systemImage: "trash")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.mayuWarning)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(Color.mayuWarning.opacity(0.10))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isBusy)
                    }
                }
            }
            .padding(18)

            // Info pills row
            HStack(spacing: 8) {
                ModelInfoPill(title: model.provider.rawValue, systemImage: "memorychip")
                ModelInfoPill(title: contextLengthTitle, systemImage: "text.alignleft")
                ModelInfoPill(title: localStatusTitle, systemImage: localStatusIcon)
                if model.supportsExplicitUnload {
                    ModelInfoPill(
                        title: model.isLoaded ? "Loaded" : "Unloaded",
                        systemImage: model.isLoaded ? "bolt.fill" : "bolt.slash"
                    )
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)

            if case .failed(let message) = state {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 12, weight: .semibold))
                    Text(message)
                        .font(.system(size: 12, weight: .regular))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .padding(.bottom, 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isHovered ? Color.mayuElevatedBackground : Color.mayuPanelBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            isHovered ? Color.mayuStrongBorder.opacity(0.7) : Color.mayuBorder.opacity(0.55),
                            lineWidth: 1
                        )
                }
        }
        .shadow(color: .black.opacity(isHovered ? 0.09 : 0.03), radius: isHovered ? 14 : 4, y: isHovered ? 6 : 2)
        .scaleEffect(isHovered ? 1.002 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
    }

    private var buttonIcon: String {
        switch state {
        case .notDownloaded:
            return "arrow.down.circle"
        case .downloading:
            return "arrow.down.circle"
        case .loading:
            return "bolt"
        case .unloading:
            return "eject"
        case .downloaded:
            return model.supportsExplicitUnload && !model.isLoaded ? "bolt" : "checkmark.circle"
        case .failed:
            return "arrow.clockwise"
        }
    }

    private var contextLengthTitle: String {
        guard model.contextLength > 0 else {
            return "Config context"
        }

        return "\(model.contextLength / 1_000)K context"
    }

    private var buttonBackground: Color {
        switch state {
        case .downloaded where model.supportsExplicitUnload && !model.isLoaded:
            return Color.mayuAccentSolid
        case .downloaded:
            return Color.secondary.opacity(0.12)
        case .failed:
            return Color.mayuWarning.opacity(0.14)
        default:
            return Color.mayuAccentSoft
        }
    }

    private var primaryButtonForeground: Color {
        if state == .downloaded && model.supportsExplicitUnload && !model.isLoaded {
            return Color.mayuOnAccent
        }

        return .primary
    }

    private var localStatusTitle: String {
        switch state {
        case .downloaded:
            return model.isDownloaded ? "On device" : "Available"
        case .downloading:
            return "Downloading"
        case .loading:
            return "Loading"
        case .unloading:
            return "Unloading"
        case .failed:
            return "Download failed"
        case .notDownloaded:
            return "Not downloaded"
        }
    }

    private var localStatusIcon: String {
        switch state {
        case .downloaded:
            return "checkmark.circle"
        case .downloading:
            return "arrow.down.circle"
        case .loading:
            return "bolt"
        case .unloading:
            return "eject"
        case .failed:
            return "exclamationmark.triangle"
        case .notDownloaded:
            return "icloud.and.arrow.down"
        }
    }

    private var isDownloading: Bool {
        if case .downloading = state {
            return true
        }

        return false
    }

    private var isBusy: Bool {
        switch state {
        case .downloading, .loading, .unloading:
            return true
        case .notDownloaded, .downloaded, .failed:
            return false
        }
    }

    private var isPrimaryActionDisabled: Bool {
        isBusy || (state == .downloaded && (!model.supportsExplicitUnload || model.isLoaded))
    }

    private var primaryButtonTitle: String {
        if state == .downloaded && model.supportsExplicitUnload && !model.isLoaded {
            return "Load"
        }

        return state.buttonTitle
    }

    private func primaryModelAction() {
        if state == .downloaded && model.supportsExplicitUnload && !model.isLoaded {
            loadAction()
        } else {
            downloadAction()
        }
    }
}

private extension LLMModel {
    var supportsExplicitUnload: Bool {
        provider == .llamaCpp
    }

    var supportsDelete: Bool {
        provider == .mlx
    }
}

private struct ModelInfoPill: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background {
                Capsule()
                    .fill(Color.mayuElevatedBackground)
                    .overlay {
                        Capsule()
                            .stroke(Color.mayuBorder.opacity(0.55), lineWidth: 1)
                    }
            }
    }
}

private struct ProviderIconBadge: View {
    let provider: LLMModel.Provider

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.mayuAccentSoft)
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(Color.mayuStrongBorder.opacity(0.5), lineWidth: 1)
                }

            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.mayuAccent)
        }
        .frame(width: 46, height: 46)
    }

    private var systemImage: String {
        switch provider {
        case .mlx: return "apple.logo"
        case .llamaCpp: return "memorychip"
        case .api: return "network"
        }
    }
}
