# Tailblaze

Terminal.Gui TUI that tails cowork task state in real time. Useful when
you've dispatched several tasks from Claude Desktop and want a live
view of queue status, running subprocesses, and log tails without
switching contexts.

## Build

```bash
cd extensions/tailblaze
dotnet build
```

## Run

```bash
dotnet run
```

Optionally, point it at a specific data dir:

```bash
dotnet run -- --data-dir /absolute/path/to/cowork-data
```

## Data directory discovery

Tailblaze locates `tasks.json` and the `logs/` dir in this order:

1. `--data-dir <path>` CLI argument
2. `COWORK_DATA_DIR` environment variable
3. Walk up from the current directory looking for either
   `tools/cowork-mcp/` (the ContextAndInternalIT layout) or
   `core/mcp/wof-cowork/` (the WOF layout). First match wins.

If none are found, Tailblaze exits with an error. Either `cd` into the
WOF repo first or pass `--data-dir` explicitly.

## Requirements

- .NET 10 SDK
- A working cowork-mcp installation (see
  [`../../docs/cowork-bootstrap.md`](../../docs/cowork-bootstrap.md))
