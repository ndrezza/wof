# Workload Orchestration Framework (WOF)

A reusable multi-agent AI orchestration framework for Claude Code projects. Enables intelligent task routing, quality gates, and automated workflows.

## Terminology: WOF vs WOI

| Term | Full Name | Description |
|------|-----------|-------------|
| **WOF** | Workload Orchestration **Framework** | The source repository, codebase, and product. This is what you're looking at now. |
| **WOI** | Workload Orchestration **Instance** | A local installation of WOF in a target project. Each project gets its own WOI. |

**Example:**
- WOF v1.2.4 is the framework version in this repository
- When you run `setup.ps1` on your project, you create a WOI (instance) based on WOF v1.2.4

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
│  PRIMARY (Opus 4.5) - ORCHESTRATOR              │   FRIEND    │
│  • Understand requirements                      │   (GPT-4o)  │
│  • Classify task complexity (T1/T2+)            │   Rules     │
│  • Route to appropriate Worker                  │   Guardian  │
│  • Synthesize and respond                       │             │
│                                                 │             │
│      PRIMARY DOES NOT CODE                      │             │
└─────────────────────────────────────────────────┴─────────────┘
            │                         │                    │
            ▼                         ▼                    ▼
┌──────────────────┐  ┌───────────────────────────────────────────┐
│ VALIDATOR        │  │           DUAL-WORKER SYSTEM              │
│ (Azure Sonnet)   │  │  ┌─────────────────┬─────────────────┐    │
│                  │  │  │ WORKER-HEAVY    │ WORKER-LITE     │    │
│ Decision valid.  │  │  │ (Azure Opus)    │ (Local DeepSeek)│    │
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
                              │ (Codex Mini)     │
                              │ Skeptical Q&A    │
                              │ ≥80% viability   │
                              └──────────────────┘
```

| Component | Backend | Role |
|-----------|---------|------|
| **Primary** | Anthropic Direct (Opus 4.5) | Orchestrator (NO coding) |
| **Friend** | Azure GPT-4o | Rules/CLAUDE.md guardian |
| **Validator** | Azure Sonnet 4.5 | Decision validation (>0.7 confidence) |
| **Worker-Heavy** | Azure Opus 4.5 | T2+ complex tasks |
| **Worker-Lite** | Local DeepSeek v2 Lite | T1 lightweight tasks |
| **Critic** | Azure Codex Mini | Quality gate (≥80% viability) |

## Installation

### Quick Start

```powershell
# Clone the framework
git clone https://github.com/ndrezza/wof.git

# Run setup
.\setup.ps1 -TargetPath "C:\code\MyProject" -SolutionName "MyProject"
```

### Git Behavior

WOI (Workload Orchestration Instance) files are gitignored at the **individual file level**. The setup script adds a managed WOI section to your `.gitignore`:

```gitignore
# <!-- WOI-SECTION-START - Managed by WOF, do not edit manually -->
# Workload Orchestration Instance (WOI)
/.ai/config/credentials.local.ps1
/.ai/config/models.yaml
/.ai/config/providers.yaml
/.ai/memory/architecture.md
/.ai/scripts/approve-command.ps1
# ... (all installed WOI files)
/.ai/state/
/.ai/logs/
/.claude/settings.json
/.claude/skills/finish-up/SKILL.md
/CLAUDE.md
# <!-- WOI-SECTION-END -->
```

**This approach allows:**
- WOI framework files to remain local (not committed)
- User-created files in `.ai/` to be tracked if desired
- Clean separation between framework and custom content

**To share WOI with your team:** Remove the specific files you want to share from the WOI section in `.gitignore`, then commit them.

### Setup Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `TargetPath` | (required) | Root path of target project |
| `SolutionName` | Directory name | Name for templates |
| `GitDefaultBranch` | `main` | Protected branch name |
| `BuildCommand` | `dotnet build` | Build verification command |
| `WorkItemPrefix` | `#` | Work item reference prefix |
| `SkipTemplates` | `false` | Copy core files only |
| `Force` | `false` | Overwrite existing files |

### Post-Setup

1. **Configure credentials:**
   ```powershell
   # Edit .ai/config/credentials.local.ps1
   $env:AZURE_ANTHROPIC_ENDPOINT = "https://your-endpoint.azure.com"
   $env:AZURE_ANTHROPIC_API_KEY = "your-key"
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
├── CLAUDE.md                    # Main orchestration document
├── .claude/
│   └── settings.json            # Claude Code hooks
└── .ai/
    ├── scripts/                 # Core automation scripts
    │   ├── get-worker-routing.ps1
    │   ├── validate-autonomy.ps1
    │   ├── bias-control.ps1
    │   ├── friend-watchdog.ps1
    │   ├── phase-gate.ps1
    │   └── ...
    ├── config/
    │   ├── routing-rules.md     # T1/T2+ routing guidelines
    │   ├── risk-rules.yaml      # Command risk classification
    │   ├── providers.yaml       # AI provider config
    │   ├── models.yaml          # Model tier definitions
    │   └── credentials.local.ps1 # (gitignored)
    ├── memory/
    │   ├── architecture.md      # System architecture
    │   ├── conventions.md       # Coding standards
    │   └── current-sprint.md    # Active work context
    ├── agents/                  # Agent persona definitions
    └── workflows/               # Process definitions
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

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `AZURE_ANTHROPIC_ENDPOINT` | Yes | Azure AI Foundry endpoint |
| `AZURE_ANTHROPIC_API_KEY` | Yes | Azure Anthropic API key |
| `AZURE_OPENAI_ENDPOINT` | Optional | Azure OpenAI endpoint |
| `AZURE_OPENAI_API_KEY` | Optional | Azure OpenAI API key |
| `AZURE_CODEX_ENDPOINT` | Optional | Azure Codex endpoint |
| `LOCAL_WORKER_ENDPOINT` | Optional | Local model endpoint (default: http://127.0.0.1:1234) |

## License

MIT License

## Contributing

1. Make changes in a feature branch
2. Test against a sample project using `setup.ps1`
3. Update CHANGELOG.md
4. Submit pull request
