# Repo-First Task Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the modal-based "Add New Task" flow with an instant, repo-first workflow where clicking "+" next to a repo creates a worktree and terminal immediately.

**Architecture:** Repos become first-class persisted entities. Tasks are always created under a repo with auto-generated IDs (`YYYY-MM-DD-task-N`), auto-created worktrees, and descriptions populated asynchronously via Claude CLI summarization of the first prompt. All remote/SSH support is removed.

**Tech Stack:** Swift, SwiftUI, macOS, Swift Testing framework

---

## File Structure

**New files:**
- `app/Sources/CentralStationCore/Models/Repo.swift` — Repo model + RepoPersistence (JSON encoding/decoding and task ID generation)
- `app/Tests/CentralStationTests/RepoTests.swift` — Tests for Repo model and persistence

**Modified files:**
- `app/Sources/CentralStationCore/Models/AppTask.swift` — Remove `prompt`, `permissionMode`, `remoteAlias`, `sshHost`, `isResume` fields; simplify initializers
- `app/Sources/CentralStation/Services/TaskCoordinator.swift` — Remove remote code paths, add repo-based `addTask(for repo:)`, add auto-description via CLI
- `app/Sources/CentralStation/Services/HookServer.swift` — Add `user_message` to HookPayload, change `onWorking` callback to pass prompt text
- `app/Sources/CentralStation/Services/TerminalStore.swift` — Remove remote/SSH terminal, remove permission mode and prompt args
- `app/Sources/CentralStation/Views/ContentView.swift` — Remove AddTaskSheet, add repo management (folder picker + drag-and-drop)
- `app/Sources/CentralStation/Views/TaskListView.swift` — Repo-first sidebar layout with per-repo "+" buttons
- `app/Sources/CentralStation/Views/TaskDetailView.swift` — Remove Shell tab
- `app/Sources/CentralStation/App.swift` — Remove config file loading, remote loading; add repo loading
- `app/Sources/CentralStation/Services/TerminalLauncher.swift` — Remove remote hook installation
- `app/Tests/CentralStationTests/ModelTests.swift` — Update for removed fields
- `app/Tests/CentralStationTests/StatusTransitionTests.swift` — Update for removed fields
- `app/Tests/CentralStationTests/HookInstallationTests.swift` — Remove remote tests

**Deleted files:**
- `app/Sources/CentralStation/Views/AddTaskSheet.swift`
- `app/Sources/CentralStationCore/Models/RemoteConfig.swift`
- `app/Sources/CentralStationCore/Models/TaskConfig.swift`
- `app/Sources/CentralStation/Services/RemoteStore.swift`
- `app/Sources/CentralStation/Services/RemoteShell.swift`

---

### Task 1: Create Repo Model and Persistence

**Files:**
- Create: `app/Sources/CentralStationCore/Models/Repo.swift`
- Create: `app/Tests/CentralStationTests/RepoTests.swift`

- [ ] **Step 1: Write failing tests for Repo model**

In `app/Tests/CentralStationTests/RepoTests.swift`:

```swift
import Testing
import Foundation
@testable import CentralStationCore

@Suite("Repo model")
struct RepoTests {
    @Test func repoNameDerivedFromPath() {
        let repo = Repo(path: "/Users/me/projects/central-station")
        #expect(repo.name == "central-station")
        #expect(!repo.id.isEmpty)
    }

    @Test func repoNameFromTrailingSlash() {
        let repo = Repo(path: "/Users/me/projects/my-app/")
        #expect(repo.name == "my-app")
    }

    @Test func repoRoundTrip() throws {
        let repo = Repo(path: "/Users/me/projects/test")
        let data = try JSONEncoder().encode(repo)
        let decoded = try JSONDecoder().decode(Repo.self, from: data)
        #expect(decoded.id == repo.id)
        #expect(decoded.path == repo.path)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && swift test --filter RepoTests 2>&1 | tail -20`
Expected: Compilation error — `Repo` type not found

- [ ] **Step 3: Implement Repo model**

