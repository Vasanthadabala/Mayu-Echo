import Foundation

nonisolated struct ProjectContextBuilder {
    private static let estimatedCharactersPerToken = 4
    private static let defaultPreferredContextTokens = LLMModel.defaultWorkingContextLength
    private static let modelContextSafetyReserveTokens = 768
    private static let minimumSystemMessageCharacters = 1_200

    private static let ignoredNames: Set<String> = [
        ".build",
        ".git",
        ".swiftpm",
        ".vscode",
        "build",
        "DerivedData",
        "node_modules",
        "Pods"
    ]

    static func makeSystemMessage(
        projectPath: String?,
        bookmarkData: Data? = nil,
        intelligence: LLMGenerationOptions.Intelligence = .medium,
        modelContextLength: Int = 0,
        reservedResponseTokens: Int? = nil,
        chatMessages: [LLMMessage] = [],
        toolsEnabled: Bool = false
    ) -> LLMMessage? {
        guard let projectPath else {
            return nil
        }

        let contextProfile = projectContextProfile(for: intelligence)
        let maximumSystemMessageCharacters = systemMessageCharacterBudget(
            profile: contextProfile,
            modelContextLength: modelContextLength,
            reservedResponseTokens: reservedResponseTokens ?? intelligence.generationPreset.maxTokens,
            chatMessages: chatMessages
        )
        let rootURL = resolvedProjectURL(projectPath: projectPath, bookmarkData: bookmarkData)
        let isAccessing = rootURL.startAccessingSecurityScopedResource()

        defer {
            if isAccessing {
                rootURL.stopAccessingSecurityScopedResource()
            }
        }

        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            return nil
        }

        let tree = fileTree(at: rootURL, profile: contextProfile)

        if tree.failedToRead {
            return LLMMessage(
                role: .system,
                content: """
                You are Mayu Echo, a local coding assistant.
                The user is currently chatting inside the selected project folder:
                \(projectPath)

                Treat phrases like "this project", "this folder", "here", and "current directory" as referring to that folder.
                Mayu Echo could not read the folder contents for this request, likely because macOS security-scoped access is missing or stale.
                Do not say the folder is empty. Tell the user to remove and add the project folder again so the app can refresh folder access.
                """
            )
        }

        let header: String

        if toolsEnabled {
            header = """
            You are Mayu Echo, an agentic coding assistant with direct, tool-based access to the user's project files:
            \(projectPath)

            Treat phrases like "this project", "this folder", "here", and "current directory" as referring to that folder.

            You have these tools and you are expected to USE them, not just talk about them:
            - read_file(path): read the full contents of a file. Call this before editing so you edit the real, current content.
            - list_directory(path): list a folder's contents (empty string = project root).
            - str_replace(path, old_str, new_str): make a targeted edit by replacing one exact, unique snippet. This is your PRIMARY editing tool — use it for almost every change.
            - edit_file(path, content): replace a file's ENTIRE contents. Use only to create a new file or when rewriting most of a file.
            - run_terminal_command(command): run a shell command in the project root.

            When the user asks you to change, add, fix, rename, refactor, or implement something in this project, DO IT:
            1. Use list_directory / read_file to find and read the relevant file(s).
            2. Prefer str_replace to change only the lines that need changing — do NOT rewrite the whole file for a small edit. 'old_str' must match the file exactly (whitespace included) and be unique; add a little surrounding context if needed. Only use edit_file for brand-new files or near-total rewrites.
            Do NOT respond with generic guidance, hypothetical snippets, or "find something like ... and change it to ..." — that is a failure. The user cannot apply changes by hand; you must perform the edit. Never guess file contents — read the file first.

            Only answer in prose (without tools) when the user is asking a general question that is not a change to this project. Use the project file tree below to locate files.
            \(languageInstruction)
            Response mode: \(intelligence.rawValue).
            \(responseModeInstruction(for: intelligence))
            """
        } else {
            header = """
            You are Mayu Echo, a local coding assistant.
            The user is currently chatting inside the selected project folder:
            \(projectPath)

            Treat phrases like "this project", "this folder", "here", and "current directory" as referring to that selected folder.
            When the user asks what files are present, answer from the project file tree below instead of asking which directory they mean.
            If the question requires file contents that are not included here, say which file you need to inspect.
            \(languageInstruction)
            Response mode: \(intelligence.rawValue).
            \(responseModeInstruction(for: intelligence))
            """
        }

        let treeContent = tree.lines.joined(separator: "\n")
        let availableTreeCharacters = max(
            0,
            maximumSystemMessageCharacters - header.count - "\n\nProject file tree:\n".count
        )
        let trimmedTreeContent = trimmedTreeContent(
            treeContent,
            maximumCharacters: availableTreeCharacters
        )
        let content = """
        \(header)

        Project file tree:
        \(trimmedTreeContent)
        """

        return LLMMessage(role: .system, content: content)
    }

    static func requestMessages(
        chatMessages: [LLMMessage],
        projectPath: String?,
        bookmarkData: Data?,
        intelligence: LLMGenerationOptions.Intelligence = .medium,
        modelContextLength: Int = 0,
        reservedResponseTokens: Int? = nil,
        toolsEnabled: Bool = false
    ) -> [LLMMessage] {
        guard let projectContextMessage = makeSystemMessage(
            projectPath: projectPath,
            bookmarkData: bookmarkData,
            intelligence: intelligence,
            modelContextLength: modelContextLength,
            reservedResponseTokens: reservedResponseTokens,
            chatMessages: chatMessages,
            toolsEnabled: toolsEnabled
        ) else {
            // Plain (non-project) chat: still send a minimal base system prompt so the
            // model has a stable identity and, importantly, replies in the user's language.
            // Without it, some models (e.g. Chinese-first models like Hunyuan) default to
            // their own language for self-referential questions.
            return [LLMMessage(role: .system, content: baseSystemInstruction)] + chatMessages
        }

        return [projectContextMessage] + chatMessages
    }

    /// Identity + language directive sent when there is no project context. Kept short so
    /// it barely costs tokens.
    static let baseSystemInstruction = """
    You are Mayu Echo, a helpful AI assistant.
    Always reply in the same language the user writes in — if the user writes in English, respond in English. Only switch languages if the user does.
    """

    /// One-line language directive folded into the project system prompt.
    private static let languageInstruction =
        "Always reply in the same language the user writes in; only switch languages if the user does."

    private static func resolvedProjectURL(projectPath: String, bookmarkData: Data?) -> URL {
        guard let bookmarkData else {
            return URL(fileURLWithPath: projectPath, isDirectory: true)
        }

        var isStale = false
        let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        return url ?? URL(fileURLWithPath: projectPath, isDirectory: true)
    }

    private static func fileTree(at rootURL: URL, profile: ProjectContextProfile) -> ProjectFileTree {
        var lines: [String] = []
        var itemCount = 0
        var failedToRead = false

        func visit(_ directoryURL: URL, depth: Int, prefix: String) {
            guard depth <= profile.maximumDepth, itemCount < profile.maximumItems else {
                return
            }

            let children: [URL]
            do {
                children = try directoryChildren(for: directoryURL)
            } catch {
                failedToRead = true
                return
            }

            for (index, child) in children.enumerated() {
                guard itemCount < profile.maximumItems else {
                    lines.append("\(prefix)...")
                    return
                }

                let isLast = index == children.count - 1
                let connector = isLast ? "`-- " : "|-- "
                let childPrefix = prefix + (isLast ? "    " : "|   ")
                let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

                itemCount += 1
                lines.append("\(prefix)\(connector)\(child.lastPathComponent)\(isDirectory ? "/" : "")")

                if isDirectory {
                    visit(child, depth: depth + 1, prefix: childPrefix)
                }
            }
        }

        lines.append(URL(fileURLWithPath: rootURL.path).lastPathComponent + "/")
        visit(rootURL, depth: 1, prefix: "")

        return ProjectFileTree(lines: lines, failedToRead: failedToRead)
    }

    private static func directoryChildren(for directoryURL: URL) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isHiddenKey]
        let children = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants]
        )

        return children
            .filter { url in
                guard !ignoredNames.contains(url.lastPathComponent) else {
                    return false
                }

                let values = try? url.resourceValues(forKeys: keys)
                return values?.isHidden != true
            }
            .sorted { lhs, rhs in
                let lhsIsDirectory = (try? lhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let rhsIsDirectory = (try? rhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

                if lhsIsDirectory != rhsIsDirectory {
                    return lhsIsDirectory && !rhsIsDirectory
                }

                return lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
            }
    }

    private static func projectContextProfile(
        for intelligence: LLMGenerationOptions.Intelligence
    ) -> ProjectContextProfile {
        switch intelligence {
        case .low:
            return ProjectContextProfile(
                maximumDepth: 3,
                maximumItems: 80,
                preferredContextTokens: defaultPreferredContextTokens
            )
        case .medium:
            return ProjectContextProfile(
                maximumDepth: 5,
                maximumItems: 220,
                preferredContextTokens: defaultPreferredContextTokens
            )
        case .high:
            return ProjectContextProfile(
                maximumDepth: 7,
                maximumItems: 520,
                preferredContextTokens: defaultPreferredContextTokens
            )
        case .extraHigh:
            return ProjectContextProfile(
                maximumDepth: 9,
                maximumItems: 1_000,
                preferredContextTokens: defaultPreferredContextTokens
            )
        }
    }

    private static func systemMessageCharacterBudget(
        profile: ProjectContextProfile,
        modelContextLength: Int,
        reservedResponseTokens: Int,
        chatMessages: [LLMMessage]
    ) -> Int {
        let chatTokens = chatMessages.reduce(0) { partialResult, message in
            partialResult + estimatedTokenCount(in: message.content)
        }
        let availableInputTokens = modelContextLength
            - reservedResponseTokens
            - chatTokens
            - modelContextSafetyReserveTokens
        let contextTokens = min(
            profile.preferredContextTokens,
            max(0, availableInputTokens)
        )

        return max(
            minimumSystemMessageCharacters,
            contextTokens * estimatedCharactersPerToken
        )
    }

    private static func estimatedTokenCount(in text: String) -> Int {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return 0
        }

        return max(1, Int(ceil(Double(trimmedText.count) / Double(estimatedCharactersPerToken))))
    }

    private static func trimmedTreeContent(_ content: String, maximumCharacters: Int) -> String {
        guard maximumCharacters > 0 else {
            return "Project tree omitted because the current chat is already near the model context limit."
        }

        guard content.count > maximumCharacters else {
            return content
        }

        return String(content.prefix(maximumCharacters)) + "\n..."
    }

    private static func responseModeInstruction(
        for intelligence: LLMGenerationOptions.Intelligence
    ) -> String {
        switch intelligence {
        case .low:
            return "Keep answers concise and prioritize speed."
        case .medium:
            return "Use balanced detail and keep the response practical."
        case .high:
            return "Use more project context, be more careful, and include implementation details when useful."
        case .extraHigh:
            return "Use the largest available project context, reason carefully about code changes, and prefer complete implementation guidance."
        }
    }

    private struct ProjectFileTree {
        let lines: [String]
        let failedToRead: Bool
    }

    private struct ProjectContextProfile {
        let maximumDepth: Int
        let maximumItems: Int
        let preferredContextTokens: Int
    }
}
