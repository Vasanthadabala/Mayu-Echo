import SwiftUI

/// One line in a rendered diff: unchanged context, a removed line, an added line, or a
/// "⋯" gap marker where unchanged lines were collapsed away.
struct FileEditDiffLine: Identifiable {
    enum Kind {
        case context
        case removed
        case added
        case gap
    }

    let id = UUID()
    let kind: Kind
    let text: String

    /// Collapses the unchanged common prefix/suffix so only the changed region (plus a
    /// few lines of surrounding context) is shown. This handles the common case — one
    /// contiguous edit, as produced by str_replace — with a tight, readable diff.
    static func compute(
        original: String?,
        proposed: String,
        contextLines: Int,
        limit: Int
    ) -> [FileEditDiffLine] {
        guard let original, !original.isEmpty else {
            // New file (or previously empty): everything is an addition.
            let lines = proposed.isEmpty ? [] : proposed.components(separatedBy: "\n")
            return Array(lines.prefix(limit)).map { FileEditDiffLine(kind: .added, text: $0) }
        }

        let originalLines = original.components(separatedBy: "\n")
        let proposedLines = proposed.components(separatedBy: "\n")

        var prefix = 0
        while prefix < originalLines.count,
              prefix < proposedLines.count,
              originalLines[prefix] == proposedLines[prefix] {
            prefix += 1
        }

        var suffix = 0
        while suffix < originalLines.count - prefix,
              suffix < proposedLines.count - prefix,
              originalLines[originalLines.count - 1 - suffix] == proposedLines[proposedLines.count - 1 - suffix] {
            suffix += 1
        }

        var result: [FileEditDiffLine] = []

        let leadingContextStart = max(0, prefix - contextLines)
        if leadingContextStart > 0 {
            result.append(FileEditDiffLine(kind: .gap, text: ""))
        }
        for index in leadingContextStart..<prefix {
            result.append(FileEditDiffLine(kind: .context, text: originalLines[index]))
        }

        for index in prefix..<(originalLines.count - suffix) {
            result.append(FileEditDiffLine(kind: .removed, text: originalLines[index]))
        }
        for index in prefix..<(proposedLines.count - suffix) {
            result.append(FileEditDiffLine(kind: .added, text: proposedLines[index]))
        }

        let trailingContextEnd = min(originalLines.count, originalLines.count - suffix + contextLines)
        for index in (originalLines.count - suffix)..<trailingContextEnd {
            result.append(FileEditDiffLine(kind: .context, text: originalLines[index]))
        }
        if trailingContextEnd < originalLines.count {
            result.append(FileEditDiffLine(kind: .gap, text: ""))
        }

        return Array(result.prefix(limit))
    }
}

/// Scrollable, minimal-diff line list — only the changed lines plus a little surrounding
/// context. Shared by the pending-approval card and the post-hoc review card.
struct DiffLinesView: View {
    let original: String?
    let proposed: String
    var lineDisplayLimit: Int = 400

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(diffLines) { line in
                    diffLineView(line)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var diffLines: [FileEditDiffLine] {
        FileEditDiffLine.compute(
            original: original,
            proposed: proposed,
            contextLines: 3,
            limit: lineDisplayLimit
        )
    }

    @ViewBuilder
    private func diffLineView(_ line: FileEditDiffLine) -> some View {
        switch line.kind {
        case .gap:
            HStack(spacing: 8) {
                Text("⋯")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 10)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 2)
        case .context:
            diffLine(text: line.text, prefix: " ", color: .clear, textOpacity: 0.55)
        case .removed:
            diffLine(text: line.text, prefix: "-", color: Color.mayuDiffRemoved, textOpacity: 0.9)
        case .added:
            diffLine(text: line.text, prefix: "+", color: Color.mayuDiffAdded, textOpacity: 0.9)
        }
    }

    private func diffLine(text: String, prefix: String, color: Color, textOpacity: Double) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(prefix)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(color == .clear ? Color.secondary : color)
                .frame(width: 10)

            Text(text.isEmpty ? " " : text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary.opacity(textOpacity))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
        .background(color == .clear ? Color.clear : color.opacity(0.12))
    }
}

/// Read-only diff shown in the right-hand panel after an edit has already been applied —
/// the "Review" affordance on a completed edit_file/str_replace tool result, opened by
/// tapping its summary row. Mirrors `ProjectChangesReviewPanel`'s look so the two panels
/// feel like the same surface.
struct EditDiffReviewPanel: View {
    let path: String?
    let originalContent: String?
    let proposedContent: String
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            topBar