In `app/Sources/CentralStationCore/Models/Repo.swift`:

```swift
import Foundation

public struct Repo: Identifiable, Codable, Hashable {
    public let id: String
    public let path: String

    public var name: String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        return URL(fileURLWithPath: trimmed).lastPathComponent
    }

    public init(path: String) {
        self.id = UUID().uuidString
        self.path = path
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && swift test --filter RepoTests 2>&1 | tail -20`
Expected: All 3 tests pass

- [ ] **Step 5: Add persistence tests**

Append to `app/Tests/CentralStationTests/RepoTests.swift`:

```swift
@Suite("Repo persistence")
struct RepoPersistenceTests {
    @Test func generateTaskIdIncrementsCounter() {
        var persistence = RepoPersistence(repos: [], nextTaskNumber: 1)
        let id1 = persistence.nextTaskId()
        let id2 = persistence.nextTaskId()

        #expect(id1.hasSuffix("-task-1"))
        #expect(id2.hasSuffix("-task-2"))
        #expect(persistence.nextTaskNumber == 3)
    }

    @Test func generateTaskIdIncludesDate() {
        var persistence = RepoPersistence(repos: [], nextTaskNumber: 1)
        let id = persistence.nextTaskId()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())

        #expect(id.hasPrefix(today))
    }

    @Test func persistenceRoundTrip() throws {
        let repos = [Repo(path: "/Users/me/proj1"), Repo(path: "/Users/me/proj2")]
        let persistence = RepoPersistence(repos: repos, nextTaskNumber: 5)
        let data = try JSONEncoder().encode(persistence)
        let decoded = try JSONDecoder().decode(RepoPersistence.self, from: data)

        #expect(decoded.repos.count == 2)
        #expect(decoded.nextTaskNumber == 5)
        #expect(decoded.repos[0].path == "/Users/me/proj1")
    }

    @Test func counterPersistsAcrossDays() {
        var persistence = RepoPersistence(repos: [], nextTaskNumber: 7)
        let id = persistence.nextTaskId()
        #expect(id.hasSuffix("-task-7"))
        #expect(persistence.nextTaskNumber == 8)
    }
}
```

- [ ] **Step 6: Run tests to verify they fail**

Run: `cd app && swift test --filter RepoPersistenceTests 2>&1 | tail -20`
Expected: Compilation error — `RepoPersistence` not found

- [ ] **Step 7: Implement RepoPersistence**

Append to `app/Sources/CentralStationCore/Models/Repo.swift`:

```swift
public struct RepoPersistence: Codable {
    public var repos: [Repo]
    public var nextTaskNumber: Int

    public init(repos: [Repo] = [], nextTaskNumber: Int = 1) {
        self.repos = repos
        self.nextTaskNumber = nextTaskNumber
    }

    public mutating func nextTaskId() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: Date())
        let id = "\(date)-task-\(nextTaskNumber)"
        nextTaskNumber += 1
        return id
    }
}
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `cd app && swift test --filter "RepoTests|RepoPersistenceTests" 2>&1 | tail -20`
Expected: All 7 tests pass

- [ ] **Step 9: Commit**

```bash
cd app && git add Sources/CentralStationCore/Models/Repo.swift Tests/CentralStationTests/RepoTests.swift
git commit -m "feat: add Repo model and RepoPersistence with task ID generation"
```

---

### Task 2: Simplify AppTask Model — Remove Remote and Config Fields

**Files:**
- Modify: `app/Sources/CentralStationCore/Models/AppTask.swift`
- Modify: `app/Tests/CentralStationTests/ModelTests.swift`

- [ ] **Step 1: Update model tests for simplified AppTask**

Replace the full contents of `app/Tests/CentralStationTests/ModelTests.swift` with:

```swift
import Testing
import Foundation
import SwiftUI
@testable import CentralStationCore

