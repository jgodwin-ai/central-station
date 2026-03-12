# SSH Remote Tasks Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Allow users to launch and monitor Claude Code tasks on remote machines over SSH, with saved remote configurations, a remote directory browser, and connection verification.

**Architecture:** Extend the existing local task flow to support remote execution. When a task targets a remote, all shell/git commands route through SSH. The terminal launches `ssh -t -R 19280:localhost:19280 host "cd dir && claude ..."` instead of `claude` directly. A new `RemoteConfig` model persists saved remotes. A `RemoteShell` service wraps SSH command execution. The `AddTaskSheet` gains a Local/Remote toggle with remote picker and directory browser.

**Tech Stack:** SwiftUI, SwiftTerm (LocalProcessTerminalView), SSH via `/usr/bin/ssh`, JSON persistence

---

### Task 1: RemoteConfig Model & Persistence

**Files:**
- Create: `app/Sources/CentralStation/Models/RemoteConfig.swift`
- Create: `app/Sources/CentralStation/Services/RemoteStore.swift`

**Step 1: Create RemoteConfig model**

```swift
// app/Sources/CentralStation/Models/RemoteConfig.swift
import Foundation

struct RemoteConfig: Codable, Identifiable, Hashable {
    var id: String  // UUID
    var alias: String  // e.g. "Dev Server"
    var sshHost: String  // e.g. "user@10.0.1.5" or SSH config alias "devbox"
    var defaultDirectory: String?  // last-used or preferred starting directory
}
```

**Step 2: Create RemoteStore for persistence**

```swift
// app/Sources/CentralStation/Services/RemoteStore.swift
import Foundation

@Observable
@MainActor
final class RemoteStore {
    var remotes: [RemoteConfig] = []

    private static var persistencePath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".claude/central-station-remotes.json")
    }

    func load() {
        guard let data = FileManager.default.contents(atPath: Self.persistencePath),
              let decoded = try? JSONDecoder().decode([RemoteConfig].self, from: data) else { return }
        remotes = decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(remotes) else { return }
        try? data.write(to: URL(fileURLWithPath: Self.persistencePath))
    }

    func add(_ remote: RemoteConfig) {
        remotes.append(remote)
        save()
    }

    func update(_ remote: RemoteConfig) {
        if let idx = remotes.firstIndex(where: { $0.id == remote.id }) {
            remotes[idx] = remote
            save()
        }
    }

    func delete(_ remote: RemoteConfig) {
        remotes.removeAll { $0.id == remote.id }
        save()
    }

    func testConnection(remote: RemoteConfig) async -> Result<String, Error> {
        do {
            let output = try await ShellHelper.run("/usr/bin/ssh", arguments: [
                "-o", "ConnectTimeout=5",
                "-o", "BatchMode=yes",
                remote.sshHost,
                "echo connected && hostname"
            ])
            return .success(output.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return .failure(error)
        }
    }
}
```

**Step 3: Verify it compiles**

Run: `cd /Users/jgoai/central-station/app && swift build 2>&1 | tail -5`
Expected: Build complete

**Step 4: Commit**

```bash
git add app/Sources/CentralStation/Models/RemoteConfig.swift app/Sources/CentralStation/Services/RemoteStore.swift
git commit -m "feat: add RemoteConfig model and RemoteStore persistence"
```

---

### Task 2: RemoteShell Service

**Files:**
- Create: `app/Sources/CentralStation/Services/RemoteShell.swift`

**Purpose:** Wraps SSH command execution so WorktreeManager and other services can run commands on a remote machine transparently.

**Step 1: Create RemoteShell**

```swift
// app/Sources/CentralStation/Services/RemoteShell.swift
import Foundation

enum RemoteShell {
    /// Run an arbitrary command on a remote host via SSH.
    @discardableResult
    static func run(host: String, command: String) async throws -> String {
        try await ShellHelper.run("/usr/bin/ssh", arguments: [
            "-o", "ConnectTimeout=10",
            host,
            command
        ])
    }

    /// Run a git command on a remote host in a specific directory.
    @discardableResult
    static func runGit(host: String, inDirectory directory: String, args: [String]) async throws -> String {
        let gitArgs = ["git", "-C", shellEscape(directory)] + args.map { shellEscape($0) }
        return try await run(host: host, command: gitArgs.joined(separator: " "))
    }

    /// List directories at a given path on the remote.
    static func listDirectories(host: String, path: String) async throws -> [String] {
        let output = try await run(host: host, command: "ls -1p \(shellEscape(path)) 2>/dev/null | grep '/$'")
        return output.split(separator: "\n")
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
            .filter { !$0.isEmpty }
    }

    /// Get the home directory on the remote.
    static func homeDirectory(host: String) async throws -> String {
        let output = try await run(host: host, command: "echo $HOME")
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Check if a path exists on the remote.
    static func pathExists(host: String, path: String) async throws -> Bool {
        do {
            _ = try await run(host: host, command: "test -d \(shellEscape(path)) && echo yes")
            return true
        } catch {
            return false
        }
    }

    /// Check if a path is a git repo on the remote.
    static func isGitRepo(host: String, path: String) async throws -> Bool {
        do {
            _ = try await runGit(host: host, inDirectory: path, args: ["rev-parse", "--git-dir"])
            return true
        } catch {
            return false
        }
    }

    private static func shellEscape(_ str: String) -> String {
        "'" + str.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
```

