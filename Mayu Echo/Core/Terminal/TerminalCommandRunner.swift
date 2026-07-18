import Foundation

nonisolated struct TerminalCommandResult: Sendable {
    let command: String
    let workingDirectoryPath: String
    let standardOutput: String
    let standardError: String
    let exitCode: Int32
    let duration: TimeInterval

    var combinedOutput: String {
        let output = [standardOutput, standardError]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        return output.isEmpty ? "No output." : output
    }
}

nonisolated struct TerminalCommandRunner: Sendable {
    func run(
        command: String,
        workingDirectoryPath: String?,
        bookmarkData: Data?
    ) async -> TerminalCommandResult {
        await Task.detached(priority: .userInitiated) {
            runSynchronously(
                command: command,
                workingDirectoryPath: workingDirectoryPath,
                bookmarkData: bookmarkData
            )
        }.value
    }
}

private nonisolated func runSynchronously(
    command: String,
    workingDirectoryPath: String?,
    bookmarkData: Data?
) -> TerminalCommandResult {
    let startDate = Date()
    let workingDirectoryURL = resolvedWorkingDirectory(
        workingDirectoryPath: workingDirectoryPath,
        bookmarkData: bookmarkData
    )
    let isAccessing = workingDirectoryURL.startAccessingSecurityScopedResource()

    defer {
        if isAccessing {
            workingDirectoryURL.stopAccessingSecurityScopedResource()
        }
    }

    let process = Process()
    let outputPipe = Pipe()
    let errorPipe = Pipe()

    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-lc", command]
    process.currentDirectoryURL = workingDirectoryURL
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return TerminalCommandResult(
            command: command,
            workingDirectoryPath: workingDirectoryURL.path,
            standardOutput: "",
            standardError: error.localizedDescription,
            exitCode: -1,
            duration: Date().timeIntervalSince(startDate)
        )
    }

    let standardOutput = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let standardError = errorPipe.fileHandleForReading.readDataToEndOfFile()

    return TerminalCommandResult(
        command: command,
        workingDirectoryPath: workingDirectoryURL.path,
        standardOutput: String(data: standardOutput, encoding: .utf8) ?? "",
        standardError: String(data: standardError, encoding: .utf8) ?? "",
        exitCode: process.terminationStatus,
        duration: Date().timeIntervalSince(startDate)
    )
}

private nonisolated func resolvedWorkingDirectory(
    workingDirectoryPath: String?,
    bookmarkData: Data?
) -> URL {
    if let bookmarkData {
        var isStale = false
        if let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            return url
        }
    }

    if let workingDirectoryPath {
        return URL(fileURLWithPath: workingDirectoryPath, isDirectory: true)
    }

    return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
}
