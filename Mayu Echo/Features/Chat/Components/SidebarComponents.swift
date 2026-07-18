import SwiftUI

// MARK: - Sidebar Header

struct SidebarHeader: View {
    var openSearch: () -> Void = {}
    @State private var isSearchHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Text("Mayu Echo")
                .font(.system(size: 17, weight: .bold, design: .serif))
                .foregroundStyle(.primary)
                .tracking(-0.2)

            Spacer(minLength: 0)

            Button(action: openSearch) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSearchHovered ? .primary : .secondary)
                    .frame(width: 26, height: 26)
                    .background {
                        Circle().fill(isSearchHovered ? Color.mayuElevatedBackground : .clear)
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.12), value: isSearchHovered)
            .onHover { isSearchHovered = $0 }
            .help("Search chats and projects")
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }
}

// MARK: - Search Field

struct SidebarSearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isFocused ? Color.mayuAccent : Color(NSColor.tertiaryLabelColor))
                .frame(width: 16)
                .animation(.easeInOut(duration: 0.15), value: isFocused)

            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .regular))
                .focused($isFocused)

            if !text.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        text = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.mayuPanelBackground.opacity(0.85))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(
                    isFocused ? Color.mayuStrongBorder : Color.mayuBorder.opacity(0.7),
                    lineWidth: isFocused ? 1.5 : 1
                )
        }
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Action Button

struct SidebarActionButton: View {
    let title: String
    let systemImage: String
    var isSelected = false
    let action: () -> Void
    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(iconBackground)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.mayuBorder.opacity(isSelected ? 0.5 : 0), lineWidth: 1)
                        }

                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.mayuAccent : .secondary)
                }
                .frame(width: 27, height: 27)
                .scaleEffect(isPressed ? 0.9 : 1)

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? .primary : .secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(backgroundColor)
        }
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeInOut(duration: 0.08)) { isPressed = true }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) { isPressed = false }
                }
        )
    }

    private var isActive: Bool { isSelected || isHovered }

    private var backgroundColor: Color {
        if isSelected { return Color.mayuSelection }
        return isHovered ? Color.mayuSelection.opacity(0.65) : .clear
    }

    private var iconBackground: Color {
        if isSelected { return Color.mayuAccentSoft }
        return isHovered ? Color.mayuElevatedBackground : Color.mayuPanelBackground.opacity(0.6)
    }
}

// MARK: - Divider

struct SidebarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.mayuBorder.opacity(0.6))
            .frame(height: 0.5)
            .padding(.horizontal, 2)
    }
}

// MARK: - Section

struct SidebarSection<Content: View>: View {
    let title: String
    var trailingSystemImage: String? = nil
    var trailingAction: (() -> Void)? = nil
    var isExpanded: Bool?
    var toggleExpansion: (() -> Void)?
    @ViewBuilder let content: Content
    @State private var isTrailingHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                if let isExpanded, let toggleExpansion {
                    Button(action: toggleExpansion) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isExpanded)

                            Text(title)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.tertiary)
                                .tracking(0.4)
                        }
                        .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(title)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.4)
                }

                Spacer()

                if let trailingSystemImage, let trailingAction {
                    Button(action: trailingAction) {
                        Image(systemName: trailingSystemImage)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isTrailingHovered ? .primary : .tertiary)
                            .frame(width: 22, height: 22)
                            .background {
                                Circle()
                                    .fill(isTrailingHovered ? Color.mayuElevatedBackground : .clear)
                            }
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.12), value: isTrailingHovered)
                    .onHover { isTrailingHovered = $0 }
                }
            }
            .padding(.horizontal, 7)

            content
        }
    }
}