**Step 2: Verify it compiles**

Run: `cd /Users/jgoai/central-station/app && swift build 2>&1 | tail -5`
Expected: Build complete

**Step 3: Commit**

```bash
git add app/Sources/CentralStation/Services/RemoteShell.swift
git commit -m "feat: add RemoteShell service for SSH command execution"
```

---

### Task 3: Extend AppTask and PersistedTask for Remote

**Files:**
- Modify: `app/Sources/CentralStation/Models/AppTask.swift`

**Step 1: Add remote fields to PersistedTask**

In `PersistedTask`, add two optional fields:

```swift
struct PersistedTask: Codable {
    let id: String
    let description: String
    let prompt: String
    let sessionId: String
    let worktreePath: String
    let projectPath: String
    let permissionMode: String?
    let status: TaskStatus
    let remoteAlias: String?  // NEW - nil means local task
    let sshHost: String?      // NEW - the SSH host for remote tasks
}
```

**Step 2: Add remote fields to AppTask**

Add to `AppTask`:

```swift
var remoteAlias: String?   // nil = local task
var sshHost: String?       // e.g. "user@host"

var isRemote: Bool { sshHost != nil }
```

**Step 3: Update AppTask initializers**

Add a new convenience init for remote tasks:

```swift
init(id: String, description: String, prompt: String, worktreePath: String, projectPath: String, permissionMode: String? = nil, remoteAlias: String? = nil, sshHost: String? = nil) {
    self.id = id
    self.description = description
    self.prompt = prompt
    self.sessionId = UUID().uuidString.lowercased()
    self.worktreePath = worktreePath
    self.projectPath = projectPath
    self.permissionMode = permissionMode
    self.remoteAlias = remoteAlias
    self.sshHost = sshHost
}
```

Update `init(persisted:)` to load the new fields:

```swift
init(persisted: PersistedTask) {
    // ... existing fields ...
    self.remoteAlias = persisted.remoteAlias
    self.sshHost = persisted.sshHost
    self.isResume = true
}
```

**Step 4: Update toPersisted()**

```swift
func toPersisted() -> PersistedTask {
    PersistedTask(
        id: id, description: description, prompt: prompt,
        sessionId: sessionId, worktreePath: worktreePath,
        projectPath: projectPath, permissionMode: permissionMode,
        status: status, remoteAlias: remoteAlias, sshHost: sshHost
    )
}
```

**Step 5: Verify it compiles**

Run: `cd /Users/jgoai/central-station/app && swift build 2>&1 | tail -5`
Expected: Build complete

**Step 6: Commit**

```bash
git add app/Sources/CentralStation/Models/AppTask.swift
git commit -m "feat: add remote fields to AppTask and PersistedTask"
```

---

### Task 4: Extend WorktreeManager for Remote Operations

**Files:**
- Modify: `app/Sources/CentralStation/Services/WorktreeManager.swift`

**Purpose:** For each git operation, add a remote-aware overload or modify existing methods to optionally route through SSH.

**Step 1: Add remote versions of all git methods**

Add these static methods alongside the existing ones:

