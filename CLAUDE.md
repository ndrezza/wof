# WOF - Workload Orchestration Framework

<!-- WOI-SECTION-START - Do not edit this section manually, managed by WOF -->
## Workload Orchestration Instance (WOI)

> **WOI v2.3.8** installed

This project has the Workload Orchestration Framework installed as a local instance (WOI).

### WOI Quick Reference

| Resource | Location |
|----------|----------|
| Architecture | `.ai/memory/architecture.md` |
| Conventions | `.ai/memory/conventions.md` |
| Current Sprint | `.ai/memory/current-sprint.md` |
| Routing Rules | `.ai/config/routing-rules.md` |
| Routing Script | `.ai/scripts/get-worker-routing.ps1` |
| Agent Definitions | `.ai/agents/` |
| Model Tiers | `.ai/config/models.yaml` |
| AI Connections | `.ai/config/connections.json` |
| Role Mappings | `.ai/config/roles.json` |

### WOI Commands

| Command | Description |
|---------|-------------|
| `/wof status` | Check orchestration health |
| `/wof update` | Update to latest WOF version |
| `/wof configure` | Configure AI connections and role mappings |
| `/wof configure-ado` | Configure Azure DevOps integration |
| `/wof route <task>` | Classify task routing |
| `/wof remove` | Remove WOI (preserves config/memory) |

### Multi-Agent Architecture

```
┌───────────────────────────────────────────────────────────────┐
│  PRIMARY (Opus 4.5) - ORCHESTRATOR                            │
│  Anthropic Direct API                                         │
│                                                               │
│  • Understand requirements                                    │
│  • Classify task complexity (T1/T2+)                          │
│  • Route to appropriate Worker                                │
│  • Consult Validator for decisions                            │
│  • Synthesize and respond                                     │
│                                                               │
│      PRIMARY DOES NOT CODE                                    │
└───────────────────────────────────────────────────────────────┘
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
                              │                  │
                              │ Skeptical Q&A    │
                              │ ≥80% viability   │
                              └──────────────────┘
```

| Component | Role |
|-----------|------|
| **Primary** | Orchestrator (NO coding) |
| **Validator** | Decision validation (>0.7 confidence) |
| **Worker-Heavy** | T2+ complex tasks |
| **Worker-Lite** | T1 lightweight tasks |
| **Critic** | Quality gate (≥80% viability) |

### Task Routing

**T1 - Lightweight (→ Worker-Lite):**
- File search, glob, grep operations
- Simple formatting and linting
- Code navigation and location

**T2+ - Complex (→ Worker-Heavy):**
- Code generation (> 20 lines)
- Test writing and execution
- Refactoring, architecture, security

**Routing:** See `.ai/config/routing-rules.md`
<!-- WOI-SECTION-END -->


> Auto-loaded by Claude Code. This document describes the WOF framework itself.

## What is WOF?

**WOF** (Workload Orchestration Framework) is a framework for AI-assisted software development. It provides:

- Multi-agent orchestration (Primary, Worker, Validator, Critic)
- Task routing (T1 lightweight vs T2+ complex)
- Memory management (architecture, conventions, current-sprint)
- Azure DevOps integration
- Configurable AI connections and role mappings

When WOF is installed in a project, it creates a **WOI** (Workload Orchestration Instance) - a local installation with `.ai/` and `.claude/` directories.

## Terminology

| Term | Full Name | Description |
|------|-----------|-------------|
| **WOF** | Workload Orchestration **Framework** | This repository - the source code and product |
| **WOI** | Workload Orchestration **Instance** | A local installation of WOF in a target project |

## Repository Structure

```
wof/
├── core/                    # Framework core (agents, scripts, config)
├── templates/               # Templates copied to WOI installations
├── extensions/              # Optional extensions (Azure DevOps, etc.)
├── examples/                # Example projects
├── setup.ps1                # Installation script
├── sync.ps1                 # Framework sync/update script
├── validate.ps1             # Validation script
├── CLAUDE.md                # This file (framework docs)
├── README.md                # Project documentation
├── CHANGELOG.md             # Version history
└── VERSION                  # Current version
```

## Inception Mode

This repository is special - it's **both WOF and a WOI**:

1. **WOF** - The framework source code lives here
2. **WOI** - An instance can be installed here for self-orchestration

This allows using AI orchestration to develop WOF itself.

| Path | Is WOF? | Is WOI? | Git Status |
|------|---------|---------|------------|
| `core/`, `templates/`, `setup.ps1`, `sync.ps1` | Yes | No | Tracked |
| `CLAUDE.md`, `README.md`, `VERSION` | Yes | No | Tracked |
| `.ai/` (when installed) | No | Yes | Gitignored |
| `.claude/` (when installed) | No | Yes | Gitignored |

**When editing this repo:**
- Changes to `core/`, `templates/`, scripts → You're improving **WOF**
- Changes to `.ai/`, `.claude/` → You're configuring the local **WOI**

## Development Guidelines

### Critical Behavioral Rules

**DO, don't suggest:**
- NEVER say "you might want to run tests" - RUN the tests
- NEVER leave work half-done - COMPLETE the workflow
- ALWAYS run builds and report results
- ALWAYS finish what you start
- ASK before committing or pushing - user controls git operations

**No AI attribution:**
- NEVER add `Co-Authored-By: Claude...` to commits
- NEVER add "Generated with Claude Code" or similar to PRs
- Keep commits and PRs clean - no AI branding

### Pre-Work Checklist

Before ANY code changes:

```bash
# 1. Check branch status
git status

# 2. If on main, create feature branch
git checkout -b feature/[meaningful-name]

# 3. Never commit directly to main
```

**Zero tolerance for main branch modifications.**

### Version Bumping

Before committing and pushing to main, bump the version:

1. Update `VERSION` file (semantic versioning: MAJOR.MINOR.PATCH)
2. Add entry to `CHANGELOG.md` describing the changes

```powershell
# Example: bump patch version
$v = [version](Get-Content VERSION); "$($v.Major).$($v.Minor).$($v.Build + 1)" | Set-Content VERSION
```

### Quality Gates

Every deliverable must pass:

1. **Build** - Solution compiles without errors
2. **Tests** - Relevant tests pass
3. **Security** - No exposed secrets
4. **Documentation** - Memory bank updated (if WOI installed)
5. **Git** - Proper branch, proper commit format

### Error Recovery

If something fails:

1. **Build fails** → Fix errors, don't proceed until green
2. **Tests fail** → Investigate, fix, re-run
3. **Security issue** → Block commit, report to user
4. **Unclear requirement** → Ask user, don't assume

## Installing WOI in This Repo

To enable AI orchestration for WOF development itself:

```powershell
# From the wof directory
.\setup.ps1 -TargetPath . -SolutionName "WOF" -Force
```

This will:
- Create `.ai/` with memory, config, scripts
- Create `.claude/` with settings and skills
- Inject a WOI-SECTION into this CLAUDE.md with orchestration instructions

To remove the WOI:

```powershell
.\.ai\scripts\remove.ps1
```

This removes the WOI files and the WOI-SECTION, leaving this base CLAUDE.md intact.

---

*This document describes the WOF framework. When a WOI is installed, additional orchestration instructions appear below.*
