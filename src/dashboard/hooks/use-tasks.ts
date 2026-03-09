import { useState, useEffect, useCallback } from "react";
import type { TaskState, TaskStatus } from "../../types.js";
import type { TaskManager } from "../../core/task-manager.js";

export function useTasks(manager: TaskManager) {
  const [tasks, setTasks] = useState<TaskState[]>(manager.getTasks());

  useEffect(() => {
    const handler = () => setTasks([...manager.getTasks()]);
    manager.on("update", handler);
    return () => {
      manager.off("update", handler);
    };
  }, [manager]);

  return tasks;
}

export function useSelectedTask(tasks: TaskState[]) {
  const [selectedIndex, setSelectedIndex] = useState(0);

  const clampedIndex = Math.min(selectedIndex, Math.max(0, tasks.length - 1));

  const moveUp = useCallback(() => {
    setSelectedIndex((i) => Math.max(0, i - 1));
  }, []);

  const moveDown = useCallback(() => {
    setSelectedIndex((i) => Math.min(tasks.length - 1, i + 1));
  }, [tasks.length]);

  return {
    selectedIndex: clampedIndex,
    selectedTask: tasks[clampedIndex] as TaskState | undefined,
    moveUp,
    moveDown,
  };
}
