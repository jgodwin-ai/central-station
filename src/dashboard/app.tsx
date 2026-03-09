import React, { useState, useEffect } from "react";
import { Box, Text, useApp, useInput } from "ink";
import type { TaskManager } from "../core/task-manager.js";
import { TaskList } from "./components/task-list.js";
import { TaskDetail } from "./components/task-detail.js";
import { DiffViewer } from "./components/diff-viewer.js";
import { HelpBar } from "./components/help-bar.js";
import { useTasks, useSelectedTask } from "./hooks/use-tasks.js";

interface Props {
  manager: TaskManager;
}

export function App({ manager }: Props) {
  const app = useApp();
  const tasks = useTasks(manager);
  const { selectedIndex, selectedTask, moveUp, moveDown } =
    useSelectedTask(tasks);
  const [showDiff, setShowDiff] = useState(false);
  const [tick, setTick] = useState(0);

  // Force re-render every 5s to update elapsed times
  useEffect(() => {
    const interval = setInterval(() => setTick((t) => t + 1), 5000);
    return () => clearInterval(interval);
  }, []);

  useInput((input, key) => {
    if (input === "q") {
      manager.stop().then(() => app.exit());
      return;
    }
    if (input === "j" || key.downArrow) {
      moveDown();
    }
    if (input === "k" || key.upArrow) {
      moveUp();
    }
    if (input === "d") {
      setShowDiff((s) => !s);
    }
    if (input === "f" && selectedTask) {
      manager.focusTask(selectedTask.id);
    }
    if (input === "r") {
      // Force diff refresh by toggling
      setShowDiff(false);
      setTimeout(() => setShowDiff(true), 100);
    }
  });

  const needsInput = tasks.filter((t) => t.status === "waiting_for_input").length;

  return (
    <Box flexDirection="column">
      <Box paddingLeft={1}>
        <Text bold color="cyan">
          CENTRAL STATION
        </Text>
        <Text color="gray">
          {"  "}
          {tasks.length} tasks
          {needsInput > 0 && (
            <Text color="yellow"> ({needsInput} need input)</Text>
          )}
        </Text>
      </Box>
      <Text color="gray">{"─".repeat(65)}</Text>

      <TaskList tasks={tasks} selectedIndex={selectedIndex} />

      <Text color="gray">{"─".repeat(65)}</Text>

      <TaskDetail task={selectedTask} />

      {showDiff && selectedTask && (
        <>
          <Text color="gray">{"─".repeat(65)}</Text>
          <DiffViewer
            worktreePath={selectedTask.worktreePath}
            visible={showDiff}
          />
        </>
      )}

      <Text color="gray">{"─".repeat(65)}</Text>
      <HelpBar />
    </Box>
  );
}
