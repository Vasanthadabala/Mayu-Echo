//
//  ContentView.swift
//  Mayu Echo
//
//  Created by Vasanth on 06/05/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

private extension Color {
    static let mayuAccent = Color(red: 1.0, green: 0.78, blue: 0.22)
}

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Item.timestamp, order: .reverse) private var items: [Item]
    @State private var selectedItemID: PersistentIdentifier?
    @State private var isPickingProject = false
    @State private var isProjectsExpanded = true
    @State private var isChatsExpanded = true
    @State private var isShowingSettingsMenu = false

    private var projects: [Item] {
        items.filter(\.isProject)
    }

    private var chats: [Item] {
        items.filter { !$0.isProject && $0.parentProjectPath == nil }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 280, ideal: 300)
        } detail: {
            ChatDetailView(item: selectedItem)
        }
        .fileImporter(
            isPresented: $isPickingProject,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: handleProjectPick
        )
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                SidebarActionButton(title: "New chat", systemImage: "square.and.pencil", action: addChat)
                SidebarActionButton(title: "Search", systemImage: "magnifyingglass", action: {})
                SidebarActionButton(title: "AI Models", systemImage: "cpu", action: {})
            }
            .padding(6)
            .background(Color.mayuAccent.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.mayuAccent.opacity(0.16), lineWidth: 1)
            }

            SidebarDivider()

            SidebarSection(
                title: "Projects",
                trailingSystemImage: "folder.badge.plus",
                trailingAction: { isPickingProject = true },
                isExpanded: isProjectsExpanded,
                toggleExpansion: {
                    withAnimation(.snappy) {
                        isProjectsExpanded.toggle()
                    }
                }
            ) {
                if isProjectsExpanded {
                    if projects.isEmpty {
                        EmptySidebarRow(title: "Pick a project folder")
                    } else {
                        ForEach(projects) { project in
                            VStack(alignment: .leading, spacing: 4) {
                                SidebarItemRow(
                                    title: project.title,
                                    systemImage: "folder",
                                    isSelected: project.persistentModelID == selectedItemID,
                                    trailingSystemImage: "square.and.pencil",
                                    menuAction: project.persistentModelID == selectedItemID ? { deleteProject(project) } : nil,
                                    trailingAction: { addChat(to: project) }
                                ) {
                                    selectedItemID = project.persistentModelID
                                }

                                ForEach(chats(for: project)) { chat in
                                    SidebarItemRow(
                                        title: chat.title,
                                        systemImage: nil,
                                        isSelected: chat.persistentModelID == selectedItemID,
                                        trailingSystemImage: "ellipsis",
                                        trailingText: relativeTime(for: chat.timestamp),
                                        leadingIndent: 26,
                                        trailingUsesMenu: true,
                                        trailingAction: { deleteChat(chat) }
                                    ) {
                                        selectedItemID = chat.persistentModelID
                                    }
                                }
                            }
                        }
                    }
                }
            }

            SidebarDivider()

            SidebarSection(
                title: "Chats",
                trailingSystemImage: "square.and.pencil",
                trailingAction: addChat,
                isExpanded: isChatsExpanded,
                toggleExpansion: {
                    withAnimation(.snappy) {
                        isChatsExpanded.toggle()
                    }
                }
            ) {
                if isChatsExpanded {
                    if chats.isEmpty {
                        EmptySidebarRow(title: "No chats yet")
                    } else {
                        ForEach(chats) { chat in
                            SidebarItemRow(
                                title: chat.title,
                                systemImage: nil,
                                isSelected: chat.persistentModelID == selectedItemID,
                                trailingSystemImage: "ellipsis",
                                trailingText: relativeTime(for: chat.timestamp),
                                trailingUsesMenu: true,
                                trailingAction: { deleteChat(chat) }
                            ) {
                                selectedItemID = chat.persistentModelID
                            }
                        }
                    }
                }
            }

            Spacer()

            SidebarActionButton(title: "Settings", systemImage: "gearshape") {
                isShowingSettingsMenu.toggle()
            }
            .popover(isPresented: $isShowingSettingsMenu, arrowEdge: .bottom) {
                SettingsPopover()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                LinearGradient(
                    colors: [
                        Color.mayuAccent.opacity(0.08),
                        Color(nsColor: .windowBackgroundColor).opacity(0.96)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private var selectedItem: Item? {
        items.first { item in
            item.persistentModelID == selectedItemID
        }
    }

    private func addChat() {
        if let selectedItem, selectedItem.isProject {
            addChat(to: selectedItem)
            return
        }

        withAnimation {
            let chatNumber = chats.count + 1
            let newItem = Item(timestamp: Date(), title: "New chat \(chatNumber)")
            modelContext.insert(newItem)
            selectedItemID = newItem.persistentModelID
        }
    }

    private func addChat(to project: Item) {
        withAnimation {
            let projectChats = chats(for: project)
            let newItem = Item(
                timestamp: Date(),
                title: "New chat \(projectChats.count + 1)",
                parentProjectPath: project.projectPath
            )
            modelContext.insert(newItem)
            selectedItemID = newItem.persistentModelID
        }
    }

    private func chats(for project: Item) -> [Item] {
        items.filter { item in
            !item.isProject && item.parentProjectPath == project.projectPath
        }
    }

    private func handleProjectPick(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result, let url = urls.first else {
            return
        }

        withAnimation {
            let project = Item(
                timestamp: Date(),
                title: url.lastPathComponent,
                isProject: true,
                projectPath: url.path
            )
            modelContext.insert(project)
            selectedItemID = project.persistentModelID
        }
    }

    private func deleteChat(_ chat: Item) {
        withAnimation {
            if chat.persistentModelID == selectedItemID {
                selectedItemID = nil
            }

            modelContext.delete(chat)
        }
    }

    private func deleteProject(_ project: Item) {
        withAnimation {
            if project.persistentModelID == selectedItemID {
                selectedItemID = nil
            }

            for chat in chats(for: project) {
                if chat.persistentModelID == selectedItemID {
                    selectedItemID = nil
                }

                modelContext.delete(chat)
            }

            modelContext.delete(project)
        }
    }

    private func relativeTime(for date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))

        switch seconds {
        case ..<60:
            return "now"
        case ..<3_600:
            return "\(seconds / 60)m"
        case ..<86_400:
            return "\(seconds / 3_600)h"
        default:
            return "\(seconds / 86_400)d"
        }
    }
}

