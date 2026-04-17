#!/usr/bin/env node

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { readFileSync, writeFileSync, existsSync, mkdirSync, appendFileSync, createWriteStream } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import { randomUUID } from "crypto";
import { spawn } from "child_process";
import { tmpdir } from "os";

// Task storage
interface Task {
  id: string;
  title: string;
  description: string;
  status: "pending" | "running" | "completed" | "failed";
  result?: string;
  createdAt: string;
  updatedAt: string;
}

const __dirname = dirname(fileURLToPath(import.meta.url));
const DATA_DIR = process.env.COWORK_DATA_DIR || join(__dirname, "..");
const TASKS_FILE = join(DATA_DIR, "tasks.json");
const LOGS_DIR = join(DATA_DIR, "logs");

// Project root: walk up from __dirname until we find a .git directory.
// Works regardless of how deep this package lives inside the repo.
function findRepoRoot(start: string): string {
  let dir = start;
  while (true) {
    if (existsSync(join(dir, ".git"))) return dir;
    const parent = dirname(dir);
    if (parent === dir) return start;
    dir = parent;
  }
}
const PROJECT_DIR = process.env.COWORK_PROJECT_DIR || findRepoRoot(__dirname);
const MCP_CONFIG_PATH = process.env.COWORK_MCP_CONFIG || join(PROJECT_DIR, ".mcp.json");

// Ensure logs directory exists
if (!existsSync(LOGS_DIR)) mkdirSync(LOGS_DIR, { recursive: true });

/** Word-wrap text to a given width, preserving existing line breaks. */
function wordWrap(text: string, width: number = 100): string {
  return text.split("\n").map((line) => {
    if (line.length <= width) return line;
    const words = line.split(" ");
    const wrapped: string[] = [];
    let current = "";
    for (const word of words) {
      if (current.length + word.length + 1 > width && current.length > 0) {
        wrapped.push(current);
        current = word;
      } else {
        current = current ? current + " " + word : word;
      }
    }
    if (current) wrapped.push(current);
    return wrapped.join("\n");
  }).join("\n");
}

/** Truncate description if over 50 lines: show first 40 with indicator. */
function truncateDescription(text: string): string {
  const lines = text.split("\n");
  if (lines.length <= 50) return text;
  return lines.slice(0, 40).join("\n") + `\n\n[truncated — showing 40 of ${lines.length} lines]`;
}

// Track task IDs with active subprocesses (in-memory only, lost on restart — that's the point)
const activeSubprocesses = new Set<string>();

/** Fire-and-forget: spawn headless Claude for a task, handle completion/failure. */
function spawnTaskSubprocess(task: Task): void {
  activeSubprocesses.add(task.id);
  runHeadlessClaude(task).then(() => {
    activeSubprocesses.delete(task.id);
    const current = loadTasks();
    const t = current.find((x) => x.id === task.id);
    if (t && t.status === "running") {
      t.status = "completed";
      t.result = t.result || "(subprocess exited successfully without calling complete_task)";
      t.updatedAt = new Date().toISOString();
      saveTasks(current);
    }
  }).catch((err) => {
    activeSubprocesses.delete(task.id);
    const current = loadTasks();
    const t = current.find((x) => x.id === task.id);
    if (t) {
      t.status = "failed";
      t.result = err.message;
      t.updatedAt = new Date().toISOString();
      saveTasks(current);
    }
  });
}

/** On startup, re-spawn Claude for any "running" tasks without an active subprocess. */
function resumeOrphanedTasks(): void {
  const tasks = loadTasks();
  for (const task of tasks) {
    if (task.status === "running" && !activeSubprocesses.has(task.id)) {
      console.error(`[cowork-mcp] Resuming orphaned task ${task.id}: ${task.title}`);
      spawnTaskSubprocess(task);
    }
  }
}

/**
 * Spawn headless `claude -p` for a task. Streams output to log file.
 * Returns stdout on success, rejects on non-zero exit.
 * Does NOT manage task status — callers handle that.
 */
