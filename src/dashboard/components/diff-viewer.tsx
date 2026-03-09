import React, { useState, useEffect } from "react";
import { Box, Text } from "ink";
import { getWorktreeDiff } from "../../core/worktree-manager.js";

interface Props {
  worktreePath: string;
  visible: boolean;
}

export function DiffViewer({ worktreePath, visible }: Props) {
  const [diff, setDiff] = useState<string>("Loading diff...");
  const [scrollOffset, setScrollOffset] = useState(0);

  useEffect(() => {
    if (!visible) return;
    setScrollOffset(0);
    getWorktreeDiff(worktreePath).then(setDiff);
  }, [worktreePath, visible]);

  if (!visible) return null;

  const lines = diff.split("\n");
  const maxLines = 20;
  const visibleLines = lines.slice(scrollOffset, scrollOffset + maxLines);

  return (
    <Box flexDirection="column" borderStyle="single" borderColor="gray">
      <Text bold> Diff ({lines.length} lines) </Text>
      {visibleLines.map((line, i) => {
        let color: string = "white";
        if (line.startsWith("+") && !line.startsWith("+++")) color = "green";
        else if (line.startsWith("-") && !line.startsWith("---")) color = "red";
        else if (line.startsWith("@@")) color = "cyan";
        else if (line.startsWith("diff ") || line.startsWith("index ")) color = "gray";

        return (
          <Text key={scrollOffset + i} color={color as any}>
            {line}
          </Text>
        );
      })}
      {lines.length > maxLines && (
        <Text color="gray">
          {" "}
          Showing {scrollOffset + 1}-{Math.min(scrollOffset + maxLines, lines.length)} of{" "}
          {lines.length} lines
        </Text>
      )}
    </Box>
  );
}
