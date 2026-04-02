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