private struct ChatDetailView: View {
    let item: Item?
    @State private var message = ""

    var body: some View {
        VStack(spacing: 0) {
            if let item {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center, spacing: 14) {
                        Image(systemName: item.isProject ? "folder" : "bubble.left.and.text.bubble.right")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 36)
                            .background(Color.mayuAccent.opacity(0.16))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title)
                                .font(.system(size: 28, weight: .semibold))
                                .lineLimit(1)
                                .truncationMode(.tail)

                            if let path = item.projectPath {
                                Text(path)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            } else {
                                Text(relativeDetailTime(for: item.timestamp))
                                    .font(.system(size: 13))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    Divider()
                        .opacity(0.5)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 34)
                .padding(.top, 30)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 58, height: 58)
                        .background(Color.mayuAccent.opacity(0.16))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Text("New chat")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            MessageComposer(message: $message, sendMessage: sendMessage)
                .padding(.horizontal, 28)
                .padding(.top, 16)
                .padding(.bottom, 22)
        }
        .background {
            ZStack {
                Color(nsColor: .textBackgroundColor)
                LinearGradient(
                    colors: [
                        Color.mayuAccent.opacity(0.06),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    private func sendMessage() {
        message = ""
    }

    private func relativeDetailTime(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct MessageComposer: View {
    @Binding var message: String
    let sendMessage: () -> Void
    @State private var selectedModel = "Model 1"
    @State private var selectedEffort = "Medium"
    @State private var inputHeight = ChatInputTextView.minimumHeight

    private var canSend: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                ChatInputTextView(
                    text: $message,
                    height: $inputHeight,
                    onSubmit: sendIfPossible
                )
                .frame(height: inputHeight, alignment: .topLeading)

                if message.isEmpty {
                    Text("Ask for follow-up changes")
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 12)

            HStack(spacing: 16) {
                Button(action: {}) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .regular))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Menu {
                    Button("Default permissions", action: {})
                } label: {
                    Label {
                        HStack(spacing: 6) {
                            Text("Default permissions")
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .medium))
                        }
                    } icon: {
                        Image(systemName: "hand.raised")
                    }
                    .font(.system(size: 16))
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.plain)

                Spacer()

                Menu {
                    Text("Intelligence")

                    IntelligenceMenuButton(title: "Low", selection: $selectedEffort)
                    IntelligenceMenuButton(title: "Medium", selection: $selectedEffort)
                    IntelligenceMenuButton(title: "High", selection: $selectedEffort)
                    IntelligenceMenuButton(title: "Extra High", selection: $selectedEffort)

                    Divider()

                    Menu("Models") {
                        ModelMenuButton(title: "Model 1", selection: $selectedModel)
                        ModelMenuButton(title: "Model 2", selection: $selectedModel)

                        Menu("More") {
                            ModelMenuButton(title: "Model 3", selection: $selectedModel)
                            ModelMenuButton(title: "Model 4", selection: $selectedModel)
                            ModelMenuButton(title: "Model 5", selection: $selectedModel)
                        }
                    }
                } label: {
                    HStack(spacing: 7) {
                        Text(selectedModel)
                            .foregroundStyle(.primary)
                        Text(selectedEffort)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 17))
                    .fixedSize()
                    .layoutPriority(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.mayuAccent.opacity(0.18))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button(action: {}) {
                    Image(systemName: "mic")
                        .font(.system(size: 18))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(Color(nsColor: .textBackgroundColor))
                        .frame(width: 46, height: 46)
                        .background(canSend ? Color.mayuAccent.opacity(0.95) : Color.mayuAccent.opacity(0.32))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .foregroundStyle(.secondary)
            .padding(.leading, 18)
            .padding(.trailing, 12)
            .padding(.bottom, 12)
        }
        .background(Color.mayuAccent.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.mayuAccent.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 22, y: 8)
    }

    private func sendIfPossible() {
        guard canSend else {
            return
        }

        sendMessage()
    }
}

private struct IntelligenceMenuButton: View {
    let title: String
    @Binding var selection: String

    var body: some View {
        Button {
            selection = title
        } label: {
            if selection == title {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}

private struct ModelMenuButton: View {
    let title: String
    @Binding var selection: String

    var body: some View {
        Button {
            selection = title
        } label: {
            if selection == title {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}

private struct ChatInputTextView: NSViewRepresentable {
    static let minimumHeight: CGFloat = 22
    static let maximumHeight: CGFloat = 176

    @Binding var text: String
    @Binding var height: CGFloat
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, height: $height)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = SubmitTextView()

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = height >= Self.maximumHeight
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.documentView = textView

        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.string = text
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = .systemFont(ofSize: 17)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = NSSize(width: 0, height: Self.minimumHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: Self.maximumHeight)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        context.coordinator.updateHeight(for: textView)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? SubmitTextView else {
            return
        }

        textView.onSubmit = onSubmit
        nsView.hasVerticalScroller = height >= Self.maximumHeight

        if textView.string != text {
            textView.string = text
        }

        context.coordinator.updateHeight(for: textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        @Binding private var height: CGFloat

        init(text: Binding<String>, height: Binding<CGFloat>) {
            _text = text
            _height = height
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }

            text = textView.string
            updateHeight(for: textView)
        }

        func updateHeight(for textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                return
            }

            layoutManager.ensureLayout(for: textContainer)

            let measuredHeight = ceil(layoutManager.usedRect(for: textContainer).height)
            let nextHeight = min(
                max(measuredHeight, ChatInputTextView.minimumHeight),
                ChatInputTextView.maximumHeight
            )

            guard abs(height - nextHeight) > 0.5 else {
                return
            }

            DispatchQueue.main.async {
                self.height = nextHeight
            }
        }
    }
}

private final class SubmitTextView: NSTextView {
    var onSubmit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        let isShiftPressed = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift)

        if isReturn && !isShiftPressed {
            onSubmit?()
            return
        }

        super.keyDown(with: event)
    }
}

private struct SettingsPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsMenuRow(
                title: "vasanthleoadabala@gmail.com",
                systemImage: "person.circle.fill",
                foregroundStyle: .secondary
            )

            SettingsMenuRow(
                title: "Personal account",
                systemImage: "gearshape",
                foregroundStyle: .secondary
            )

            Divider()
                .padding(.vertical, 8)

            SettingsMenuRow(title: "Settings", systemImage: "gearshape")

            Divider()
                .padding(.vertical, 8)

            SettingsMenuRow(
                title: "Rate limits remaining",
                systemImage: "gauge.with.dots.needle.33percent",
                showsChevron: true
            )

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

private struct SidebarActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

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
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct SidebarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.mayuAccent.opacity(0.22))
            .frame(height: 1)
            .padding(.horizontal, 4)
    }
}

