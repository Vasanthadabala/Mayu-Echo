import Foundation

/// Where a tool call executes: the active project's root path plus its
/// security-scoped bookmark (needed for folders under Desktop/Documents/Downloads,
/// which macOS's TCC privacy system protects even for non-sandboxed apps).
nonisolated struct ProjectAgentContext: Sendable {
    let rootPath: String
    let bookmarkData: Data?
}

nonisolated enum ToolExecutionResult: Sendable {
    case text(String)
    case pendingEdit(ProjectFileEditProposal)
    case pendingCommand(ProjectCommandProposal)
}

/// A model-proposed file write, held for user approval before anything touches disk.
nonisolated struct ProjectFileEditProposal: Sendable, Identifiable, Hashable {
    let id: UUID
    /// Absolute, safety-checked path.
    let path: String
    let originalContent: String?
    let proposedContent: String
    let toolCallID: String
}

/// A model-proposed shell command, held for user approval before it runs (when the
/// "confirm terminal commands" setting requires it).
nonisolated struct ProjectCommandProposal: Sendable, Identifiable, Hashable {
    let id: UUID
    let command: String
    let toolCallID: String
}

nonisolated enum ProjectAgentTools {
    // MARK: - Schemas

    private static let readFileSchema: [String: Any] = [
        "name": "read_file",
        "description": "Read the full text contents of a file in the current project. Path is relative to the project root.",
        "parameters": [
            "type": "object",
            "properties": [
                "path": ["type": "string", "description": "File path relative to the project root, e.g. Sources/App.swift"]
            ],
            "required": ["path"]
        ]
    ]

    private static let listDirectorySchema: [String: Any] = [
        "name": "list_directory",
        "description": "List files and folders inside a directory in the current project. Path is relative to the project root; use an empty string for the root.",
        "parameters": [
            "type": "object",
            "properties": [
                "path": ["type": "string", "description": "Directory path relative to the project root. Empty string means the root."]
            ],
            "required": ["path"]
        ]
    ]

    private static let strReplaceSchema: [String: Any] = [
        "name": "str_replace",
        "description": "Make a targeted edit to an existing file by replacing one exact snippet of text with new text. PREFER THIS over edit_file for any small or localized change — it changes only the matched lines instead of rewriting the whole file. 'old_str' must match the file EXACTLY, including all whitespace and indentation, and must be unique in the file (include a few surrounding lines for context if needed to make it unique).",
        "parameters": [
            "type": "object",
            "properties": [
                "path": ["type": "string", "description": "File path relative to the project root."],
                "old_str": ["type": "string", "description": "The exact existing text to replace, including surrounding whitespace/indentation. Must appear exactly once in the file."],
                "new_str": ["type": "string", "description": "The replacement text. Use an empty string to delete the matched text."]
            ],
            "required": ["path", "old_str", "new_str"]
        ]
    ]

    private static let editFileSchema: [String: Any] = [
        "name": "edit_file",
        "description": "Replace the ENTIRE contents of a file. Use this only to create a new file or when rewriting most of a file. For small or localized changes, use str_replace instead so you don't regenerate the whole file. The user must approve before anything is written to disk. Path is relative to the project root; if the file does not exist it will be created.",
        "parameters": [
            "type": "object",
            "properties": [
                "path": ["type": "string", "description": "File path relative to the project root."],
                "content": ["type": "string", "description": "The complete new contents of the file."]
            ],
            "required": ["path", "content"]
        ]
    ]

    private static let runCommandSchema: [String: Any] = [
        "name": "run_terminal_command",
        "description": "Run a shell command in the current project's root directory. Depending on the user's settings, this may require their approval before it runs.",
        "parameters": [
            "type": "object",
            "properties": [
                "command": ["type": "string", "description": "The shell command to run, e.g. 'swift build' or 'ls -la'."]
            ],
            "required": ["command"]
        ]
    ]

    /// OpenAI-style function-calling schema (`{"type": "function", "function": {... "parameters": ...}}`).
    static var toolSchemas: [[String: Any]] {
        [readFileSchema, listDirectorySchema, strReplaceSchema, editFileSchema, runCommandSchema].map { schema in
            ["type": "function", "function": schema]
        }
    }

    /// Anthropic-style tool schema (flat, `input_schema` instead of `parameters`).
    static var anthropicToolSchemas: [[String: Any]] {
        [readFileSchema, listDirectorySchema, strReplaceSchema, editFileSchema, runCommandSchema].map { schema in
            var converted = schema
            converted["input_schema"] = schema["parameters"]
            converted.removeValue(forKey: "parameters")
            return converted
        }
    }

    // MARK: - Execution

    static func execute(
        name: String,
        argumentsJSON: String,
        toolCallID: String,
        context: ProjectAgentContext
    ) -> ToolExecutionResult {
        let arguments = (try? JSONSerialization.jsonObject(
            with: Data(argumentsJSON.utf8)
        )) as? [String: Any] ?? [:]

        switch name {
        case "read_file":
            return .text(readFile(arguments: arguments, context: context))
        case "list_directory":
            return .text(listDirectory(arguments: arguments, context: context))
        case "str_replace":
            return strReplace(arguments: arguments, toolCallID: toolCallID, context: context)
        case "edit_file":
            return editFile(arguments: arguments, toolCallID: toolCallID, context: context)
        case "run_terminal_command":
            return runTerminalCommand(arguments: arguments, toolCallID: toolCallID)
        default:
            return .text("Unknown tool: \(name)")
        }
    }

    /// Outcome of writing an approved edit to disk. `.permissionDenied` is called out
    /// separately so the caller can re-request folder access and retry.
    nonisolated enum EditWriteResult: Sendable {
        case success(String)
        case permissionDenied(String)
        case failure(String)

        var message: String {
            switch self {
            case .success(let message), .permissionDenied(let message), .failure(let message):
                return message
            }
        }
    }

    /// Actually writes an approved edit to disk.
    static func applyEdit(_ proposal: ProjectFileEditProposal, context: ProjectAgentContext) -> EditWriteResult {
        withSecurityScope(context: context) {
            do {
                let url = URL(fileURLWithPath: proposal.path)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                // Write in place (atomically: false) so the write stays within the folder's
                // security-scoped bookmark rather than creating a separate temp file.
                let data = Data(proposal.proposedContent.utf8)
                try data.write(to: url, options: [])
                return .success("File written successfully.")
            } catch let error as NSError {
                if error.domain == NSCocoaErrorDomain && error.code == NSFileWriteNoPermissionError {
                    return .permissionDenied("Error writing file: Mayu Echo does not have write access to this folder.")
                }
                return .failure("Error writing file: \(error.localizedDescription)")
            }
        }
    }

    private static func readFile(arguments: [String: Any], context: ProjectAgentContext) -> String {
        guard let relativePath = arguments["path"] as? String else {
            return "Error: missing 'path' argument."
        }

        guard let resolvedPath = resolveSafePath(relativePath, context: context) else {
            return "Error: '\(relativePath)' is outside the project or invalid."
        }

        return withSecurityScope(context: context) {
            guard let data = FileManager.default.contents(atPath: resolvedPath) else {
                return "Error: '\(relativePath)' does not exist."
            }

            guard data.count <= 400_000 else {
                return "Error: '\(relativePath)' is too large to read (over 400KB)."
            }

            guard let text = String(data: data, encoding: .utf8) else {
                return "Error: '\(relativePath)' is not a text file."
            }

            return text
        }
    }

    private static func listDirectory(arguments: [String: Any], context: ProjectAgentContext) -> String {
        let relativePath = (arguments["path"] as? String) ?? ""

        guard let resolvedPath = resolveSafePath(relativePath, context: context) else {
            return "Error: '\(relativePath)' is outside the project or invalid."
        }

        return withSecurityScope(context: context) {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: resolvedPath) else {
                return "Error: could not list '\(relativePath.isEmpty ? "." : relativePath)'."
            }

            let visible = entries
                .filter { !$0.hasPrefix(".") }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

            return visible.isEmpty ? "(empty directory)" : visible.joined(separator: "\n")
        }
    }

    private static func editFile(
        arguments: [String: Any],
        toolCallID: String,
        context: ProjectAgentContext
    ) -> ToolExecutionResult {
        guard let relativePath = arguments["path"] as? String,
              let content = arguments["content"] as? String else {
            return .text("Error: 'edit_file' requires 'path' and 'content' arguments.")
        }

        guard let resolvedPath = resolveSafePath(relativePath, context: context) else {
            return .text("Error: '\(relativePath)' is outside the project or invalid.")
        }

        let originalContent = withSecurityScope(context: context) {
            FileManager.default.contents(atPath: resolvedPath).flatMap {
                String(data: $0, encoding: .utf8)
            }
        }

        return .pendingEdit(
            ProjectFileEditProposal(
                id: UUID(),
                path: resolvedPath,
                originalContent: originalContent,
                proposedContent: content,
                toolCallID: toolCallID
            )
        )
    }

    /// Surgical edit: replace one exact, unique snippet inside an existing file. Produces
    /// the same `ProjectFileEditProposal` as `editFile` (full original + full proposed
    /// content) so the approval/apply pipeline is identical, but the model only had to
    /// supply the changed snippet instead of the whole file.
    private static func strReplace(
        arguments: [String: Any],
        toolCallID: String,
        context: ProjectAgentContext
    ) -> ToolExecutionResult {
        guard let relativePath = arguments["path"] as? String,
              let oldStr = arguments["old_str"] as? String,
              let newStr = arguments["new_str"] as? String else {
            return .text("Error: 'str_replace' requires 'path', 'old_str', and 'new_str' arguments.")
        }

        guard let resolvedPath = resolveSafePath(relativePath, context: context) else {
            return .text("Error: '\(relativePath)' is outside the project or invalid.")
        }

        guard !oldStr.isEmpty else {
            return .text("Error: 'old_str' must not be empty. Use edit_file to create or fully replace a file.")
        }

        let originalContent = withSecurityScope(context: context) {
            FileManager.default.contents(atPath: resolvedPath).flatMap {
                String(data: $0, encoding: .utf8)
            }
        }

        guard let originalContent else {
            return .text("Error: '\(relativePath)' does not exist or is not a readable text file. Use edit_file to create it.")
        }

        let occurrences = originalContent.components(separatedBy: oldStr).count - 1

        guard occurrences > 0 else {
            return .text("Error: 'old_str' was not found in '\(relativePath)'. Read the file again and match the exact text, including whitespace and indentation.")
        }

        guard occurrences == 1 else {
            return .text("Error: 'old_str' appears \(occurrences) times in '\(relativePath)'. Include more surrounding context so it matches exactly one location.")
        }

        let proposedContent = originalContent.replacingOccurrences(of: oldStr, with: newStr)

        return .pendingEdit(
            ProjectFileEditProposal(
                id: UUID(),
                path: resolvedPath,
                originalContent: originalContent,
                proposedContent: proposedContent,
                toolCallID: toolCallID
            )
        )
    }

    /// Always returns a pending proposal — whether it auto-runs or waits for the user is
    /// decided by the caller (which knows the user's "confirm terminal commands" setting).
    private static func runTerminalCommand(arguments: [String: Any], toolCallID: String) -> ToolExecutionResult {
        guard let command = arguments["command"] as? String, !command.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .text("Error: 'run_terminal_command' requires a non-empty 'command' argument.")
        }

        return .pendingCommand(ProjectCommandProposal(id: UUID(), command: command, toolCallID: toolCallID))
    }

    // MARK: - Live-preview support

    /// Best-effort extraction of a growing string value from a JSON object that is still
    /// being streamed and therefore not yet valid JSON. Used only to show a live preview
    /// while a tool call's arguments are still arriving — the final values always come
    /// from a fully-parsed JSON payload once the call is complete.
    static func partialStringValue(forKey key: String, inPartialJSON json: String) -> String? {
        guard let keyRange = json.range(of: "\"\(key)\"") else {
            return nil
        }

        guard let colonRange = json.range(of: ":", range: keyRange.upperBound..<json.endIndex) else {
            return nil
        }

        var index = colonRange.upperBound

        while index < json.endIndex, json[index].isWhitespace {
            index = json.index(after: index)
        }

        guard index < json.endIndex, json[index] == "\"" else {
            return nil
        }

        index = json.index(after: index)

        var result = ""
        var isEscaping = false

        while index < json.endIndex {
            let character = json[index]

            if isEscaping {
                switch character {
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                default: result.append(character)
                }
                isEscaping = false
            } else if character == "\\" {
                isEscaping = true
            } else if character == "\"" {
                return result
            } else {
                result.append(character)
            }

            index = json.index(after: index)
        }

        // No closing quote yet — the value is still streaming; return what we have.
        return result
    }

    // MARK: - Path safety

    /// Resolves a model-supplied path against the project root and rejects anything
    /// that would escape it (no `../` traversal outside the project).
    private static func resolveSafePath(_ relativePath: String, context: ProjectAgentContext) -> String? {
        var cleaned = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let rootURL = URL(fileURLWithPath: context.rootPath).standardizedFileURL

        // Models often write a leading "/" meaning "from the project root," not the
        // filesystem root — treat it that way unless it's already under the root.
        if cleaned.hasPrefix("/"), !cleaned.hasPrefix(rootURL.path) {
            cleaned.removeFirst()
        }

        let candidateURL = cleaned.isEmpty
            ? rootURL
            : URL(fileURLWithPath: cleaned, relativeTo: rootURL).standardizedFileURL

        guard candidateURL.path == rootURL.path || candidateURL.path.hasPrefix(rootURL.path + "/") else {
            return nil
        }

        return candidateURL.path
    }

    private static func withSecurityScope<T>(context: ProjectAgentContext, _ body: () -> T) -> T {
        guard let bookmarkData = context.bookmarkData else {
            return body()
        }

        var isStale = false
        guard let scopedURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return body()
        }

        let isAccessing = scopedURL.startAccessingSecurityScopedResource()

        defer {
            if isAccessing {
                scopedURL.stopAccessingSecurityScopedResource()
            }
        }

        return body()
    }
}
