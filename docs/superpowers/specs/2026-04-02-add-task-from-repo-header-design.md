# Add Task from Repo Header

## Summary

Add a "+" button to each repository section header in the sidebar's TaskListView. Clicking it opens the AddTaskSheet with the working directory pre-filled to that repo's path and worktree creation enabled by default.

## Design

### TaskListView Changes

- Add `onAddTaskForRepo: (String) -> Void` callback that receives the repo's directory path
- Add a `Button` with `plus` SF Symbol in each section header `HStack`, right-aligned via `Spacer()`
- Style: `.borderless` button, `.caption2` font, `.secondary` foreground to match existing header aesthetic

### ContentView Changes

- Add `@State private var addTaskProjectPath: String?` to track which repo triggered the sheet
- Wire `TaskListView.onAddTaskForRepo` to set this path and open the add-task sheet
- Pass the path into `AddTaskSheet` so it pre-fills `customPath`

### AddTaskSheet Changes

- Add optional `initialCustomPath: String?` parameter (default `nil`)
- Initialize `@State private var customPath` from `initialCustomPath` so the working directory is pre-filled on open

### Tests

- Test that TaskListView calls `onAddTaskForRepo` with the correct directory path when the button is tapped
- Verify AddTaskSheet initializes `customPath` from `initialCustomPath`
