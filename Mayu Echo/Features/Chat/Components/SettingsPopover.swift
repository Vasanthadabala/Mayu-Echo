import SwiftUI

struct SettingsPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsMenuRow(
                title: "vasanthleoadabala@gmail.com",
                systemImage: "person.circle.fill",
                foregroundStyle: .secondary
            )

            Divider()
                .padding(.vertical, 8)

            SettingsMenuRow(title: "Settings", systemImage: "gearshape")

            Divider()
                .padding(.vertical, 8)

            SettingsMenuRow(title: "Log out", systemImage: "rectangle.portrait.and.arrow.right")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(width: 560)
    }
}

private struct SettingsMenuRow: View {
    let title: String
    let systemImage: String
    var foregroundStyle: HierarchicalShapeStyle = .primary
    var showsChevron = false

    var body: some View {
        Button(action: {}) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 18))
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 18))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 12)

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(foregroundStyle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
    }
}
