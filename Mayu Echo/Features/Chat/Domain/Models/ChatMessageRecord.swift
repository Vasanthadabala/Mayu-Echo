import Foundation
import SwiftData

@Model
final class ChatMessageRecord {
    var id: UUID
    var roleRawValue: String
    var content: String
    var createdAt: Date
    var chat: Item?
    var toolCallsData: Data?
    var toolCallID: String?
    var toolName: String?
    var diffOriginalContent: String?
    var diffProposedContent: String?
    var diffPath: String?

    init(
        id: UUID = UUID(),
        role: LLMMessage.Role,
        content: String,
        createdAt: Date = Date(),
        chat: Item? = nil,
        toolCalls: [ToolCallRequest]? = nil,
        toolCallID: String? = nil,
        toolName: String? = nil,
        diffOriginalContent: String? = nil,
        diffProposedContent: String? = nil,
        diffPath: String? = nil
    ) {
        self.id = id
        self.roleRawValue = role.rawValue
        self.content = content
        self.createdAt = createdAt
        self.chat = chat
        self.toolCallsData = toolCalls.flatMap { try? JSONEncoder().encode($0) }
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.diffOriginalContent = diffOriginalContent
        self.diffProposedContent = diffProposedContent
        self.diffPath = diffPath
    }

    convenience init(message: LLMMessage, chat: Item?) {
        self.init(
            id: message.id,
            role: message.role,
            content: message.content,
            createdAt: message.createdAt,
            chat: chat,
            toolCalls: message.toolCalls,
            toolCallID: message.toolCallID,
            toolName: message.toolName,
            diffOriginalContent: message.diffOriginalContent,
            diffProposedContent: message.diffProposedContent,
            diffPath: message.diffPath
        )
    }

    var message: LLMMessage {
        let toolCalls = toolCallsData.flatMap {
            try? JSONDecoder().decode([ToolCallRequest].self, from: $0)
        }

        return LLMMessage(
            id: id,
            role: LLMMessage.Role(rawValue: roleRawValue) ?? .assistant,
            content: content,
            createdAt: createdAt,
            toolCalls: toolCalls,
            toolCallID: toolCallID,
            toolName: toolName,
            diffOriginalContent: diffOriginalContent,
            diffProposedContent: diffProposedContent,
            diffPath: diffPath
        )
    }

    func update(from message: LLMMessage) {
        roleRawValue = message.role.rawValue
        content = message.content
        createdAt = message.createdAt
        toolCallsData = message.toolCalls.flatMap { try? JSONEncoder().encode($0) }
        toolCallID = message.toolCallID
        toolName = message.toolName
        diffOriginalContent = message.diffOriginalContent
        diffProposedContent = message.diffProposedContent
        diffPath = message.diffPath
    }
}
