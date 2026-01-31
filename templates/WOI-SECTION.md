<!-- WOI-SECTION-START - Do not edit this section manually, managed by WOF -->
## Workload Orchestration Instance (WOI)

> **WOI v{{WOI_VERSION}}** installed

This project has the Workload Orchestration Framework installed as a local instance (WOI).

### CRITICAL: How to Invoke External Agents

**External agents are invoked via MCP servers, NOT PowerShell scripts.**

Each agent role runs as a separate Claude Code MCP server with full tool access:

| Role | MCP Server | How to Invoke |
|------|------------|---------------|
| **Validator** | `validator-claude` | `mcp__validator-claude__Task` |
| **Critic** | `critic-claude` | `mcp__critic-claude__Task` |
| **Worker-Heavy** | `worker-claude-heavy` | `mcp__worker-claude-heavy__Task` |
| **Worker-Lite** | N/A (REST) | `powershell -File ".ai/scripts/delegate-to-local-worker.ps1"` |

**Why MCP, not scripts?** MCP servers have **independent tool access** - they can read files, run tests, and verify claims themselves. REST scripts only see what you tell them.

### MCP Server Setup

If MCP servers aren't configured yet, run these commands:

```bash
claude mcp add --scope local validator-claude -- claude mcp serve
claude mcp add --scope local critic-claude -- claude mcp serve
claude mcp add --scope local worker-claude-heavy -- claude mcp serve
```

Then **restart Claude Code** to load the servers.

### Example: Validate a Decision

```
# Use the MCP Task tool to spawn a validation task
mcp__validator-claude__Task with prompt:

"You are the VALIDATOR. Verify this decision is safe:
- Decision: [what you want to do]
- Context: [relevant context]

IMPORTANT: Don't trust my description. Use Read tool to check files yourself.
Return JSON: {confidence: 0.0-1.0, reasoning: '...', approved: true/false}"
```

### Example: Run Critic Quality Gate

```
# Use the MCP Task tool to spawn a critique task
mcp__critic-claude__Task with prompt:

"You are the CRITIC. Verify work quality before commit:
- Changes: [summary of changes]
- Claims: [what Worker claims - tests pass, etc.]

IMPORTANT: Don't trust claims. Run tests yourself using Bash tool.
Return JSON: {viability: 0.0-1.0, findings: '...', approved: true/false}"
```

### When Validation is Required

| Situation | Requires Validation? |
|-----------|---------------------|
| Making decisions WITHOUT asking user | ✅ YES - validate first |
| Asking user a question | ❌ NO - user IS the validation |
| Implementing your own plan | ✅ YES - validate the plan |
| Before committing code | ✅ YES - run Critic quality gate |

### Multi-Agent Architecture

```
┌───────────────────────────────────────────────────────────────┐
│  ORCHESTRATOR CLAUDE (You - Native Claude Code)               │
│                                                               │
│  • Understand requirements                                    │
│  • Classify task complexity (T1/T2+)                          │
│  • Invoke MCP servers for validation/work                     │
│  • Synthesize and respond                                     │
│                                                               │
│      ORCHESTRATOR DOES NOT CODE - DELEGATE TO WORKERS         │
└───────────────────────────────────────────────────────────────┘
      │               │                    │               │
      ▼               ▼                    ▼               ▼
┌───────────┐  ┌─────────────────────────────────────┐  ┌───────────┐
│ VALIDATOR │  │       DUAL-WORKER SYSTEM            │  │ CRITIC    │
│ (MCP)     │  │  ┌───────────────┬───────────────┐  │  │ (MCP)     │
│           │  │  │ WORKER-HEAVY  │ WORKER-LITE   │  │  │           │
│ Independent│  │  │ (MCP)        │ (REST)        │  │  │ Independent│
│ verification│ │  │               │               │  │  │ quality   │
│ >0.7 conf │  │  │ T2+ Complex:  │ T1 Light:     │  │  │ gate      │
│           │  │  │ • Code gen    │ • File search │  │  │ ≥0.8 viab │
│ Can READ  │  │  │ • Testing     │ • Formatting  │  │  │           │
│ files to  │  │  │ • Refactoring │ • Navigation  │  │  │ Can RUN   │
│ verify    │  │  └───────────────┴───────────────┘  │  │ tests to  │
│ claims    │  └─────────────────────────────────────┘  │ verify    │
└───────────┘                                           └───────────┘
```

### WOI Quick Reference

| Resource | Location |
|----------|----------|
| Architecture | `.ai/memory/architecture.md` |
| Conventions | `.ai/memory/conventions.md` |
| Current Sprint | `.ai/memory/current-sprint.md` |
| Routing Rules | `.ai/config/routing-rules.md` |
| Agent Definitions | `.ai/agents/` |
| MCP Setup Guide | `.ai/docs/mcp-agent-setup.md` |

### WOI Commands

| Command | Description |
|---------|-------------|
| `/wof status` | Check orchestration health |
| `/wof update` | Update to latest WOF version |
| `/wof configure` | Configure AI connections |
| `/wof route <task>` | Classify task routing |
| `/wof finish` | Complete work: update WI, commit, push |

### Task Routing

**T1 - Lightweight (→ Worker-Lite via REST):**
- File search, glob, grep operations
- Simple formatting and linting
- Code navigation and location

**T2+ - Complex (→ Worker-Heavy via MCP):**
- Code generation (> 20 lines)
- Test writing and execution
- Refactoring, architecture, security

### Thresholds

| Gate | Threshold | Meaning |
|------|-----------|---------|
| Validator | confidence ≥ 0.7 | Safe to proceed |
| Critic | viability ≥ 0.8 | Safe to commit |

<!-- WOI-SECTION-END -->
