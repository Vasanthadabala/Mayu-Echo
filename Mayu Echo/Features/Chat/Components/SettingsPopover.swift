import SwiftUI

struct SettingsPopover: View {
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Profile header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.mayuAccentSoft)
                        .overlay {
                            Circle()
                                .stroke(Color.mayuStrongBorder.opacity(0.5), lineWidth: 1)
                        }

                    Image(systemName: "person.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.mayuAccent)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text("vasanthleoadabala")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Personal account")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.mayuElevatedBackground.opacity(0.6))

            Rectangle()
                .fill(Color.mayuBorder.opacity(0.55))
                .frame(height: 1)
                .padding(.bottom, 6)

            VStack(alignment: .leading, spacing: 2) {
                PopoverMenuRow(title: "Profile", systemImage: "person.circle")
                PopoverMenuRow(
                    title: "Settings",
                    systemImage: "gearshape",
                    shortcut: "⌘,"
                ) {
                    openSettings()
                }
            }
            .padding(.horizontal, 8)

            Rectangle()
                .fill(Color.mayuBorder.opacity(0.55))
                .frame(height: 1)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: 2) {
                PopoverMenuRow(
                    title: "Usage remaining",
                    systemImage: "gauge.with.dots.needle.67percent",
                    showsChevron: true
                )
                PopoverMenuRow(
                    title: "Log out",
                    systemImage: "rectangle.portrait.and.arrow.right",
                    foregroundStyle: .secondary
                )
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
        .frame(width: 300)
        .background(Color.mayuPanelBackground)
    }
}

private struct PopoverMenuRow: View {
    let title: String
    let systemImage: String
    var foregroundStyle: HierarchicalShapeStyle = .primary
    var shortcut: String?
    var showsChevron = false
    var action: () -> Void = {}
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovered ? Color.mayuAccentSoft : Color.mayuElevatedBackground)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.mayuBorder.opacity(0.4), lineWidth: 1)
                        }

                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isHovered ? Color.mayuAccent : .secondary)
                }
                .frame(width: 26, height: 26)
                .animation(.easeInOut(duration: 0.12), value: isHovered)

                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                }

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(foregroundStyle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Color.mayuSelection.opacity(0.7) : .clear)
        }
        .animation(.easeInOut(duration: 0.1), value: isHovered)
        .onHover { isHovered = $0 }
    }
}
