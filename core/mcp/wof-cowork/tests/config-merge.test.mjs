import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  mkdtempSync,
  rmSync,
  copyFileSync,
  writeFileSync,
  readFileSync,
  existsSync,
  readdirSync,
  statSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const MERGER_PATH = join(__dirname, "..", "..", "..", "scripts", "cowork-config-merge.mjs");
const FIXTURES = join(__dirname, "fixtures");

const SERVER_NAME = "wof-cowork";
const SERVER_PATH = "/fake/build/index.js";
const PROJECT_DIR = "/fake/proj";
const DATA_DIR = "/fake/data";

function makeTmpDir() {
  return mkdtempSync(join(tmpdir(), "cowork-merge-"));
}

function runMerger(extraArgs, opts = {}) {
  return spawnSync(
    process.execPath,
    [MERGER_PATH, ...extraArgs],
    { encoding: "utf8", ...opts }
  );
}

function defaultArgs(configPath, overrides = {}) {
  const a = {
    "--config": configPath,
    "--server-name": SERVER_NAME,
    "--server-path": SERVER_PATH,
    "--project-dir": PROJECT_DIR,
    "--data-dir": DATA_DIR,
    ...overrides,
  };
  const out = [];
  for (const [k, v] of Object.entries(a)) {
    if (v === null || v === undefined) continue;
    if (v === true) out.push(k);
    else { out.push(k); out.push(v); }
  }
  return out;
}

function expectedEntry() {
  return {
    type: "stdio",
    command: "node",
    args: [SERVER_PATH],
    env: {
      COWORK_DATA_DIR: DATA_DIR,
      COWORK_PROJECT_DIR: PROJECT_DIR,
    },
  };
}

