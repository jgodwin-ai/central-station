import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { parse as parseYaml } from "yaml";
import { ProjectConfigSchema } from "./schema.js";
import type { ProjectConfig } from "../types.js";

export function loadConfig(configPath: string): ProjectConfig {
  const absPath = resolve(configPath);
  let raw: string;
  try {
    raw = readFileSync(absPath, "utf-8");
  } catch {
    throw new Error(`Cannot read config file: ${absPath}`);
  }

  let parsed: unknown;
  try {
    parsed = parseYaml(raw);
  } catch {
    throw new Error(`Invalid YAML in config file: ${absPath}`);
  }

  const result = ProjectConfigSchema.safeParse(parsed);
  if (!result.success) {
    const issues = result.error.issues
      .map((i) => `  - ${i.path.join(".")}: ${i.message}`)
      .join("\n");
    throw new Error(`Invalid config:\n${issues}`);
  }

  return result.data;
}
