# wof-cowork MCP server

An MCP bridge that lets Claude Desktop (Claude Chat) dispatch tasks to a
headless `claude -p` subprocess running against a project repo. Claude
Desktop submits work; the subprocess executes it with full Claude Code
tooling; results flow back through the MCP connection.

Registers as MCP server `cowork-mcp`.

## Tools

| Tool | Purpose |
|------|---------|
| `submit_task` | Create a new task. `autorun=true` spawns a subprocess immediately; otherwise task stays `pending`. |
| `start_task` | Spawn a subprocess for an existing pending task. `pending` → `running`. |
| `process_task` | Submit + wait: one round-trip, returns result directly. |
| `get_result` | Current status and (if finished) result of a task. |
| `list_tasks` | List all tasks, optionally filtered by status. |
| `complete_task` | Mark a task `completed` with a result summary — called by the headless Claude subprocess itself when it finishes work. |
| `get_log` | Full stdout/stderr log captured from the headless subprocess. |

## Environment variables

| Var | Purpose |
|-----|---------|
| `COWORK_PROJECT_DIR` | Absolute path to the repo the headless subprocess operates against. Defaults to walking up from the MCP server's own location until a `.git` dir is found. |
| `COWORK_DATA_DIR` | Where `tasks.json` and `logs/` live. Defaults to the MCP server's own package dir (`core/mcp/wof-cowork/`). |
| `COWORK_MCP_CONFIG` | Path to the `.mcp.json` passed to the headless `claude -p` subprocess. Defaults to `$COWORK_PROJECT_DIR/.mcp.json`. |
| `COWORK_CHILD_MODE` | Internal. Set automatically on subprocess spawn to suppress orphan-task resume in the child MCP instance. **Do not set manually.** |

## Runtime data layout

```
$COWORK_DATA_DIR/
├── tasks.json          # task queue (array of Task objects)
└── logs/
    └── <task-id>.log   # captured stdout/stderr from headless claude -p
```

`tasks.json` schema (per task):

```ts
{
  id: string;               // uuid
  title: string;
  description: string;
  status: "pending" | "running" | "completed" | "failed";
  result?: string;          // populated on completion
  createdAt: string;        // ISO 8601
  updatedAt: string;        // ISO 8601
}
```

## Build

```bash
npm install
npm run build
```

tsc emits to `build/`. The Claude Desktop config entry points at
`build/index.js`.

## Install into Claude Desktop

See [`../../docs/cowork-bootstrap.md`](../../../docs/cowork-bootstrap.md)
for the end-to-end fresh-machine setup, including the automated
`setup-cowork.sh` / `setup-cowork.ps1` path and the manual JSON edit.

## Template (for `/wof configure` consumers)

`templates/mcp.json.template` uses three placeholders that the WOF
wizard substitutes: `{{SOLUTION_NAME}}`, `{{WOF_ABS_PATH}}`,
`{{PROJECT_ABS_PATH}}`. If `SolutionName` is unset at substitution
time, consumers should fall back to `wof-cowork` for the server key
(JSON does not permit comments, so the fallback is documented here).
