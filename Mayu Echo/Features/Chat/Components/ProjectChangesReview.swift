import SwiftUI
import Combine
import Foundation

nonisolated struct ProjectChangesSnapshot: Equatable, Sendable {
    var projectPath: String?
    var files: [ProjectChangedFile] = []
    var errorMessage: String?

    static let empty = ProjectChangesSnapshot()

    var hasProject: Bool {
        projectPath != nil
    }

    var hasChanges: Bool {
        !files.isEmpty
    }

    var changeCount: Int {
        files.count
    }

    var additions: Int {
        files.reduce(0) { $0 + $1.additions }
    }

    var deletions: Int {
        files.reduce(0) { $0 + $1.deletions }
    }

    var projectName: String {
        guard let projectPath else {
            return "Project"
        }

        return URL(fileURLWithPath: projectPath).lastPathComponent
    }

    var fileCountDescription: String {
        "\(changeCount) \(changeCount == 1 ? "file" : "files") changed"
    }
}

nonisolated struct ProjectChangedFile: Identifiable, Equatable, Sendable {
    let id: String
    let path: String
    let status: String
    let additions: Int
    let deletions: Int
    let diffLines: [ProjectDiffLine]

    init(
        path: String,
        status: String,
        additions: Int,
        deletions: Int,
        diffLines: [ProjectDiffLine]
    ) {
        self.id = path
        self.path = path
        self.status = status
        self.additions = additions
        self.deletions = deletions
        self.diffLines = diffLines
    }
}

nonisolated struct ProjectDiffLine: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case context
        case added
        case removed
        case hunk
        case note
    }

    let id: UUID
    let oldLine: Int?
    let newLine: Int?
    let content: String
    let kind: Kind

    init(oldLine: Int?, newLine: Int?, content: String, kind: Kind) {
        self.id = UUID()
        self.oldLine = oldLine
        self.newLine = newLine
        self.content = content
        self.kind = kind
    }
}

@MainActor
final class ProjectChangesViewModel: ObservableObject {
    @Published private(set) var snapshot = ProjectChangesSnapshot.empty
    @Published private(set) var isLoading = false

    private var projectPath: String?
    private var refreshTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?

    deinit {
        refreshTask?.cancel()
        pollingTask?.cancel()
    }

    func configure(projectPath: String?) {
        guard self.projectPath != projectPath else {
            return
        }

        self.projectPath = projectPath
        refreshTask?.cancel()
        pollingTask?.cancel()

        guard let projectPath else {
            snapshot = .empty
            isLoading = false
            return
        }

        snapshot = ProjectChangesSnapshot(projectPath: projectPath)
        startPolling()
    }

    func refresh() {
        guard let projectPath else {
            snapshot = .empty
            isLoading = false
            return
        }

        refreshTask?.cancel()
        isLoading = true

        refreshTask = Task { [weak self] in
            let nextSnapshot = await ProjectGitChangeLoader.load(projectPath: projectPath)

            guard !Task.isCancelled else {
                return
            }

            self?.snapshot = nextSnapshot
            self?.isLoading = false
        }
    }

    private func startPolling() {
        refresh()

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                self?.refresh()
            }
        }
    }
}

private struct ProjectGitChangeLoader {
    struct FileSeed {
        var path: String
        var status: String
        var additions = 0
        var deletions = 0
    }

    static func load(projectPath: String) async -> ProjectChangesSnapshot {
        await Task.detached(priority: .utility) {
            loadSnapshot(projectPath: projectPath)
        }.value
    }

