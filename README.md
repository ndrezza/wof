# Workload Orchestration Framework (WOF)

A reusable multi-agent AI orchestration framework for Claude Code projects. Enables intelligent task routing, quality gates, and automated workflows.

## Terminology: WOF vs WOI

| Term | Full Name | Description |
|------|-----------|-------------|
| **WOF** | Workload Orchestration **Framework** | The source repository, codebase, and product. This is what you're looking at now. |
| **WOI** | Workload Orchestration **Instance** | A local installation of WOF in a target project. Each project gets its own WOI. |

**Example:**
- WOF v2.0.0 is the framework version in this repository
- When you run `setup.ps1` on your project, you create a WOI (instance) based on WOF v2.0.0

## For AI Assistants

**If you are an AI coding assistant** and a user wants WOF installed:

1. Fetch and read: https://raw.githubusercontent.com/ndrezza/wof/main/AI-SETUP.md
2. Follow the structured installation protocol
3. Interview user for credentials if not found

This provides machine-readable step-by-step instructions for installing WOF into any project.

---

## Overview

This framework provides:

- **Multi-Agent Architecture** - Primary orchestrator with specialized workers
- **Dual-Worker Routing** - T1 lightweight tasks → local model, T2+ complex → Azure
- **Quality Gates** - Validator, Friend, and Critic agents for decision validation
- **Automated Workflows** - 9-phase feature development with phase gates
- **Hook Integration** - Claude Code hooks for command approval and file validation

## Architecture

```
┌─────────────────────────────────────────────────┬─────────────┐
│  PRIMARY - ORCHESTRATOR                         │   FRIEND    │
│  • Understand requirements                      │   Rules     │
│  • Classify task complexity (T1/T2+)            │   Guardian  │
│  • Route to appropriate Worker                  │             │
│  • Synthesize and respond                       │             │
│                                                 │             │
│      PRIMARY DOES NOT CODE                      │             │
└─────────────────────────────────────────────────┴─────────────┘
            │                         │                    │
            ▼                         ▼                    ▼
┌──────────────────┐  ┌───────────────────────────────────────────┐
│ VALIDATOR        │  │           DUAL-WORKER SYSTEM              │
│                  │  │  ┌─────────────────┬─────────────────┐    │
│ Decision valid.  │  │  │ WORKER-HEAVY    │ WORKER-LITE     │    │
│ >0.7 confidence  │  │  │                 │                 │    │
│                  │  │  │ T2+ Complex:    │ T1 Lightweight: │    │
│                  │  │  │ • Code gen      │ • File search   │    │
│                  │  │  │ • Testing       │ • Formatting    │    │
│                  │  │  │ • Refactoring   │ • Navigation    │    │
│                  │  │  └─────────────────┴─────────────────┘    │
└──────────────────┘  └───────────────────────────────────────────┘
                                          │
                                          ▼
                              ┌──────────────────┐
                              │ CRITIC           │
                              │ Skeptical Q&A    │
                              │ ≥80% viability   │
                              └──────────────────┘
```

| Role | Description | Config |
|------|-------------|--------|
| **Primary** | Orchestrator (NO coding) | See `roles.json` |
| **Worker-Heavy** | T2+ complex tasks (code gen, testing) | See `roles.json` |
| **Worker-Lite** | T1 lightweight tasks (search, format) | See `roles.json` |
| **Validator** | Decision validation (>0.7 threshold) | See `roles.json` |
| **Friend** | Rules/CLAUDE.md guardian | See `roles.json` |
| **Critic** | Quality gate (≥80% threshold) | See `roles.json` |

> **Configuration:** Role-to-connection mappings are defined in `.ai/config/roles.json`.
> AI connections are defined in `.ai/config/connections.json`.

## Installation

### Quick Start

```powershell
# Clone the framework
git clone https://github.com/ndrezza/wof.git

# Run setup
.\setup.ps1 -TargetPath "C:\code\MyProject" -SolutionName "MyProject"
```

