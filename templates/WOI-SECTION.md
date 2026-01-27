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
| Workflows | `.ai/workflows/` |
| Model Tiers | `.ai/config/models.yaml` |
| Providers | `.ai/config/providers.yaml` |

### WOI Commands

| Command | Description |
|---------|-------------|
| `/wof status` | Check orchestration health |
| `/wof update` | Update to latest WOF version |
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
| **Validator** | Azure Sonnet 4.5 | Decision validation (>0.7) |
| **Worker-Heavy** | Azure Opus 4.5 | T2+ complex tasks |
| **Worker-Lite** | Local DeepSeek v2 Lite | T1 lightweight tasks |
| **Critic** | Azure Codex Mini | Quality gate (≥80%) |

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
