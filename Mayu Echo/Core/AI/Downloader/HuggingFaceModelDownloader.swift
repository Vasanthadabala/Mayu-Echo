import Foundation

nonisolated final class HuggingFaceModelDownloader {
    private let baseURL = URL(string: "https://huggingface.co")!
    private let apiBaseURL = URL(string: "https://huggingface.co/api/models")!
    private let fileManager: FileManager
    private let revision: String

    init(fileManager: FileManager = .default, revision: String = "main") {
        self.fileManager = fileManager
        self.revision = revision
    }

    func modelWithLocalStatus(_ model: LLMModel) -> LLMModel {
        var resolvedModel = model
        let directory = localDirectory(for: model)
        let isDownloaded = fileManager.fileExists(atPath: completionMarkerURL(for: model).path)

        resolvedModel.localPath = isDownloaded ? directory.path : nil
        resolvedModel.isDownloaded = isDownloaded
        resolvedModel.contextLength = contextLength(in: directory) ?? model.contextLength
        return resolvedModel
    }

    func download(
        model: LLMModel,
        progress: @MainActor @escaping (Double) -> Void
    ) async throws -> URL {
        let directory = localDirectory(for: model)

        if fileManager.fileExists(atPath: completionMarkerURL(for: model).path) {
            await progress(1)
            return directory
        }

        let info = try await fetchModelInfo(repository: model.repository)
        let files = info.downloadableFiles

        guard !files.isEmpty else {
            throw HuggingFaceDownloadError.emptyRepository(model.repository)
        }

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        await progress(0.02)

        let totalDownloadSize = files.reduce(Int64(0)) { partialResult, file in
            partialResult + file.progressSize
        }
        var completedDownloadSize: Int64 = 0

        for file in files {
            try Task.checkCancellation()

            let filename = file.filename
            let destinationURL = localFileURL(for: filename, in: directory)
            if fileManager.fileExists(atPath: destinationURL.path) {
                completedDownloadSize += file.progressSize
                await progress(progressValue(completedBytes: completedDownloadSize, totalBytes: totalDownloadSize))
                continue
            }

            let sourceURL = resolveURL(repository: model.repository, filename: filename)
            let completedSizeBeforeFile = completedDownloadSize
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let partialURL = partialFileURL(for: destinationURL)
            if try finalizeCompletedPartialFile(
                destinationURL: destinationURL,
                partialURL: partialURL,
                expectedSize: file.size
            ) {
                completedDownloadSize += file.progressSize
                await progress(progressValue(completedBytes: completedDownloadSize, totalBytes: totalDownloadSize))
                continue
            }

            let response = try await downloadFile(
                from: sourceURL,
                destinationURL: destinationURL,
                partialURL: partialURL,
                expectedSize: file.size
            ) { downloadedBytes in
                Task { @MainActor in
                    await progress(
                        self.progressValue(
                            completedBytes: completedSizeBeforeFile + min(downloadedBytes, file.progressSize),
                            totalBytes: totalDownloadSize
                        )
                    )
                }
            }
            try validate(response: response, filename: filename)
            completedDownloadSize += file.progressSize
            await progress(progressValue(completedBytes: completedDownloadSize, totalBytes: totalDownloadSize))
        }

        try writeManifest(info: info, model: model, files: files.map(\.filename), directory: directory)
        await progress(1)
        return directory
    }

    func deleteDownloadedModel(_ model: LLMModel) throws {
        let directory = localDirectory(for: model)

        guard fileManager.fileExists(atPath: directory.path) else {
            return
        }

        try fileManager.removeItem(at: directory)
    }

    private func fetchModelInfo(repository: String) async throws -> HuggingFaceModelInfo {
        let url = modelAPIURL(repository: repository)
        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(response: response, filename: repository)

        do {
            return try JSONDecoder().decode(HuggingFaceModelInfo.self, from: data)
        } catch {
            throw HuggingFaceDownloadError.invalidModelInfo(repository)
        }
    }

    private func writeManifest(
        info: HuggingFaceModelInfo,
        model: LLMModel,
        files: [String],
        directory: URL
    ) throws {
        let manifest = HuggingFaceModelManifest(
            repository: model.repository,
            revision: revision,
            sha: info.sha,
            downloadedAt: Date(),
            files: files
        )
        let data = try JSONEncoder.prettyPrinted.encode(manifest)
        try data.write(to: manifestURL(for: model), options: .atomic)
        try Data().write(to: completionMarkerURL(for: model), options: .atomic)
    }

    private func validate(response: URLResponse, filename: String) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            return
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw HuggingFaceDownloadError.badResponse(filename, httpResponse.statusCode)
        }
    }

    private func downloadFile(
        from sourceURL: URL,
        destinationURL: URL,
        partialURL: URL,
        expectedSize: Int64?,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws -> URLResponse {
        let resumeOffset = try resumablePartialSize(at: partialURL, expectedSize: expectedSize)
        var request = URLRequest(url: sourceURL)

        if resumeOffset > 0 {
            request.setValue("bytes=\(resumeOffset)-", forHTTPHeaderField: "Range")
        }

        let delegate = HuggingFaceResumableDownloadDelegate(
            partialURL: partialURL,
            destinationURL: destinationURL,
            fileManager: fileManager,
            resumeOffset: resumeOffset,
            expectedSize: expectedSize,
            progress: progress
        )
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1

        let session = URLSession(
            configuration: .default,
            delegate: delegate,
            delegateQueue: delegateQueue
        )

        defer {
            session.finishTasksAndInvalidate()
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.start(continuation: continuation)
                let task = session.dataTask(with: request)
                delegate.setTask(task)
                task.resume()
            }
        } onCancel: {
            delegate.cancel()
        }
    }

    private func finalizeCompletedPartialFile(
        destinationURL: URL,
        partialURL: URL,
        expectedSize: Int64?
    ) throws -> Bool {
        guard let expectedSize,
              fileManager.fileExists(atPath: partialURL.path) else {
            return false
        }

        let partialSize = try fileSize(at: partialURL)

        guard partialSize >= expectedSize else {
            return false
        }

        if partialSize > expectedSize {
            try fileManager.removeItem(at: partialURL)
            return false
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.moveItem(at: partialURL, to: destinationURL)
        return true
    }

    private func resumablePartialSize(at partialURL: URL, expectedSize: Int64?) throws -> Int64 {
        guard fileManager.fileExists(atPath: partialURL.path) else {
            return 0
        }

        let partialSize = try fileSize(at: partialURL)

        if let expectedSize, partialSize > expectedSize {
            try fileManager.removeItem(at: partialURL)
            return 0
        }

        return max(partialSize, 0)
    }

    private func fileSize(at url: URL) throws -> Int64 {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func progressValue(completedBytes: Int64, totalBytes: Int64) -> Double {
        guard totalBytes > 0 else {
            return 1
        }

        return min(max(Double(completedBytes) / Double(totalBytes), 0), 1)
    }

    private func modelAPIURL(repository: String) -> URL {
        let url = apiBaseURL.appending(pathComponents: repositoryPathComponents(repository))
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "blobs", value: "true")
        ]

        return components?.url ?? url
    }

    private func resolveURL(repository: String, filename: String) -> URL {
        baseURL.appending(pathComponents: repositoryPathComponents(repository) + ["resolve", revision] + filePathComponents(filename))
    }

    private func localDirectory(for model: LLMModel) -> URL {
        modelsDirectory
            .appendingPathComponent(model.repository.replacingOccurrences(of: "/", with: "--"), isDirectory: true)
    }

    private var modelsDirectory: URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return applicationSupport
            .appendingPathComponent("Mayu Echo", isDirectory: true)
            .appendingPathComponent("AI Models", isDirectory: true)
    }

    private func manifestURL(for model: LLMModel) -> URL {
        localDirectory(for: model).appendingPathComponent("mayu-model-manifest.json")
    }

    private func completionMarkerURL(for model: LLMModel) -> URL {
        localDirectory(for: model).appendingPathComponent(".download-complete")
    }

    private func partialFileURL(for destinationURL: URL) -> URL {
        destinationURL.appendingPathExtension("download")
    }

    private func localFileURL(for filename: String, in directory: URL) -> URL {
        filePathComponents(filename).reduce(directory) { partialURL, component in
            partialURL.appendingPathComponent(component)
        }
    }

    private func contextLength(in directory: URL) -> Int? {
        let configURL = directory.appendingPathComponent("config.json")

        guard fileManager.fileExists(atPath: configURL.path),
              let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(HuggingFaceModelConfig.self, from: data) else {
            return nil
        }

        return config.contextLength
    }

    private func repositoryPathComponents(_ repository: String) -> [String] {
        repository
            .split(separator: "/")
            .map(String.init)
    }

    private func filePathComponents(_ filename: String) -> [String] {
        filename
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}

