import AppKit
import Foundation

/// Re-requests write access to a project folder through the system file picker.
///
/// A sandboxed app's security-scoped bookmark encodes the access level it was minted with.
/// A folder added while the app only had read-only access yields a read-only bookmark, so
/// writes keep failing even after the app gains the read-write entitlement. The only way to
/// obtain write access is to have the user re-select the folder through the powerbox, which
/// mints a fresh read-write bookmark.
enum ProjectFolderAccess {
    /// Presents an open panel pointed at the given folder and returns a fresh read-write
    /// security-scoped bookmark, or nil if the user cancels.
    @MainActor
    static func reauthorize(projectPath: String) -> Data? {
        let folderURL = URL(fileURLWithPath: projectPath, isDirectory: true)

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        // Open the parent so the project folder itself is visible and selectable.
        panel.directoryURL = folderURL.deletingLastPathComponent()
        panel.title = "Grant Write Access"
        panel.message = "Select the \"\(folderURL.lastPathComponent)\" folder to let Mayu Echo save edits to it."
        panel.prompt = "Grant Access"

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }
}
