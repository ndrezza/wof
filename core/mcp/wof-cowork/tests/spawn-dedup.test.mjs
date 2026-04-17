import { test } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { setTimeout as delay } from "node:timers/promises";

const __dirname = dirname(fileURLToPath(import.meta.url));
const SERVER_PATH = join(__dirname, "..", "build", "index.js");

// Strip the test's PATH so the spawned cowork server cannot find a real
// `claude` binary — runHeadlessClaude will then fail fast with ENOENT, which
// gives us a deterministic side effect on tasks.json (status -> "failed")
// without needing a real Claude CLI present in the test environment.
const SAFE_PATH = "/usr/bin:/bin";

async function startAndObserve({ childMode }) {
  const dir = mkdtempSync(join(tmpdir(), "cowork-spawn-"));
  const tasksPath = join(dir, "tasks.json");
  const seeded = [
    {
      id: "orphan01",
      title: "seeded orphan",
      description: "pretend this was running before the server restarted",
      status: "running",
      createdAt: "2026-01-01T00:00:00.000Z",
      updatedAt: "2026-01-01T00:00:00.000Z",
    },
  ];
  writeFileSync(tasksPath, JSON.stringify(seeded, null, 2));

  const env = {
    PATH: SAFE_PATH,
    HOME: process.env.HOME ?? "",
    COWORK_DATA_DIR: dir,
    COWORK_PROJECT_DIR: dir,
    COWORK_MCP_CONFIG: join(dir, ".mcp.json"),
  };
  if (childMode) env.COWORK_CHILD_MODE = "1";

  const child = spawn(process.execPath, [SERVER_PATH], {
    env,
    stdio: ["pipe", "pipe", "pipe"],
  });

  let stderr = "";
  child.stderr.on("data", (d) => { stderr += d.toString(); });

  // Register exit handler immediately — we cannot wait for it because, in
  // parent mode, the server may crash on its own before we'd send a signal.
  let exitInfo = null;
  child.on("exit", (code, signal) => { exitInfo = { code, signal }; });

  // Give the server time to: load module, run resumeOrphanedTasks (parent
  // mode), spawn claude (which fails ENOENT), let the catch-handler save
  // tasks.json, and possibly crash from the unhandled stream error.
  await delay(2000);

  if (exitInfo === null) {
    child.kill("SIGKILL");
    await new Promise((resolve) => child.on("exit", resolve));
  }

  const after = JSON.parse(readFileSync(tasksPath, "utf-8"));
  rmSync(dir, { recursive: true, force: true });
  return { after, stderr, exitInfo };
}

test("parent mode (COWORK_CHILD_MODE unset) — resumes orphaned running tasks", async () => {
  const { after, stderr } = await startAndObserve({ childMode: false });
  assert.equal(after.length, 1);
  assert.notEqual(
    after[0].status,
    "running",
    `expected resume to have transitioned the task off 'running'; stderr was:\n${stderr}`
  );
  assert.match(stderr, /Resuming orphaned task/);
});

test("child mode (COWORK_CHILD_MODE=1) — does NOT resume orphaned running tasks", async () => {
  const { after, stderr } = await startAndObserve({ childMode: true });
  assert.equal(after.length, 1);
  assert.equal(
    after[0].status,
    "running",
    `expected child mode to leave the task untouched; stderr was:\n${stderr}`
  );
  assert.doesNotMatch(stderr, /Resuming orphaned task/);
});
