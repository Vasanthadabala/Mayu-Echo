import SwiftUI
import AppKit

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

// MARK: - File system browsing

struct ProjectFileNode: Identifiable, Equatable {
    let id: String
    let name: String
    let path: String
    let isDirectory: Bool
}

enum ProjectFileBrowser {
    private static let ignoredNames: Set<String> = [
        ".git", ".build", ".swiftpm", "node_modules", "DerivedData",
        ".DS_Store", "Pods", ".index-build", ".xcodeproj", ".xcworkspace"
    ]

    static func children(of directoryPath: String) -> [ProjectFileNode] {
        let fileManager = FileManager.default

        guard let entries = try? fileManager.contentsOfDirectory(atPath: directoryPath) else {
            return []
        }

        let nodes: [ProjectFileNode] = entries.compactMap { name in
            guard !name.hasPrefix("."), !ignoredNames.contains(name) else {
                return nil
            }

            let fullPath = (directoryPath as NSString).appendingPathComponent(name)
            var isDirectory: ObjCBool = false

            guard fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory) else {
                return nil
            }

            return ProjectFileNode(id: fullPath, name: name, path: fullPath, isDirectory: isDirectory.boolValue)
        }

        return nodes.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    static func readTextContent(atPath path: String, maxBytes: Int = 400_000) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? Int,
              size <= maxBytes,
              let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        return text
    }
}

// MARK: - Sidebar tree

struct ProjectCodeSection: View {
    let project: Item
    @Binding var expandedPaths: Set<String>
    @Binding var selectedFilePath: String?
    let selectFile: (String) -> Void
    var removeProject: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            FileTreeRow(
                name: project.title,
                isDirectory: true,
                depth: 0,
                isExpanded: isExpanded,
                isSelected: false,
                select: toggleProject,
                removeAction: removeProject
            )

            if let projectPath = project.projectPath, isExpanded {
                FileTreeChildren(
                    directoryPath: projectPath,
                    depth: 1,
                    expandedPaths: $expandedPaths,
                    selectedFilePath: $selectedFilePath,
                    selectFile: selectFile
                )
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

private struct FileTreeChildren: View {
    let directoryPath: String
    let depth: Int
    @Binding var expandedPaths: Set<String>
    @Binding var selectedFilePath: String?
    let selectFile: (String) -> Void

    var body: some View {
        let nodes = ProjectFileBrowser.children(of: directoryPath)

        if nodes.isEmpty {
            EmptySidebarRow(title: "Empty folder")
                .padding(.leading, CGFloat(depth) * 14)
        } else {
            ForEach(nodes) { node in
                VStack(alignment: .leading, spacing: 2) {
                    FileTreeRow(
                        name: node.name,
                        isDirectory: node.isDirectory,
                        depth: depth,
                        isExpanded: expandedPaths.contains(node.path),
                        isSelected: selectedFilePath == node.path,
                        select: {
                            if node.isDirectory {
                                toggleExpansion(node.path)
                            } else {
                                selectedFilePath = node.path
                                selectFile(node.path)
                            }
                        }
                    )

                    if node.isDirectory && expandedPaths.contains(node.path) {
                        FileTreeChildren(
                            directoryPath: node.path,
                            depth: depth + 1,
                            expandedPaths: $expandedPaths,
                            selectedFilePath: $selectedFilePath,
                            selectFile: selectFile
                        )
                    }
                }
            }
        }
    }

    private func toggleExpansion(_ path: String) {
        withAnimation(.easeInOut(duration: 0.12)) {
            if expandedPaths.contains(path) {
                expandedPaths.remove(path)
            } else {
                expandedPaths.insert(path)
            }
        }
    }
}

private struct FileTreeRow: View {
    let name: String
    let isDirectory: Bool
    let depth: Int
    let isExpanded: Bool
    let isSelected: Bool
    let select: () -> Void
    var removeAction: (() -> Void)? = nil
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            if isDirectory {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 10)
            } else {
                Color.clear.frame(width: 10)
            }

            Image(systemName: iconName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isDirectory ? Color.mayuAccent : .secondary)
                .frame(width: 16)

            Text(name)
                .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : (isDirectory ? .primary : .secondary))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

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
                .opacity(isHovered ? 1 : 0)
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
        .onTapGesture(perform: select)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }

    private var iconName: String {
        guard !isDirectory else {
            return isExpanded ? "folder.fill" : "folder"
        }

        switch (name as NSString).pathExtension.lowercased() {
        case "swift", "js", "ts", "tsx", "jsx", "py", "rb", "go", "rs", "c", "cpp", "h", "hpp", "java", "kt":
            return "chevron.left.forwardslash.chevron.right"
        case "json", "yml", "yaml", "plist", "xml":
            return "curlybraces"
        case "md", "txt":
            return "doc.text"
        case "png", "jpg", "jpeg", "gif", "svg", "pdf":
            return "photo"
        default:
            return "doc"
        }
    }
}

// MARK: - Detail file viewer

struct CodeFileViewerView: View {
    let filePath: String
    @State private var content: String?
    @State private var isUnavailable = false
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider().background(Color.mayuBorder)

            ScrollView([.vertical, .horizontal]) {
                if let content {
                    Text(content)
                        .font(.system(size: 13, design: .monospaced))
                        .lineSpacing(5)
                        .foregroundStyle(.primary.opacity(0.92))
                        .textSelection(.enabled)
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if isUnavailable {
                    emptyState(message: "Can't preview this file — it may be binary or too large.")
                } else {
                    emptyState(message: "Loading…")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.mayuChatBackground)
        .onAppear(perform: load)
        .onChange(of: filePath) {
            content = nil
            isUnavailable = false
            load()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.mayuAccent)

            Text((filePath as NSString).lastPathComponent)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            Text(filePath)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button(action: copyContent) {
                HStack(spacing: 5) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    Text(copied ? "Copied" : "Copy")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(copied ? Color.mayuAccent : .secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background {
                    Capsule()
                        .fill(Color.mayuElevatedBackground)
                        .overlay {
                            Capsule().stroke(Color.mayuBorder.opacity(0.6), lineWidth: 1)
                        }
                }
            }
            .buttonStyle(.plain)
            .disabled(content == nil)
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
    }

    private func emptyState(message: String) -> some View {
        Text(message)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 200)
    }

    private func load() {
        let path = filePath

        DispatchQueue.global(qos: .userInitiated).async {
            let text = ProjectFileBrowser.readTextContent(atPath: path)

            DispatchQueue.main.async {
                guard path == filePath else { return }

                if let text {
                    content = text
                } else {
                    isUnavailable = true
                }
            }
        }
    }

    private func copyContent() {
        guard let content else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        copied = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            copied = false
        }
    }
}