private nonisolated struct HuggingFaceModelInfo: Decodable {
    let id: String
    let sha: String?
    let siblings: [Sibling]

    var downloadableFiles: [DownloadFile] {
        siblings
            .filter { !$0.rfilename.hasSuffix("/") }
            .map { sibling in
                DownloadFile(
                    filename: sibling.rfilename,
                    size: sibling.downloadSize
                )
            }
    }

    nonisolated struct Sibling: Decodable {
        let rfilename: String
        let size: Int64?
        let lfs: LFS?

        var downloadSize: Int64? {
            lfs?.size ?? size
        }
    }

    nonisolated struct LFS: Decodable {
        let size: Int64?
    }
}

private nonisolated struct DownloadFile {
    let filename: String
    let size: Int64?

    var progressSize: Int64 {
        max(size ?? 1, 1)
    }
}

private nonisolated struct HuggingFaceModelManifest: Encodable {
    let repository: String
    let revision: String
    let sha: String?
    let downloadedAt: Date
    let files: [String]
}

private nonisolated struct HuggingFaceModelConfig: Decodable {
    let maxPositionEmbeddings: Int?
    let modelMaxLength: Int?
    let maxSequenceLength: Int?
    let slidingWindow: Int?
    let useSlidingWindow: Bool?

    var contextLength: Int? {
        if let modelMaxLength, modelMaxLength > 0 {
            return modelMaxLength
        }

        if let maxSequenceLength, maxSequenceLength > 0 {
            return maxSequenceLength
        }

        if useSlidingWindow == true, let slidingWindow, slidingWindow > 0 {
            return slidingWindow
        }

        return maxPositionEmbeddings
    }

    enum CodingKeys: String, CodingKey {
        case maxPositionEmbeddings = "max_position_embeddings"
        case modelMaxLength = "model_max_length"
        case maxSequenceLength = "max_sequence_length"
        case slidingWindow = "sliding_window"
        case useSlidingWindow = "use_sliding_window"
    }
}

