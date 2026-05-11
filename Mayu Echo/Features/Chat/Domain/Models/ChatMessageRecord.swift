import Foundation
import SwiftData

@Model
final class ChatMessageRecord {
    var id: UUID
    var roleRawValue: String
    var content: String
    var createdAt: Date
    var chat: Item?

    init(
        id: UUID = UUID(),
        role: LLMMessage.Role,
        content: String,
        createdAt: Date = Date(),
        chat: Item? = nil
    ) {
        self.id = id
        self.roleRawValue = role.rawValue
        self.content = content
        self.createdAt = createdAt
        self.chat = chat
    }

    convenience init(message: LLMMessage, chat: Item?) {
        self.init(
            id: message.id,
            role: message.role,
            content: message.content,
            createdAt: message.createdAt,
            chat: chat
        )
    }

    var message: LLMMessage {
        LLMMessage(
            id: id,
            role: LLMMessage.Role(rawValue: roleRawValue) ?? .assistant,
            content: content,
            createdAt: createdAt
        )
    }

    func update(from message: LLMMessage) {
        roleRawValue = message.role.rawValue
        content = message.content
        createdAt = message.createdAt
    }
}