@Suite("Model serialization")
struct ModelTests {
    @Test func persistedTaskRoundTrip() throws {
        let task = PersistedTask(
            id: "2026-04-03-task-1",
            description: "Test task",
            sessionId: "abc-123",
            worktreePath: "/tmp/wt",
            projectPath: "/tmp/proj",
            status: .working
        )

        let data = try JSONEncoder().encode(task)
        let decoded = try JSONDecoder().decode(PersistedTask.self, from: data)

        #expect(decoded.id == "2026-04-03-task-1")
        #expect(decoded.status == .working)
        #expect(decoded.description == "Test task")
    }

    @Test func persistedTaskDefaultsEmptyDescription() throws {
        let json = """
        {
            "id": "t1", "sessionId": "s",
            "worktreePath": "/w", "projectPath": "/p",
            "status": "Pending"
        }
        """
        let task = try JSONDecoder().decode(PersistedTask.self, from: json.data(using: .utf8)!)
        #expect(task.description == "")
    }

    @Test func taskStatusRawValues() {
        #expect(TaskStatus.pending.rawValue == "Pending")
        #expect(TaskStatus.working.rawValue == "Working")
        #expect(TaskStatus.waitingForInput.rawValue == "Needs Input")
        #expect(TaskStatus.completed.rawValue == "Completed")
        #expect(TaskStatus.error.rawValue == "Error")
    }

    @Test func taskStatusColorIsNonNilForAllCases() {
        let allCases: [TaskStatus] = [.pending, .starting, .working, .waitingForInput, .completed, .stopped, .error]
        for status in allCases {
            let _: Color = status.color
        }
    }

    @Test func taskStatusIconStrings() {
        #expect(TaskStatus.pending.icon == "circle")
        #expect(TaskStatus.starting.icon == "circle.dotted")
        #expect(TaskStatus.working.icon == "circle.fill")
        #expect(TaskStatus.waitingForInput.icon == "pause.circle.fill")
        #expect(TaskStatus.completed.icon == "checkmark.circle.fill")
        #expect(TaskStatus.stopped.icon == "stop.circle")
        #expect(TaskStatus.error.icon == "xmark.circle.fill")
    }

    @Test func appTaskInitSimple() {
        let task = AppTask(
            id: "2026-04-03-task-1",
            worktreePath: "/tmp/wt",
            projectPath: "/tmp/proj"
        )

        #expect(task.id == "2026-04-03-task-1")
        #expect(task.description == "")
        #expect(task.worktreePath == "/tmp/wt")
        #expect(task.projectPath == "/tmp/proj")
        #expect(!task.sessionId.isEmpty)
        #expect(task.status == .pending)
    }

    @Test func appTaskInitFromPersistedTask() {
        let persisted = PersistedTask(
            id: "2026-04-03-task-1", description: "Persisted",
            sessionId: "sess-42", worktreePath: "/wt", projectPath: "/proj",
            status: .working
        )
        let task = AppTask(persisted: persisted)

        #expect(task.id == "2026-04-03-task-1")
        #expect(task.description == "Persisted")
        #expect(task.sessionId == "sess-42")
        #expect(task.worktreePath == "/wt")
        #expect(task.projectPath == "/proj")
        #expect(task.status == .working)
    }

    @Test func appTaskToPersistedRoundTrip() {
        let task = AppTask(
            id: "2026-04-03-task-1",
            worktreePath: "/wt",
            projectPath: "/proj"
        )
        task.description = "Round trip"
        task.status = .completed

        let persisted = task.toPersisted()
        #expect(persisted.id == "2026-04-03-task-1")
        #expect(persisted.description == "Round trip")
        #expect(persisted.sessionId == task.sessionId)
        #expect(persisted.status == .completed)
    }

    @Test func appTaskElapsedWhenStartedAtIsNil() {
        let task = AppTask(
            id: "e1",
            worktreePath: "/w",
            projectPath: "/p"
        )
        #expect(task.elapsed == "--")
    }

