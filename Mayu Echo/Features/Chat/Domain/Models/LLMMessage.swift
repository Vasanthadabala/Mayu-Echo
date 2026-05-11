import Foundation

nonisolated struct LLMMessage: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var role: Role
    var content: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }

    enum Role: String, Codable, Hashable, Sendable {
        case system
        case user
        case assistant
        case tool
    }
}