```swift
// MARK: - Remote operations

static func ensureGitRepoRemote(host: String, at path: String) async throws {
    do {
        _ = try await RemoteShell.runGit(host: host, inDirectory: path, args: ["rev-parse", "--git-dir"])
    } catch {
        _ = try await RemoteShell.runGit(host: host, inDirectory: path, args: ["init"])
        _ = try await RemoteShell.runGit(host: host, inDirectory: path, args: ["commit", "--allow-empty", "-m", "initial commit"])
    }
}

static func createWorktreeRemote(host: String, projectPath: String, taskId: String) async throws -> String {
    let worktreesDir = projectPath + "/.worktrees"
    let worktreePath = worktreesDir + "/" + taskId
    let branchName = "cs/\(taskId)"

    // Create .worktrees dir if needed
    _ = try? await RemoteShell.run(host: host, command: "mkdir -p '\(worktreesDir)'")

    // Check if already exists
    if try await RemoteShell.pathExists(host: host, path: worktreePath) {
        return worktreePath
    }

    _ = try await RemoteShell.runGit(host: host, inDirectory: projectPath, args: [
        "worktree", "add", "-b", branchName, worktreePath
    ])
    return worktreePath
}

static func removeWorktreeRemote(host: String, projectPath: String, taskId: String) async {
    let worktreePath = projectPath + "/.worktrees/" + taskId
    _ = try? await RemoteShell.runGit(host: host, inDirectory: projectPath, args: [
        "worktree", "remove", worktreePath, "--force"
    ])
}

static func getDiffRemote(host: String, worktreePath: String) async -> String {
    do {
        let stat = try await RemoteShell.runGit(host: host, inDirectory: worktreePath, args: ["diff", "HEAD", "--stat"])
        let diff = try await RemoteShell.runGit(host: host, inDirectory: worktreePath, args: ["diff", "HEAD"])
        if stat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
           diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let status = try await RemoteShell.runGit(host: host, inDirectory: worktreePath, args: ["status", "--short"])
            if !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Untracked/new files:\n\(status)"
            }
            return "No changes yet."
        }
        return stat + "\n" + diff
    } catch {
        return "Unable to get diff."
    }
}

static func getChangedFilesRemote(host: String, worktreePath: String) async -> [ChangedFile] {
    do {
        let diffNames = try await RemoteShell.runGit(host: host, inDirectory: worktreePath, args: ["diff", "HEAD", "--name-status"])
        let untracked = try await RemoteShell.runGit(host: host, inDirectory: worktreePath, args: ["ls-files", "--others", "--exclude-standard"])
        var files: [ChangedFile] = []
        for line in diffNames.split(separator: "\n") where !line.isEmpty {
            let parts = line.split(separator: "\t", maxSplits: 1)
            if parts.count == 2 {
                files.append(ChangedFile(id: String(parts[1]), path: String(parts[1]), status: String(parts[0])))
            }
        }
        for line in untracked.split(separator: "\n") where !line.isEmpty {
            let path = String(line)
            if !files.contains(where: { $0.path == path }) {
                files.append(ChangedFile(id: path, path: path, status: "??"))
            }
        }
        return files
    } catch {
        return []
    }
}

static func getFileDiffRemote(host: String, worktreePath: String, filePath: String) async -> String {
    do {
        let diff = try await RemoteShell.runGit(host: host, inDirectory: worktreePath, args: ["diff", "HEAD", "--", filePath])
        if diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let content = try await RemoteShell.run(host: host, command: "cat '\(worktreePath)/\(filePath)' 2>/dev/null || echo '(binary or empty)'")
            let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
                .map { "+\($0)" }.joined(separator: "\n")
            return "New file: \(filePath)\n\(lines)"
        }
        return diff
    } catch {
        return "Unable to get diff."
    }
}

static func commitWorktreeRemote(host: String, worktreePath: String, message: String) async throws {
    _ = try await RemoteShell.runGit(host: host, inDirectory: worktreePath, args: ["add", "-A"])
    _ = try? await RemoteShell.runGit(host: host, inDirectory: worktreePath, args: ["commit", "-m", message, "--allow-empty"])
}

static func mergeToMainRemote(host: String, projectPath: String, taskId: String, message: String) async throws {
    let status = try await RemoteShell.runGit(host: host, inDirectory: projectPath, args: ["status", "--porcelain"])
    if !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        throw WorktreeError.dirtyWorkingTree
    }
    let taskBranch = "cs/\(taskId)"
    _ = try await RemoteShell.runGit(host: host, inDirectory: projectPath, args: ["merge", taskBranch, "--no-ff", "-m", "Merge \(taskBranch): \(message)"])
}

static func pushBranchRemote(host: String, projectPath: String, taskId: String) async throws {
    let taskBranch = "cs/\(taskId)"
    _ = try await RemoteShell.runGit(host: host, inDirectory: projectPath, args: ["push", "-u", "origin", taskBranch])
}

static func createPRRemote(host: String, projectPath: String, taskId: String, message: String) async throws -> String {
    let taskBranch = "cs/\(taskId)"
    _ = try await RemoteShell.runGit(host: host, inDirectory: projectPath, args: ["push", "-u", "origin", taskBranch])
    let firstLine = message.split(separator: "\n").first.map(String.init) ?? "Changes from \(taskId)"
    let result = try await RemoteShell.run(host: host, command: "cd '\(projectPath)' && gh pr create --head '\(taskBranch)' --title '\(firstLine)' --body '\(message)'")
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
}
```

**Step 2: Verify it compiles**

Run: `cd /Users/jgoai/central-station/app && swift build 2>&1 | tail -5`
Expected: Build complete

**Step 3: Commit**

```bash
git add app/Sources/CentralStation/Services/WorktreeManager.swift
git commit -m "feat: add remote-aware WorktreeManager methods"
```

---

### Task 5: Extend TerminalStore for SSH Launch

**Files:**
- Modify: `app/Sources/CentralStation/Services/TerminalStore.swift`

**Step 1: Update terminal() to handle remote tasks**

Modify the `terminal(for:onProcessExit:)` method. When `task.isRemote`, launch SSH instead of claude directly:

