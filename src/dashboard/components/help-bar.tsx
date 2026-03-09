import React from "react";
import { Box, Text } from "ink";

export function HelpBar() {
  return (
    <Box paddingLeft={1}>
      <Text color="gray">
        <Text bold color="white">[↑↓/jk]</Text> Navigate
        <Text bold color="white">[d]</Text> Diff
        <Text bold color="white">[f]</Text> Focus terminal
        <Text bold color="white">[r]</Text> Refresh diff
        <Text bold color="white">[q]</Text> Quit
      </Text>
    </Box>
  );
}