private nonisolated enum HuggingFaceDownloadError: LocalizedError {
    case badResponse(String, Int)
    case emptyRepository(String)
    case invalidModelInfo(String)
    case incompleteFile(String)
    case missingDownloadedFile

    var errorDescription: String? {
        switch self {
        case .badResponse(let filename, let statusCode):
            return "Hugging Face returned \(statusCode) for \(filename)."
        case .emptyRepository(let repository):
            return "No downloadable files were found for \(repository)."
        case .invalidModelInfo(let repository):
            return "Could not read model info for \(repository)."
        case .incompleteFile(let filename):
            return "\(filename) did not finish downloading."
        case .missingDownloadedFile:
            return "The downloaded file could not be prepared."
        }
    }
}

private final class HuggingFaceResumableDownloadDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let partialURL: URL
    private let destinationURL: URL
    private let fileManager: FileManager
    private let resumeOffset: Int64
    private let expectedSize: Int64?
    private let progress: @Sendable (Int64) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URLResponse, Error>?
    private var task: URLSessionDataTask?
    private var response: URLResponse?
    private var fileHandle: FileHandle?
    private var baseBytesWritten: Int64 = 0
    private var bytesWrittenInRequest: Int64 = 0
    private var deferredError: Error?

    init(
        partialURL: URL,
        destinationURL: URL,
        fileManager: FileManager,
        resumeOffset: Int64,
        expectedSize: Int64?,
        progress: @escaping @Sendable (Int64) -> Void
    ) {
        self.partialURL = partialURL
        self.destinationURL = destinationURL
        self.fileManager = fileManager
        self.resumeOffset = resumeOffset
        self.expectedSize = expectedSize
        self.progress = progress
    }

    func start(continuation: CheckedContinuation<URLResponse, Error>) {
        lock.withLock {
            self.continuation = continuation
        }
    }

    func setTask(_ task: URLSessionDataTask) {
        lock.withLock {
            self.task = task
        }
    }

    func cancel() {
        let currentTask = lock.withLock {
            task
        }

        currentTask?.cancel()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        do {
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            if let statusCode, !(200..<300).contains(statusCode) {
                lock.withLock {
                    deferredError = HuggingFaceDownloadError.badResponse(partialURL.lastPathComponent, statusCode)
                }
                completionHandler(.cancel)
                return
            }

            let shouldRestart = resumeOffset > 0 && statusCode == 200
            let baseBytes = shouldRestart ? 0 : resumeOffset

            if shouldRestart, fileManager.fileExists(atPath: partialURL.path) {
                try fileManager.removeItem(at: partialURL)
            }

            if !fileManager.fileExists(atPath: partialURL.path) {
                fileManager.createFile(atPath: partialURL.path, contents: nil)
            }

            let handle = try FileHandle(forWritingTo: partialURL)
            try handle.seekToEnd()

            lock.withLock {
                self.response = response
                self.fileHandle = handle
                self.baseBytesWritten = baseBytes
                self.bytesWrittenInRequest = 0
            }

            progress(baseBytes)
            completionHandler(.allow)
        } catch {
            lock.withLock {
                deferredError = error
            }
            completionHandler(.cancel)
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        var shouldCancel = false
        let update = lock.withLock {
            do {
                try fileHandle?.write(contentsOf: data)
                bytesWrittenInRequest += Int64(data.count)
                return baseBytesWritten + bytesWrittenInRequest
            } catch {
                deferredError = error
                shouldCancel = true
                return baseBytesWritten + bytesWrittenInRequest
            }
        }

        if shouldCancel {
            dataTask.cancel()
        }

        progress(update)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        closeFileHandle()

        if let error = lock.withLock({ deferredError }) {
            complete(.failure(error))
            return
        }

        if let error {
            complete(.failure(error))
            return
        }

        guard let response = lock.withLock({ response ?? task.response }) else {
            complete(.failure(HuggingFaceDownloadError.missingDownloadedFile))
            return
        }

        do {
            try validateAndMovePartialFile()
            complete(.success(response))
        } catch {
            complete(.failure(error))
        }
    }

    private func validateAndMovePartialFile() throws {
        if let expectedSize {
            let attributes = try fileManager.attributesOfItem(atPath: partialURL.path)
            let partialSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0

            guard partialSize >= expectedSize else {
                throw HuggingFaceDownloadError.incompleteFile(partialURL.lastPathComponent)
            }
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.moveItem(at: partialURL, to: destinationURL)
    }

    private func closeFileHandle() {
        let handle = lock.withLock {
            let handle = fileHandle
            fileHandle = nil
            return handle
        }

        do {
            try handle?.close()
        } catch {
            lock.withLock {
                deferredError = deferredError ?? error
            }
        }
    }

    private func complete(_ result: Result<URLResponse, Error>) {
        let continuation = lock.withLock {
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }

        guard let continuation else {
            return
        }

        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

private nonisolated extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private nonisolated extension URL {
    func appending(pathComponents components: [String]) -> URL {
        components.reduce(self) { partialURL, component in
            partialURL.appendingPathComponent(component)
        }
    }
}
