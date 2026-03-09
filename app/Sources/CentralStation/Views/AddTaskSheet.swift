import SwiftUI
import AppKit

struct AddTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    let defaultProjectPath: String
    let onAdd: (String, String, String, String?, String?) -> Void

    @State private var description = ""
    @State private var prompt = ""
    @State private var permissionMode = "default"
    @State private var customPath = ""
    @State private var isGeneratingDescription = false

    private let permissionModes = ["default", "acceptEdits", "plan", "auto"]

    private var taskId: String {
        slugify(description)
    }

    private var isValid: Bool {
        !description.isEmpty && !prompt.isEmpty && !taskId.isEmpty
    }

    private var effectivePath: String {
        customPath.isEmpty ? defaultProjectPath : customPath
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Task")
                .font(.title2.bold())

            Form {
                HStack {
                    TextField("Description", text: $description)
                        .textFieldStyle(.roundedBorder)
                    if isGeneratingDescription {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if !description.isEmpty {
                    LabeledContent("Branch") {
                        Text("cs/\(taskId)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading) {
                    HStack {
                        Text("Prompt")
                            .font(.caption)
                        Spacer()
                        if !prompt.isEmpty && description.isEmpty {
                            Button("Auto-summarize") {
                                generateDescription()
                            }
                            .font(.caption)
                            .buttonStyle(.borderless)
                            .disabled(isGeneratingDescription)
                        }
                    }
                    TextEditor(text: $prompt)
                        .font(.body)
                        .frame(minHeight: 100)
                        .border(Color.secondary.opacity(0.3))
                }

                Picker("Permission Mode", selection: $permissionMode) {
                    ForEach(permissionModes, id: \.self) { mode in
                        Text(mode).tag(mode)
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Working Directory")
                            .font(.caption)
                        Text(effectivePath)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Choose...") {
                        pickFolder()
                    }
                    if !customPath.isEmpty {
                        Button("Reset") {
                            customPath = ""
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Launch") {
                    let mode = permissionMode == "default" ? nil : permissionMode
                    let path = customPath.isEmpty ? nil : customPath
                    onAdd(taskId, description, prompt, mode, path)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding()
        .frame(width: 520, height: 440)
        .onChange(of: prompt) {
            if description.isEmpty && !prompt.isEmpty && prompt.count > 20 {
                generateDescription()
            }
        }
    }

    private func slugify(_ text: String) -> String {
        let lowered = text.lowercased()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -"))
        let filtered = lowered.unicodeScalars.filter { allowed.contains($0) }
        let cleaned = String(String.UnicodeScalarView(filtered))
        let slug = cleaned
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        // Truncate to reasonable branch name length
        let maxLen = 50
        if slug.count > maxLen {
            return String(slug.prefix(maxLen)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }
        return slug
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the working directory for this task"
        if panel.runModal() == .OK, let url = panel.url {
            customPath = url.path
        }
    }

    private func generateDescription() {
        guard !prompt.isEmpty, !isGeneratingDescription else { return }
        isGeneratingDescription = true
        let currentPrompt = prompt
        Task.detached {
            let claudePath = "\(NSHomeDirectory())/.local/bin/claude"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: claudePath)
            process.arguments = ["-p", "Summarize this task in under 10 words. Output ONLY the summary, nothing else:\n\n\(currentPrompt)"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let summary = (String(data: data, encoding: .utf8) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                await MainActor.run {
                    if !summary.isEmpty && description.isEmpty {
                        description = summary
                    }
                    isGeneratingDescription = false
                }
            } catch {
                await MainActor.run {
                    isGeneratingDescription = false
                }
            }
        }
    }
}