```swift
func terminal(for task: AppTask, onProcessExit: @escaping @MainActor () -> Void) -> LocalProcessTerminalView {
    if let existing = terminals[task.id] {
        return existing
    }

    let termView = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
    termView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    let executable: String
    var args: [String]

    if let sshHost = task.sshHost {
        // Remote task: launch via SSH with reverse tunnel for hooks
        executable = "/usr/bin/ssh"
        args = [
            "-t",  // Force PTY allocation
            "-R", "\(HookServer.defaultPort):localhost:\(HookServer.defaultPort)",  // Reverse tunnel for hooks
            sshHost
        ]
        // Build the remote command
        var remoteCmd: String
        if task.isResume {
            remoteCmd = "cd \(shellEscape(task.worktreePath)) && claude --resume \(task.sessionId)"
        } else {
            remoteCmd = "cd \(shellEscape(task.worktreePath)) && claude --session-id \(task.sessionId)"
            if let mode = task.permissionMode {
                remoteCmd += " --permission-mode \(mode)"
            }
            remoteCmd += " \(shellEscape(task.prompt))"
        }
        args.append(remoteCmd)
    } else {
        // Local task: launch claude directly
        executable = "\(NSHomeDirectory())/.local/bin/claude"
        if task.isResume {
            args = ["--resume", task.sessionId]
        } else {
            args = ["--session-id", task.sessionId]
            if let mode = task.permissionMode {
                args += ["--permission-mode", mode]
            }
            args.append(task.prompt)
        }
    }

    let delegate = ProcessDelegate(onProcessExit: onProcessExit)
    delegates[task.id] = delegate
    termView.processDelegate = delegate

    termView.startProcess(
        executable: executable,
        args: args,
        environment: nil,
        execName: task.isRemote ? "ssh" : "claude",
        currentDirectory: task.isRemote ? NSHomeDirectory() : task.worktreePath
    )

    terminals[task.id] = termView
    return termView
}

private func shellEscape(_ str: String) -> String {
    "'" + str.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
```

**Step 2: Verify it compiles**

Run: `cd /Users/jgoai/central-station/app && swift build 2>&1 | tail -5`
Expected: Build complete

**Step 3: Commit**

```bash
git add app/Sources/CentralStation/Services/TerminalStore.swift
git commit -m "feat: launch remote tasks via SSH with reverse tunnel"
```

---

### Task 6: Extend TaskCoordinator for Remote Tasks

**Files:**
- Modify: `app/Sources/CentralStation/Services/TaskCoordinator.swift`

**Step 1: Add RemoteStore to coordinator**

Add a property and load it on startup:

```swift
let remoteStore = RemoteStore()
```

In `startup()` in App.swift, add `coordinator.remoteStore.load()` after `coordinator.loadPersistedTasks()`.

**Step 2: Add addRemoteTask method**

```swift
func addRemoteTask(id: String, description: String, prompt: String, permissionMode: String?, remote: RemoteConfig, remotePath: String) async throws {
    try await WorktreeManager.ensureGitRepoRemote(host: remote.sshHost, at: remotePath)
    let worktreePath = try await WorktreeManager.createWorktreeRemote(
        host: remote.sshHost, projectPath: remotePath, taskId: id
    )
    let task = AppTask(
        id: id, description: description, prompt: prompt,
        worktreePath: worktreePath, projectPath: remotePath,
        permissionMode: permissionMode,
        remoteAlias: remote.alias, sshHost: remote.sshHost
    )
    tasks.append(task)
    sessionToTaskId[task.sessionId] = task.id
    task.startedAt = Date()
    task.status = .working
    saveTasks()

    // Update default directory on remote
    var updated = remote
    updated.defaultDirectory = remotePath
    remoteStore.update(updated)
}
```

**Step 3: Update refreshDiff to handle remote**

```swift
func refreshDiff(for task: AppTask) async {
    if let host = task.sshHost {
        task.diff = await WorktreeManager.getDiffRemote(host: host, worktreePath: task.worktreePath)
    } else {
        task.diff = await WorktreeManager.getDiff(worktreePath: task.worktreePath)
    }
}
```

**Step 4: Update handleMergeAction to handle remote**

In `handleMergeAction`, before calling WorktreeManager methods, check `task.isRemote` and call the Remote variants:

```swift
func handleMergeAction(task: AppTask, action: MergeAction) async throws -> String? {
    let message: String
    switch action {
    case .mergeToMain(let msg): message = msg
    case .createBranch(let msg): message = msg
    case .createPR(let msg): message = msg
    }

    if let host = task.sshHost {
        try await WorktreeManager.commitWorktreeRemote(host: host, worktreePath: task.worktreePath, message: message)
        var prURL: String?
        switch action {
        case .mergeToMain:
            try await WorktreeManager.mergeToMainRemote(host: host, projectPath: task.projectPath, taskId: task.id, message: message)
        case .createBranch:
            try await WorktreeManager.pushBranchRemote(host: host, projectPath: task.projectPath, taskId: task.id)
        case .createPR:
            prURL = try await WorktreeManager.createPRRemote(host: host, projectPath: task.projectPath, taskId: task.id, message: message)
        }
        task.status = .completed
        saveTasks()
        return prURL
    } else {
        try await WorktreeManager.commitWorktree(worktreePath: task.worktreePath, message: message)
        var prURL: String?
        switch action {
        case .mergeToMain:
            try await WorktreeManager.mergeToMain(projectPath: task.projectPath, taskId: task.id, message: message)
        case .createBranch:
            try await WorktreeManager.pushBranch(projectPath: task.projectPath, taskId: task.id)
        case .createPR:
            prURL = try await WorktreeManager.createPR(projectPath: task.projectPath, taskId: task.id, message: message)
        }
        task.status = .completed
        saveTasks()
        return prURL
    }
}
```

**Step 5: Update deleteTask to handle remote**