    nonisolated private static func loadSnapshot(projectPath: String) -> ProjectChangesSnapshot {
        guard FileManager.default.fileExists(atPath: projectPath) else {
            return ProjectChangesSnapshot(
                projectPath: projectPath,
                errorMessage: "Project folder not found"
            )
        }

        guard runGit(["rev-parse", "--is-inside-work-tree"], in: projectPath)?.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else {
            return ProjectChangesSnapshot(
                projectPath: projectPath,
                errorMessage: "No git repository found"
            )
        }

        var seeds: [String: FileSeed] = [:]
        var orderedPaths: [String] = []

        for seed in parseStatus(runGit(["status", "--porcelain=v1", "--untracked-files=all"], in: projectPath) ?? "") {
            if seeds[seed.path] == nil {
                orderedPaths.append(seed.path)
            }

            seeds[seed.path] = seed
        }

        for seed in parseNumstat(runGit(["diff", "--numstat"], in: projectPath) ?? "") {
            if var existing = seeds[seed.path] {
                existing.additions = seed.additions
                existing.deletions = seed.deletions
                seeds[seed.path] = existing
            } else {
                orderedPaths.append(seed.path)
                seeds[seed.path] = seed
            }
        }

        let files = orderedPaths.compactMap { path -> ProjectChangedFile? in
            guard let seed = seeds[path] else {
                return nil
            }

            return ProjectChangedFile(
                path: seed.path,
                status: seed.status,
                additions: seed.additions,
                deletions: seed.deletions,
                diffLines: diffLines(for: seed, projectPath: projectPath)
            )
        }

        return ProjectChangesSnapshot(projectPath: projectPath, files: files)
    }

    nonisolated private static func parseStatus(_ output: String) -> [FileSeed] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { rawLine in
                let line = String(rawLine)
                guard line.count >= 4 else {
                    return nil
                }

                let status = String(line.prefix(2)).trimmingCharacters(in: .whitespaces)
                var path = String(line.dropFirst(3))

                if let renameRange = path.range(of: " -> ") {
                    path = String(path[renameRange.upperBound...])
                }

                path = path.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                return FileSeed(path: path, status: status.isEmpty ? "M" : status)
            }
    }

    nonisolated private static func parseNumstat(_ output: String) -> [FileSeed] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { rawLine in
                let parts = rawLine.split(separator: "\t", omittingEmptySubsequences: false)
                guard parts.count >= 3 else {
                    return nil
                }

                let additions = Int(parts[0]) ?? 0
                let deletions = Int(parts[1]) ?? 0
                let path = parts[2...].joined(separator: "\t")

                return FileSeed(
                    path: path,
                    status: "M",
                    additions: additions,
                    deletions: deletions
                )
            }
    }

    nonisolated private static func diffLines(for seed: FileSeed, projectPath: String) -> [ProjectDiffLine] {
        if seed.status == "??" {
            return untrackedFilePreview(path: seed.path, projectPath: projectPath)
        }

        let diff = runGit(
            ["diff", "--no-ext-diff", "--unified=6", "--", seed.path],
            in: projectPath
        ) ?? ""

        let parsedLines = parseDiff(diff)
        guard !parsedLines.isEmpty else {
            return [
                ProjectDiffLine(
                    oldLine: nil,
                    newLine: nil,
                    content: "No unstaged diff available for this file.",
                    kind: .note
                )
            ]
        }

        return parsedLines
    }

    nonisolated private static func parseDiff(_ diff: String) -> [ProjectDiffLine] {
        var rows: [ProjectDiffLine] = []
        var oldLine: Int?
        var newLine: Int?

        for rawLine in diff.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if rawLine.hasPrefix("diff --git") || rawLine.hasPrefix("index ") || rawLine.hasPrefix("--- ") || rawLine.hasPrefix("+++ ") {
                continue
            }

            if rawLine.hasPrefix("@@") {
                let starts = parseHunkStarts(rawLine)
                oldLine = starts.old
                newLine = starts.new
                rows.append(ProjectDiffLine(oldLine: nil, newLine: nil, content: rawLine, kind: .hunk))
                continue
            }

            guard oldLine != nil || newLine != nil else {
                continue
            }

            if rawLine.hasPrefix("+") {
                rows.append(ProjectDiffLine(
                    oldLine: nil,
                    newLine: newLine,
                    content: String(rawLine.dropFirst()),
                    kind: .added
                ))
                newLine = (newLine ?? 0) + 1
            } else if rawLine.hasPrefix("-") {
                rows.append(ProjectDiffLine(
                    oldLine: oldLine,
                    newLine: nil,
                    content: String(rawLine.dropFirst()),
                    kind: .removed
                ))
                oldLine = (oldLine ?? 0) + 1
            } else {
                rows.append(ProjectDiffLine(
                    oldLine: oldLine,
                    newLine: newLine,
                    content: rawLine.hasPrefix(" ") ? String(rawLine.dropFirst()) : rawLine,
                    kind: .context
                ))
                oldLine = (oldLine ?? 0) + 1
                newLine = (newLine ?? 0) + 1
            }
        }

        return rows
    }

    nonisolated private static func parseHunkStarts(_ line: String) -> (old: Int, new: Int) {
        let pattern = #"@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let oldRange = Range(match.range(at: 1), in: line),
              let newRange = Range(match.range(at: 2), in: line) else {
            return (1, 1)
        }

        return (Int(line[oldRange]) ?? 1, Int(line[newRange]) ?? 1)
    }

    nonisolated private static func untrackedFilePreview(path: String, projectPath: String) -> [ProjectDiffLine] {
        let projectURL = URL(fileURLWithPath: projectPath, isDirectory: true).standardizedFileURL
        let fileURL = projectURL.appendingPathComponent(path).standardizedFileURL

        guard fileURL.path.hasPrefix(projectURL.path),
              let data = try? Data(contentsOf: fileURL),
              data.count < 120_000,
              let text = String(data: data, encoding: .utf8) else {
            return [
                ProjectDiffLine(
                    oldLine: nil,
                    newLine: nil,
                    content: "Untracked file",
                    kind: .note
                )
            ]
        }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.prefix(140).enumerated().map { index, line in
            ProjectDiffLine(
                oldLine: nil,
                newLine: index + 1,
                content: String(line),
                kind: .added
            )
        }
    }

    nonisolated private static func runGit(_ arguments: [String], in projectPath: String) -> String? {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", projectPath] + arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: outputData, encoding: .utf8)
    }
}

