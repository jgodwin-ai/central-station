import { z } from "zod";

export const TaskConfigSchema = z.object({
  id: z
    .string()
    .regex(/^[a-z0-9-]+$/, "Task ID must be lowercase alphanumeric with dashes"),
  description: z.string().min(1),
  prompt: z.string().min(1),
  worktree: z.boolean().default(true),
  permission_mode: z
    .enum(["default", "acceptEdits", "plan", "auto"])
    .optional(),
});

export const ProjectConfigSchema = z.object({
  project: z.string().min(1),
  tasks: z.array(TaskConfigSchema).min(1, "At least one task is required"),
});

export type TaskConfigInput = z.input<typeof TaskConfigSchema>;
export type ProjectConfigInput = z.input<typeof ProjectConfigSchema>;
