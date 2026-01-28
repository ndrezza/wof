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
| `ado` | Azure DevOps operations | Haiku |

**ADO Subagent Usage:**
- Route ALL Azure DevOps operations through the `ado` subagent
- Returns concise, human-readable summaries (not verbose JSON)
- Handles: work items, PRs, pipelines, code search, wikis

**When to use:** Any query involving work items, pull requests, pipelines, or ADO search.

**Example routing:**
```
User: "get work items"
→ Route to: Task tool with subagent_type="ado"
```

**IMPORTANT - Handling Subagent Responses:**
When a subagent (like `ado`) returns a formatted response, do NOT re-echo or re-summarize the same information. The subagent's output is already displayed to the user. Instead:
- Simply acknowledge completion (e.g., "Done." or move to next step)
- Only add commentary if there's genuinely new insight or action needed
- Avoid duplicating tables, lists, or summaries the subagent already provided

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
