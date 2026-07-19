import SwiftUI
import AppKit
import SwiftData

enum SidebarMode: String, CaseIterable, Identifiable {
    case home = "Chat"
    case code = "Code"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .home: return "bubble.left.and.bubble.right"
        case .code: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

struct SidebarModeSwitcher: View {
    @Binding var mode: SidebarMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SidebarMode.allCases) { candidate in
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        mode = candidate
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: candidate.systemImage)
                            .font(.system(size: 11, weight: .semibold))
                        Text(candidate.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(mode == candidate ? Color.mayuElevatedBackground : .clear)
                            .overlay {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(Color.mayuBorder.opacity(mode == candidate ? 0.65 : 0), lineWidth: 1)
                            }
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(mode == candidate ? .primary : .secondary)
            }
        }
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.mayuPanelBackground.opacity(0.7))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.mayuBorder.opacity(0.5), lineWidth: 1)
                }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: mode)
    }
}

// MARK: - Sidebar tree

struct ProjectCodeSection: View {
    let project: Item
    var chats: [Item] = []
    @Binding var expandedPaths: Set<String>
    var selectedChatID: PersistentIdentifier? = nil
    var selectChat: ((Item) -> Void)? = nil
    var deleteChat: ((Item) -> Void)? = nil
    var removeProject: (() -> Void)? = nil
    var addChat: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            FileTreeRow(
                name: project.title,
                depth: 0,
                isExpanded: isExpanded,
                select: toggleProject,
                removeAction: removeProject,
                addChatAction: addChat
            )

            if isExpanded {
                // Project-scoped chats, nested directly under the folder.
                ForEach(chats) { chat in
                    ProjectChatRow(
                        title: chat.title,
                        depth: 1,
                        isSelected: chat.persistentModelID == selectedChatID,
                        select: { selectChat?(chat) },
                        deleteAction: deleteChat != nil ? { deleteChat?(chat) } : nil
                    )
                }
            }
        }
    }

    private var isExpanded: Bool {
        guard let projectPath = project.projectPath else { return false }
        return expandedPaths.contains(projectPath)
    }

    private func toggleProject() {
        guard let projectPath = project.projectPath else { return }

        withAnimation(.easeInOut(duration: 0.12)) {
            if expandedPaths.contains(projectPath) {
                expandedPaths.remove(projectPath)
            } else {
                expandedPaths.insert(projectPath)
            }
        }
    }
}

private struct ProjectChatRow: View {
    let title: String
    let depth: Int
    let isSelected: Bool
    let select: () -> Void
    var deleteAction: (() -> Void)? = nil
    @State private var isHovered = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 6) {
                Color.clear.frame(width: 10)

                Image(systemName: "bubble.left")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? Color.mayuAccent : .secondary)
                    .frame(width: 16)

                Text(title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
                if isHovered, deleteAction != nil {
                    Color.clear.frame(width: 22, height: 22)
                }
            }
            .padding(.leading, CGFloat(depth) * 14 + 8)
            .padding(.trailing, 8)
            .padding(.vertical, 5)
            .frame(minHeight: 26)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.mayuSelection : (isHovered ? Color.mayuSelection.opacity(0.5) : .clear))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            if isHovered, let deleteAction {
                Menu {
                    Button(role: .destructive, action: deleteAction) {
                        Label("Delete chat", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                .transition(.opacity.animation(.easeInOut(duration: 0.1)))
            }
        }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}

private struct FileTreeRow: View {
    let name: String
    let depth: Int
    let isExpanded: Bool
    let select: () -> Void
    var removeAction: (() -> Void)? = nil
    var addChatAction: (() -> Void)? = nil
    @State private var isHovered = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 10)

                Image(systemName: isExpanded ? "folder.fill" : "folder")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.mayuAccent)
                    .frame(width: 16)

                Text(name)
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                // Reserve space for trailing buttons so text doesn't shift on hover
                Spacer(minLength: 0)
                if isHovered {
                    Color.clear
                        .frame(width: trailingWidth, height: 22)
                }
            }
            .padding(.leading, CGFloat(depth) * 14 + 8)
            .padding(.trailing, 8)
            .padding(.vertical, 5)
            .frame(minHeight: 26)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.mayuSelection.opacity(0.5) : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Trailing action buttons in an overlay so they get higher hit-test priority
        .overlay(alignment: .trailing) {
            if isHovered {
                HStack(spacing: 4) {
                    if let addChatAction, depth == 0 {
                        Button(action: addChatAction) {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("New chat in this project")
                    }

                    if let removeAction {
                        Menu {
                            Button(role: .destructive, action: removeAction) {
                                Label("Remove project", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.trailing, 8)
                .transition(.opacity.animation(.easeInOut(duration: 0.1)))
            }
        }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }

    /// Approximate trailing-button width so the text Spacer doesn't shift.
    private var trailingWidth: CGFloat {
        var w: CGFloat = 0
        if addChatAction != nil && depth == 0 { w += 26 }
        if removeAction != nil { w += 26 }
        return w
    }
}
