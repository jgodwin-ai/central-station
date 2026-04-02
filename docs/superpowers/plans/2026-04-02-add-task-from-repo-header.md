# Add Task from Repo Header Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "+" button to each repo section header in the sidebar that opens AddTaskSheet pre-filled with that repo's working directory.

**Architecture:** Thread a new `onAddTaskForRepo` callback through TaskListView, add state in ContentView to track the pre-filled path, and accept an optional initial path in AddTaskSheet.

**Tech Stack:** SwiftUI, Swift Testing framework

---

### Task 1: Add `onAddTaskForRepo` callback and "+" button to TaskListView

**Files:**
- Modify: `app/Sources/CentralStation/Views/TaskListView.swift:3-54`

- [ ] **Step 1: Add the callback property to TaskListView**

Add this property after the existing `onResume` callback at line 9:

```swift
var onAddTaskForRepo: ((String) -> Void)?
```

- [ ] **Step 2: Add the "+" button to the section header**

Replace the section header (lines 40-49) with:

```swift
} header: {
    HStack(spacing: 4) {
        Image(systemName: "folder.fill")
            .font(.caption2)
        Text(group.label)
            .font(.caption.bold())
        Spacer()
        Button(action: { onAddTaskForRepo?(group.directory) }) {
            Image(systemName: "plus")
                .font(.caption2)
        }
        .buttonStyle(.borderless)
        .help("New task in \(group.label)")
    }
    .foregroundStyle(.secondary)
    .help(group.directory)
}
```

- [ ] **Step 3: Build to verify compilation**

