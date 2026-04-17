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
const SAFE_PATH = "/usr/bin:/bin"; // no `claude` here → ENOENT on spawn

// Regression: when `claude` isn't on PATH, Node fires both `error` and `close`
// on the child. The old code ended the log stream in `error` and then wrote
// to it in `close`, throwing ERR_STREAM_WRITE_AFTER_END and killing the
// server. The server must survive the spawn failure and cleanly shut down
// on SIGTERM.
test("server survives child-process spawn error (no ERR_STREAM_WRITE_AFTER_END crash)", async () => {
  const dir = mkdtempSync(join(tmpdir(), "cowork-spawnerr-"));
  const tasksPath = join(dir, "tasks.json");
  writeFileSync(
    tasksPath,
    JSON.stringify(
      [
        {
          id: "spawnerr",
          title: "forces spawn failure",
          description: "claude is not on PATH in this test, so spawn fails",
          status: "running",
          createdAt: "2026-01-01T00:00:00.000Z",
          updatedAt: "2026-01-01T00:00:00.000Z",
        },
      ],
      null,
      2
    )
  );

  const env = {
    PATH: SAFE_PATH,
    HOME: process.env.HOME ?? "",
    COWORK_DATA_DIR: dir,
    COWORK_PROJECT_DIR: dir,
    COWORK_MCP_CONFIG: join(dir, ".mcp.json"),
  };

  const child = spawn(process.execPath, [SERVER_PATH], {
    env,
    stdio: ["pipe", "pipe", "pipe"],
  });

  let stderr = "";
  child.stderr.on("data", (d) => { stderr += d.toString(); });

  let exitInfo = null;
  child.on("exit", (code, signal) => { exitInfo = { code, signal }; });

  // Let the server run resumeOrphanedTasks → spawn claude → ENOENT → both
  // `error` and `close` fire on the child, and the bug (if unfixed) crashes
  // the server during that window.
  await delay(2000);

  const crashedBeforeSignal = exitInfo !== null;
  if (!crashedBeforeSignal) {
    child.kill("SIGTERM");
    await new Promise((resolve) => child.on("exit", resolve));
  }

  const after = JSON.parse(readFileSync(tasksPath, "utf-8"));
  rmSync(dir, { recursive: true, force: true });

  assert.doesNotMatch(
    stderr,
    /ERR_STREAM_WRITE_AFTER_END/,
    `server crashed with ERR_STREAM_WRITE_AFTER_END; full stderr:\n${stderr}`
  );
  assert.equal(
    crashedBeforeSignal,
    false,
    `server exited on its own before SIGTERM (exit=${JSON.stringify(exitInfo)}); stderr:\n${stderr}`
  );
  assert.equal(exitInfo.signal, "SIGTERM", `expected clean SIGTERM shutdown, got ${JSON.stringify(exitInfo)}`);

  assert.equal(after.length, 1);
  assert.equal(after[0].status, "failed", `expected task to be marked failed; got ${after[0].status}`);
  assert.ok(
    after[0].result && after[0].result.length > 0,
    "expected failure message to be written to task.result"
  );
});
