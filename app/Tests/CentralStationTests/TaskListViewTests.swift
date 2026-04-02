import Testing
@testable import CentralStationCore

@Suite("TaskListView repo grouping")
struct TaskListViewTests {
    @Test("Tasks are grouped by projectPath")
    func tasksGroupedByProjectPath() {
        let task1 = AppTask(id: "task-1", description: "First", prompt: "", worktreePath: "/repos/alpha/.worktrees/task-1", projectPath: "/repos/alpha")
        let task2 = AppTask(id: "task-2", description: "Second", prompt: "", worktreePath: "/repos/beta/.worktrees/task-2", projectPath: "/repos/beta")
        let task3 = AppTask(id: "task-3", description: "Third", prompt: "", worktreePath: "/repos/alpha/.worktrees/task-3", projectPath: "/repos/alpha")

        let groups = AppTask.groupByRepo([task1, task2, task3])

        #expect(groups.count == 2)
        #expect(groups[0].directory == "/repos/alpha")
        #expect(groups[0].label == "alpha")
        #expect(groups[0].tasks.count == 2)
        #expect(groups[1].directory == "/repos/beta")
        #expect(groups[1].label == "beta")
        #expect(groups[1].tasks.count == 1)
    }

    @Test("Empty task list produces no groups")
    func emptyTaskList() {
        let groups = AppTask.groupByRepo([])
        #expect(groups.isEmpty)
    }

    @Test("Single task produces one group")
    func singleTask() {
        let task = AppTask(id: "task-1", description: "Only", prompt: "", worktreePath: "/repos/solo/.worktrees/task-1", projectPath: "/repos/solo")
        let groups = AppTask.groupByRepo([task])

        #expect(groups.count == 1)
        #expect(groups[0].directory == "/repos/solo")
        #expect(groups[0].label == "solo")
    }
}
