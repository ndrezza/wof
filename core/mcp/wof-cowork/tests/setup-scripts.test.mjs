import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  mkdtempSync,
  rmSync,
  writeFileSync,
  readFileSync,
  mkdirSync,
} from "node:fs";
import { tmpdir, platform } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const SCRIPTS_DIR = join(__dirname, "..", "..", "..", "scripts");
const SETUP_SH = join(SCRIPTS_DIR, "setup-cowork.sh");
const SETUP_PS1 = join(SCRIPTS_DIR, "setup-cowork.ps1");

function commandExists(cmd) {
  const r = spawnSync("which", [cmd], { encoding: "utf8" });
  return r.status === 0;
}

test("setup-cowork.sh parses (bash -n)", () => {
  const r = spawnSync("bash", ["-n", SETUP_SH], { encoding: "utf8" });
  assert.equal(r.status, 0, `bash -n failed:\n${r.stderr}`);
});

test("setup-cowork.ps1 parses", { skip: commandExists("pwsh") ? false : "pwsh not on PATH" }, () => {
  const r = spawnSync(
    "pwsh",
    [
      "-NoProfile",
      "-Command",
      `$null = [ScriptBlock]::Create((Get-Content '${SETUP_PS1}' -Raw))`,
    ],
    { encoding: "utf8" }
  );
  assert.equal(r.status, 0, `pwsh parse failed:\n${r.stderr}`);
});

test(
  "setup-cowork.sh --dry-run leaves an existing config byte-for-byte unchanged",
  { skip: platform() === "win32" ? "bash setup script targets macOS/Linux" : false },
  () => {
    const fakeHome = mkdtempSync(join(tmpdir(), "cowork-setup-home-"));
    const fakeProject = mkdtempSync(join(tmpdir(), "cowork-setup-proj-"));
    try {
      const isDarwin = platform() === "darwin";
      const configDir = isDarwin
        ? join(fakeHome, "Library", "Application Support", "Claude")
        : join(fakeHome, ".config", "Claude");
      mkdirSync(configDir, { recursive: true });
      const configPath = join(configDir, "claude_desktop_config.json");

      // Seed an existing config with an unrelated mcpServer entry. Dry-run
      // must NOT mutate this file.
      const seed = {
        mcpServers: {
          "some-other-server": {
            type: "stdio",
            command: "node",
            args: ["/somewhere/else.js"],
          },
        },
      };
      writeFileSync(configPath, JSON.stringify(seed, null, 2) + "\n");
      const before = readFileSync(configPath);

      const env = { ...process.env, HOME: fakeHome };
      const r = spawnSync(
        "bash",
        [SETUP_SH, "--dry-run", "--project-dir", fakeProject, "--server-name", "test-cowork"],
        { encoding: "utf8", env }
      );

      assert.equal(
        r.status,
        0,
        `setup-cowork.sh --dry-run failed (status ${r.status}):\nSTDOUT:\n${r.stdout}\nSTDERR:\n${r.stderr}`
      );

      const after = readFileSync(configPath);
      assert.deepEqual(after, before, "dry-run must not modify the config file");
    } finally {
      rmSync(fakeHome, { recursive: true, force: true });
      rmSync(fakeProject, { recursive: true, force: true });
    }
  }
);
