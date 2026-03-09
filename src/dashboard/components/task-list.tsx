import React from "react";
import { Box, Text } from "ink";
import type { TaskState } from "../../types.js";
import { formatElapsed } from "../../core/task.js";

const STATUS_DISPLAY: Record<string, { icon: string; color: string }> = {
  pending: { icon: "○", color: "gray" },
  starting: { icon: "◌", color: "yellow" },
  working: { icon: "●", color: "green" },
  waiting_for_input: { icon: "⏸", color: "yellow" },
  completed: { icon: "✓", color: "cyan" },
  error: { icon: "✗", color: "red" },
};

interface Props {
  tasks: TaskState[];
  selectedIndex: number;
}

export function TaskList({ tasks, selectedIndex }: Props) {
  return (
    <Box flexDirection="column">
      <Box>
        <Text bold>
          <Text color="gray">{" # │ "}</Text>
          <Text>{"Task".padEnd(20)}</Text>
          <Text color="gray">{" │ "}</Text>
          <Text>{"Status".padEnd(18)}</Text>
          <Text color="gray">{" │ "}</Text>
          <Text>{"Time"}</Text>
        </Text>
      </Box>
      <Text color="gray">{"─".repeat(65)}</Text>
      {tasks.map((task, i) => {
        const selected = i === selectedIndex;
        const { icon, color } = STATUS_DISPLAY[task.status] ?? STATUS_DISPLAY.pending;
        const statusLabel =
          task.status === "waiting_for_input" ? "Needs Input" : task.status;

        return (
          <Box key={task.id}>
            <Text>
              <Text color={selected ? "cyan" : "white"}>
                {selected ? ">" : " "}
              </Text>
              <Text color="gray">{`${(i + 1).toString().padStart(2)} │ `}</Text>
              <Text color={selected ? "cyan" : "white"} bold={selected}>
                {task.id.padEnd(20)}
              </Text>
              <Text color="gray">{" │ "}</Text>
              <Text color={color as any}>
                {`${icon} ${statusLabel}`.padEnd(18)}
              </Text>
              <Text color="gray">{" │ "}</Text>
              <Text>{formatElapsed(task)}</Text>
            </Text>
          </Box>
        );
      })}
    </Box>
  );
}
