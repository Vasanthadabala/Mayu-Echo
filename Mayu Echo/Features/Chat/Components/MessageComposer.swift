import SwiftUI
import AppKit

struct MessageComposer: View {
    @Binding var message: String
    @Binding var selectedModel: LLMModel
    let availableModels: [LLMModel]
    @Binding var generationOptions: LLMGenerationOptions
    let contextUsage: ContextWindowUsage
    let isGenerating: Bool
    let sendMessage: () -> Void
    let stopGeneration: () -> Void
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

                ContextWindowButton(usage: contextUsage)

                Menu {
                    Text("Intelligence")

                    ForEach(LLMGenerationOptions.Intelligence.allCases, id: \.self) { intelligence in
                        IntelligenceMenuButton(
                            intelligence: intelligence,
                            selection: intelligenceSelection
                        )
                    }

                    Divider()

                    Menu("Models") {
                        ForEach(availableModels, id: \.id) { model in
                            ModelMenuButton(model: model, selection: $selectedModel)
                        }
                    }
                } label: {
                    HStack(spacing: 7) {
                        Text(selectedModel.displayName)
                            .foregroundStyle(.primary)
                        Text(generationOptions.intelligence.rawValue)
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
                    .background(Color.mayuSelection)
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

                Button(action: primaryAction) {
                    Image(systemName: isGenerating ? "stop.fill" : "arrow.up")
                        .font(.system(size: isGenerating ? 14 : 21, weight: .medium))
                        .foregroundStyle(Color.mayuChatBackground)
                        .frame(width: 46, height: 46)
                        .background(primaryButtonBackground)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!isGenerating && !canSend)
            }
            .foregroundStyle(.secondary)
            .padding(.leading, 18)
            .padding(.trailing, 12)
            .padding(.bottom, 12)
        }
        .background(Color.mayuComposerBackground)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.mayuBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 22, y: 8)
    }

    private func sendIfPossible() {
        guard !isGenerating, canSend else {
            return
        }

        sendMessage()
    }

    private func primaryAction() {
        if isGenerating {
            stopGeneration()
        } else {
            sendIfPossible()
        }
    }

    private var primaryButtonBackground: Color {
        if isGenerating {
            return Color.secondary.opacity(0.95)
        }

        return canSend ? Color.secondary.opacity(0.95) : Color.secondary.opacity(0.28)
    }

    private var intelligenceSelection: Binding<LLMGenerationOptions.Intelligence> {
        Binding {
            generationOptions.intelligence
        } set: { intelligence in
            generationOptions.applyIntelligencePreset(intelligence)
        }
    }
}

struct ContextWindowUsage: Equatable {
    let usedTokens: Int
    let maxTokens: Int

    var usedFraction: Double {
        guard maxTokens > 0 else {
            return 0
        }

        return min(max(Double(usedTokens) / Double(maxTokens), 0), 1)
    }

    var usedPercentage: Int {
        guard maxTokens > 0 else {
            return 0
        }

        return Int((usedFraction * 100).rounded())
    }

    var leftPercentage: Int {
        max(0, 100 - usedPercentage)
    }

    var usedDescription: String {
        guard maxTokens > 0 else {
            return "Context length will be read from config.json after download"
        }

        return "\(formattedTokenCount(usedTokens)) / \(formattedTokenCount(maxTokens)) tokens used"
    }

    private func formattedTokenCount(_ value: Int) -> String {
        guard value >= 1_000 else {
            return "\(value)"
        }

        return "\(Int((Double(value) / 1_000).rounded()))k"
    }
}

private struct ContextWindowButton: View {
    let usage: ContextWindowUsage
    @State private var isShowingDetails = false

    var body: some View {
        Button {
            isShowingDetails.toggle()
        } label: {
            ContextProgressRing(progress: usage.usedFraction)
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowingDetails, arrowEdge: .top) {
            ContextWindowPopover(usage: usage)
        }
        .accessibilityLabel("Context window")
        .accessibilityValue("\(usage.usedPercentage)% used")
    }
}

private struct ContextProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.28), lineWidth: 4)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.secondary,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .padding(4)
    }
}

private struct ContextWindowPopover: View {
    let usage: ContextWindowUsage

    var body: some View {
        VStack(spacing: 12) {
            Text("Context window:")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("\(usage.usedPercentage)% used (\(usage.leftPercentage)% left)")
                Text(usage.usedDescription)
            }
            .font(.system(size: 19, weight: .regular))
            .foregroundStyle(.primary)

            Text("Mayu Echo automatically\ncompacts its context")
                .font(.system(size: 18, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .foregroundStyle(.primary)
                .padding(.top, 10)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .frame(width: 260)
    }
}

private struct IntelligenceMenuButton: View {
    let intelligence: LLMGenerationOptions.Intelligence
    @Binding var selection: LLMGenerationOptions.Intelligence

    var body: some View {
        Button {
            selection = intelligence
        } label: {
            if selection == intelligence {
                Label(intelligence.rawValue, systemImage: "checkmark")
            } else {
                Text(intelligence.rawValue)
            }
        }
    }
}

private struct ModelMenuButton: View {
    let model: LLMModel
    @Binding var selection: LLMModel

    var body: some View {
        Button {
            selection = model
        } label: {
            if selection.id == model.id {
                Label(model.displayName, systemImage: "checkmark")
            } else {
                Text(model.displayName)
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