            Divider().background(Color.mayuBorder)

            DiffLinesView(original: originalContent, proposed: proposedContent, lineDisplayLimit: 4000)
        }
        .background(Color.mayuChatBackground)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Image(systemName: originalContent == nil ? "doc.badge.plus" : "pencil.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.mayuAccent)

            VStack(alignment: .leading, spacing: 1) {
                Text(originalContent == nil ? "Created file" : "Edited file")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                if let path {
                    Text((path as NSString).lastPathComponent)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

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
}

/// Shows a proposed file edit as a minimal diff (only the changed lines plus a few lines
/// of context) with Accept/Reject actions that gate whether anything is written to disk.
struct FileEditProposalCard: View {
    let proposal: ProjectFileEditProposal
    let approve: () -> Void
    let reject: () -> Void

    private let lineDisplayLimit = 400

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().background(Color.mayuBorder)

            diffBody

            Divider().background(Color.mayuBorder)

            actions
        }
        .background(Color.mayuCodeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.mayuBorder.opacity(0.6), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.mayuAccent)

            Text(proposal.originalContent == nil ? "Create file" : "Edit file")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            Text(displayPath)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var diffBody: some View {
        DiffLinesView(
            original: proposal.originalContent,
            proposed: proposal.proposedContent,
            lineDisplayLimit: lineDisplayLimit
        )
        .frame(maxHeight: 260)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button(action: reject) {
                Text("Reject")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background {
                        Capsule()
                            .fill(Color.mayuElevatedBackground)
                            .overlay {
                                Capsule().stroke(Color.mayuBorder.opacity(0.6), lineWidth: 1)
                            }
                    }
            }
            .buttonStyle(.plain)

            Button(action: approve) {
                Text("Accept")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.mayuOnAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background {
                        Capsule().fill(Color.mayuAccentSolid)
                    }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var displayPath: String {
        (proposal.path as NSString).lastPathComponent
    }

    private func splitLines(_ text: String) -> [String] {
        text.isEmpty ? [] : text.components(separatedBy: "\n")
    }
}

/// Shows an `edit_file` tool call's content growing live as the model streams it — same
/// visual language as `FileEditProposalCard` but with no actions. It's swapped out for
/// the real approval card the moment the tool call finishes.
struct LiveEditPreviewCard: View {
    let preview: ChatSessionViewModel.LiveEditPreview

    private let lineDisplayLimit = 400
    private let bottomAnchorID = "live-edit-preview-bottom"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().background(Color.mayuBorder)

            previewBody
        }
        .background(Color.mayuCodeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.mayuBorder.opacity(0.6), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }

    private var header: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)

            Text("Writing file")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            if let path = preview.path {
                Text((path as NSString).lastPathComponent)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var previewBody: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(splitLines(preview.content).suffix(lineDisplayLimit).enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top, spacing: 8) {
                            Text("+")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.mayuDiffAdded)
                                .frame(width: 10)

                            Text(line.isEmpty ? " " : line)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.primary.opacity(0.9))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 2)
                        .background(Color.mayuDiffAdded.opacity(0.12))
                    }

                    Color.clear.frame(height: 1).id(bottomAnchorID)
                }
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 260)
            .onChange(of: preview.content) {
                scrollProxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        }
    }

    private func splitLines(_ text: String) -> [String] {
        text.isEmpty ? [] : text.components(separatedBy: "\n")
    }
}

/// Shows a model-proposed shell command with Accept/Reject actions gating whether it runs.
struct CommandProposalCard: View {
    let proposal: ProjectCommandProposal
    let approve: () -> Void
    let reject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().background(Color.mayuBorder)

            commandBody

            Divider().background(Color.mayuBorder)

            actions
        }
        .background(Color.mayuCodeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.mayuBorder.opacity(0.6), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.mayuAccent)

            Text("Run terminal command")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var commandBody: some View {
        Text(proposal.command)
            .font(.system(size: 12.5, design: .monospaced))
            .foregroundStyle(.primary.opacity(0.9))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button(action: reject) {
                Text("Reject")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background {
                        Capsule()
                            .fill(Color.mayuElevatedBackground)
                            .overlay {
                                Capsule().stroke(Color.mayuBorder.opacity(0.6), lineWidth: 1)
                            }
                    }
            }
            .buttonStyle(.plain)

            Button(action: approve) {
                Text("Run")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.mayuOnAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background {
                        Capsule().fill(Color.mayuAccentSolid)
                    }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
