import React from "react";
import { Box, Text } from "ink";
import type { TaskState } from "../../types.js";

interface Props {
  task: TaskState | undefined;
}

export function TaskDetail({ task }: Props) {
  if (!task) {
    return (
      <Box flexDirection="column" paddingLeft={1}>
        <Text color="gray">No task selected</Text>
      </Box>
    );
  }

  const truncatedMessage = task.lastMessage
    ? task.lastMessage.length > 200
      ? task.lastMessage.slice(0, 200) + "..."
      : task.lastMessage
    : "No messages yet";

  return (
    <Box flexDirection="column" paddingLeft={1}>
      <Text bold color="cyan">
        Task: {task.id}
      </Text>
      <Text color="gray">"{task.description}"</Text>
      <Text>
        <Text color="gray">Worktree: </Text>
        <Text>{task.worktreePath}</Text>
      </Text>
      <Text>
        <Text color="gray">Session: </Text>
        <Text>{task.sessionId.slice(0, 8)}...</Text>
      </Text>
      <Text>
        <Text color="gray">Last: </Text>
        <Text>{truncatedMessage}</Text>
      </Text>
    </Box>
  );
}