    @Test func appTaskElapsedWhenStartedAtIsSet() {
        let task = AppTask(
            id: "e2",
            worktreePath: "/w",
            projectPath: "/p"
        )
        task.startedAt = Date().addingTimeInterval(-125)
        let elapsed = task.elapsed
        #expect(elapsed.contains("m"))
        #expect(elapsed.contains("s"))
        #expect(elapsed != "--")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && swift test --filter ModelTests 2>&1 | tail -30`
Expected: Compilation errors — initializers don't match yet

- [ ] **Step 3: Simplify AppTask and PersistedTask**

Rewrite `app/Sources/CentralStationCore/Models/AppTask.swift`. Remove `prompt`, `permissionMode`, `remoteAlias`, `sshHost`, `isResume` from both `PersistedTask` and `AppTask`. Remove the `init(config:)` initializer. Remove `isRemote` computed property. Simplify the main initializer:

`PersistedTask` becomes:
```swift
public struct PersistedTask: Codable {
    public let id: String
    public var description: String
    public let sessionId: String
    public let worktreePath: String
    public let projectPath: String
    public var status: TaskStatus

    public init(id: String, description: String = "", sessionId: String,
                worktreePath: String, projectPath: String, status: TaskStatus) {
        self.id = id
        self.description = description
        self.sessionId = sessionId
        self.worktreePath = worktreePath
        self.projectPath = projectPath
        self.status = status
    }
}
```

`AppTask` initializers become:
```swift
public init(id: String, worktreePath: String, projectPath: String) {
    self.id = id
    self.description = ""
    self.sessionId = UUID().uuidString
    self.worktreePath = worktreePath
    self.projectPath = projectPath
}

public init(persisted: PersistedTask) {
    self.id = persisted.id
    self.description = persisted.description
    self.sessionId = persisted.sessionId
    self.worktreePath = persisted.worktreePath
    self.projectPath = persisted.projectPath
    self.status = persisted.status
}
```

`toPersisted()` becomes:
```swift
public func toPersisted() -> PersistedTask {
    PersistedTask(
        id: id, description: description,
        sessionId: sessionId,
        worktreePath: worktreePath, projectPath: projectPath,
        status: status
    )
}
```

Remove `isRemote`, `hasWorktree` computed properties. Keep `elapsed`, `groupByRepo()`, `TaskStatus`, `SessionUsage`, and the remaining UI properties (`diff`, `pendingPermission`, `lastMessage`, `lastActivityAt`, `startedAt`, `terminalWindowId`, `usage`).

- [ ] **Step 4: Run model tests to verify they pass**

Run: `cd app && swift test --filter ModelTests 2>&1 | tail -20`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
cd app && git add Sources/CentralStationCore/Models/AppTask.swift Tests/CentralStationTests/ModelTests.swift
git commit -m "refactor: simplify AppTask — remove remote, config, and permission fields"
```

---

### Task 3: Delete Remote Infrastructure and TaskConfig

**Files:**
- Delete: `app/Sources/CentralStationCore/Models/RemoteConfig.swift`
- Delete: `app/Sources/CentralStationCore/Models/TaskConfig.swift`
- Delete: `app/Sources/CentralStation/Services/RemoteStore.swift`
- Delete: `app/Sources/CentralStation/Services/RemoteShell.swift`
- Delete: `app/Sources/CentralStation/Views/AddTaskSheet.swift`
- Modify: `app/Tests/CentralStationTests/ModelTests.swift` (remove RemoteConfig test if still present)

- [ ] **Step 1: Delete the files**

```bash
cd app
rm Sources/CentralStationCore/Models/RemoteConfig.swift
rm Sources/CentralStationCore/Models/TaskConfig.swift
rm Sources/CentralStation/Services/RemoteStore.swift
rm Sources/CentralStation/Services/RemoteShell.swift
rm Sources/CentralStation/Views/AddTaskSheet.swift
```

- [ ] **Step 2: Remove remote WorktreeManager methods from executable target**

In `app/Sources/CentralStation/Services/WorktreeManager.swift`, remove all methods that reference remote/SSH operations: `ensureGitRepoRemote`, `createWorktreeRemote`, `removeWorktreeRemote`, `getDiffRemote`, `getChangedFilesRemote`, `getFileDiffRemote`, `commitWorktreeRemote`, `mergeToMainRemote`, `pushBranchRemote`, `createPRRemote`. Keep only `pushBranch` and `createPR` (local versions).

- [ ] **Step 3: Verify the project compiles**

Run: `cd app && swift build 2>&1 | tail -30`
Expected: Compilation errors in files that reference deleted types (TaskCoordinator, ContentView, TaskDetailView, TerminalStore, App.swift, etc.). This is expected — we'll fix these in subsequent tasks.

- [ ] **Step 4: Commit the deletions**

```bash
cd app && git add -A
git commit -m "refactor: delete remote infrastructure, TaskConfig, and AddTaskSheet"
```

---

### Task 4: Simplify TaskCoordinator — Repo-First Task Creation

**Files:**
- Modify: `app/Sources/CentralStation/Services/TaskCoordinator.swift`

- [ ] **Step 1: Rewrite TaskCoordinator for repo-first flow**

Key changes to `TaskCoordinator`:

1. Replace `projectPath: String` property with `var repoPersistence: RepoPersistence` (loaded from `~/.claude/central-station-repos.json`)
2. Add `loadRepos()` and `saveRepos()` methods for persistence
3. Replace `addTask(id:description:prompt:mode:customPath:useWorktree:)` with:

```swift
func addTask(for repo: Repo) -> AppTask {
    let taskId = repoPersistence.nextTaskId()
    let worktreePath = WorktreeManager.createWorktree(projectPath: repo.path, taskId: taskId)
    let task = AppTask(id: taskId, worktreePath: worktreePath, projectPath: repo.path)
    task.status = .working
    task.startedAt = Date()
    tasks.append(task)
    sessionToTask[task.sessionId] = task.id
    saveRepos()
    saveTasks()
    return task
}
```

4. Remove `addRemoteTask()` entirely
5. Remove `loadConfig(from:)` entirely
6. Add repo CRUD methods:

```swift
func addRepo(path: String) {
    let repo = Repo(path: path)
    repoPersistence.repos.append(repo)
    saveRepos()
}

func removeRepo(id: String) {
    repoPersistence.repos.removeAll { $0.id == id }
    saveRepos()
}
```

7. Update `deleteTask()` to remove remote-specific cleanup. Keep worktree removal and terminal kill.
8. Update `handleMergeAction()` — remove all remote branches (keep local merge, push, PR).
9. Remove `resumeTask()` or simplify (the `isResume` field is gone — if we keep resume, we just restart the terminal for the existing task). Keep a simplified version that sets status to `.starting`.
10. Add `summarizeFirstPrompt(taskId:promptText:)`:

```swift
func summarizeFirstPrompt(taskId: String, promptText: String) {
    guard let task = tasks.first(where: { $0.id == taskId }),
          task.description.isEmpty else { return }

    Task {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        let escaped = promptText.replacingOccurrences(of: "\"", with: "\\\"")
        process.arguments = ["claude", "-p", "Summarize this task in 3-5 words as a short title. Output ONLY the title, nothing else: \(escaped)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let summary = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            await MainActor.run {
                task.description = summary
                self.saveTasks()
            }
        }
    }
}
```

11. Update `start()` to use `repoPersistence` instead of `projectPath`. Remove config-based task creation logic. Keep hook server startup. Note: the `onWorking` callback wiring for `summarizeFirstPrompt` happens in Task 5 after HookServer is updated — for now, just define the `summarizeFirstPrompt` method.

- [ ] **Step 2: Verify compilation**

Run: `cd app && swift build 2>&1 | tail -30`
Expected: May still fail due to ContentView/other UI references. That's fine — we'll fix those next.

- [ ] **Step 3: Commit**

```bash
cd app && git add Sources/CentralStation/Services/TaskCoordinator.swift
git commit -m "refactor: TaskCoordinator — repo-first task creation, remove remote code paths"
```

---

### Task 5: Update HookServer — Capture Prompt Text

**Files:**
- Modify: `app/Sources/CentralStation/Services/HookServer.swift`

- [ ] **Step 1: Add user_message to HookPayload**

In `HookPayload`, add:
```swift
let user_message: String?
```

- [ ] **Step 2: Change onWorking callback signature**

Change the callback from:
```swift
var onWorking: ((String) -> Void)?  // (sessionId)
```
to:
```swift
var onWorking: ((String, String?) -> Void)?  // (sessionId, promptText)
```

- [ ] **Step 3: Pass prompt text in /hook/prompt handler**

Update the `/hook/prompt` handler:
```swift
} else if firstLine.contains("/hook/prompt") {
    if let sessionId = payload.session_id {
        let promptText = payload.user_message
        DispatchQueue.main.async {
            self.onWorking?(sessionId, promptText)
        }
    }
}
```

- [ ] **Step 4: Update TaskCoordinator's hook callback registration**

In `TaskCoordinator.start()`, update the `onWorking` handler to call `summarizeFirstPrompt`:
```swift
hookServer.onWorking = { [weak self] sessionId, promptText in
    self?.handleWorking(sessionId: sessionId)
    if let promptText, let taskId = self?.sessionToTask[sessionId] {
        self?.summarizeFirstPrompt(taskId: taskId, promptText: promptText)
    }
}
```

- [ ] **Step 5: Commit**

```bash
cd app && git add Sources/CentralStation/Services/HookServer.swift Sources/CentralStation/Services/TaskCoordinator.swift
git commit -m "feat: capture prompt text from UserPromptSubmit hook for auto-description"
```

---

### Task 6: Simplify TerminalStore

**Files:**
- Modify: `app/Sources/CentralStation/Services/TerminalStore.swift`

- [ ] **Step 1: Remove remote terminal support and simplify command building**

In `TerminalStore`, the `terminal(for:)` method currently branches on `task.isRemote` and builds SSH commands with reverse tunnels. Remove the entire remote branch. Simplify the local command to always use:

```swift
let claudeArgs = "--session-id \(task.sessionId)"
let cmd = "cd \(shellEscape(task.worktreePath)) && exec claude \(claudeArgs)"
```

Remove:
- The `task.isRemote` branch with SSH command building
- The `--permission-mode` argument (always use default)
- The initial prompt argument (`task.prompt`)
- The `--resume` vs `--session-id` logic (always use `--session-id`)
- The hookPort parameter since we don't need it for remote tunnels

Keep:
- Terminal caching per task
- Shell escaping utility
- Process exit callback
- killTerminal(), killAll()

- [ ] **Step 2: Verify compilation**

Run: `cd app && swift build 2>&1 | tail -30`

- [ ] **Step 3: Commit**

```bash
cd app && git add Sources/CentralStation/Services/TerminalStore.swift
git commit -m "refactor: simplify TerminalStore — remove remote/SSH support and extra CLI args"
```

---

### Task 7: Simplify TerminalLauncher — Remove Remote Hook Installation

**Files:**
- Modify: `app/Sources/CentralStation/Services/TerminalLauncher.swift`

- [ ] **Step 1: Remove remote hook installation**

The `TerminalLauncher` has two code paths for installing hooks: local (writing to `~/.claude/settings.json`) and remote (writing via SSH to remote `settings.json`). Remove the entire remote path — the `installHooksRemote` method or remote branch in `installHooks`. Keep only the local hook installation.

Also remove the `SubagentStop` hook type if it was only needed for remote — check if it's used for local tasks too. If used for local, keep it.

- [ ] **Step 2: Verify compilation**

Run: `cd app && swift build 2>&1 | tail -30`

- [ ] **Step 3: Commit**

```bash
cd app && git add Sources/CentralStation/Services/TerminalLauncher.swift
git commit -m "refactor: remove remote hook installation from TerminalLauncher"
```

---

### Task 8: Update ContentView — Repo Management UI

**Files:**
- Modify: `app/Sources/CentralStation/Views/ContentView.swift`

- [ ] **Step 1: Replace AddTaskSheet with repo management**

Key changes to `ContentView`:

1. Remove `@State private var showingAddTask = false` and the `.sheet` for AddTaskSheet
2. Remove the `ManageRemotesSheet` button and sheet
3. Remove the Cmd+N keyboard shortcut
4. Add "Add Repo" button in the toolbar that opens `NSOpenPanel`:

```swift
Button(action: pickRepoFolder) {
    Label("Add Repo", systemImage: "plus.rectangle.on.folder")
}
```

5. Add `pickRepoFolder()` method:

```swift
private func pickRepoFolder() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.message = "Select a git repository folder"
    if panel.runModal() == .OK, let url = panel.url {
        let path = url.path
        // Validate it's a git repo
        if FileManager.default.fileExists(atPath: path + "/.git") {
            coordinator.addRepo(path: path)
        } else {
            showNotGitRepoAlert = true
        }
    }
}
```

6. Add alert for non-git-repo folders:
```swift
@State private var showNotGitRepoAlert = false
// ... in body:
.alert("Not a Git Repository", isPresented: $showNotGitRepoAlert) {
    Button("OK") {}
} message: {
    Text("The selected folder is not a git repository. Please select a folder that contains a .git directory.")
}
```

7. Remove the `onAdd` closure that was passed to `AddTaskSheet` (the old 15+ parameter callback)

8. Add drag-and-drop on the sidebar — handle `.onDrop(of:)` for file URLs, validate they're git repos, call `coordinator.addRepo(path:)`

9. Update the "+" button handler on repo sections to call:
```swift
let task = coordinator.addTask(for: repo)
selectedTaskId = task.id
```

- [ ] **Step 2: Verify compilation**

Run: `cd app && swift build 2>&1 | tail -30`

- [ ] **Step 3: Commit**

```bash
cd app && git add Sources/CentralStation/Views/ContentView.swift
git commit -m "feat: replace AddTaskSheet with repo management UI — folder picker and drag-and-drop"
```

---

### Task 9: Update TaskListView — Repo-First Sidebar

**Files:**
- Modify: `app/Sources/CentralStation/Views/TaskListView.swift`

- [ ] **Step 1: Rewrite sidebar for repo-first layout**

Key changes to `TaskListView`:

1. Accept `repos: [Repo]` as input instead of deriving groups from task `projectPath`
2. Each repo is a `Section` with folder icon, repo name, and "+" button
3. Tasks are filtered per repo by matching `task.projectPath == repo.path`
4. Repos with zero tasks still display (they're persisted independently)
5. Add "Remove Repo" context menu on repo headers (only if no active tasks)
6. Task rows: simplify by removing remote badge, permission mode display
7. Keep: status icon, task ID, description (or placeholder if empty), elapsed time, context menu (stop, delete)

```swift
struct TaskListView: View {
    let repos: [Repo]
    let tasks: [AppTask]
    @Binding var selectedTaskId: String?
    var onAddTask: (Repo) -> Void
    var onRemoveRepo: (Repo) -> Void

