import SwiftUI

struct APIProviderDraft: Identifiable {
    var id: String
    var name: String
    var baseURL: String
    var format: APIProviderFormat
    var modelID: String
    var apiKey: String
    var isNew: Bool
}

struct APIProviderRow: View {
    let config: APIProviderConfig
    let editAction: () -> Void
    let deleteAction: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(config.name)
                        .font(.system(size: 14, weight: .semibold))

                    Text(config.format.rawValue)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.mayuAccent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.mayuAccentSoft)
                        .clipShape(Capsule())
                }

                Text("\(config.modelID) · \(config.normalizedBaseURL)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                Button(action: editAction) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.mayuElevatedBackground)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: deleteAction) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.mayuWarning)
                        .frame(width: 28, height: 28)
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.mayuWarning.opacity(0.10))
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .opacity(isHovered ? 1 : 0.6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}

struct APIProviderEditorSheet: View {
    @State var draft: APIProviderDraft
    let onSave: (APIProviderDraft) -> Void
    let onCancel: () -> Void
    @State private var isKeyVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(draft.isNew ? "Add API connection" : "Edit API connection")
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 14) {
                labeledField("Name", text: $draft.name, placeholder: "Company Gateway")

                VStack(alignment: .leading, spacing: 6) {
                    Text("Format")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Picker("", selection: $draft.format) {
                        ForEach(APIProviderFormat.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                labeledField("Base URL", text: $draft.baseURL, placeholder: "https://llm.company.com/v1", monospaced: true)
                labeledField("Model ID", text: $draft.modelID, placeholder: "gpt-4o, claude-sonnet-4-5, ...", monospaced: true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("API Key")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Group {
                            if isKeyVisible {
                                TextField("sk-...", text: $draft.apiKey)
                            } else {
                                SecureField("sk-...", text: $draft.apiKey)
                            }
                        }
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))

                        Button(action: { isKeyVisible.toggle() }) {
                            Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.mayuElevatedBackground)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.mayuBorder.opacity(0.6), lineWidth: 1)
                            }
                    }

                    Text("Stored in the macOS Keychain, never in plain text.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            HStack {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: { onSave(draft) }) {
                    Text("Save")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isValid ? Color.mayuOnAccent : .secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background {
                            Capsule().fill(isValid ? Color.mayuAccentSolid : Color.secondary.opacity(0.15))
                        }
                }
                .buttonStyle(.plain)
                .disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(Color.mayuPanelBackground)
    }

    private var isValid: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draft.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draft.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func labeledField(_ label: String, text: Binding<String>, placeholder: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: monospaced ? .monospaced : .default))
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.mayuElevatedBackground)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.mayuBorder.opacity(0.6), lineWidth: 1)
                        }
                }
        }
    }
}
