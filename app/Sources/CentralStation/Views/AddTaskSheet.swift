import SwiftUI
import AppKit

struct AddTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    let defaultProjectPath: String
    let remoteStore: RemoteStore
    let onAdd: (String, String, String, String?, String?, Bool, RemoteConfig?, String?) -> Void
    var initialCustomPath: String?

    @State private var description = ""
    @State private var prompt = ""
    @State private var permissionMode = "default"
    @State private var customPath = ""
    @State private var isGeneratingDescription = false

    @State private var useWorktree = true
    @State private var isRemote = false
    @State private var selectedRemote: RemoteConfig?
    @State private var remotePath = ""
    @State private var connectionStatus: ConnectionStatus = .untested
    @State private var showManageRemotes = false

    enum ConnectionStatus {
        case untested, testing, success(String), failed(String)
    }

    private let permissionModes = ["default", "acceptEdits", "plan", "auto"]

    private var taskId: String {
        slugify(description)
    }

    private var isValid: Bool {
        if isRemote {
            return !description.isEmpty && !taskId.isEmpty && selectedRemote != nil && !remotePath.isEmpty
        }
        return !description.isEmpty && !taskId.isEmpty
    }

    private var effectivePath: String {
        customPath.isEmpty ? defaultProjectPath : customPath
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Task")
                .font(.title2.bold())

            Form {
                Picker("Location", selection: $isRemote) {
                    Text("Local").tag(false)
                    Text("Remote").tag(true)
                }
                .pickerStyle(.segmented)

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
                        Text("Prompt (optional)")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
                    ZStack(alignment: .topLeading) {
                        if prompt.isEmpty {
                            Text("Leave blank to start an interactive session...")
                                .foregroundColor(.secondary.opacity(0.5))
                                .font(.body)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                        }
                        TextEditor(text: $prompt)
                            .font(.body)
                            .frame(minHeight: 100)
                    }
                    .border(Color.secondary.opacity(0.3))
                }

                Picker("Permission Mode", selection: $permissionMode) {
                    ForEach(permissionModes, id: \.self) { mode in
                        Text(mode).tag(mode)
                    }
                }

                if !isRemote {
                    Toggle("Create git worktree", isOn: $useWorktree)
                        .help("When enabled, creates an isolated git worktree for this task. Disable to work directly in the project directory.")
                }

                if isRemote {
                    HStack {
                        Picker("Remote", selection: $selectedRemote) {
                            Text("Select a remote...").tag(nil as RemoteConfig?)
                            ForEach(remoteStore.remotes) { remote in
                                Text(remote.alias).tag(remote as RemoteConfig?)
                            }
                        }
                        Button("Manage...") { showManageRemotes = true }
                            .buttonStyle(.borderless)
                    }

                    switch connectionStatus {
                    case .untested:
                        EmptyView()
                    case .testing:
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Testing connection...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    case .success(let msg):
                        Label("Connected: \(msg)", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    case .failed(let msg):
                        Label("Failed: \(msg)", systemImage: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if selectedRemote != nil {
                        if case .success = connectionStatus {
                            RemoteDirectoryBrowser(sshHost: selectedRemote!.sshHost, selectedPath: $remotePath)
                        }
                    }
                }

                if !isRemote {
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
                        Button("New Project...") {
                            createNewProject()
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
            }

            HStack {
                Spacer()
                Text("⇧↩ to launch")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Launch") { launchTask() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding()
        .frame(width: 520, height: isRemote ? 640 : 440)
        .onKeyPress(.return, phases: .down) { press in
            if press.modifiers.contains(.shift) && isValid {
                launchTask()
                return .handled
            }
            return .ignored
        }
        .onChange(of: prompt) {
            if description.isEmpty && !prompt.isEmpty && prompt.count > 20 {
                generateDescription()
            }
        }
        .onChange(of: selectedRemote) { _, remote in
            guard let remote else {
                connectionStatus = .untested
                return
            }
            connectionStatus = .testing
            remotePath = remote.defaultDirectory ?? ""
            Task {
                let result = await remoteStore.testConnection(remote: remote)
                switch result {
                case .success(let msg): connectionStatus = .success(msg)
                case .failure(let err): connectionStatus = .failed(err.localizedDescription)
                }
            }
        }
        .sheet(isPresented: $showManageRemotes) {
            ManageRemotesSheet(remoteStore: remoteStore)
        }
        .onAppear {
            if let path = initialCustomPath {
                customPath = path
            }
        }
    }

    private func launchTask() {
        guard isValid else { return }
        let mode = permissionMode == "default" ? nil : permissionMode
        if isRemote, let remote = selectedRemote {
            onAdd(taskId, description, prompt, mode, nil, true, remote, remotePath)
        } else {
            let path = customPath.isEmpty ? nil : customPath
            onAdd(taskId, description, prompt, mode, path, useWorktree, nil, nil)
        }
        dismiss()
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

    private func createNewProject() {
        let panel = NSSavePanel()
        panel.title = "Create New Project"
        panel.message = "Choose a location and name for the new project"
        panel.nameFieldLabel = "Project Name:"
        panel.nameFieldStringValue = "my-project"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            let fm = FileManager.default
            do {
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = ["init", url.path]
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                try process.run()
                process.waitUntilExit()
                customPath = url.path
            } catch {
                // Directory creation failed — ignore silently
            }
        }
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
