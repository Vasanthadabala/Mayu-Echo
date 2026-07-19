import Foundation

nonisolated struct LLMMessage: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var role: Role
    var content: String
    var createdAt: Date
    /// Set on an assistant message that is requesting one or more tool calls.
    var toolCalls: [ToolCallRequest]?
    /// Set on a `.tool` role message: which call this is the result of.
    var toolCallID: String?
    /// Set on a `.tool` role message: the tool that produced this result, for display.
    var toolName: String?
    /// Set on a successful edit_file/str_replace `.tool` result: the file's content before
    /// the edit, so the UI can offer a "Review" affordance after the fact. Display-only —
    /// never sent back to the model.
    var diffOriginalContent: String?
    /// Set alongside `diffOriginalContent`: the file's content after the edit.
    var diffProposedContent: String?
    /// Set alongside `diffOriginalContent`: the absolute path of the edited file, for display.
    var diffPath: String?

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        createdAt: Date = Date(),
        toolCalls: [ToolCallRequest]? = nil,
        toolCallID: String? = nil,
        toolName: String? = nil,
        diffOriginalContent: String? = nil,
        diffProposedContent: String? = nil,
        diffPath: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.diffOriginalContent = diffOriginalContent
        self.diffProposedContent = diffProposedContent
        self.diffPath = diffPath
    }

    enum Role: String, Codable, Hashable, Sendable {
        case system
        case user
        case assistant
        case tool
    }
}