```swift
func deleteTask(_ task: AppTask) async {
    TerminalStore.shared.killTerminal(for: task.id)
    if let host = task.sshHost {
        await WorktreeManager.removeWorktreeRemote(host: host, projectPath: task.projectPath, taskId: task.id)
    } else {
        await WorktreeManager.removeWorktree(projectPath: task.projectPath, taskId: task.id)
    }
    sessionToTaskId.removeValue(forKey: task.sessionId)
    tasks.removeAll { $0.id == task.id }
    saveTasks()
}
```

**Step 6: Verify it compiles**

Run: `cd /Users/jgoai/central-station/app && swift build 2>&1 | tail -5`
Expected: Build complete

**Step 7: Commit**

```bash
git add app/Sources/CentralStation/Services/TaskCoordinator.swift app/Sources/CentralStation/App.swift
git commit -m "feat: extend TaskCoordinator for remote task lifecycle"
```

---

### Task 7: Manage Remotes Sheet

**Files:**
- Create: `app/Sources/CentralStation/Views/ManageRemotesSheet.swift`

**Step 1: Create the view**

```swift
// app/Sources/CentralStation/Views/ManageRemotesSheet.swift
import SwiftUI

struct ManageRemotesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let remoteStore: RemoteStore

    @State private var editingRemote: RemoteConfig?
    @State private var showAddForm = false
    @State private var testResult: (id: String, success: Bool, message: String)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Manage Remotes")
                .font(.title2.bold())

            if remoteStore.remotes.isEmpty && !showAddForm {
                VStack(spacing: 12) {
                    Image(systemName: "network")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("No saved remotes")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                List {
                    ForEach(remoteStore.remotes) { remote in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(remote.alias).font(.headline)
                                Text(remote.sshHost)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                if let dir = remote.defaultDirectory {
                                    Text(dir)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }

                            Spacer()

                            if let result = testResult, result.id == remote.id {
                                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(result.success ? .green : .red)
                                    .help(result.message)
                            }

                            Button("Test") {
                                Task {
                                    let result = await remoteStore.testConnection(remote: remote)
                                    switch result {
                                    case .success(let msg):
                                        testResult = (remote.id, true, msg)
                                    case .failure(let err):
                                        testResult = (remote.id, false, err.localizedDescription)
                                    }
                                }
                            }
                            .buttonStyle(.borderless)

                            Button(role: .destructive) {
                                remoteStore.delete(remote)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .frame(minHeight: 120)
            }

            if showAddForm || editingRemote != nil {
                RemoteFormView(
                    remote: editingRemote,
                    onSave: { remote in
                        if editingRemote != nil {
                            remoteStore.update(remote)
                        } else {
                            remoteStore.add(remote)
                        }
                        editingRemote = nil
                        showAddForm = false
                    },
                    onCancel: {
                        editingRemote = nil
                        showAddForm = false
                    }
                )
            }

            HStack {
                Button("Add Remote") { showAddForm = true }
                    .disabled(showAddForm)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 480, minHeight: 300)
    }
}

struct RemoteFormView: View {
    let remote: RemoteConfig?
    let onSave: (RemoteConfig) -> Void
    let onCancel: () -> Void

    @State private var alias: String = ""
    @State private var sshHost: String = ""

    var body: some View {
        GroupBox("New Remote") {
            Form {
                TextField("Alias", text: $alias, prompt: Text("e.g. Dev Server"))
                    .textFieldStyle(.roundedBorder)
                TextField("SSH Host", text: $sshHost, prompt: Text("e.g. user@10.0.1.5 or devbox"))
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Save") {
                    let config = RemoteConfig(
                        id: remote?.id ?? UUID().uuidString.lowercased(),
                        alias: alias,
                        sshHost: sshHost,
                        defaultDirectory: remote?.defaultDirectory
                    )
                    onSave(config)
                }
                .disabled(alias.isEmpty || sshHost.isEmpty)
            }
            .padding(.top, 4)
        }
        .onAppear {
            if let remote {
                alias = remote.alias
                sshHost = remote.sshHost
            }
        }
    }
}
```

**Step 2: Verify it compiles**

Run: `cd /Users/jgoai/central-station/app && swift build 2>&1 | tail -5`
Expected: Build complete

**Step 3: Commit**

```bash
git add app/Sources/CentralStation/Views/ManageRemotesSheet.swift
git commit -m "feat: add Manage Remotes sheet for saved SSH remotes"
```

---

### Task 8: Remote Directory Browser

**Files:**
- Create: `app/Sources/CentralStation/Views/RemoteDirectoryBrowser.swift`

**Step 1: Create the directory browser view**