test("fresh config — file missing creates new file with entry", () => {
  const dir = makeTmpDir();
  try {
    const configPath = join(dir, "claude_desktop_config.json");
    assert.equal(existsSync(configPath), false);

    const result = runMerger(defaultArgs(configPath));
    assert.equal(result.status, 0, `stderr: ${result.stderr}\nstdout: ${result.stdout}`);
    assert.equal(existsSync(configPath), true);

    const doc = JSON.parse(readFileSync(configPath, "utf-8"));
    assert.deepEqual(doc.mcpServers[SERVER_NAME], expectedEntry());
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("fresh config — parent dir missing is created", () => {
  const dir = makeTmpDir();
  try {
    const configPath = join(dir, "nested", "deeper", "claude_desktop_config.json");

    const result = runMerger(defaultArgs(configPath));
    assert.equal(result.status, 0, `stderr: ${result.stderr}`);
    assert.equal(existsSync(configPath), true);

    const doc = JSON.parse(readFileSync(configPath, "utf-8"));
    assert.deepEqual(doc.mcpServers[SERVER_NAME], expectedEntry());
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("existing config — server absent — entry added, others preserved", () => {
  const dir = makeTmpDir();
  try {
    const configPath = join(dir, "claude_desktop_config.json");
    copyFileSync(join(FIXTURES, "config-with-other-server.json"), configPath);

    const result = runMerger(defaultArgs(configPath));
    assert.equal(result.status, 0, `stderr: ${result.stderr}`);

    const doc = JSON.parse(readFileSync(configPath, "utf-8"));
    assert.deepEqual(doc.mcpServers[SERVER_NAME], expectedEntry());
    assert.deepEqual(doc.mcpServers["other-server"], {
      type: "stdio",
      command: "node",
      args: ["/some/other/server.js"],
      env: { FOO: "bar" },
    });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("existing config — preserves top-level non-mcp fields", () => {
  const dir = makeTmpDir();
  try {
    const configPath = join(dir, "claude_desktop_config.json");
    copyFileSync(join(FIXTURES, "config-with-other-server.json"), configPath);

    const result = runMerger(defaultArgs(configPath));
    assert.equal(result.status, 0, `stderr: ${result.stderr}`);

    const doc = JSON.parse(readFileSync(configPath, "utf-8"));
    assert.equal(doc.someOtherKey, "preserve-me");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("idempotent — identical entry produces no changes and no backup", () => {
  const dir = makeTmpDir();
  try {
    const configPath = join(dir, "claude_desktop_config.json");
    copyFileSync(join(FIXTURES, "config-identical.json"), configPath);
    const before = readFileSync(configPath);

    const result = runMerger(defaultArgs(configPath));
    assert.equal(result.status, 0, `stderr: ${result.stderr}`);

    const after = readFileSync(configPath);
    assert.deepEqual(after, before, "file content should be byte-identical");

    const siblings = readdirSync(dir);
    assert.equal(
      siblings.some((f) => f.includes(".bak.")),
      false,
      `expected no backup file, got: ${siblings.join(", ")}`
    );
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("dry-run on conflict — exit 0 and file unchanged on disk", () => {
  const dir = makeTmpDir();
  try {
    const configPath = join(dir, "claude_desktop_config.json");
    copyFileSync(join(FIXTURES, "config-conflicting.json"), configPath);
    const before = readFileSync(configPath);

    const result = runMerger(defaultArgs(configPath, { "--dry-run": true }));
    assert.equal(result.status, 0, `stderr: ${result.stderr}`);

    const after = readFileSync(configPath);
    assert.deepEqual(after, before, "file content should be unchanged after --dry-run");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("malformed JSON — non-zero exit, file unchanged, helpful stderr", () => {
  const dir = makeTmpDir();
  try {
    const configPath = join(dir, "claude_desktop_config.json");
    copyFileSync(join(FIXTURES, "malformed.json"), configPath);
    const before = readFileSync(configPath);

    const result = runMerger(defaultArgs(configPath));
    assert.notEqual(result.status, 0, "should exit non-zero on malformed JSON");
    assert.match(result.stderr, /Refusing to auto-fix/);

    const after = readFileSync(configPath);
    assert.deepEqual(after, before, "file content should be unchanged");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("non-object mcpServers — non-zero exit", () => {
  const dir = makeTmpDir();
  try {
    const configPath = join(dir, "claude_desktop_config.json");
    writeFileSync(configPath, JSON.stringify({ mcpServers: ["not", "an", "object"] }));

    const result = runMerger(defaultArgs(configPath));
    assert.notEqual(result.status, 0, "should reject array-shaped mcpServers");
    assert.match(result.stderr, /mcpServers/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("missing required flag — non-zero exit, stderr names the flag", () => {
  const dir = makeTmpDir();
  try {
    const configPath = join(dir, "claude_desktop_config.json");
    const args = defaultArgs(configPath, { "--server-name": null });

    const result = runMerger(args);
    assert.notEqual(result.status, 0, "should fail without --server-name");
    assert.match(result.stderr, /server-name/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("backup filename format on overwrite", () => {
  const dir = makeTmpDir();
  try {
    const configPath = join(dir, "claude_desktop_config.json");
    copyFileSync(join(FIXTURES, "config-conflicting.json"), configPath);

    // Pipe "o\n" to answer the interactive overwrite prompt.
    const result = runMerger(defaultArgs(configPath), { input: "o\n" });
    assert.equal(result.status, 0, `stderr: ${result.stderr}\nstdout: ${result.stdout}`);

    const siblings = readdirSync(dir);
    const backups = siblings.filter((f) =>
      /^claude_desktop_config\.json\.bak\.\d{8}-\d{6}$/.test(f)
    );
    assert.equal(backups.length, 1, `expected exactly one backup, got: ${siblings.join(", ")}`);

    const doc = JSON.parse(readFileSync(configPath, "utf-8"));
    assert.deepEqual(doc.mcpServers[SERVER_NAME], expectedEntry());
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("atomic write — no leftover .tmp file in config dir", () => {
  const dir = makeTmpDir();
  try {
    const configPath = join(dir, "claude_desktop_config.json");
    const result = runMerger(defaultArgs(configPath));
    assert.equal(result.status, 0, `stderr: ${result.stderr}`);

    const siblings = readdirSync(dir);
    const tmps = siblings.filter((f) => f.includes(".tmp."));
    assert.equal(tmps.length, 0, `expected no leftover .tmp files, got: ${tmps.join(", ")}`);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