struct ProjectChangesSummaryBar: View {
    let snapshot: ProjectChangesSnapshot
    let reviewAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.mayuAccent)

                HStack(spacing: 6) {
                    Text(snapshot.fileCountDescription)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    HStack(spacing: 4) {
                        Text("+\(snapshot.additions)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.mayuDiffAdded)

                        Text("-\(snapshot.deletions)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.mayuDiffRemoved)
                    }
                }
            }

            Spacer(minLength: 8)

            Button(action: reviewAction) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Review")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background {
                    Capsule()
                        .fill(Color.mayuSelection)
                        .overlay {
                            Capsule()
                                .stroke(Color.mayuStrongBorder.opacity(0.5), lineWidth: 1)
                        }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.mayuComposerBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.mayuBorder.opacity(0.55), lineWidth: 1)
                }
        }
    }
}

struct ProjectChangesReviewPanel: View {
    let snapshot: ProjectChangesSnapshot
    let isLoading: Bool
    let refresh: () -> Void
    let close: () -> Void
    @State private var expandedFileIDs: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            topBar

            Divider()
                .background(Color.mayuBorder)

            if snapshot.hasChanges {
                reviewContent
            } else {
                emptyState
            }
        }
        .background(Color.mayuChatBackground)
        .onAppear {
            expandFirstFileIfNeeded()
        }
        .onChange(of: snapshot.files.map(\.id)) {
            expandedFileIDs.formIntersection(Set(snapshot.files.map(\.id)))
            expandFirstFileIfNeeded()
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button(action: {}) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.mayuElevatedBackground)
                            .overlay {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(Color.mayuBorder.opacity(0.5), lineWidth: 1)
                            }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: refresh) {
                HStack(spacing: 7) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Review")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.mayuSelection)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.mayuBorder.opacity(0.5), lineWidth: 1)
                        }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: refresh) {
                Image(systemName: isLoading ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: {}) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: close) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
    }

    private var reviewContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Unstaged")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("\(snapshot.changeCount)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.mayuSelection)
                    .clipShape(Capsule())

                Text("+\(snapshot.additions)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.mayuDiffAdded)

                Text("-\(snapshot.deletions)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.mayuDiffRemoved)

                Spacer()

                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .frame(height: 54)

            Divider()
                .background(Color.mayuBorder)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(snapshot.files) { file in
                        ProjectChangedFileSection(
                            file: file,
                            isExpanded: expandedFileIDs.contains(file.id),
                            toggle: { toggle(file) }
                        )
                    }
                }
            }

            reviewFooter
        }
    }

    private var reviewFooter: some View {
        HStack(spacing: 16) {
            Button(action: {}) {
                Label("Revert all", systemImage: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Review-only for now")

            Divider()
                .frame(height: 18)

            Button(action: {}) {
                Label("Stage all", systemImage: "plus")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Review-only for now")
        }
        .padding(.horizontal, 18)
        .frame(height: 46)
        .background(Color.mayuComposerBackground)
        .clipShape(Capsule())
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            if let errorMessage = snapshot.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Pick a git project to review file changes here.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                Text(snapshot.hasProject ? "No file changes" : "Nothing here yet")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)

                if snapshot.hasProject {
                    Text(snapshot.projectName)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func toggle(_ file: ProjectChangedFile) {
        if expandedFileIDs.contains(file.id) {
            expandedFileIDs.remove(file.id)
        } else {
            expandedFileIDs.insert(file.id)
        }
    }

    private func expandFirstFileIfNeeded() {
        guard expandedFileIDs.isEmpty, let firstFile = snapshot.files.first else {
            return
        }

        expandedFileIDs.insert(firstFile.id)
    }
}

private struct ProjectChangedFileSection: View {
    let file: ProjectChangedFile
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 8) {
                    Text(file.path)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text("+\(file.additions)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.mayuDiffAdded)

                    Text("-\(file.deletions)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.mayuDiffRemoved)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    if file.diffLines.isEmpty {
                        ProjectDiffLineRow(
                            line: ProjectDiffLine(
                                oldLine: nil,
                                newLine: nil,
                                content: "No preview available.",
                                kind: .note
                            )
                        )
                    } else {
                        ForEach(file.diffLines) { line in
                            ProjectDiffLineRow(line: line)
                        }
                    }
                }
                .padding(.bottom, 8)
            }

            Divider()
                .background(Color.mayuBorder)
        }
    }
}