```swift
// app/Sources/CentralStation/Views/RemoteDirectoryBrowser.swift
import SwiftUI

struct RemoteDirectoryBrowser: View {
    let sshHost: String
    @Binding var selectedPath: String

    @State private var currentPath: String = ""
    @State private var directories: [String] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var pathInput: String = ""
    @State private var isGitRepo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Path input for direct typing
            HStack {
                TextField("Path", text: $pathInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit {
                        navigateTo(pathInput)
                    }
                Button("Go") {
                    navigateTo(pathInput)
                }
                .disabled(pathInput.isEmpty)
            }

            // Breadcrumb bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    Button("/") { navigateTo("/") }
                        .buttonStyle(.borderless)
                    ForEach(breadcrumbs, id: \.path) { crumb in
                        Text("/").foregroundStyle(.tertiary)
                        Button(crumb.name) { navigateTo(crumb.path) }
                            .buttonStyle(.borderless)
                    }
                }
                .font(.caption)
            }

            // Directory list
            if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if let error {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                List {
                    if currentPath != "/" {
                        Button(action: { navigateUp() }) {
                            HStack {
                                Image(systemName: "arrow.turn.up.left")
                                Text("..")
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                    ForEach(directories, id: \.self) { dir in
                        Button(action: { navigateTo(currentPath + "/" + dir) }) {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.blue)
                                Text(dir)
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .frame(minHeight: 150, maxHeight: 200)
            }

            // Status bar
            HStack {
                if isGitRepo {
                    Label("Git repo", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Spacer()
                Button("Select This Directory") {
                    selectedPath = currentPath
                }
                .disabled(currentPath.isEmpty)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .task {
            // Start at home directory or last-used path
            if selectedPath.isEmpty {
                if let home = try? await RemoteShell.homeDirectory(host: sshHost) {
                    navigateTo(home)
                } else {
                    navigateTo("/")
                }
            } else {
                navigateTo(selectedPath)
            }
        }
    }

    private struct Breadcrumb: Hashable {
        let name: String
        let path: String
    }

    private var breadcrumbs: [Breadcrumb] {
        let components = currentPath.split(separator: "/").map(String.init)
        var crumbs: [Breadcrumb] = []
        for (i, name) in components.enumerated() {
            let path = "/" + components[0...i].joined(separator: "/")
            crumbs.append(Breadcrumb(name: name, path: path))
        }
        return crumbs
    }

    private func navigateTo(_ path: String) {
        let cleanPath = path.isEmpty ? "/" : path
        isLoading = true
        error = nil
        Task {
            do {
                let dirs = try await RemoteShell.listDirectories(host: sshHost, path: cleanPath)
                let gitCheck = try await RemoteShell.isGitRepo(host: sshHost, path: cleanPath)
                await MainActor.run {
                    currentPath = cleanPath
                    pathInput = cleanPath
                    directories = dirs.sorted()
                    isGitRepo = gitCheck
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = "Could not list directory: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }

    private func navigateUp() {
        let parent = (currentPath as NSString).deletingLastPathComponent
        navigateTo(parent.isEmpty ? "/" : parent)
    }
}
```

**Step 2: Verify it compiles**

Run: `cd /Users/jgoai/central-station/app && swift build 2>&1 | tail -5`
Expected: Build complete

**Step 3: Commit**

```bash
git add app/Sources/CentralStation/Views/RemoteDirectoryBrowser.swift
git commit -m "feat: add remote directory browser with SSH ls navigation"
```

---

### Task 9: Update AddTaskSheet for Remote Tasks

**Files:**
- Modify: `app/Sources/CentralStation/Views/AddTaskSheet.swift`

**Step 1: Update the onAdd callback signature**

Change the sheet's callback to include optional remote info:

```swift
let onAdd: (String, String, String, String?, String?, RemoteConfig?, String?) -> Void
// params: id, description, prompt, permissionMode, customPath, remote, remotePath
```

**Step 2: Add remote state and UI**

Add state variables:

```swift
@State private var isRemote = false
@State private var selectedRemote: RemoteConfig?
@State private var remotePath = ""
@State private var connectionStatus: ConnectionStatus = .untested
@State private var showManageRemotes = false

let remoteStore: RemoteStore

enum ConnectionStatus {
    case untested, testing, success(String), failed(String)
}
```

**Step 3: Update the form body**

Add a Local/Remote toggle at the top of the form. When Remote is selected, show:
- Remote picker dropdown (+ "Manage Remotes..." button)
- Remote directory browser (using `RemoteDirectoryBrowser`)
- Connection status indicator

Replace the "Working Directory" section conditionally — when remote, show the directory browser instead of the local folder picker.

The Launch button calls onAdd with remote info when in remote mode.

**Step 4: Update isValid**

```swift
private var isValid: Bool {
    if isRemote {
        return !description.isEmpty && !prompt.isEmpty && !taskId.isEmpty && selectedRemote != nil && !remotePath.isEmpty
    }
    return !description.isEmpty && !prompt.isEmpty && !taskId.isEmpty
}
```

**Step 5: Update Launch button action**

```swift
Button("Launch") {
    let mode = permissionMode == "default" ? nil : permissionMode
    if isRemote, let remote = selectedRemote {
        onAdd(taskId, description, prompt, mode, nil, remote, remotePath)
    } else {
        let path = customPath.isEmpty ? nil : customPath
        onAdd(taskId, description, prompt, mode, path, nil, nil)
    }
    dismiss()
}
```

**Step 6: Test connection when remote is selected**

When a remote is picked from the dropdown, automatically test the connection:

```swift
.onChange(of: selectedRemote) { _, remote in
    guard let remote else { return }
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
```

**Step 7: Verify it compiles**

Run: `cd /Users/jgoai/central-station/app && swift build 2>&1 | tail -5`
Expected: Build complete

**Step 8: Commit**

```bash
git add app/Sources/CentralStation/Views/AddTaskSheet.swift
git commit -m "feat: add remote task support to AddTaskSheet"
```

