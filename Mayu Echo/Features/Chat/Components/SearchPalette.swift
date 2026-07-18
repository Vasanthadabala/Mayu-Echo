import SwiftUI
import SwiftData

struct SearchPaletteOverlay: View {
    let items: [Item]
    @Binding var isPresented: Bool
    let relativeTime: (Date) -> String
    let selectItem: (Item) -> Void

    @State private var query = ""
    @State private var highlightedIndex = 0
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            card
                .padding(.top, 90)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .onAppear { isFieldFocused = true }
        .onChange(of: query) { highlightedIndex = 0 }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard !filteredResults.isEmpty else { return .handled }
            highlightedIndex = min(highlightedIndex + 1, filteredResults.count - 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            highlightedIndex = max(highlightedIndex - 1, 0)
            return .handled
        }
        .onKeyPress(.return) {
            choose(highlightedItem)
            return .handled
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            searchField

            Divider().background(Color.mayuBorder)

            if filteredResults.isEmpty {
                Text("No matches")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 90)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(filteredResults.enumerated()), id: \.element.persistentModelID) { index, item in
                            SearchResultRow(
                                item: item,
                                isHighlighted: index == highlightedIndex,
                                relativeTime: relativeTime(item.timestamp),
                                action: { choose(item) }
                            )
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 420)
            }
        }
        .frame(width: 560)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.mayuPanelBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.mayuStrongBorder.opacity(0.6), lineWidth: 1)
                }
        }
        .shadow(color: .black.opacity(0.3), radius: 40, y: 20)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search chats and projects", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($isFieldFocused)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background {
                        Circle().fill(Color.mayuElevatedBackground)
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var filteredResults: [Item] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return items
        }

        return items.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    private var highlightedItem: Item? {
        guard filteredResults.indices.contains(highlightedIndex) else {
            return nil
        }

        return filteredResults[highlightedIndex]
    }

    private func choose(_ item: Item?) {
        guard let item else { return }

        selectItem(item)
        dismiss()
    }

    private func dismiss() {
        isPresented = false
    }
}

private struct SearchResultRow: View {
    let item: Item
    let isHighlighted: Bool
    let relativeTime: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isHighlighted ? Color.mayuOnAccent : .secondary)
                    .frame(width: 20)

                Text(item.title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(isHighlighted ? Color.mayuOnAccent : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Text(relativeTime)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isHighlighted ? Color.mayuOnAccent.opacity(0.8) : Color.secondary.opacity(0.7))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHighlighted ? Color.mayuAccentSolid : (isHovered ? Color.mayuSelection.opacity(0.6) : .clear))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var iconName: String {
        item.isProject || item.parentProjectPath != nil ? "chevron.left.forwardslash.chevron.right" : "bubble.left.and.bubble.right"
    }
}
