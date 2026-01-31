<!-- WOI-SECTION-START - Do not edit this section manually, managed by WOF -->
## Workload Orchestration Instance (WOI)

> **WOI v{{WOI_VERSION}}** installed

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
| Finish Config | `.ai/config/finish.json` |

### WOI Commands

| Command | Description |
|---------|-------------|
| `/wof status` | Check orchestration health |
| `/wof update` | Update to latest WOF version |
| `/wof configure` | Configure AI connections and role mappings |
| `/wof configure-ado` | Configure Azure DevOps integration |
| `/wof route <task>` | Classify task routing |
| `/wof finish` | Complete work: update WI, bump version, commit, push |
| `/wof remove` | Remove WOI (preserves config/memory) |

### Specialized Agents

| Agent | Purpose | Model |
|-------|---------|-------|
| `ado` | Formats ADO JSON into human-readable summaries | Haiku |

**ADO Subagent Usage (Relay Pattern):**

The `ado` subagent is a **formatter**, not a tool-caller. Subagents cannot access MCP tools directly.

**Workflow:**
1. Primary calls `mcp__azure-devops__*` tools directly
2. Primary passes raw JSON to `ado` subagent for formatting
3. Subagent returns concise, human-readable summary

**Example:**
```
1. Primary: Call mcp__azure-devops__list_work_items
2. Primary: Task tool → subagent_type="ado" → "Format this: <raw JSON>"
3. Subagent: Returns formatted table
```

**When to use:** After any ADO MCP tool call, to format verbose JSON into clean output.

**IMPORTANT - Handling Subagent Responses:**
When the subagent returns a formatted response, do NOT re-echo it. The output is already displayed to the user. Just acknowledge completion or move to the next step.

### CRITICAL: How to Invoke External Agents

**External agents (Validator, Critic, Worker-Lite) are invoked via PowerShell scripts using the Bash tool.**

Do NOT look for Task tool subagent types named "validator" or "critic". The ONLY way is:

```bash
# Validator - for autonomous decisions
powershell -File ".ai/scripts/validate-autonomy.ps1" -Decision "[question]" -Context "[context]"

# Critic - quality gate before commit
powershell -File ".ai/scripts/bias-control.ps1" -Phase "questions" -Context "[work summary]"

# Worker-Lite - delegate simple tasks
powershell -File ".ai/scripts/delegate-to-local-worker.ps1" -Task "[task]"
```

**When validation is required:**
- ✅ Making decisions WITHOUT asking user → Validate first
- ❌ Asking user a question → No validation needed (user IS the validation)
- ✅ Implementing your own plan → Validate the plan
- ❌ Implementing exactly what user specified → Usually no validation*

*Unless security, production, or irreversible changes.

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
      │               │                    │               │
      ▼               ▼                    ▼               ▼
┌───────────┐  ┌─────────────────────────────────────┐  ┌───────────┐
│ VALIDATOR │  │       DUAL-WORKER SYSTEM            │  │ ADO       │
│           │  │  ┌───────────────┬───────────────┐  │  │ SUBAGENT  │
│ Decision  │  │  │ WORKER-HEAVY  │ WORKER-LITE   │  │  │ (Haiku)   │
│ validation│  │  │               │               │  │  │           │
│ >0.7 conf │  │  │ T2+ Complex:  │ T1 Light:     │  │  │ • Work    │
│           │  │  │ • Code gen    │ • File search │  │  │   Items   │
│           │  │  │ • Testing     │ • Formatting  │  │  │ • PRs     │
│           │  │  │ • Refactoring │ • Navigation  │  │  │ • Pipes   │
│           │  │  └───────────────┴───────────────┘  │  │           │
└───────────┘  └─────────────────────────────────────┘  └───────────┘
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
| **ADO Subagent** | Azure DevOps operations (concise output) |

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
