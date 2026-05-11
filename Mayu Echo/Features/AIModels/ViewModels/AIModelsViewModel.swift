import Foundation
import Combine

@MainActor
final class AIModelsViewModel: ObservableObject {
    @Published private(set) var models: [LLMModel]
    @Published private(set) var downloadStates: [LLMModel.ID: ModelDownloadState] = [:]
    @Published private(set) var addModelError: String?

    private let downloader: HuggingFaceModelDownloader

    init(models: [LLMModel]? = nil, downloader: HuggingFaceModelDownloader? = nil) {
        let resolvedDownloader = downloader ?? HuggingFaceModelDownloader()
        self.downloader = resolvedDownloader
        self.models = (models ?? LLMModelCatalog.allModels).map { resolvedDownloader.modelWithLocalStatus($0) }
    }

    func state(for model: LLMModel) -> ModelDownloadState {
        downloadStates[model.id] ?? (model.isDownloaded ? .downloaded : .notDownloaded)
    }

    func download(_ model: LLMModel) {
        guard case .downloading = state(for: model) else {
            startDownload(model)
            return
        }
    }

    func deleteDownloadedModel(_ model: LLMModel) {
        guard state(for: model) == .downloaded else {
            return
        }

        do {
            try downloader.deleteDownloadedModel(model)
            markDeleted(modelID: model.id)
        } catch {
            downloadStates[model.id] = .failed(error.localizedDescription)
        }
    }

    func removeCustomModel(_ model: LLMModel) {
        guard isCustomModel(model), !isDownloading(model) else {
            return
        }

        do {
            try downloader.deleteDownloadedModel(model)
            models.removeAll { $0.id == model.id }
            downloadStates[model.id] = nil
            persistCustomModels()
            addModelError = nil
        } catch {
            downloadStates[model.id] = .failed(error.localizedDescription)
        }
    }

    func isCustomModel(_ model: LLMModel) -> Bool {
        !LLMModel.defaultMLXModels.contains { $0.id == model.id }
    }

    @discardableResult
    func addModel(fromHuggingFaceInput input: String) -> Bool {
        do {
            let repository = try LLMModelCatalog.repository(fromHuggingFaceInput: input)
            let model = LLMModel.customHuggingFaceModel(repository: repository)

            guard !models.contains(where: { $0.repository.caseInsensitiveCompare(model.repository) == .orderedSame }) else {
                addModelError = "This model is already in the list."
                return false
            }

            models.append(downloader.modelWithLocalStatus(model))
            persistCustomModels()
            addModelError = nil
            return true
        } catch {
            addModelError = error.localizedDescription
            return false
        }
    }

    private func startDownload(_ model: LLMModel) {
        downloadStates[model.id] = .downloading(progress: 0)

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let localURL = try await downloader.download(model: model) { progress in
                    self.downloadStates[model.id] = .downloading(progress: progress)
                }
                markDownloaded(
                    modelID: model.id,
                    resolvedModel: downloader.modelWithLocalStatus(model),
                    fallbackLocalPath: localURL.path
                )
                downloadStates[model.id] = .downloaded
            } catch is CancellationError {
                downloadStates[model.id] = .notDownloaded
            } catch {
                downloadStates[model.id] = .failed(error.localizedDescription)
            }
        }
    }

    private func markDownloaded(
        modelID: LLMModel.ID,
        resolvedModel: LLMModel,
        fallbackLocalPath: String
    ) {
        guard let index = models.firstIndex(where: { $0.id == modelID }) else {
            return
        }

        models[index] = resolvedModel
        models[index].localPath = resolvedModel.localPath ?? fallbackLocalPath
        models[index].isDownloaded = true
    }

    private func markDeleted(modelID: LLMModel.ID) {
        guard let index = models.firstIndex(where: { $0.id == modelID }) else {
            return
        }

        models[index].localPath = nil
        models[index].isDownloaded = false
        downloadStates[modelID] = .notDownloaded
        persistCustomModels()
    }

    private func persistCustomModels() {
        let defaultIDs = Set(LLMModel.defaultMLXModels.map(\.id))
        let customModels = models
            .filter { !defaultIDs.contains($0.id) }
            .map { model in
                var storedModel = model
                storedModel.localPath = nil
                storedModel.isDownloaded = false
                return storedModel
            }

        LLMModelCatalog.saveCustomModels(customModels)
    }

    private func isDownloading(_ model: LLMModel) -> Bool {
        if case .downloading = state(for: model) {
            return true
        }

        return false
    }
}

enum ModelDownloadState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
    case failed(String)

    var buttonTitle: String {
        switch self {
        case .notDownloaded:
            return "Download"
        case .downloading(let progress):
            return "\(Int(progress * 100))%"
        case .downloaded:
            return "Downloaded"
        case .failed:
            return "Retry"
        }
    }
}