private struct ProjectDiffLineRow: View {
    let line: ProjectDiffLine

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(lineNumber(line.oldLine))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
                .padding(.trailing, 8)

            Text(lineNumber(line.newLine))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
                .padding(.trailing, 10)

            Text(prefix)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(prefixColor)
                .frame(width: 16, alignment: .leading)

            Text(line.content.isEmpty ? " " : line.content)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(textColor)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .padding(.trailing, 12)
        .background(backgroundColor)
    }

    private var prefix: String {
        switch line.kind {
        case .added:
            return "+"
        case .removed:
            return "-"
        default:
            return ""
        }
    }

    private var prefixColor: Color {
        switch line.kind {
        case .added:
            return Color.mayuDiffAdded
        case .removed:
            return Color.mayuDiffRemoved
        default:
            return .secondary
        }
    }

    private var textColor: Color {
        switch line.kind {
        case .hunk, .note:
            return .secondary
        default:
            return .primary
        }
    }

    private var backgroundColor: Color {
        switch line.kind {
        case .added:
            return Color.mayuDiffAdded.opacity(0.14)
        case .removed:
            return Color.mayuDiffRemoved.opacity(0.14)
        case .hunk:
            return Color.mayuSelection.opacity(0.7)
        default:
            return .clear
        }
    }

    private func lineNumber(_ value: Int?) -> String {
        guard let value else {
            return ""
        }

        return "\(value)"
    }
}