function runHeadlessClaude(task: Task): Promise<string> {
  const prompt = `You are a headless task executor with full tool access via MCP.\nProject directory: ${PROJECT_DIR}\n\nTask ID: ${task.id}\nTask: ${task.description}\n\nExecute this task now using your available tools. When complete, call the complete_task MCP tool with task_id "${task.id}" and a brief result summary. Do not ask questions — just execute.`;

  const logFile = join(LOGS_DIR, `${task.id}.log`);
  const started = new Date().toISOString();
  let logHeader = `=== Task: ${task.title} ===\n=== ID: ${task.id} | Started: ${started} ===\n`;
  if (task.description) {
    const descWrapped = wordWrap(task.description);
    const descTruncated = truncateDescription(descWrapped);
    logHeader += `\n--- Assignment ---\n${descTruncated}\n\n--- Log ---\n`;
  } else {
    logHeader += "\n";
  }
  writeFileSync(logFile, logHeader, "utf-8");

  return new Promise<string>((resolve, reject) => {
    const chunks: Buffer[] = [];
    const errChunks: Buffer[] = [];
    const logStream = createWriteStream(logFile, { flags: "a" });
    let errored = false;

    const child = spawn("claude", ["-p", prompt, "--dangerously-skip-permissions", "--output-format", "stream-json", "--verbose", "--mcp-config", MCP_CONFIG_PATH], {
      cwd: tmpdir(),
      shell: false,
      stdio: ["ignore", "pipe", "pipe"],
      env: { ...process.env, COWORK_CHILD_MODE: "1" },
    });

    let lineBuf = "";
    child.stdout.on("data", (data: Buffer) => {
      chunks.push(data);
      lineBuf += data.toString("utf-8");
      const lines = lineBuf.split("\n");
      lineBuf = lines.pop() || "";
      for (const line of lines) {
        if (!line.trim()) continue;
        try {
          const evt = JSON.parse(line);
          if (evt.type === "assistant" && evt.message?.content) {
            for (const block of evt.message.content) {
              if (block.type === "text") logStream.write(block.text + "\n");
              if (block.type === "tool_use") logStream.write(`[tool] ${block.name}(${JSON.stringify(block.input).substring(0, 200)})\n`);
            }
          } else if (evt.type === "result" && evt.result) {
            logStream.write(`\n[result] ${evt.result}\n`);
          }
        } catch { /* not valid JSON, skip */ }
      }
    });
    child.stderr.on("data", (data: Buffer) => {
      errChunks.push(data);
    });

    child.on("close", (code) => {
      // `error` already ended the stream and rejected; skip to avoid
      // ERR_STREAM_WRITE_AFTER_END crashing the MCP server.
      if (errored) return;
      const footer = `\n\n=== Finished: ${new Date().toISOString()} | Exit code: ${code} ===\n`;
      logStream.write(footer);
      logStream.end();

      const stdout = Buffer.concat(chunks).toString("utf-8").trim();
      const stderr = Buffer.concat(errChunks).toString("utf-8").trim();
      if (code === 0) {
        resolve(stdout || "(no output)");
      } else {
        reject(new Error(`claude exited with code ${code}.\nstderr: ${stderr}\nstdout: ${stdout}`));
      }
    });

    child.on("error", (err) => {
      errored = true;
      logStream.write(`\n[error] ${err.message}\n`);
      logStream.end();
      reject(err);
    });
  });
}

function loadTasks(): Task[] {
  if (!existsSync(TASKS_FILE)) return [];
  try {
    return JSON.parse(readFileSync(TASKS_FILE, "utf-8"));
  } catch {
    return [];
  }
}

function saveTasks(tasks: Task[]): void {
  writeFileSync(TASKS_FILE, JSON.stringify(tasks, null, 2), "utf-8");
}

// MCP Server
const server = new McpServer({
  name: "cowork-mcp",
  version: "1.0.0",
});