### Git Behavior

WOI files are gitignored using **two managed sections** in `.gitignore`:

```gitignore
# <!-- WOI-FRAMEWORK-START - Managed by WOF, removed with framework -->
# WOF Framework Files (deleted when WOF is removed)
/.ai/scripts/approve-command.ps1
/.ai/scripts/check-orchestration-health.ps1
/.ai/agents/worker.md
/.ai/.framework-version
/.ai/.installed-files.json
/.claude/settings.json
/.claude/skills/finish-up/SKILL.md
/CLAUDE.md
# <!-- WOI-FRAMEWORK-END -->

# <!-- WOI-USERDATA-START - Managed by WOF, preserved after removal -->
# WOI User Data (kept after WOF removal - contains secrets/customizations)
/.ai/config/credentials.local.json
/.ai/config/connections.json
/.ai/config/roles.json
/.ai/config/models.yaml
/.ai/memory/architecture.md
/.ai/memory/conventions.md
/.ai/state/
/.ai/logs/
# <!-- WOI-USERDATA-END -->
```

**Why two sections?**
- **FRAMEWORK**: Removed when you uninstall WOF (scripts, agents, CLAUDE.md)
- **USERDATA**: Preserved after uninstall (credentials, memory, customizations remain gitignored)

This ensures `credentials.local.json` stays gitignored even after removing WOF.

**To share files with your team:** Remove specific entries from either section, then commit those files.

### Setup Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `TargetPath` | (required) | Root path of target project |
| `SolutionName` | Directory name | Name for templates |
| `GitDefaultBranch` | `main` | Protected branch name |
| `BuildCommand` | `dotnet build` | Build verification command |
| `WorkItemPrefix` | `#` | Work item reference prefix |
| `ConfigFormat` | `v2` | Config format: `v2` (JSON) or `legacy` (YAML/PS1) |
| `SkipTemplates` | `false` | Copy core files only |
| `Force` | `false` | Overwrite existing files |

### Post-Setup

1. **Configure credentials:**
   ```json
   // Edit .ai/config/credentials.local.json
   {
     "credentials": {
       "AI1_ENDPOINT": "https://your-resource.services.ai.azure.com/anthropic",
       "AI1_API_KEY": "your-key-here",
       "AI2_ENDPOINT": "https://your-resource.cognitiveservices.azure.com",
       "AI2_API_KEY": "your-key-here"
     }
   }
   ```

2. **Set up MCP server:**
   ```bash
   claude mcp add --scope local secondary-claude -- claude mcp serve
   ```

3. **Start local Worker-Lite (optional):**
   - Start LM Studio with DeepSeek Coder v2 Lite on port 1234

4. **Verify setup:**
   ```powershell
   .\.ai\scripts\check-orchestration-health.ps1
   ```

## Project Structure

After installation, your project will have:

```
your-project/
├── CLAUDE.md                      # Main orchestration document
├── .claude/
│   └── settings.json              # Claude Code hooks
└── .ai/
    ├── scripts/                   # Core automation scripts
    │   ├── get-worker-routing.ps1
    │   ├── validate-autonomy.ps1
    │   ├── bias-control.ps1
    │   ├── resolve-role.ps1
    │   ├── migrate-config.ps1
    │   └── ...
    ├── config/
    │   ├── connections.json       # AI connection definitions (v2)
    │   ├── roles.json             # Role-to-connection mappings (v2)
    │   ├── credentials.local.json # Secrets (gitignored, v2)
    │   ├── routing-rules.md       # T1/T2+ routing guidelines
    │   ├── risk-rules.yaml        # Command risk classification
    │   └── models.yaml            # Model tier definitions
    ├── memory/
    │   ├── architecture.md        # System architecture
    │   ├── conventions.md         # Coding standards
    │   └── current-sprint.md      # Active work context
    ├── agents/                    # Agent persona definitions
    └── workflows/                 # Process definitions
```

## Core Scripts