private struct SidebarSection<Content: View>: View {
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

private struct SidebarItemRow: View {
    let title: String
    let systemImage: String?
    let isSelected: Bool
    var trailingSystemImage: String?
    var trailingText: String?
    var leadingIndent: CGFloat = 0
    var trailingUsesMenu = false
    var menuAction: (() -> Void)?
    var trailingAction: (() -> Void)?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: action) {
                HStack(spacing: 10) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                    }

                    Text(title)
                        .font(.system(size: 16, weight: isSelected ? .medium : .regular))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 8)

                    if let trailingText {
                        Text(trailingText)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, leadingIndent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let menuAction {
                Menu {
                    Button(role: .destructive, action: menuAction) {
                        Label("Remove", systemImage: "xmark")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if let trailingSystemImage {
                if let trailingAction {
                    if trailingUsesMenu {
                        Menu {
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
                    } else {
                        Button(action: trailingAction) {
                            Image(systemName: trailingSystemImage)
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .frame(width: 34, height: 34)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Image(systemName: trailingSystemImage)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .foregroundStyle(isSelected ? .primary : .secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.mayuAccent.opacity(0.20) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.mayuAccent.opacity(0.30) : Color.clear, lineWidth: 1)
        }
    }
}

private struct EmptySidebarRow: View {
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
