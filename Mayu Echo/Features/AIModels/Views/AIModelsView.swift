import SwiftUI

struct AIModelsView: View {
    @StateObject private var viewModel = AIModelsViewModel()
    @State private var huggingFaceInput = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                addModelPanel

                VStack(alignment: .leading, spacing: 12) {
                    Text("Available Models")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.secondary)

                    ForEach(viewModel.models) { model in
                        AIModelCard(
                            model: model,
                            state: viewModel.state(for: model),
                            isRemovable: viewModel.isCustomModel(model),
                            downloadAction: {
                                viewModel.download(model)
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
            .frame(maxWidth: 920, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.mayuChatBackground)
    }

    private var addModelPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color.secondary.opacity(0.10))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("Add Hugging Face Model")
                        .font(.system(size: 16, weight: .semibold))

                    Text("Paste a model URL or repo id. Mayu Echo will create a downloadable MLX model card.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                TextField("https://huggingface.co/mlx-community/Qwen2.5-Coder-7B-Instruct-4bit", text: $huggingFaceInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .background(Color.mayuComposerBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.mayuBorder, lineWidth: 1)
                    }
                    .onSubmit(addCustomModel)

                Button(action: addCustomModel) {
                    Label("Add", systemImage: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 10)
                        .background(addButtonBackground)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(trimmedHuggingFaceInput.isEmpty)
            }

            if let error = viewModel.addModelError {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mayuPanelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.mayuBorder, lineWidth: 1)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "cpu")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 54, height: 54)
                .background(Color.mayuSelection)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text("AI Models")
                    .font(.system(size: 30, weight: .semibold))

                Text("Download local MLX models for native coding assistance.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 4)
    }

    private var trimmedHuggingFaceInput: String {
        huggingFaceInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var addButtonBackground: Color {
        trimmedHuggingFaceInput.isEmpty ? Color.secondary.opacity(0.12) : Color.mayuSelection
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

private struct AIModelCard: View {
    let model: LLMModel
    let state: ModelDownloadState
    let isRemovable: Bool
    let downloadAction: () -> Void
    let deleteAction: () -> Void
    let removeAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(model.displayName)
                            .font(.system(size: 19, weight: .semibold))

                        if model.isRecommendedForCoding {
                            Text("Coding")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.mayuSelection)
                                .clipShape(Capsule())
                        }
                    }

                    Text(model.repository)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 16)

                HStack(spacing: 8) {
                    Button(action: downloadAction) {
                        HStack(spacing: 7) {
                            if case .downloading = state {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: buttonIcon)
                                    .font(.system(size: 13, weight: .medium))
                            }

                            Text(state.buttonTitle)
                        }
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(buttonBackground)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(state == .downloaded || isDownloading)

                    if state == .downloaded && !isRemovable {
                        Button(role: .destructive, action: deleteAction) {
                            Image(systemName: "trash")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.red)
                                .frame(width: 34, height: 34)
                                .background(Color.red.opacity(0.12))
                                .clipShape(Circle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Delete downloaded model")
                    }

                    if isRemovable {
                        Button(role: .destructive, action: removeAction) {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.red)
                                .frame(width: 34, height: 34)
                                .background(Color.red.opacity(0.12))
                                .clipShape(Circle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isDownloading)
                        .help("Remove custom model and downloaded files")
                    }
                }
            }

            HStack(spacing: 10) {
                ModelInfoPill(title: model.provider.rawValue, systemImage: "memorychip")
                ModelInfoPill(title: contextLengthTitle, systemImage: "text.alignleft")
                ModelInfoPill(title: localStatusTitle, systemImage: localStatusIcon)
            }

            if case .failed(let message) = state {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mayuPanelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.mayuBorder, lineWidth: 1)
        }
    }

    private var buttonIcon: String {
        switch state {
        case .notDownloaded:
            return "arrow.down.circle"
        case .downloading:
            return "arrow.down.circle"
        case .downloaded:
            return "checkmark.circle"
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
        case .downloaded:
            return Color.secondary.opacity(0.12)
        case .failed:
            return Color.red.opacity(0.14)
        default:
            return Color.mayuSelection
        }
    }

    private var localStatusTitle: String {
        switch state {
        case .downloaded:
            return "On device"
        case .downloading:
            return "Downloading"
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
}

private struct ModelInfoPill: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.10))
            .clipShape(Capsule())
    }
}
