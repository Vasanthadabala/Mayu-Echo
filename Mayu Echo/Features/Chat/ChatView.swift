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
    @EnvironmentObject private var appSettings: AppSettings
    @Query(sort: \Item.timestamp, order: .reverse) private var items: [Item]
    @State private var selectedItemID: PersistentIdentifier?
    @State private var isPickingProject = false
    @State private var isChatsExpanded = true
    @State private var isShowingSettingsMenu = false
    @State private var selectedDestination: DetailDestination = .chat
    @State private var renamingItemID: PersistentIdentifier?
    @State private var renameDraft = ""
    @State private var isSearchPresented = false
    @State private var sidebarMode: SidebarMode = .home
    @State private var expandedCodePaths: Set<String> = []

    private var projects: [Item] {
        items.filter(\.isProject)
    }

    /// Standalone chats shown in the Chat tab. Project-scoped chats live under their
    /// folder in the Code tab, not here.
    private var chats: [Item] {
        items.filter { !$0.isProject && $0.parentProjectPath == nil }
    }

    private var settingsAvailableModels: [LLMModel] {
        let downloader = HuggingFaceModelDownloader()
        return LLMModelCatalog.allModels.map { model in
            model.provider == .mlx ? downloader.modelWithLocalStatus(model) : model
        }
    }

    var body: some View {
        ZStack {
            // The NavigationSplitView is ALWAYS alive so ChatDetailView (and its
            // @StateObject ChatSessionViewModel) is never deallocated while the
            // LLM is generating. Settings is layered on top via ZStack.
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 280, ideal: 300)
            } detail: {
                switch selectedDestination {
                case .chat, .settings:
                    ChatDetailView(item: selectedItem, ensureChat: ensureChatForDetail)
                case .aiModels:
                    AIModelsView(backAction: { selectedDestination = .chat })
                }
            }
            .toolbar(selectedDestination == .settings ? .hidden : .automatic, for: .windowToolbar)

            // Settings screen overlaid — generation keeps running underneath.
            if selectedDestination == .settings {
                AppSettingsView(
                    availableModels: settingsAvailableModels,
                    backAction: {
                        selectedDestination = .chat
                    }
                )
                .transition(.opacity)
                .zIndex(1)
            }

            if isSearchPresented {
                SearchPaletteOverlay(
                    items: items,
                    isPresented: $isSearchPresented,
                    relativeTime: relativeTime,
                    selectItem: handleSearchSelection
                )
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: selectedDestination == .settings)
        .animation(.easeInOut(duration: 0.12), value: isSearchPresented)
        .fileImporter(
            isPresented: $isPickingProject,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: handleProjectPick
        )
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            SidebarHeader(openSearch: { isSearchPresented = true })
                .padding(.bottom, 10)

            SidebarModeSwitcher(mode: $sidebarMode)
                .padding(.bottom, 10)

            SidebarDivider()
                .padding(.bottom, 10)

            // Top actions
            VStack(alignment: .leading, spacing: 3) {
                SidebarActionButton(title: "New Chat", systemImage: "square.and.pencil", action: addChat)

                SidebarActionButton(
                    title: "AI Models",
                    systemImage: "cpu",
                    isSelected: selectedDestination == .aiModels
                ) {
                    selectedDestination = .aiModels
                }
            }

            SidebarDivider()
                .padding(.top, 10)
                .padding(.bottom, 14)

            // Scrollable sections
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if sidebarMode == .code {
                        SidebarSection(
                            title: "CODE",
                            trailingSystemImage: "folder.badge.plus",
                            trailingAction: { isPickingProject = true }
                        ) {
                            if projects.isEmpty {
                                SidebarEmptyState(
                                    icon: "folder.badge.plus",
                                    title: "No projects yet",
                                    subtitle: "Pick a folder to browse its files.",
                                    actionTitle: "Add Project",
                                    action: { isPickingProject = true }
                                )
                            } else {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(projects) { project in
                                        ProjectCodeSection(
                                            project: project,
                                            chats: chats(for: project),
                                            expandedPaths: $expandedCodePaths,
                                            selectedChatID: selectedDestination == .chat ? selectedItemID : nil,
                                            selectChat: { chat in
                                                selectedDestination = .chat
                                                selectedItemID = chat.persistentModelID
                                            },
                                            deleteChat: { chat in deleteChat(chat) },
                                            removeProject: { deleteProject(project) },
                                            addChat: {
                                                if let path = project.projectPath {
                                                    expandedCodePaths.insert(path)
                                                }
                                                selectedDestination = .chat
                                                _ = createChat(in: project)
                                            }
                                        )
                                    }
                                }
                            }
                        }
                    } else {
                        SidebarSection(
                            title: "CHATS",
                            trailingSystemImage: "square.and.pencil",
                            trailingAction: addChat,
                            isExpanded: isChatsExpanded,
                            toggleExpansion: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    isChatsExpanded.toggle()
                                }
                            }
                        ) {
                            if isChatsExpanded {
                                VStack(alignment: .leading, spacing: 2) {
                                    if chats.isEmpty {
                                        SidebarEmptyState(
                                            icon: "bubble.left.and.bubble.right",
                                            title: "No chats yet",
                                            subtitle: "Start a conversation with your local model.",
                                            actionTitle: "New Chat",
                                            action: addChat
                                        )
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
                        }
                    }
                }
            }

            Spacer()

            SidebarDivider()
                .padding(.vertical, 10)

            SidebarActionButton(title: "Settings", systemImage: "gearshape") {
                isShowingSettingsMenu.toggle()
            }
            .popover(isPresented: $isShowingSettingsMenu, arrowEdge: .bottom) {
                SettingsPopover {
                    isShowingSettingsMenu = false
                    selectedDestination = .settings
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.top, 16)
        .padding(.bottom, 14)
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

    private func handleSearchSelection(_ item: Item) {
        if item.isProject {
            sidebarMode = .code

            if let path = item.projectPath {
                expandedCodePaths.insert(path)
            }
        } else {
            sidebarMode = .home
            selectedDestination = .chat
            selectedItemID = item.persistentModelID
        }
    }
}

private enum DetailDestination: Equatable {
    case chat
    case aiModels
    case settings
}