    var body: some View {
        List(selection: $selectedTaskId) {
            ForEach(repos) { repo in
                Section {
                    let repoTasks = tasks.filter { $0.projectPath == repo.path }
                    ForEach(repoTasks) { task in
                        TaskRow(task: task)
                            .tag(task.id)
                    }
                } header: {
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.blue)
                        Text(repo.name)
                            .fontWeight(.semibold)
                        Spacer()
                        Button(action: { onAddTask(repo) }) {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.plain)
                    }
                    .contextMenu {
                        Button("Remove Repo", role: .destructive) {
                            onRemoveRepo(repo)
                        }
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Verify compilation**

Run: `cd app && swift build 2>&1 | tail -30`

- [ ] **Step 3: Commit**

```bash
cd app && git add Sources/CentralStation/Views/TaskListView.swift
git commit -m "feat: repo-first sidebar layout with per-repo task grouping"
```

---

### Task 10: Update TaskDetailView — Remove Shell Tab

**Files:**
- Modify: `app/Sources/CentralStation/Views/TaskDetailView.swift`

- [ ] **Step 1: Remove the Shell tab**

In `TaskDetailView`:

1. Remove the `.shell` case from the tab enum (or the `EmbeddedShellView` tab option)
2. Remove the `EmbeddedShellView` from the tab content switch
3. Keep: Terminal, Diff, Files tabs
4. Remove any references to `task.isRemote` or `task.sshHost` in action menus (e.g., "Open in VS Code via SSH")

- [ ] **Step 2: Verify compilation**

Run: `cd app && swift build 2>&1 | tail -30`

- [ ] **Step 3: Commit**

```bash
cd app && git add Sources/CentralStation/Views/TaskDetailView.swift
git commit -m "refactor: remove Shell tab from TaskDetailView"
```

---

### Task 11: Update App.swift — Simplified Startup

**Files:**
- Modify: `app/Sources/CentralStation/App.swift`

- [ ] **Step 1: Simplify startup sequence**

In `App.swift`:

1. Remove config file loading (args-based path, tasks.yaml/json scanning)
2. Remove remote config loading (`RemoteStore` references)
3. Add repo loading: `coordinator.loadRepos()` which reads `~/.claude/central-station-repos.json` into `coordinator.repoPersistence`
4. Keep: persisted task loading, system requirements check, hook server startup

The startup sequence becomes:
```
1. Check system requirements
2. Load persisted tasks
3. Load repos
4. Start coordinator (hook server)
```

- [ ] **Step 2: Verify compilation**

Run: `cd app && swift build 2>&1 | tail -30`

- [ ] **Step 3: Commit**

```bash
cd app && git add Sources/CentralStation/App.swift
git commit -m "refactor: simplify app startup — remove config and remote loading, add repo loading"
```

---

### Task 12: Update Existing Tests

**Files:**
- Modify: `app/Tests/CentralStationTests/StatusTransitionTests.swift`
- Modify: `app/Tests/CentralStationTests/HookInstallationTests.swift`

- [ ] **Step 1: Update StatusTransitionTests for simplified AppTask**

Update all `AppTask(...)` initializer calls throughout `StatusTransitionTests.swift`:
- Remove `prompt:`, `permissionMode:`, `sshHost:`, `remoteAlias:` parameters
- Use the new `AppTask(id:worktreePath:projectPath:)` initializer
- Remove any tests that specifically test remote behavior (e.g., "remote command building")
- Remove tests for `isResume` flag if they relied on the removed field
- Keep all status transition tests, hook handler tests, and lifecycle tests — just update the initializer calls

- [ ] **Step 2: Update HookInstallationTests**

- Remove tests for remote hook installation
- Update any tests that reference `RemoteConfig`, `RemoteShell`, or remote settings.json paths
- Keep tests for local hook installation

- [ ] **Step 3: Run all tests**

Run: `cd app && swift test 2>&1 | tail -30`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
cd app && git add Tests/CentralStationTests/
git commit -m "test: update existing tests for simplified AppTask model"
```

---

### Task 13: Final Build Verification and Cleanup

**Files:**
- Any remaining compilation errors across all files

- [ ] **Step 1: Full build**

Run: `cd app && swift build 2>&1`
Fix any remaining compilation errors. Common issues:
- Views referencing `task.prompt`, `task.permissionMode`, `task.isRemote`, `task.sshHost`
- References to deleted types (`RemoteConfig`, `TaskConfig`, `RemoteStore`, `RemoteShell`)
- Stale imports

- [ ] **Step 2: Run all tests**

Run: `cd app && swift test 2>&1`
Expected: All tests pass

- [ ] **Step 3: Commit any remaining fixes**

```bash
cd app && git add -A
git commit -m "fix: resolve remaining compilation errors after repo-first refactor"
```
