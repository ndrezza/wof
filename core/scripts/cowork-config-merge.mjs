#!/usr/bin/env node
// Merge a cowork MCP server entry into claude_desktop_config.json.
//
// Exit codes: 0 = success, 1 = user aborted, 2 = error.

import { readFileSync, writeFileSync, existsSync, mkdirSync, renameSync } from "node:fs";
import { dirname, join, basename } from "node:path";
import { execSync } from "node:child_process";
import { createInterface } from "node:readline";
import { platform } from "node:os";

function parseArgs(argv) {
  const out = { dryRun: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const take = () => argv[++i];
    switch (a) {
      case "--config": out.config = take(); break;
      case "--server-name": out.serverName = take(); break;
      case "--server-path": out.serverPath = take(); break;
      case "--project-dir": out.projectDir = take(); break;
      case "--data-dir": out.dataDir = take(); break;
      case "--dry-run": out.dryRun = true; break;
      case "--help": case "-h": out.help = true; break;
      default:
        console.error(`unknown arg: ${a}`);
        process.exit(2);
    }
  }
  return out;
}

function usage() {
  console.log(`Usage: cowork-config-merge.mjs \\
  --config <path-to-claude_desktop_config.json> \\
  --server-name <name> \\
  --server-path <abs-path-to-build-index-js> \\
  --project-dir <abs-path> \\
  --data-dir <abs-path> \\
  [--dry-run]`);
}

function die(msg, code = 2) {
  console.error(`error: ${msg}`);
  process.exit(code);
}

function ts() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, "0");
  return (
    d.getFullYear().toString() +
    pad(d.getMonth() + 1) +
    pad(d.getDate()) +
    "-" +
    pad(d.getHours()) +
    pad(d.getMinutes()) +
    pad(d.getSeconds())
  );
}

function promptChoice(question, choices) {
  return new Promise((resolve) => {
    const rl = createInterface({ input: process.stdin, output: process.stdout });
    rl.question(question, (answer) => {
      rl.close();
      const a = answer.trim().toLowerCase();
      resolve(choices[a] ?? null);
    });
  });
}

function isClaudeDesktopRunning() {
  try {
    if (platform() === "win32") {
      const out = execSync('tasklist /FI "IMAGENAME eq Claude.exe" /NH', {
        stdio: ["ignore", "pipe", "ignore"],
      }).toString();
      return /Claude\.exe/i.test(out);
    }
    const out = execSync("ps -Ao comm=", { stdio: ["ignore", "pipe", "ignore"] }).toString();
    return out
      .split("\n")
      .some((line) => /(^|\/)Claude$/.test(line.trim()) || /Claude Helper/i.test(line));
  } catch {
    return false;
  }
}

function atomicWrite(target, contents) {
  const dir = dirname(target);
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  const tmp = join(dir, `.${basename(target)}.tmp.${process.pid}.${Date.now()}`);
  writeFileSync(tmp, contents, "utf-8");
  renameSync(tmp, target);
}

function deepEqual(a, b) {
  return JSON.stringify(a) === JSON.stringify(b);
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    usage();
    process.exit(0);
  }

  const required = ["config", "serverName", "serverPath", "projectDir", "dataDir"];
  for (const k of required) {
    if (!args[k]) die(`missing --${k.replace(/([A-Z])/g, "-$1").toLowerCase()}`);
  }

  const entry = {
    type: "stdio",
    command: "node",
    args: [args.serverPath],
    env: {
      COWORK_DATA_DIR: args.dataDir,
      COWORK_PROJECT_DIR: args.projectDir,
    },
  };

  let doc = { mcpServers: {} };
  if (existsSync(args.config)) {
    const raw = readFileSync(args.config, "utf-8");
    try {
      doc = JSON.parse(raw);
    } catch (e) {
      die(
        `${args.config} is not valid JSON (${e.message}). ` +
          `Refusing to auto-fix. Fix or move it aside and re-run.`
      );
    }
    if (typeof doc !== "object" || doc === null || Array.isArray(doc)) {
      die(`${args.config} root is not a JSON object.`);
    }
    if (doc.mcpServers === undefined) {
      doc.mcpServers = {};
    } else if (
      typeof doc.mcpServers !== "object" ||
      doc.mcpServers === null ||
      Array.isArray(doc.mcpServers)
    ) {
      die(`${args.config} has a "mcpServers" field that is not an object.`);
    }
  }

  const existing = doc.mcpServers[args.serverName];
  let action = "add";
  if (existing !== undefined) {
    if (deepEqual(existing, entry)) {
      console.log(
        `[cowork-config-merge] "${args.serverName}" already present and identical — no-op.`
      );
      if (isClaudeDesktopRunning()) {
        console.log(
          "[cowork-config-merge] Claude Desktop is running — fully quit and relaunch to reload config."
        );
      }
      process.exit(0);
    }
    if (args.dryRun) {
      console.log(
        `[dry-run] Would overwrite "${args.serverName}" in ${args.config}:`
      );
      console.log("  existing:", JSON.stringify(existing, null, 2));
      console.log("  new:     ", JSON.stringify(entry, null, 2));
      process.exit(0);
    }
    const choice = await promptChoice(
      `Server "${args.serverName}" already exists in ${args.config} with different settings.\n` +
        `  [o] overwrite  [s] skip  [a] abort  > `,
      { o: "overwrite", s: "skip", a: "abort" }
    );
    if (choice === null) die("invalid choice, aborting", 1);
    if (choice === "abort") {
      console.log("[cowork-config-merge] aborted by user.");
      process.exit(1);
    }
    if (choice === "skip") {
      console.log("[cowork-config-merge] skipped — existing entry preserved.");
      if (isClaudeDesktopRunning()) {
        console.log(
          "[cowork-config-merge] Claude Desktop is running — fully quit and relaunch to reload config."
        );
      }
      process.exit(0);
    }
    action = "overwrite";
  }

  if (args.dryRun) {
    console.log(`[dry-run] Would ${action} "${args.serverName}" in ${args.config}:`);
    console.log(JSON.stringify(entry, null, 2));
    process.exit(0);
  }

  let backupPath = null;
  if (existsSync(args.config)) {
    backupPath = `${args.config}.bak.${ts()}`;
    writeFileSync(backupPath, readFileSync(args.config), { encoding: null });
  }

  doc.mcpServers[args.serverName] = entry;
  const serialized = JSON.stringify(doc, null, 2) + "\n";
  atomicWrite(args.config, serialized);

  console.log(`[cowork-config-merge] ${action === "add" ? "added" : "overwrote"} "${args.serverName}" in ${args.config}`);
  if (backupPath) console.log(`[cowork-config-merge] backup: ${backupPath}`);
  if (isClaudeDesktopRunning()) {
    console.log(
      "[cowork-config-merge] Claude Desktop is running — fully quit and relaunch to reload config."
    );
  }
}

main().catch((err) => {
  console.error(`error: ${err.stack || err.message || err}`);
  process.exit(2);
});
