import Foundation

actor RemoteAPIEngine: LLMEngine {
    nonisolated let name = "API"

    private var generationTask: Task<Void, Never>?
    private var generationID: UUID?

    func availableModels() async throws -> [LLMModel] {
        APIProviderCatalog.allModels
    }

    func load(model: LLMModel) async throws {
        guard model.provider == .api else {
            throw LLMEngineError.unsupportedModel(model.displayName)
        }
        // Remote connections don't require an explicit load step.
    }

    func unload(model: LLMModel) async throws {
        // No persistent local state to release.
    }

    func streamChat(
        messages: [LLMMessage],
        model: LLMModel,
        options: LLMGenerationOptions
    ) async -> AsyncThrowingStream<LLMStreamEvent, Error> {
        generationTask?.cancel()

        let generationID = UUID()
        let stream = AsyncThrowingStream<LLMStreamEvent, Error>.makeStream(of: LLMStreamEvent.self)
        let task = Task {
            await runGeneration(
                messages: messages,
                model: model,
                options: options,
                continuation: stream.continuation
            )
            clearGenerationTask(id: generationID)
        }

        self.generationID = generationID
        generationTask = task
        stream.continuation.onTermination = { @Sendable _ in
            task.cancel()
        }

        return stream.stream
    }

    func cancel() async {
        generationTask?.cancel()
        generationTask = nil
        generationID = nil
    }

    private func clearGenerationTask(id: UUID) {
        guard generationID == id else {
            return
        }

        generationTask = nil
        generationID = nil
    }

    private func runGeneration(
        messages: [LLMMessage],
        model: LLMModel,
        options: LLMGenerationOptions,
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation
    ) async {
        do {
            guard let configID = model.apiProviderConfigID,
                  let config = APIProviderCatalog.config(withID: configID) else {
                throw LLMEngineError.providerUnavailable(model.displayName)
            }

            guard let apiKey = APIProviderCatalog.apiKey(for: config),
                  !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LLMEngineError.dependencyMissing("API key for \(config.name)")
            }

            switch config.format {
            case .openAICompatible:
                try await streamOpenAICompatible(
                    config: config,
                    apiKey: apiKey,
                    messages: messages,
                    options: options,
                    continuation: continuation
                )
            case .anthropicCompatible:
                try await streamAnthropicCompatible(
                    config: config,
                    apiKey: apiKey,
                    messages: messages,
                    options: options,
                    continuation: continuation
                )
            }

            continuation.yield(.completed)
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    private func streamOpenAICompatible(
        config: APIProviderConfig,
        apiKey: String,
        messages: [LLMMessage],
        options: LLMGenerationOptions,
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation
    ) async throws {
        guard let url = URL(string: "\(config.normalizedBaseURL)/chat/completions") else {
            throw LLMEngineError.invalidEndpoint(config.baseURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        // Optional OpenRouter-specific headers (appear on leaderboards)
        if config.isOpenRouter {
            request.setValue("https://mayu.app", forHTTPHeaderField: "HTTP-Referer")
            request.setValue("Mayu Echo", forHTTPHeaderField: "X-Title")
        }

        let payload: [String: Any] = [
            "model": config.modelID,
            "stream": true,
            "temperature": options.temperature,
            "top_p": options.topP,
            "max_tokens": options.maxTokens,
            "messages": messages.map { message in
                ["role": openAIRole(for: message.role), "content": message.content]
            }
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        try await validate(response: response, bytes: bytes)

        for try await line in bytes.lines {
            guard !Task.isCancelled else {
                return
            }

            guard line.hasPrefix("data:") else {
                continue
            }

            let payloadText = line.dropFirst(5).trimmingCharacters(in: .whitespaces)

            guard payloadText != "[DONE]" else {
                break
            }

            guard let data = payloadText.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let delta = first["delta"] as? [String: Any],
                  let content = delta["content"] as? String,
                  !content.isEmpty else {
                continue
            }

            continuation.yield(.token(content))
        }
    }

    private func streamAnthropicCompatible(
        config: APIProviderConfig,
        apiKey: String,
        messages: [LLMMessage],
        options: LLMGenerationOptions,
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation
    ) async throws {
        guard let url = URL(string: "\(config.normalizedBaseURL)/messages") else {
            throw LLMEngineError.invalidEndpoint(config.baseURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let systemText = messages.first { $0.role == .system }?.content
        let conversationMessages = anthropicMessages(from: messages.filter { $0.role != .system })

        var payload: [String: Any] = [
            "model": config.modelID,
            "stream": true,
            "max_tokens": options.maxTokens,
            "temperature": options.temperature,
            "top_p": options.topP,
            "messages": conversationMessages
        ]

        if let systemText, !systemText.isEmpty {
            payload["system"] = systemText
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        try await validate(response: response, bytes: bytes)

        for try await line in bytes.lines {
            guard !Task.isCancelled else {
                return
            }

            guard line.hasPrefix("data:") else {
                continue
            }

            let payloadText = line.dropFirst(5).trimmingCharacters(in: .whitespaces)

            guard let data = payloadText.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else {
                continue
            }

            if type == "content_block_delta",
               let delta = json["delta"] as? [String: Any],
               let text = delta["text"] as? String {
                continuation.yield(.token(text))
            }

            if type == "message_stop" {
                break
            }
        }
    }

    /// Anthropic's Messages API requires strict user/assistant alternation starting with "user".
    private func anthropicMessages(from messages: [LLMMessage]) -> [[String: String]] {
        var result: [[String: String]] = []

        for message in messages {
            let role = anthropicRole(for: message.role)

            if let lastIndex = result.indices.last, result[lastIndex]["role"] == role {
                result[lastIndex]["content"] = (result[lastIndex]["content"] ?? "") + "\n\n" + message.content
            } else {
                result.append(["role": role, "content": message.content])
            }
        }

        if let first = result.first, first["role"] != "user" {
            result.insert(["role": "user", "content": "(continued)"], at: 0)
        }

        return result
    }

    private func validate(response: URLResponse, bytes: URLSession.AsyncBytes) async throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            return
        }

        guard !(200..<300).contains(httpResponse.statusCode) else {
            return
        }

        var bodyText = ""

        for try await line in bytes.lines {
            bodyText += line
            if bodyText.count > 2_000 {
                break
            }
        }

        let detail = bodyText.isEmpty ? "HTTP \(httpResponse.statusCode)" : bodyText.prefix(500)
        throw LLMEngineError.providerUnavailable(String(detail))
    }

    private func openAIRole(for role: LLMMessage.Role) -> String {
        switch role {
        case .system: return "system"
        case .user: return "user"
        case .assistant: return "assistant"
        case .tool: return "user"
        }
    }

    private func anthropicRole(for role: LLMMessage.Role) -> String {
        switch role {
        case .user, .tool, .system: return "user"
        case .assistant: return "assistant"
        }
    }
}
