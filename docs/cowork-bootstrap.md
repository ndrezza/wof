# Cowork bootstrap

Fresh-machine guide to get the `wof-cowork` MCP bridge working with
Claude Desktop. Claude Desktop submits tasks → headless `claude -p`
executes them → results come back through chat.

Follow this top-to-bottom even if you're not using the rest of WOF.

## 1. Prerequisites

- **Node.js ≥ 20** (`node --version`)
- **Claude Code CLI** on your `PATH` — the `claude` command must work
  from any directory
- **Claude Desktop** installed (macOS, Windows, or Linux)
- *(Optional)* **.NET 10 SDK** — only needed for the Tailblaze TUI

## 2. Clone WOF

Anywhere is fine; scripts derive paths from their own location.

```bash
# Option A: under your home dir
git clone https://github.com/ndrezza/wof.git ~/code/wof

# Option B: any path
git clone https://github.com/ndrezza/wof.git /path/of/your/choice/wof
```

For the rest of this doc, `$WOF` refers to wherever you cloned it.

## 3. Build the server

```bash
cd "$WOF/core/mcp/wof-cowork"
npm install
npm run build
```

tsc emits to `build/`. If this fails, stop here and fix Node/npm before
continuing — the Claude Desktop entry points at `build/index.js`.

## 4. Wire it into Claude Desktop

Pick one of the two paths below.

### 4a. Automated (recommended)

#### macOS / Linux

```bash
"$WOF/core/scripts/setup-cowork.sh" --project-dir "$WOF"
```

#### Windows (PowerShell)

```powershell
& "$env:WOF\core\scripts\setup-cowork.ps1" -ProjectDir $env:WOF
```

What the script does:

1. Verifies Node ≥ 20.
2. Runs `npm install && npm run build` in `core/mcp/wof-cowork/`.
3. Prompts for (or accepts as flags):
   - `--project-dir` — the repo the headless subprocess works against.
     Defaults to the WOF clone itself.
   - `--server-name` — key under `mcpServers` in Claude Desktop config.
     Defaults to `wof-cowork`. Use a unique name per project if you
     want multiple cowork servers wired into Claude Desktop at once.
4. Merges an entry into `claude_desktop_config.json`:
   - Creates the file if missing.
   - Backs the existing file up to `claude_desktop_config.json.bak.<timestamp>`.
   - Writes atomically (temp file + rename).
   - If an entry under that server name already exists and differs,
     prompts you to overwrite / skip / abort.
5. Warns if Claude Desktop is currently running — you must fully quit
   it for config changes to load.
6. Supports `--dry-run` to print the planned change without writing.

Re-running is safe and idempotent.

### 4b. Manual

If you'd rather edit by hand:

**macOS:** `~/Library/Application Support/Claude/claude_desktop_config.json`
**Windows:** `%APPDATA%\Claude\claude_desktop_config.json`
**Linux:** `~/.config/Claude/claude_desktop_config.json`

Merge this into the top-level `mcpServers` object (create the file and
key if they don't exist):

```json
{
  "mcpServers": {
    "wof-cowork": {
      "type": "stdio",
      "command": "node",
      "args": ["{{WOF_ABS_PATH}}/core/mcp/wof-cowork/build/index.js"],
      "env": {
        "COWORK_DATA_DIR": "{{WOF_ABS_PATH}}/core/mcp/wof-cowork",
        "COWORK_PROJECT_DIR": "{{PROJECT_ABS_PATH}}"
      }
    }
  }
}
```

Replace `{{WOF_ABS_PATH}}` with the absolute path to your WOF clone
and `{{PROJECT_ABS_PATH}}` with the absolute path to the repo you want
the headless subprocess to work against (often the same as WOF).

**Windows only:** use forward slashes in these paths — Claude Desktop
rejects backslashes in the JSON.

## 5. Restart Claude Desktop

**Fully quit** — not just close the window.

- **macOS:** `⌘Q` or `Claude → Quit Claude`. Verify via Activity
  Monitor; stale helper processes can hold the old config.
- **Windows:** right-click the tray icon → Quit. Verify in Task Manager.
- **Linux:** close and confirm no `Claude` process remains.

Then relaunch.

## 6. Verify

In Claude Desktop chat:

> list your available MCP tools

You should see the cowork tools namespaced with your server name, e.g.
`submit_task`, `start_task`, `process_task`, `get_result`, `list_tasks`,
`complete_task`, `get_log`. (Claude Desktop prefixes them with the
server name in display, e.g. `wof-cowork__submit_task`.)

Smoke-test with a trivial task:

> submit_task title: "hello" description: "print the current date and
> commit nothing" autorun: true

Check it completes, then `get_log` to see the subprocess output.

## 7. Optional: Tailblaze TUI

```bash
cd "$WOF/extensions/tailblaze"
dotnet run
```

Tails the cowork task queue live. See
[`../extensions/tailblaze/README.md`](../extensions/tailblaze/README.md).

## 8. Troubleshooting

**Tools don't appear in Claude Desktop**

- Verify the config path for your OS and that the file is valid JSON.
- Verify you fully quit + relaunched Claude Desktop (not just closed
  the window).
- Verify `npm run build` completed — `build/index.js` must exist.
- Run the entry by hand: `node "$WOF/core/mcp/wof-cowork/build/index.js"`.
  It should print `[cowork-mcp] Server running on stdio` and block.
  Ctrl+C to quit.

**Permission errors on `tasks.json`**

If an earlier run under `sudo` created the data files as root:

```bash
sudo chown -R "$USER" "$WOF/core/mcp/wof-cowork/tasks.json" \
                     "$WOF/core/mcp/wof-cowork/logs"
```

**Spawn cascade / duplicate subprocesses**

Symptom: one `submit_task` spawns many `claude -p` processes. This was
a bug in older builds where the child MCP instance saw its own parent
task as "orphaned" and respawned it. The fix (guarded by
`COWORK_CHILD_MODE=1`) is in the current source. If you see this,
you're running a stale build — re-run `npm run build` and confirm
`build/index.js` has a newer mtime than `src/index.ts`.

**JSON merge fails**

The setup script refuses to touch a malformed `claude_desktop_config.json`.
Fix the JSON (or move it aside) and re-run.
