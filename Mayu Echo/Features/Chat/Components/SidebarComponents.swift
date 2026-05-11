import SwiftUI

struct SidebarActionButton: View {
    let title: String
    let systemImage: String
    var isSelected = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
                    .lineLimit(1)
            } icon: {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 24)
            }
                .font(.system(size: 17, weight: .regular))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? .primary : .secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isActive ? Color.mayuBorder : Color.clear, lineWidth: 1)
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var isActive: Bool {
        isSelected || isHovered
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.mayuSelection
        }

        return isHovered ? Color.mayuSelection.opacity(0.72) : Color.clear
    }
}

struct SidebarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.mayuBorder)
            .frame(height: 1)
            .padding(.horizontal, 4)
    }
}

struct SidebarSection<Content: View>: View {
    let title: String
    let trailingSystemImage: String
    let trailingAction: () -> Void
    var isExpanded: Bool?
    var toggleExpansion: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                if let isExpanded, let toggleExpansion {
                    Button(action: toggleExpansion) {
                        HStack(spacing: 6) {
                            Text(title)
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: trailingAction) {
                    Image(systemName: trailingSystemImage)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)

            content
        }
    }
}

struct SidebarItemRow: View {
    let title: String
    let systemImage: String?
    let isSelected: Bool
    var trailingSystemImage: String?
    var trailingText: String?
    var leadingIndent: CGFloat = 0
    var trailingUsesMenu = false
    var isRenaming = false
    var renameText: Binding<String>?
    var renameAction: (() -> Void)?
    var commitRenameAction: (() -> Void)?
    var cancelRenameAction: (() -> Void)?
    var menuAction: (() -> Void)?
    var menuShowsOnHover = false
    var menuTitle = "Delete"
    var menuSystemImage = "trash"
    var trailingAction: (() -> Void)?
    let action: () -> Void
    @State private var isHovered = false
    @FocusState private var isRenameFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                }

                if isRenaming, let renameText {
                    TextField("", text: renameText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                        .focused($isRenameFocused)
                        .onSubmit {
                            commitRenameAction?()
                        }
                        .onAppear {
                            isRenameFocused = true
                        }
                        .onExitCommand {
                            cancelRenameAction?()
                        }
                } else {
                    Text(title)
                        .font(.system(size: 16, weight: isSelected ? .medium : .regular))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)

                if shouldShowTrailingText, let trailingText {
                    Text(trailingText)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, leadingIndent)
            .frame(maxWidth: .infinity, alignment: .leading)

            if shouldShowMenuAction, let menuAction {
                Menu {
                    Button(role: .destructive, action: menuAction) {
                        Label(menuTitle, systemImage: menuSystemImage)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(isHovered || !menuShowsOnHover ? 1 : 0)
            }

            if let trailingSystemImage {
                if let trailingAction {
                    if trailingUsesMenu {
                        if shouldShowTrailingMenu {
                            Menu {
                                if let renameAction {
                                    Button(action: renameAction) {
                                        Label("Rename", systemImage: "pencil")
                                    }
                                }

                                Button(role: .destructive, action: trailingAction) {
                                    Label("Delete", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: trailingSystemImage)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 34, height: 34)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .opacity(isHovered ? 1 : 0)
                        }
                    } else {
                        Button(action: trailingAction) {
                            Image(systemName: trailingSystemImage)
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .frame(width: 34, height: 34)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .opacity(isActive ? 1 : 0.72)
                    }
                } else {
                    Image(systemName: trailingSystemImage)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }

            if isRenaming {
                Button(action: cancelRenameAction ?? {}) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: commitRenameAction ?? {}) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(isActive ? .primary : .secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isActive ? Color.mayuBorder : Color.clear, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            if !isRenaming {
                action()
            }
        }
        .accessibilityAddTraits(.isButton)
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var isActive: Bool {
        isSelected || isHovered || isRenaming
    }

    private var shouldShowTrailingText: Bool {
        trailingText != nil && (!trailingUsesMenu || !isHovered) && !isRenaming
    }

    private var shouldShowTrailingMenu: Bool {
        trailingUsesMenu && isHovered && !isRenaming
    }

    private var shouldShowMenuAction: Bool {
        menuAction != nil && (!menuShowsOnHover || isHovered) && !isRenaming
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.mayuSelection
        }

        return isHovered ? Color.mayuSelection.opacity(0.72) : Color.clear
    }
}

struct EmptySidebarRow: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 14))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