| Script | Purpose |
|--------|---------|
| `get-worker-routing.ps1` | Classify tasks and route to Worker-Lite or Worker-Heavy |
| `validate-autonomy.ps1` | Validate decisions with Azure Sonnet (>0.7 confidence) |
| `bias-control.ps1` | Skeptical Q&A quality gate with Codex Mini (≥80%) |
| `friend-watchdog.ps1` | CLAUDE.md rules compliance with GPT-4o |
| `phase-gate.ps1` | 9-phase workflow enforcement |
| `check-orchestration-health.ps1` | AI component status dashboard |
| `delegate-to-local-worker.ps1` | Worker-Lite task delegation |
| `approve-command.ps1` | Bash command risk classification |
| `approve-write.ps1` | File write validation |
| `log-worker-operation.ps1` | Worker operation audit logging |

## Task Routing

Tasks are classified and routed based on complexity:

**T1 - Lightweight (→ Worker-Lite):**
- File search, glob, grep operations
- Simple formatting and linting
- Code navigation and location
- Syntax validation
- Single-line or trivial edits
- Context requirement < 16K tokens

**T2+ - Complex (→ Worker-Heavy):**
- Code generation (> 20 lines)
- Test writing and execution
- Refactoring with semantic preservation
- Architectural work
- Security analysis
- Debug and optimization

**Always-Heavy Keywords:** deploy, production, critical, security, comprehensive, unit test, integration test

## Updating

To update to the latest framework version:

```powershell
# From Workload-Orchestration repo
.\sync.ps1 -TargetPath "C:\code\MyProject"

# Preview changes without applying
.\sync.ps1 -TargetPath "C:\code\MyProject" -DryRun
```

### Customization Preservation

Files marked with `# CUSTOMIZED` comment are preserved during sync. Add this marker to files you've customized:

```powershell
# CUSTOMIZED
# Your custom changes below...
```

## Validation

Verify your framework configuration:

```powershell
# From Workload-Orchestration repo
.\validate.ps1 -TargetPath "C:\code\MyProject"

# Or from your project
.\.ai\scripts\check-orchestration-health.ps1
```

## Extensions

### Azure DevOps Integration

For ADO work item management:

```powershell
# Copy template to your project
Copy-Item "extensions\azure-devops\ado-utils.ps1.template" ".ai\scripts\ado-utils.ps1"

# Edit and replace placeholders:
# {{ADO_ORGANIZATION}} → your-org
# {{ADO_PROJECT}} → your-project
```

## Requirements

- PowerShell 5.1+
- Claude Code CLI
- Azure AI Foundry access (for Worker-Heavy, Validator)
- Azure OpenAI access (for Friend, Critic)
- (Optional) LM Studio with local model for Worker-Lite

## Environment Variables (v2 Format)

Credentials are stored in `.ai/config/credentials.local.json` with generic names:

| Variable | Required | Description |
|----------|----------|-------------|
| `AI1_ENDPOINT` | Yes | Primary AI endpoint (e.g., Azure AI Foundry Anthropic) |
| `AI1_API_KEY` | Yes | Primary AI API key |
| `AI2_ENDPOINT` | Optional | Secondary AI endpoint (e.g., Azure OpenAI) |
| `AI2_API_KEY` | Optional | Secondary AI API key |
| `AI3_ENDPOINT` | Optional | Tertiary AI endpoint (e.g., Azure Codex) |
| `AI3_API_KEY` | Optional | Tertiary AI API key |
| `LOCAL1_ENDPOINT` | Optional | Local model endpoint (default: http://localhost:1234) |

> **Note:** The generic naming (AI1, AI2, AI3) allows role reassignment without changing credentials.
> Connection types (Azure AI Foundry, Azure OpenAI, etc.) are specified in `connections.json`.

## License

MIT License

## Contributing

1. Make changes in a feature branch
2. Test against a sample project using `setup.ps1`
3. Update CHANGELOG.md
4. Submit pull request