---

### Task 10: Wire Up ContentView and FileDiffView

**Files:**
- Modify: `app/Sources/CentralStation/Views/ContentView.swift`
- Modify: `app/Sources/CentralStation/Views/FileDiffView.swift`
- Modify: `app/Sources/CentralStation/Views/TaskDetailView.swift`
- Modify: `app/Sources/CentralStation/Views/TaskListView.swift`

**Step 1: Update ContentView AddTaskSheet call**

Pass `remoteStore` to AddTaskSheet. Update the `.sheet` modifier to handle the new callback:

```swift
.sheet(isPresented: $showAddTask) {
    AddTaskSheet(defaultProjectPath: coordinator.projectPath, remoteStore: coordinator.remoteStore) { id, description, prompt, mode, customPath, remote, remotePath in
        Task {
            if let remote, let remotePath {
                try? await coordinator.addRemoteTask(
                    id: id, description: description, prompt: prompt,
                    permissionMode: mode, remote: remote, remotePath: remotePath
                )
            } else {
                try? await coordinator.addTask(
                    id: id, description: description, prompt: prompt,
                    permissionMode: mode, customProjectPath: customPath
                )
            }
            if let newTask = coordinator.tasks.last {
                selectedTask = newTask
            }
        }
    }
}
```

**Step 2: Add a "Manage Remotes" option in sidebar**

Add a button near the hooks indicator:

```swift
HStack {
    Button(action: { showHookInfo = true }) {
        Label("Hooks", systemImage: coordinator.hooksInstalled ? "checkmark.circle" : "exclamationmark.triangle")
    }
    .buttonStyle(.borderless)
    .foregroundStyle(coordinator.hooksInstalled ? Color.secondary : Color.orange)
    Spacer()
    Button(action: { showManageRemotes = true }) {
        Label("Remotes", systemImage: "network")
    }
    .buttonStyle(.borderless)
    .foregroundStyle(.secondary)
}
```

Add `@State private var showManageRemotes = false` and the sheet:

```swift
.sheet(isPresented: $showManageRemotes) {
    ManageRemotesSheet(remoteStore: coordinator.remoteStore)
}
```

**Step 3: Update FileDiffView to handle remote diffs**

In `FileDiffView`, check `task.isRemote` and call the remote variants of `getChangedFiles` and `getFileDiff`.

**Step 4: Update TaskListView to show remote indicator**

In `TaskRow`, add a small network icon for remote tasks:

```swift
if task.isRemote {
    Image(systemName: "network")
        .font(.caption2)
        .foregroundStyle(.blue)
        .help(task.remoteAlias ?? task.sshHost ?? "Remote")
}
```

**Step 5: Update TaskDetailView Actions menu**

Disable "Open in Finder" and "Open in Terminal" for remote tasks (the paths are remote). Optionally replace with "SSH into remote":

```swift
if task.isRemote {
    Button(action: {
        let script = "tell application \"Terminal\" to do script \"ssh \(task.sshHost ?? "") -t 'cd \(task.worktreePath) && exec $SHELL'\""
        Process.launchedProcess(launchPath: "/usr/bin/osascript", arguments: ["-e", script])
    }) {
        Label("SSH to Remote", systemImage: "terminal")
    }
} else {
    Button(action: { NSWorkspace.shared.open(URL(fileURLWithPath: task.worktreePath)) }) {
        Label("Open in Finder", systemImage: "folder")
    }
    Button(action: {
        let script = "tell application \"Terminal\" to do script \"cd \(task.worktreePath.replacingOccurrences(of: "\"", with: "\\\""))\""
        Process.launchedProcess(launchPath: "/usr/bin/osascript", arguments: ["-e", script])
    }) {
        Label("Open in Terminal", systemImage: "terminal")
    }
}
```

**Step 6: Verify it compiles**

Run: `cd /Users/jgoai/central-station/app && swift build 2>&1 | tail -5`
Expected: Build complete

**Step 7: Commit**

```bash
git add app/Sources/CentralStation/Views/ContentView.swift app/Sources/CentralStation/Views/FileDiffView.swift app/Sources/CentralStation/Views/TaskDetailView.swift app/Sources/CentralStation/Views/TaskListView.swift
git commit -m "feat: wire up remote task support across all views"
```

---

### Task 11: Update MergeSheet for Remote Tasks

**Files:**
- Modify: `app/Sources/CentralStation/Views/MergeSheet.swift`

**Step 1: Pass task to MergeSheet**

Update `MergeSheet` to accept an `AppTask` instead of just `taskId` and `worktreePath`, so it can check `isRemote` and run diff/commit message generation over SSH when needed.

For the commit message auto-generation (which runs `claude -p` locally on the diff), fetch the diff via SSH for remote tasks, then run the local claude to generate the message.

**Step 2: Verify it compiles**

Run: `cd /Users/jgoai/central-station/app && swift build 2>&1 | tail -5`
Expected: Build complete

**Step 3: Commit**

```bash
git add app/Sources/CentralStation/Views/MergeSheet.swift
git commit -m "feat: update MergeSheet to support remote tasks"
```

---

### Task 12: Install Hooks on Remote

**Files:**
- Modify: `app/Sources/CentralStation/Services/TerminalLauncher.swift`

