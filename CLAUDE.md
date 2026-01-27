# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

This is the **Workload Orchestration Framework (WOF)** - a reusable multi-agent AI orchestration framework for Claude Code projects. It provides intelligent task routing, quality gates, and automated workflows that get installed into target projects.

**This repository is the framework source, not a target project.** The framework is designed to be installed into other projects via `setup.ps1`.

## Commands

### Framework Installation (into a target project)
```powershell
# Source Controlled (default) - framework committed to git
.\setup.ps1 -TargetPath "C:\code\MyProject" -SolutionName "MyProject"

# Local Only - framework gitignored, personal use
.\setup.ps1 -TargetPath "C:\code\MyProject" -SolutionName "MyProject" -Mode LocalOnly
```

### Update an Existing Installation
```powershell
.\sync.ps1 -TargetPath "C:\code\MyProject"        # Apply updates
.\sync.ps1 -TargetPath "C:\code\MyProject" -DryRun  # Preview changes
```

### Validate Installation
```powershell
.\validate.ps1 -TargetPath "C:\code\MyProject"
```

## Architecture

The framework implements a multi-agent AI orchestration system:

```
PRIMARY ORCHESTRATOR (Opus 4.5 - Anthropic Direct)
├── Routes tasks based on complexity (T1 vs T2+)
├── Delegates to appropriate Worker
├── Consults Friend (GPT-4o) for rules compliance
├── Consults Validator (Azure Sonnet) for decisions (>0.7 confidence)
└── Passes output through Critic (Azure Codex Mini) quality gate (≥80%)

DUAL-WORKER SYSTEM
├── Worker-Lite (Local DeepSeek v2): T1 lightweight tasks
│   - File search/glob/grep, formatting, navigation, simple edits
│   - Cost: $0, Latency: 0.5-2s, Context: 32K tokens
│
└── Worker-Heavy (Azure Opus 4.5): T2+ complex tasks
    - Code generation (>20 lines), tests, refactoring, architecture
    - Cost: ~$0.015/1K, Latency: 2-8s, Context: 200K tokens
```

**Key principle:** The Primary AI orchestrator never codes directly - all coding is delegated to specialized workers with quality validation at each stage.

## Repository Structure

```
├── setup.ps1              # Installs framework into target projects
├── sync.ps1               # Updates existing installations
├── validate.ps1           # Validates installations
├── sync-manifest.json     # Defines sync behavior for each file
│
├── core/                  # Core framework files (copied to .ai/)
│   ├── scripts/           # Automation scripts (~10 PowerShell files)
│   ├── config/            # routing-rules.md, risk-rules.yaml
│   └── agents/            # Agent persona definitions
│
├── templates/             # Template files with {{PLACEHOLDER}} syntax
│   ├── CLAUDE.md.template       # Main orchestration document
│   ├── .claude/settings.json.template
│   └── memory/*.template        # architecture, conventions, sprint tracking
│
├── extensions/            # Optional add-ons
│   └── azure-devops/      # ADO work item integration
│
└── examples/              # Example configurations
    └── dotnet/            # .NET-specific setup
```

## Key Files to Understand

| File | Purpose |
|------|---------|
| `sync-manifest.json` | Controls how files are synced (overwrite, skip_if_customized, always_preserve) |
| `core/config/routing-rules.md` | Complete T1/T2+ task routing decision framework |
| `core/config/risk-rules.yaml` | Command risk classification (low/medium/high) |
| `templates/CLAUDE.md.template` | The main orchestration rules installed in target projects |

## Template Placeholders

Templates use `{{PLACEHOLDER}}` syntax replaced during setup:
- `{{SOLUTION_NAME}}` - Project name
- `{{BUILD_COMMAND}}` - Build command (default: `dotnet build`)
- `{{GIT_DEFAULT_BRANCH}}` - Protected branch (default: `main`)
- `{{WORK_ITEM_PREFIX}}` - Work item prefix (default: `#`)
- `{{ADO_ORGANIZATION}}`, `{{ADO_PROJECT}}` - Azure DevOps settings

## Customization Preservation

Files marked with `# CUSTOMIZED` as the first line are preserved during sync updates. The sync behavior is defined in `sync-manifest.json`:
- `overwrite` - Always update (scripts, core rules)
- `skip_if_customized` - Skip if file has `# CUSTOMIZED` marker
- `always_preserve` - Never touched (credentials, current-sprint.md)
- `template_only` - Created during setup, not updated on sync

## Testing Changes

After modifying the framework:
1. Run `setup.ps1` against a test project
2. Verify the target project structure is correct
3. Run `validate.ps1` to check configuration
4. If updating sync behavior, test `sync.ps1` with `-DryRun`