server.registerTool(
  "submit_task",
  {
    title: "Submit Task",
    description:
      "Submit a new task for Claude Code to work on. Tasks are created as 'pending' by default. Use autorun=true to immediately spawn a headless Claude subprocess.",
    inputSchema: {
      title: z.string().describe("Short task title"),
      description: z
        .string()
        .describe(
          "Detailed task description — what to do, acceptance criteria, relevant file paths"
        ),
      autorun: z
        .boolean()
        .optional()
        .describe("If true, immediately spawn headless Claude to run the task. Default: false (task stays pending)."),
    },
  },
  async ({ title, description, autorun }) => {
    const tasks = loadTasks();
    const shouldAutorun = autorun === true;
    const task: Task = {
      id: randomUUID().slice(0, 8),
      title,
      description,
      status: shouldAutorun ? "running" : "pending",
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };
    tasks.push(task);
    saveTasks(tasks);

    if (shouldAutorun) {
      // Fire-and-forget: spawn headless Claude without awaiting
      spawnTaskSubprocess(task);
    }

    return {
      content: [
        {
          type: "text" as const,
          text: JSON.stringify(
            { id: task.id, title: task.title, status: task.status },
            null,
            2
          ),
        },
      ],
    };
  }
);

server.registerTool(
  "start_task",
  {
    title: "Start Task",
    description:
      "Start a pending task by spawning a headless Claude subprocess for it. Transitions status from 'pending' to 'running'.",
    inputSchema: {
      task_id: z.string().describe("The task ID to start"),
    },
  },
  async ({ task_id }) => {
    const tasks = loadTasks();
    const task = tasks.find((t) => t.id === task_id);
    if (!task) {
      return {
        content: [{ type: "text" as const, text: JSON.stringify({ error: `Task '${task_id}' not found` }) }],
        isError: true,
      };
    }
    if (task.status !== "pending") {
      return {
        content: [{ type: "text" as const, text: JSON.stringify({ error: `Task '${task_id}' is '${task.status}', not 'pending'` }) }],
        isError: true,
      };
    }
    task.status = "running";
    task.updatedAt = new Date().toISOString();
    saveTasks(tasks);

    spawnTaskSubprocess(task);

    return {
      content: [
        {
          type: "text" as const,
          text: JSON.stringify({ id: task.id, title: task.title, status: task.status }, null, 2),
        },
      ],
    };
  }
);

server.registerTool(
  "get_result",
  {
    title: "Get Task Result",
    description:
      "Get the current status and result of a task by ID.",
    inputSchema: {
      task_id: z.string().describe("The task ID returned by submit_task"),
    },
  },
  async ({ task_id }) => {
    const tasks = loadTasks();
    const task = tasks.find((t) => t.id === task_id);
    if (!task) {
      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify({ error: `Task '${task_id}' not found` }),
          },
        ],
        isError: true,
      };
    }
    return {
      content: [
        {
          type: "text" as const,
          text: JSON.stringify(task, null, 2),
        },
      ],
    };
  }
);

server.registerTool(
  "list_tasks",
  {
    title: "List Tasks",
    description:
      "List all tasks, optionally filtered by status.",
    inputSchema: {
      status: z
        .enum(["pending", "running", "completed", "failed"])
        .optional()
        .describe("Filter by task status"),
    },
  },
  async ({ status }) => {
    let tasks = loadTasks();
    if (status) {
      tasks = tasks.filter((t) => t.status === status);
    }
    const summary = tasks.map((t) => ({
      id: t.id,
      title: t.title,
      status: t.status,
      updatedAt: t.updatedAt,
      hasResult: !!t.result,
    }));
    return {
      content: [
        {
          type: "text" as const,
          text: JSON.stringify({ count: summary.length, tasks: summary }, null, 2),
        },
      ],
    };
  }
);

server.registerTool(
  "complete_task",
  {
    title: "Complete Task",
    description:
      "Mark a task as completed with a result summary. Used by Claude Code after finishing work.",
    inputSchema: {
      task_id: z.string().describe("The task ID to complete"),
      result: z
        .string()
        .describe(
          "Result summary — what was done, file paths changed, URLs to test, any issues"
        ),
      status: z
        .enum(["completed", "failed"])
        .optional()
        .describe("Final status (defaults to completed)"),
    },
  },
  async ({ task_id, result, status }) => {
    const tasks = loadTasks();
    const task = tasks.find((t) => t.id === task_id);
    if (!task) {
      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify({ error: `Task '${task_id}' not found` }),
          },
        ],
        isError: true,
      };
    }
    task.status = status || "completed";
    task.result = result;
    task.updatedAt = new Date().toISOString();
    saveTasks(tasks);
    return {
      content: [
        {
          type: "text" as const,
          text: JSON.stringify(task, null, 2),
        },
      ],
    };
  }
);