**Step 1: Add remote hook installation method**

```swift
static func installHooksOnRemote(host: String) async throws {
    let port = HookServer.defaultPort
    let settingsPath = "$HOME/.claude/settings.json"

    // Create .claude dir if needed
    _ = try await RemoteShell.run(host: host, command: "mkdir -p $HOME/.claude")

    // Generate the hooks JSON
    let hooksJSON = """
    {
      "hooks": {
        "Stop": [{"hooks": [{"type": "command", "command": "curl -s --connect-timeout 1 --max-time 2 -X POST http://127.0.0.1:\(port)/hook/stop -H 'Content-Type: application/json' -d \\"$(cat)\\" || true"}]}],
        "Notification": [
          {"hooks": [{"type": "command", "command": "curl -s --connect-timeout 1 --max-time 2 -X POST http://127.0.0.1:\(port)/hook/notification -H 'Content-Type: application/json' -d \\"$(cat)\\" || true"}], "matcher": "permission_prompt"},
          {"hooks": [{"type": "command", "command": "curl -s --connect-timeout 1 --max-time 2 -X POST http://127.0.0.1:\(port)/hook/notification -H 'Content-Type: application/json' -d \\"$(cat)\\" || true"}], "matcher": "idle_prompt"},
          {"hooks": [{"type": "command", "command": "curl -s --connect-timeout 1 --max-time 2 -X POST http://127.0.0.1:\(port)/hook/notification -H 'Content-Type: application/json' -d \\"$(cat)\\" || true"}], "matcher": "elicitation_dialog"}
        ],
        "PermissionRequest": [{"hooks": [{"type": "command", "command": "curl -s --connect-timeout 1 --max-time 2 -X POST http://127.0.0.1:\(port)/hook/permission -H 'Content-Type: application/json' -d \\"$(cat)\\" || true"}]}]
      }
    }
    """

    // Use python/jq to merge hooks into existing settings, or write fresh if none
    let mergeScript = """
    if [ -f \(settingsPath) ]; then
      python3 -c "
    import json, sys
    with open('\(settingsPath.replacingOccurrences(of: "$HOME", with: "' + __import__('os').path.expanduser('~') + '"))') as f:
        existing = json.load(f)
    new_hooks = json.loads(sys.stdin.read())['hooks']
    existing.setdefault('hooks', {}).update(new_hooks)
    existing['hooks'].pop('PreToolUse', None)
    with open('\(settingsPath.replacingOccurrences(of: "$HOME", with: "' + __import__('os').path.expanduser('~') + '"))'), 'w') as f:
        json.dump(existing, f, indent=2)
    " <<'HOOKS_EOF'
    \(hooksJSON)
    HOOKS_EOF
    else
      echo '\(hooksJSON)' > \(settingsPath)
    fi
    """

    _ = try await RemoteShell.run(host: host, command: mergeScript)
}
```

**NOTE:** This is complex string escaping. A simpler approach: just write the hooks JSON directly using `echo` + `python3 -c` on the remote. The implementer should test escaping carefully and simplify if needed — e.g., upload a small script via `cat << 'EOF' > /tmp/install-hooks.py` then run it.

**Step 2: Call it during remote task creation**

In `TaskCoordinator.addRemoteTask()`, before creating the worktree:

```swift
try await TerminalLauncher.installHooksOnRemote(host: remote.sshHost)
```

**Step 3: Verify it compiles**

Run: `cd /Users/jgoai/central-station/app && swift build 2>&1 | tail -5`
Expected: Build complete

**Step 4: Commit**

```bash
git add app/Sources/CentralStation/Services/TerminalLauncher.swift app/Sources/CentralStation/Services/TaskCoordinator.swift
git commit -m "feat: auto-install hooks on remote machine before task launch"
```

---

### Task 13: End-to-End Testing & Polish

**Files:**
- All modified files

**Step 1: Build and run**

```bash
cd /Users/jgoai/central-station/app && swift build 2>&1
```

**Step 2: Manual test checklist**

1. Launch app, verify local tasks still work normally
2. Open Manage Remotes, add a remote, test connection — verify green checkmark
3. Create a new remote task:
   - Toggle to Remote
   - Select saved remote
   - Verify connection status shows success
   - Browse remote file system, select a directory
   - Fill description and prompt, launch
4. Verify terminal shows SSH connection and Claude starts on remote
5. Verify hooks fire (permission requests, notifications appear in UI)
6. Check diff tab shows remote file changes
7. Test Accept/Merge for remote task
8. Stop and resume a remote task — verify SSH reconnects
9. Delete a remote task — verify remote worktree is cleaned up
10. Verify remote tasks show network icon in sidebar

**Step 3: Fix any issues found**

**Step 4: Final commit**

```bash
git add -A
git commit -m "feat: SSH remote task support - complete implementation"
```

---

Plan saved to `docs/plans/2026-03-09-ssh-remote-tasks.md`.

**Two execution options:**

1. **Subagent-Driven (this session)** — I dispatch a fresh subagent per task, review between tasks, fast iteration

2. **Parallel Session (separate)** — Open a new session with executing-plans, batch execution with checkpoints

Which approach?