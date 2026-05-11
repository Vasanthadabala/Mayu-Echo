//
//  ContentView.swift
//  Mayu Echo
//
//  Created by Vasanth on 06/05/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Item.timestamp, order: .reverse) private var items: [Item]
    @State private var selectedItemID: PersistentIdentifier?
    @State private var isPickingProject = false
    @State private var isProjectsExpanded = true
    @State private var isChatsExpanded = true
    @State private var isShowingSettingsMenu = false
    @State private var selectedDestination: DetailDestination = .chat
    @State private var renamingItemID: PersistentIdentifier?
    @State private var renameDraft = ""

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
            switch selectedDestination {
            case .chat:
                ChatDetailView(item: selectedItem, ensureChat: ensureChatForDetail)
            case .aiModels:
                AIModelsView()
            }
        }
        .fileImporter(
            isPresented: $isPickingProject,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: handleProjectPick
        )
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                SidebarActionButton(title: "New chat", systemImage: "square.and.pencil", action: addChat)
                SidebarActionButton(title: "Search", systemImage: "magnifyingglass", action: {})
                SidebarActionButton(
                    title: "AI Models",
                    systemImage: "cpu",
                    isSelected: selectedDestination == .aiModels
                ) {
                    selectedDestination = .aiModels
                }
            }
            .padding(6)
            .background(Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.clear, lineWidth: 1)
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
                                    isSelected: selectedDestination == .chat && project.persistentModelID == selectedItemID,
                                    trailingSystemImage: "square.and.pencil",
                                    menuAction: selectedDestination == .chat && project.persistentModelID == selectedItemID ? { deleteProject(project) } : nil,
                                    menuShowsOnHover: true,
                                    trailingAction: { addChat(to: project) }
                                ) {
                                    selectedDestination = .chat
                                    selectedItemID = project.persistentModelID
                                }

                                ForEach(chats(for: project)) { chat in
                                    SidebarItemRow(
                                        title: chat.title,
                                        systemImage: nil,
                                        isSelected: selectedDestination == .chat && chat.persistentModelID == selectedItemID,
                                        trailingSystemImage: "ellipsis",
                                        trailingText: relativeTime(for: chat.timestamp),
                                        leadingIndent: 26,
                                        trailingUsesMenu: true,
                                        isRenaming: renamingItemID == chat.persistentModelID,
                                        renameText: $renameDraft,
                                        renameAction: { beginRename(chat) },
                                        commitRenameAction: { commitRename(chat) },
                                        cancelRenameAction: cancelRename,
                                        trailingAction: { deleteChat(chat) }
                                    ) {
                                        selectedDestination = .chat
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
                                isSelected: selectedDestination == .chat && chat.persistentModelID == selectedItemID,
                                trailingSystemImage: "ellipsis",
                                trailingText: relativeTime(for: chat.timestamp),
                                trailingUsesMenu: true,
                                isRenaming: renamingItemID == chat.persistentModelID,
                                renameText: $renameDraft,
                                renameAction: { beginRename(chat) },
                                commitRenameAction: { commitRename(chat) },
                                cancelRenameAction: cancelRename,
                                trailingAction: { deleteChat(chat) }
                            ) {
                                selectedDestination = .chat
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
        .background(Color.mayuSidebarBackground)
    }

    private var selectedItem: Item? {
        items.first { item in
            item.persistentModelID == selectedItemID
        }
    }

    private func addChat() {
        selectedDestination = .chat

        if let selectedItem, selectedItem.isProject {
            addChat(to: selectedItem)
            return
        }

        _ = createRootChat()
    }

    private func addChat(to project: Item) {
        selectedDestination = .chat

        _ = createChat(in: project)
    }

    private func ensureChatForDetail() -> Item? {
        selectedDestination = .chat

        if let selectedItem, selectedItem.isProject {
            if let existingChat = chats(for: selectedItem).first {
                selectedItemID = existingChat.persistentModelID
                return existingChat
            }

            return createChat(in: selectedItem)
        }

        if let selectedItem {
            return selectedItem
        }

        return createRootChat()
    }

    @discardableResult
    private func createRootChat() -> Item {
        let chatNumber = chats.count + 1
        let newItem = Item(timestamp: Date(), title: "New chat \(chatNumber)")

        modelContext.insert(newItem)
        saveContext()

        withAnimation {
            selectedItemID = newItem.persistentModelID
        }

        return newItem
    }

    @discardableResult
    private func createChat(in project: Item) -> Item {
        let projectChats = chats(for: project)
        let newItem = Item(
            timestamp: Date(),
            title: "New chat \(projectChats.count + 1)",
            parentProjectPath: project.projectPath,
            projectBookmarkData: project.projectBookmarkData
        )

        modelContext.insert(newItem)
        saveContext()

        withAnimation {
            selectedItemID = newItem.persistentModelID
        }

        return newItem
    }

    private func chats(for project: Item) -> [Item] {
        var chatsByID: [PersistentIdentifier: Item] = [:]
        let queryChats = items.filter { item in
            !item.isProject && item.parentProjectPath == project.projectPath
        }

        for chat in queryChats {
            chatsByID[chat.persistentModelID] = chat
        }

        do {
            let descriptor = FetchDescriptor<Item>(
                sortBy: [SortDescriptor(\Item.timestamp, order: .reverse)]
            )
            let storedChats = try modelContext.fetch(descriptor).filter { item in
                !item.isProject && item.parentProjectPath == project.projectPath
            }

            for chat in storedChats {
                chatsByID[chat.persistentModelID] = chat
            }
        } catch {
            assertionFailure("Failed to fetch project chats: \(error.localizedDescription)")
        }

        return chatsByID.values.sorted { lhs, rhs in
            lhs.timestamp > rhs.timestamp
        }
    }

    private func handleProjectPick(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result, let url = urls.first else {
            return
        }

        let isAccessing = url.startAccessingSecurityScopedResource()
        let bookmarkData = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        let project = Item(
            timestamp: Date(),
            title: url.lastPathComponent,
            isProject: true,
            projectPath: url.path,
            projectBookmarkData: bookmarkData
        )
        modelContext.insert(project)
        saveContext()

        withAnimation {
            selectedDestination = .chat
            selectedItemID = project.persistentModelID
        }

        if isAccessing {
            url.stopAccessingSecurityScopedResource()
        }
    }

    private func deleteChat(_ chat: Item) {
        withAnimation {
            if chat.persistentModelID == selectedItemID {
                selectedItemID = nil
            }

            if chat.persistentModelID == renamingItemID {
                cancelRename()
            }

            modelContext.delete(chat)
        }

        saveContext()
    }

    private func beginRename(_ item: Item) {
        selectedDestination = .chat
        selectedItemID = item.persistentModelID
        renamingItemID = item.persistentModelID
        renameDraft = item.title
    }

    private func commitRename(_ item: Item) {
        let newTitle = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newTitle.isEmpty else {
            cancelRename()
            return
        }

        withAnimation {
            item.title = newTitle
        }

        cancelRename()
        saveContext()
    }

    private func cancelRename() {
        renamingItemID = nil
        renameDraft = ""
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

                if chat.persistentModelID == renamingItemID {
                    cancelRename()
                }

                modelContext.delete(chat)
            }

            modelContext.delete(project)
        }

        saveContext()
    }

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Failed to save sidebar changes: \(error.localizedDescription)")
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

private enum DetailDestination {
    case chat
    case aiModels
}
