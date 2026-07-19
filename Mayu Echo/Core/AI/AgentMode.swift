import Foundation

/// How much autonomy the agent has when it proposes file edits and terminal commands,
/// mirroring the Manual / Accept edits / Auto modes in tools like Cursor and Claude Code.
enum AgentMode: String, CaseIterable, Identifiable, Sendable {
    /// Every file edit and terminal command waits for the user's approval.
    case manual
    /// File edits apply automatically; terminal commands still wait for approval.
    case acceptEdits
    /// File edits apply and terminal commands run automatically.
    case auto

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: return "Manual"
        case .acceptEdits: return "Accept edits"
        case .auto: return "Auto"
        }
    }

    var subtitle: String {
        switch self {
        case .manual: return "Approve every edit and command"
        case .acceptEdits: return "Apply edits automatically, ask before commands"
        case .auto: return "Apply edits and run commands automatically"
        }
    }

    var iconName: String {
        switch self {
        case .manual: return "hand.raised"
        case .acceptEdits: return "checkmark.circle"
        case .auto: return "bolt.fill"
        }
    }

    /// Whether a proposed file edit should be written without asking first.
    var autoApplyEdits: Bool {
        self != .manual
    }

    /// Whether a proposed terminal command should run without asking first.
    var autoRunCommands: Bool {
        self == .auto
    }
}