// MARK: - Item Row

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
        HStack(spacing: 6) {
            // Leading selection indicator
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(isSelected ? Color.mayuAccent : .clear)
                .frame(width: 2.5)
                .padding(.vertical, 6)
                .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isSelected)

            HStack(spacing: 8) {
                HStack(spacing: 9) {
                    if let systemImage {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? Color.mayuAccentSoft : Color.mayuPanelBackground.opacity(0.5))

                            Image(systemName: systemImage)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(isSelected ? Color.mayuAccent : .secondary)
                        }
                        .frame(width: 24, height: 24)
                        .animation(.easeInOut(duration: 0.15), value: isSelected)
                    }

                    if isRenaming, let renameText {
                        TextField("", text: renameText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                            .focused($isRenameFocused)
                            .onSubmit { commitRenameAction?() }
                            .onAppear { isRenameFocused = true }
                            .onExitCommand { cancelRenameAction?() }
                    } else {
                        Text(title)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(isActive ? .primary : .secondary)
                            .animation(.easeInOut(duration: 0.12), value: isSelected)
                    }

                    Spacer(minLength: 4)

                    if shouldShowTrailingText, let trailingText {
                        Text(trailingText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.quaternary)
                            .monospacedDigit()
                    }
                }
                .padding(.leading, leadingIndent)
                .frame(maxWidth: .infinity, alignment: .leading)

                // Trailing controls
                if shouldShowMenuAction, let menuAction {
                    Menu {
                        Button(role: .destructive, action: menuAction) {
                            Label(menuTitle, systemImage: menuSystemImage)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.mayuElevatedBackground)
                            }
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
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 28, height: 28)
                                        .background {
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .fill(Color.mayuElevatedBackground)
                                        }
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .opacity(isHovered ? 1 : 0)
                                .transition(.scale(scale: 0.8).combined(with: .opacity))
                            }
                        } else {
                            Button(action: trailingAction) {
                                Image(systemName: trailingSystemImage)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .opacity(isActive ? 1 : 0.65)
                        }
                    } else {
                        Image(systemName: trailingSystemImage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }

                if isRenaming {
                    HStack(spacing: 4) {
                        Button(action: cancelRenameAction ?? {}) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 24, height: 24)
                                .background {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(Color.mayuElevatedBackground)
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button(action: commitRenameAction ?? {}) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.mayuAccent)
                                .frame(width: 24, height: 24)
                                .background {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(Color.mayuAccentSoft)
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(minHeight: 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(rowBackground)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isRenaming { action() }
        }
        .accessibilityAddTraits(.isButton)
        .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isHovered)
        .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isSelected)
        .onHover { isHovered = $0 }
    }

    private var isActive: Bool { isSelected || isHovered || isRenaming }

    private var shouldShowTrailingText: Bool {
        trailingText != nil && (!trailingUsesMenu || !isHovered) && !isRenaming
    }

    private var shouldShowTrailingMenu: Bool {
        trailingUsesMenu && isHovered && !isRenaming
    }

    private var shouldShowMenuAction: Bool {
        menuAction != nil && (!menuShowsOnHover || isHovered) && !isRenaming
    }

    private var rowBackground: Color {
        if isSelected { return Color.mayuSelection }
        return isHovered ? Color.mayuSelection.opacity(0.55) : .clear
    }
}

// MARK: - Empty Row

struct EmptySidebarRow: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.quaternary)

            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Empty State (hero)

struct SidebarEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String
    let actionTitle: String
    let action: () -> Void
    @State private var isActionHovered = false

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.mayuAccentSoft)
                    .overlay {
                        Circle().stroke(Color.mayuStrongBorder.opacity(0.4), lineWidth: 1)
                    }

                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.mayuAccent)
            }
            .frame(width: 44, height: 44)

            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: action) {
                Text(actionTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.mayuOnAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background {
                        Capsule().fill(Color.mayuAccentSolid.opacity(isActionHovered ? 0.9 : 1))
                    }
            }
            .buttonStyle(.plain)
            .scaleEffect(isActionHovered ? 1.03 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isActionHovered)
            .onHover { isActionHovered = $0 }
        }
        .padding(.horizontal, 20)
        .padding(.top, 30)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity)
    }
}
