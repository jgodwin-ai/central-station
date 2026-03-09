#!/usr/bin/env node
import { program } from "commander";
import React from "react";
import { render } from "ink";
import { loadConfig } from "./config/loader.js";
import { TaskManager } from "./core/task-manager.js";
import { App } from "./dashboard/app.js";

program
  .name("central-station")
  .description("Terminal multiplexer for Claude Code instances")
  .argument("<config>", "Path to tasks.yaml config file")
  .action(async (configPath: string) => {
    let config: ReturnType<typeof loadConfig>;
    try {
      config = loadConfig(configPath);
    } catch (err) {
      console.error(
        err instanceof Error ? err.message : "Failed to load config"
      );
      process.exit(1);
    }

    const manager = new TaskManager(config);

    const { waitUntilExit } = render(React.createElement(App, { manager }));

    try {
      await manager.start();
    } catch (err) {
      console.error(
        "Failed to start:",
        err instanceof Error ? err.message : String(err)
      );
      process.exit(1);
    }

    await waitUntilExit();
    process.exit(0);
  });

program.parse();
