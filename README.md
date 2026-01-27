# Workload Orchestration Framework

A reusable multi-agent AI orchestration framework for Claude Code projects. Enables intelligent task routing, quality gates, and automated workflows.

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
```

**Option A: Source Controlled** (team shares framework)
```powershell
.\setup.ps1 -TargetPath "C:\code\MyProject" -SolutionName "MyProject"
```

**Option B: Local Only** (personal use, invisible to team)
```powershell
.\setup.ps1 -TargetPath "C:\code\MyProject" -SolutionName "MyProject" -Mode LocalOnly
```

### Installation Modes

| Mode | Git Behavior | Use Case |
|------|--------------|----------|
| **SourceControlled** (default) | Framework committed to repo | Team collaboration, shared AI workflows |
| **LocalOnly** | Framework completely gitignored | Personal use, trying out, other devs unaffected |

#### Source Controlled (Default)

Framework files are tracked in git and shared with the team. Only sensitive files are gitignored.

```powershell
.\setup.ps1 -TargetPath "C:\code\MyProject" -SolutionName "MyProject"
```

**.gitignore entries:**
```gitignore
.ai/config/credentials.local.ps1
.ai/state/
.ai/logs/
```

#### Local Only

Framework is completely gitignored. Your AI orchestration setup is invisible to other developers.

```powershell
.\setup.ps1 -TargetPath "C:\code\MyProject" -SolutionName "MyProject" -Mode LocalOnly
```

**.gitignore entries:**
```gitignore
.ai/
.claude/
CLAUDE.md
```

**Use Local Only when:**
- You want to try the framework without affecting the team
- Other developers don't use Claude Code
- You want personal AI workflows that aren't shared
- The team hasn't decided on AI tooling yet

**Switching modes:** To convert from LocalOnly to SourceControlled:
1. Remove `.ai/`, `.claude/`, `CLAUDE.md` entries from `.gitignore`
2. Commit the framework files to the repository

### Setup Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `TargetPath` | (required) | Root path of target project |
| `SolutionName` | Directory name | Name for templates |
| `Mode` | `SourceControlled` | `SourceControlled` or `LocalOnly` |
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
