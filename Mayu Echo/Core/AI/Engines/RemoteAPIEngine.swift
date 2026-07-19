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
        options: LLMGenerationOptions,
        toolsEnabled: Bool
    ) async -> AsyncThrowingStream<LLMStreamEvent, Error> {
        generationTask?.cancel()

        let generationID = UUID()
        let stream = AsyncThrowingStream<LLMStreamEvent, Error>.makeStream(of: LLMStreamEvent.self)
        let task = Task {
            await runGeneration(
                messages: messages,
                model: model,
                options: options,
                toolsEnabled: toolsEnabled,
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
        toolsEnabled: Bool,
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
                    toolsEnabled: toolsEnabled,
                    continuation: continuation
                )
            case .anthropicCompatible:
                try await streamAnthropicCompatible(
                    config: config,
                    apiKey: apiKey,
                    messages: messages,
                    options: options,
                    toolsEnabled: toolsEnabled,
                    continuation: continuation
                )
            }

            continuation.yield(.completed)
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    // MARK: - OpenAI-compatible

    private func streamOpenAICompatible(
        config: APIProviderConfig,
        apiKey: String,
        messages: [LLMMessage],
        options: LLMGenerationOptions,
        toolsEnabled: Bool,
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

        var payload: [String: Any] = [
            "model": config.modelID,
            "stream": true,
            "temperature": options.temperature,
            "top_p": options.topP,
            "max_tokens": options.maxTokens,
            "messages": messages.map(openAIMessageJSON)
        ]

        if toolsEnabled {
            payload["tools"] = ProjectAgentTools.toolSchemas
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        try await validate(response: response, bytes: bytes)

        var pendingToolCalls: [Int: PendingToolCall] = [:]

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
                  let delta = first["delta"] as? [String: Any] else {
                continue
            }

            if let content = delta["content"] as? String, !content.isEmpty {
                continuation.yield(.token(content))
            }

            if let toolCallDeltas = delta["tool_calls"] as? [[String: Any]] {
                for toolCallDelta in toolCallDeltas {
                    guard let index = toolCallDelta["index"] as? Int else {
                        continue
                    }

                    var pending = pendingToolCalls[index] ?? PendingToolCall()

                    if let id = toolCallDelta["id"] as? String {
                        pending.id = id
                    }

                    if let function = toolCallDelta["function"] as? [String: Any] {
                        if let name = function["name"] as? String {
                            pending.name = (pending.name ?? "") + name
                        }

                        if let argumentsFragment = function["arguments"] as? String {
                            pending.arguments += argumentsFragment
                        }
                    }

                    pendingToolCalls[index] = pending

                    if let name = pending.name {
                        continuation.yield(.toolCallProgress(index: index, name: name, argumentsJSON: pending.arguments))
                    }
                }
            }
        }

        finalizeOpenAIToolCalls(pendingToolCalls, continuation: continuation)
    }

    private func finalizeOpenAIToolCalls(
        _ pendingToolCalls: [Int: PendingToolCall],
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation
    ) {
        guard !pendingToolCalls.isEmpty else {
            return
        }

        let toolCalls = pendingToolCalls
            .sorted { $0.key < $1.key }
            .compactMap { _, pending -> ToolCallRequest? in
                guard let id = pending.id, let name = pending.name else {
                    return nil
                }

                return ToolCallRequest(id: id, name: name, argumentsJSON: pending.arguments)
            }

        if !toolCalls.isEmpty {
            continuation.yield(.toolCalls(toolCalls))
        }
    }

    // MARK: - Anthropic-compatible

    private func streamAnthropicCompatible(
        config: APIProviderConfig,
        apiKey: String,
        messages: [LLMMessage],
        options: LLMGenerationOptions,
        toolsEnabled: Bool,
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
        let conversationMessages = anthropicMessageBlocks(from: messages.filter { $0.role != .system })

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

        if toolsEnabled {
            payload["tools"] = ProjectAgentTools.anthropicToolSchemas
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        try await validate(response: response, bytes: bytes)

        var blocks: [Int: AnthropicBlock] = [:]

        func finalizeToolCalls() {
            let toolCalls = blocks
                .sorted { $0.key < $1.key }
                .compactMap { _, block -> ToolCallRequest? in
                    guard block.type == "tool_use", let id = block.id, let name = block.name else {
                        return nil
                    }

                    return ToolCallRequest(id: id, name: name, argumentsJSON: block.accumulated)
                }

            if !toolCalls.isEmpty {
                continuation.yield(.toolCalls(toolCalls))
            }
        }

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

            switch type {
            case "content_block_start":
                guard let index = json["index"] as? Int,
                      let contentBlock = json["content_block"] as? [String: Any],
                      let blockType = contentBlock["type"] as? String else {
                    continue
                }

                var block = AnthropicBlock(type: blockType)

                if blockType == "tool_use" {
                    block.id = contentBlock["id"] as? String
                    block.name = contentBlock["name"] as? String
                }

                blocks[index] = block

            case "content_block_delta":
                guard let index = json["index"] as? Int, let delta = json["delta"] as? [String: Any] else {
                    continue
                }

                if let text = delta["text"] as? String {
                    blocks[index]?.accumulated += text
                    continuation.yield(.token(text))
                } else if let partialJSON = delta["partial_json"] as? String {
                    blocks[index]?.accumulated += partialJSON

                    if let name = blocks[index]?.name {
                        continuation.yield(.toolCallProgress(index: index, name: name, argumentsJSON: blocks[index]?.accumulated ?? ""))
                    }
                }

            case "message_stop":
                finalizeToolCalls()
                return

            default:
                continue
            }
        }

        finalizeToolCalls()
    }

    /// Anthropic's Messages API requires strict user/assistant alternation starting with
    /// "user", and structured content blocks (not plain strings) once tool use is involved.
    private func anthropicMessageBlocks(from messages: [LLMMessage]) -> [[String: Any]] {
        var result: [[String: Any]] = []

        func append(role: String, block: [String: Any]) {
            if let lastIndex = result.indices.last, result[lastIndex]["role"] as? String == role {
                var content = result[lastIndex]["content"] as? [[String: Any]] ?? []
                content.append(block)
                result[lastIndex]["content"] = content
            } else {
                result.append(["role": role, "content": [block]])
            }
        }

        for message in messages {
            switch message.role {
            case .system:
                continue

            case .user:
                append(role: "user", block: ["type": "text", "text": message.content])

            case .assistant:
                var addedAny = false

                if !message.content.isEmpty {
                    append(role: "assistant", block: ["type": "text", "text": message.content])
                    addedAny = true
                }

                for call in message.toolCalls ?? [] {
                    let input = (try? JSONSerialization.jsonObject(
                        with: Data(call.argumentsJSON.utf8)
                    )) as? [String: Any] ?? [:]

                    append(role: "assistant", block: [
                        "type": "tool_use",
                        "id": call.id,
                        "name": call.name,
                        "input": input
                    ])
                    addedAny = true
                }

                if !addedAny {
                    append(role: "assistant", block: ["type": "text", "text": " "])
                }

            case .tool:
                append(role: "user", block: [
                    "type": "tool_result",
                    "tool_use_id": message.toolCallID ?? "",
                    "content": message.content
                ])
            }
        }

        if let first = result.first, first["role"] as? String != "user" {
            result.insert(["role": "user", "content": [["type": "text", "text": "(continued)"]]], at: 0)
        }

        return result
    }

    // MARK: - Shared

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

    /// Maps a message to OpenAI's chat-completions JSON shape, including the
    /// `tool_calls` array on assistant messages and `tool_call_id` on tool results —
    /// both required for the model to correctly follow a multi-turn tool-use exchange.
    private func openAIMessageJSON(_ message: LLMMessage) -> [String: Any] {
        if message.role == .tool {
            var json: [String: Any] = [
                "role": "tool",
                "content": message.content
            ]

            if let toolCallID = message.toolCallID {
                json["tool_call_id"] = toolCallID
            }

            return json
        }

        if message.role == .assistant, let toolCalls = message.toolCalls, !toolCalls.isEmpty {
            return [
                "role": "assistant",
                "content": message.content,
                "tool_calls": toolCalls.map { call in
                    [
                        "id": call.id,
                        "type": "function",
                        "function": [
                            "name": call.name,
                            "arguments": call.argumentsJSON
                        ]
                    ]
                }
            ]
        }

        return ["role": openAIRole(for: message.role), "content": message.content]
    }
}

private struct PendingToolCall {
    var id: String?
    var name: String?
    var arguments: String = ""
}

private struct AnthropicBlock {
    var type: String
    var id: String?
    var name: String?
    var accumulated: String = ""
}