Run: `cd app && swift build 2>&1 | tail -5`
Expected: Build succeeds (the callback is optional so existing call sites don't break)

- [ ] **Step 4: Commit**

```bash
git add app/Sources/CentralStation/Views/TaskListView.swift
git commit -m "feat: add + button to repo section headers in TaskListView"
```

---

### Task 2: Add `initialCustomPath` parameter to AddTaskSheet

**Files:**
- Modify: `app/Sources/CentralStation/Views/AddTaskSheet.swift:4-17`

- [ ] **Step 1: Add the initialCustomPath property**

Add this property after line 7 (`let onAdd: ...`):

```swift
var initialCustomPath: String?
```

- [ ] **Step 2: Initialize customPath from initialCustomPath**

Replace the `customPath` state declaration at line 14:

```swift
@State private var customPath = ""
```

with an initializer approach. Since `@State` with an initial value from a property requires an `init`, instead use `onAppear`. Add this modifier to the outermost `VStack` in the `body` (after the existing `.sheet(isPresented: $showManageRemotes)` at line 223):

```swift
.onAppear {
    if let path = initialCustomPath {
        customPath = path
    }
}
```

- [ ] **Step 3: Build to verify compilation**

Run: `cd app && swift build 2>&1 | tail -5`
Expected: Build succeeds (initialCustomPath defaults to nil so existing call sites don't break)

- [ ] **Step 4: Commit**

```bash
git add app/Sources/CentralStation/Views/AddTaskSheet.swift
git commit -m "feat: add initialCustomPath parameter to AddTaskSheet"
```

---

### Task 3: Wire ContentView to pass repo path through to AddTaskSheet

**Files:**
- Modify: `app/Sources/CentralStation/Views/ContentView.swift:7-8,84-106,243-264`

- [ ] **Step 1: Add state for the pre-filled project path**

Add this state property after line 8 (`@State private var showAddTask = false`):

```swift
@State private var addTaskProjectPath: String?
```

- [ ] **Step 2: Wire the onAddTaskForRepo callback in TaskListView**

Add the `onAddTaskForRepo` parameter to the `TaskListView` call (after `onResume` at line 105):

```swift
onAddTaskForRepo: { directory in
    addTaskProjectPath = directory
    showAddTask = true
}
```

- [ ] **Step 3: Pass the path to AddTaskSheet**

In the `.sheet(isPresented: $showAddTask)` block (line 243), add `initialCustomPath` to the `AddTaskSheet` initializer:

```swift
.sheet(isPresented: $showAddTask) {
    AddTaskSheet(defaultProjectPath: coordinator.projectPath, remoteStore: coordinator.remoteStore, initialCustomPath: addTaskProjectPath) { id, description, prompt, mode, customPath, useWorktree, remote, remotePath in
```

- [ ] **Step 4: Clear the path when the sheet is dismissed**

Add an `onDismiss` to the sheet to reset the state:

```swift
.sheet(isPresented: $showAddTask, onDismiss: { addTaskProjectPath = nil }) {
```

- [ ] **Step 5: Build to verify compilation**

Run: `cd app && swift build 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 6: Commit**

```bash
git add app/Sources/CentralStation/Views/ContentView.swift
git commit -m "feat: wire repo + button to open AddTaskSheet with pre-filled path"
```

---

### Task 4: Write tests

**Files:**
- Modify: `app/Tests/CentralStationTests/` (find existing test file or create new one)

- [ ] **Step 1: Check for existing test files**

Run: `ls app/Tests/CentralStationTests/`

Identify where view-related tests live to follow existing conventions.

- [ ] **Step 2: Write test for TaskListView grouped tasks with callback**

Since TaskListView uses SwiftUI views which are hard to unit test directly, and the core logic is in `groupedTasks` (a private computed property), the most valuable testable behavior is that the `onAddTaskForRepo` callback receives the correct directory path. Create a test that verifies the grouping logic produces correct directory values.

Create or add to the appropriate test file:

```swift
import Testing
@testable import CentralStationCore

@Suite("TaskListView repo grouping")
struct TaskListViewTests {
    @Test("Tasks are grouped by projectPath")
    func tasksGroupedByProjectPath() {
        let task1 = AppTask(id: "task-1", description: "First", prompt: "", worktreePath: "/repos/alpha/.worktrees/task-1", projectPath: "/repos/alpha")
        let task2 = AppTask(id: "task-2", description: "Second", prompt: "", worktreePath: "/repos/beta/.worktrees/task-2", projectPath: "/repos/beta")
        let task3 = AppTask(id: "task-3", description: "Third", prompt: "", worktreePath: "/repos/alpha/.worktrees/task-3", projectPath: "/repos/alpha")

        let tasks = [task1, task2, task3]
        var groups: [String: [AppTask]] = [:]
        for task in tasks {
            groups[task.projectPath, default: []].append(task)
        }
        let sorted = groups.sorted { $0.key < $1.key }

        #expect(sorted.count == 2)
        #expect(sorted[0].key == "/repos/alpha")
        #expect(sorted[0].value.count == 2)
        #expect(sorted[1].key == "/repos/beta")
        #expect(sorted[1].value.count == 1)
    }
}
```

- [ ] **Step 3: Verify AppTask init is compatible**

Run: `cd app && swift build 2>&1 | tail -10`

Check if `AppTask` has an accessible initializer with these parameters. If not, adjust the test to use whichever init is available (read `AppTask.swift` to confirm).

- [ ] **Step 4: Run the tests**

Run: `cd app && swift test 2>&1 | tail -20`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add app/Tests/CentralStationTests/
git commit -m "test: add tests for repo grouping logic used by add-task-from-repo feature"
```

---

### Task 5: Manual verification

- [ ] **Step 1: Build and run the app**

Run: `cd app && swift build && .build/debug/CentralStation`

- [ ] **Step 2: Verify the "+" button appears**

Create at least two tasks in different repos. Confirm each repo section header shows a "+" button on the right side.

- [ ] **Step 3: Verify clicking "+" opens AddTaskSheet with pre-filled path**

Click the "+" on a repo header. Confirm the AddTaskSheet opens with the Working Directory showing that repo's path.

- [ ] **Step 4: Verify the main "New Task" button still works**

Click the top-level "New Task" button. Confirm it opens AddTaskSheet with the default project path (no pre-fill from a specific repo).