server.registerTool(
  "process_task",
  {
    title: "Process Task",
    description:
      "Submit a task and wait for Claude Code to complete it. Returns the result directly in one round-trip.",
    inputSchema: {
      title: z.string().describe("Short task title"),
      description: z
        .string()
        .describe(
          "Detailed task description — what to do, acceptance criteria, relevant file paths"
        ),
    },
  },
  async ({ title, description }) => {
    const tasks = loadTasks();
    const task: Task = {
      id: randomUUID().slice(0, 8),
      title,
      description,
      status: "running",
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };
    tasks.push(task);
    saveTasks(tasks);

    const logFile = join(LOGS_DIR, `${task.id}.log`);

    try {
      const result = await runHeadlessClaude(task);

      // Reload task to get the result that claude may have written via complete_task
      const updatedTasks = loadTasks();
      const updatedTask = updatedTasks.find((t) => t.id === task.id);

      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify(
              {
                task_id: task.id,
                status: updatedTask?.status || "completed",
                result: updatedTask?.result || result,
                log_file: logFile,
              },
              null,
              2
            ),
          },
        ],
      };
    } catch (err: any) {
      // Mark task as failed
      const failedTasks = loadTasks();
      const failedTask = failedTasks.find((t) => t.id === task.id);
      if (failedTask) {
        failedTask.status = "failed";
        failedTask.result = err.message;
        failedTask.updatedAt = new Date().toISOString();
        saveTasks(failedTasks);
      }

      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify(
              {
                task_id: task.id,
                status: "failed",
                error: err.message,
                log_file: logFile,
              },
              null,
              2
            ),
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "get_log",
  {
    title: "Get Task Log",
    description:
      "Read the full Claude Code output log for a task processed via submit_task or process_task.",
    inputSchema: {
      task_id: z.string().describe("The task ID to get the log for"),
    },
  },
  async ({ task_id }) => {
    const tasks = loadTasks();
    const task = tasks.find((t) => t.id === task_id);

    const logFile = join(LOGS_DIR, `${task_id}.log`);
    const logExists = existsSync(logFile);

    if (!task && !logExists) {
      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify({ error: `Task '${task_id}' not found and no log file exists` }),
          },
        ],
        isError: true,
      };
    }

    // Build formatted task detail view
    const parts: string[] = [];

    if (task) {
      const created = task.createdAt.replace("T", " ").replace(/\.\d+Z$/, "");
      parts.push(`=== Task: ${task.title} ===`);
      parts.push(`ID: ${task.id}`);
      parts.push(`Status: ${task.status}`);
      parts.push(`Created: ${created}`);

      if (task.description) {
        parts.push("");
        parts.push("--- Assignment ---");
        const wrapped = wordWrap(task.description);
        parts.push(truncateDescription(wrapped));
      }

      if (task.result) {
        parts.push("");
        parts.push("--- Result ---");
        parts.push(task.result);
      }
    }

    parts.push("");
    parts.push("--- Log ---");
    if (logExists) {
      parts.push(readFileSync(logFile, "utf-8"));
    } else {
      parts.push("(no log file found)");
    }

    return {
      content: [
        {
          type: "text" as const,
          text: parts.join("\n"),
        },
      ],
    };
  }
);

// Start
async function main() {
  // Skip orphan resume when running as a child MCP instance inside a headless
  // subprocess — otherwise the child sees its own parent task as "orphaned"
  // and respawns it, causing a spawn cascade.
  if (process.env.COWORK_CHILD_MODE !== "1") {
    resumeOrphanedTasks();
  }
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("[cowork-mcp] Server running on stdio");
}

main().catch((error) => {
  console.error("[cowork-mcp] Fatal error:", error);
  process.exit(1);
});
