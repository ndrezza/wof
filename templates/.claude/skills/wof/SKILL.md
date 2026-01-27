---
name: wof
description: Workload Orchestration Framework commands - update, status, route, remove
disable-model-invocation: true
allowed-tools:
  - Bash
---

# WOF - Workload Orchestration Framework Commands

Parse the arguments to determine which WOF command to run.

**Arguments received:** $ARGUMENTS

## Available Commands

| Command | Description |
|---------|-------------|
| `update` | Update WOF to latest version from repository |
| `update --dry-run` | Preview update changes without applying |
| `status` | Check orchestration health and component status |
| `route <task>` | Classify a task and show routing decision (Worker-Lite vs Worker-Heavy) |
| `remove` | Remove WOF scripts (preserves config & memory files) |
| `remove --dry-run` | Preview what would be removed without making changes |
| `remove --force` | Remove WOF without confirmation prompt |
| `remove --include-config` | Also remove config files (credentials, providers, etc.) |
| `remove --remove-all` | Nuclear option: remove entire .ai/ and .claude/ directories |
| `help` | Show this help information |

## Command Handling

Based on the arguments, execute the appropriate action:

### If arguments contain "update"
Run the update-framework script:
```powershell
.\.ai\scripts\update-framework.ps1
```
If arguments also contain "--dry-run" or "-DryRun", add the -DryRun flag.

### If arguments contain "status"
Run the orchestration health check:
```powershell
.\.ai\scripts\check-orchestration-health.ps1
```

### If arguments contain "route"
Extract the task description (everything after "route") and run:
```powershell
.\.ai\scripts\get-worker-routing.ps1 -TaskDescription "<task description>"
```

### If arguments contain "remove"
Run the remove-framework script:
```powershell
.\.ai\scripts\remove-framework.ps1
```
If arguments also contain "--dry-run" or "-DryRun", add the -DryRun flag.
If arguments also contain "--force" or "-Force", add the -Force flag.
If arguments also contain "--include-config" or "-IncludeConfig", add the -IncludeConfig flag.
If arguments also contain "--remove-all" or "-RemoveAll", add the -RemoveAll flag (removes everything).

### If arguments are empty or contain "help"
Display the available commands table above and explain each option.

## Important Notes

- All scripts are located in `.ai/scripts/`
- The update command requires git access to the WOF repository
- Status checks may show warnings for optional components (Worker-Lite, etc.)
- Route classification helps understand which worker will handle a task
- The remove command preserves config files (credentials, providers, models) and memory files by default
- Use --include-config to also remove config/memory files, --remove-all for complete deletion
