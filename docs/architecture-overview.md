# WOF Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                                                                                 │
│                    WOF - WORKLOAD ORCHESTRATION FRAMEWORK                       │
│                                                                                 │
│                         "Coordinate, Validate, Complete"                        │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Repository Structure

```
wof/
│
├── 📄 CLAUDE.md                 # Framework instructions (auto-loaded)
├── 📄 README.md                 # Project documentation
├── 📄 CHANGELOG.md              # Version history
├── 📄 VERSION                   # Current version
├── 📄 AI-SETUP.md               # AI connection setup guide
│
├── 🔧 setup.ps1                 # Install WOI in target project
├── 🔧 sync.ps1                  # Sync/update framework
├── 🔧 validate.ps1              # Validate installation
├── 📄 sync-manifest.json        # Sync behavior definitions
│
├── core/                        # 🧠 FRAMEWORK CORE
│   │
│   ├── agents/                  # Agent role definitions
│   │   ├── orchestrator-claude.md    # Primary coordinator
│   │   ├── validator-claude.md       # Decision validator
│   │   ├── critic-claude.md          # Quality gate
│   │   └── orchestrator.md           # Legacy orchestrator spec
│   │
│   ├── philosophy/              # Core principles
│   │   └── test-driven-improvement.md  # Three Laws of TDI
│   │
│   ├── workflows/               # Process definitions
│   │   └── task-execution-workflow.md  # 6-phase workflow
│   │
│   ├── config/                  # Configuration schemas
│   │   ├── risk-rules.yaml           # Risk-based approval routing
│   │   └── routing-rules.md          # T1/T2+ task routing
│   │
│   └── scripts/                 # PowerShell automation
│       ├── validate-autonomy.ps1     # Validator API calls
│       ├── interview-validator.ps1   # Validator demo
│       ├── delegate-to-local-worker.ps1  # Worker-Lite REST
│       ├── get-worker-routing.ps1    # Task routing logic
│       ├── check-orchestration-health.ps1  # Health checks
│       ├── resolve-role.ps1          # Role→connection mapping
│       ├── phase-gate.ps1            # 9-phase workflow
│       ├── bias-control.ps1          # Critic quality loop
│       └── ... (more scripts)
│
├── templates/                   # 📋 WOI TEMPLATES
│   │
│   ├── WOI-SECTION.md           # CLAUDE.md section for WOI
│   │
│   ├── dot-claude/              # .claude/ directory templates
│   │   ├── agents/
│   │   │   └── ado.md           # ADO subagent definition
│   │   └── skills/
│   │       └── wof/SKILL.md     # /wof skill definition
│   │
│   └── config/                  # .ai/config/ templates
│       ├── connections.json.template
│       ├── roles.json.template
│       ├── providers.yaml.template
│       └── credentials.local.json.template
│
├── extensions/                  # 🔌 OPTIONAL EXTENSIONS
│   └── azure-devops/            # ADO integration
│
├── examples/                    # 📚 EXAMPLE PROJECTS
│   └── dotnet/                  # .NET example
│
└── docs/                        # 📖 DOCUMENTATION
    ├── architecture-overview.md        # This file
    └── agent-communication-methods.md  # Communication guide
```

---

## Multi-Agent Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           MULTI-AGENT SYSTEM                                    │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│                              USER / ADO BACKLOG                                 │
│                                      │                                          │
│                                      ▼                                          │
│  ┌───────────────────────────────────────────────────────────────────────────┐ │
│  │                        ORCHESTRATOR CLAUDE                                 │ │
│  │                        (Claude Opus - Native)                              │ │
│  │                                                                            │ │
│  │  • Receives tasks from user or ADO                                        │ │
│  │  • Consults Validator for approval & testing strategy                     │ │
│  │  • Delegates to Workers (with test requirements)                          │ │
│  │  • Submits to Critic before commit                                        │ │
│  │  • Reports results to user                                                │ │
│  └────────────────────────────────┬──────────────────────────────────────────┘ │
│                                   │                                             │
│         ┌─────────────────────────┼─────────────────────────┐                  │
│         │                         │                         │                   │
│         ▼                         ▼                         ▼                   │
│  ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐          │
│  │  WORKER CLAUDE  │     │   VALIDATOR     │     │  CRITIC CLAUDE  │          │
│  │                 │     │    CLAUDE       │     │                 │          │
│  ├─────────────────┤     ├─────────────────┤     ├─────────────────┤          │
│  │ Heavy (MCP)     │     │ MCP Server      │     │ MCP Server      │          │
│  │ • Opus/Sonnet   │     │ • Sonnet        │     │ • Sonnet/Codex  │          │
│  │ • Full tools    │     │ • Read access   │     │ • Test runner   │          │
│  │ • T2+ tasks     │     │ • Git access    │     │ • Coverage      │          │
│  │                 │     │                 │     │ • Linters       │          │
│  ├─────────────────┤     ├─────────────────┤     ├─────────────────┤          │
│  │ Lite (REST)     │     │ Responsibilities│     │ Responsibilities│          │
│  │ • DeepSeek      │     │ • Verify claims │     │ • Run ALL tests │          │
│  │ • Local :1234   │     │ • Score 0.0-1.0 │     │ • Check coverage│          │
│  │ • T1 tasks      │     │ • Enforce tests │     │ • Score 0.0-1.0 │          │
│  │ • Queries only  │     │ • Keep on point │     │ • PASS/FAIL/    │          │
│  └─────────────────┘     └─────────────────┘     │   REMEDIATE     │          │
│                                                   └─────────────────┘          │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Communication Methods

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        AGENT COMMUNICATION METHODS                              │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐           │
│  │     MCP     │  │    REST     │  │    FILE     │  │    TASK     │           │
│  │   SERVER    │  │    API      │  │    BASED    │  │    TOOL     │           │
│  ├─────────────┤  ├─────────────┤  ├─────────────┤  ├─────────────┤           │
│  │ Worker-Heavy│  │ Worker-Lite │  │ Memory Bank │  │ Subagents   │           │
│  │ Validator   │  │ (old Critic)│  │ Config JSON │  │ (Explore,   │           │
│  │ Critic      │  │             │  │ Credentials │  │  Plan, etc) │           │
│  ├─────────────┤  ├─────────────┤  ├─────────────┤  ├─────────────┤           │
│  │ stdio/JSON  │  │ HTTP POST   │  │ Read/Write  │  │ In-process  │           │
│  │ Tool access │  │ Stateless   │  │ Persistent  │  │ Shared ctx  │           │
│  │ Persistent  │  │ Fast        │  │ Git-tracked │  │ No MCP      │           │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘           │
│                                                                                 │
│  Additional (conceptual): SSH Remote, Message Queues, WebSockets, Database     │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

See `docs/agent-communication-methods.md` for detailed documentation on each method.

---

## Task Execution Workflow

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         TASK EXECUTION WORKFLOW                                 │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│   PHASE 1: INTAKE                                                              │
│   ════════════════                                                             │
│   V0: Pre-Flight ──► Snapshot state, verify rollback readiness                 │
│   V1: Intake ──────► Is task clear? Can it be tested?                          │
│                                                                                 │
│   PHASE 2: PLANNING                                                            │
│   ═════════════════                                                            │
│   V2: Plan ────────► Testing strategy REQUIRED                                 │
│                      Validator must approve before implementation              │
│                                                                                 │
│   PHASE 3: IMPLEMENTATION                                                      │
│   ═══════════════════════                                                      │
│   Workers execute ─► Anomaly detection monitors                                │
│                      Tests written WITH code                                   │
│                                                                                 │
│   PHASE 4: QUALITY GATE                                                        │
│   ═════════════════════                                                        │
│   V3: Critic ──────► Run ALL tests (don't trust claims)                        │
│                      Check coverage, run linters                               │
│                      PASS / FAIL / REMEDIATE                                   │
│                                                                                 │
│   PHASE 5: COMMIT                                                              │
│   ═══════════════                                                              │
│   V4: Commit ──────► All tests pass? Coverage OK?                              │
│                      No secrets? Atomic change?                                │
│                                                                                 │
│   PHASE 6: COMPLETION                                                          │
│   ═══════════════════                                                          │
│   V5: Close ───────► Objectively validatable?                                  │
│                      Repeatable by anyone?                                     │
│                      Update ADO, close work item                               │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

See `core/workflows/task-execution-workflow.md` for detailed workflow documentation.

---

## Test-Driven Improvement (Three Laws)

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    TEST-DRIVEN IMPROVEMENT PHILOSOPHY                           │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│   ╔═══════════════════════════════════════════════════════════════════════╗    │
│   ║  LAW 1: NO PLAN WITHOUT TEST STRATEGY                                 ║    │
│   ║  ─────────────────────────────────────                                ║    │
│   ║  Before implementation: How will we verify this works?                ║    │
│   ║  Validator REJECTS plans without testing approach.                    ║    │
│   ╚═══════════════════════════════════════════════════════════════════════╝    │
│                                                                                 │
│   ╔═══════════════════════════════════════════════════════════════════════╗    │
│   ║  LAW 2: NO COMMIT WITHOUT TESTS                                       ║    │
│   ║  ──────────────────────────────                                       ║    │
│   ║  Every commit includes tests. ALL tests must pass.                    ║    │
│   ║  Critic BLOCKS commits without test coverage.                         ║    │
│   ╚═══════════════════════════════════════════════════════════════════════╝    │
│                                                                                 │
│   ╔═══════════════════════════════════════════════════════════════════════╗    │
│   ║  LAW 3: NO CLOSURE WITHOUT REPEATABLE VALIDATION                      ║    │
│   ║  ───────────────────────────────────────────────                      ║    │
│   ║  Work items close only when objectively verifiable.                   ║    │
│   ║  Automated tests = validation. Manual testing ≠ validation.           ║    │
│   ╚═══════════════════════════════════════════════════════════════════════╝    │
│                                                                                 │
│   Pre-Commit Protocol:                                                         │
│   ────────────────────                                                         │
│   $ git status          # Clean state?                                         │
│   $ dotnet build        # Build succeeds?                                      │
│   $ dotnet test         # ALL tests pass?                                      │
│   $ coverage report     # Coverage maintained?                                 │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

See `core/philosophy/test-driven-improvement.md` for the complete philosophy.

---

## Risk-Based Routing

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                          RISK-BASED ROUTING                                     │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│   TASK ROUTING (T1 vs T2+)                                                     │
│   ────────────────────────                                                     │
│                                                                                 │
│   T1 (Worker-Lite):              T2+ (Worker-Heavy):                           │
│   • Search, grep, find           • Implement features                          │
│   • Format, lint                 • Fix bugs                                    │
│   • Simple queries               • Refactor code                               │
│   • Status checks                • Write tests                                 │
│                                  • Architecture changes                        │
│                                                                                 │
│   VALIDATION ROUTING                                                           │
│   ──────────────────                                                           │
│                                                                                 │
│   Auto-Approve (>0.85):          Individual Validation (<0.70):                │
│   • Read operations              • Write operations                            │
│   • Status checks                • Config changes                              │
│   • Documentation                • Security-sensitive                          │
│                                  • Irreversible actions                        │
│                                                                                 │
│   ESCALATION TRIGGERS                                                          │
│   ───────────────────                                                          │
│                                                                                 │
│   Auto-escalate to human:                                                      │
│   • Validator confidence < 0.50                                                │
│   • Any architectural change                                                   │
│   • Any security-related task                                                  │
│   • 3+ consecutive validation rejections                                       │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## WOF vs WOI

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              WOF vs WOI                                         │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│   WOF (Framework)                    WOI (Instance)                            │
│   ═══════════════                    ═════════════                             │
│   This repository                    Installed in target projects              │
│   Source code & templates            .ai/ and .claude/ directories             │
│   Shared across projects             Project-specific configuration            │
│                                                                                 │
│   ┌─────────────────┐               ┌─────────────────┐                        │
│   │      WOF        │               │  Target Project │                        │
│   │   (this repo)   │               │                 │                        │
│   │                 │   setup.ps1   │  ┌───────────┐  │                        │
│   │  core/          │ ────────────► │  │   .ai/    │  │                        │
│   │  templates/     │               │  │  config/  │  │                        │
│   │  extensions/    │               │  │  memory/  │  │                        │
│   │                 │               │  │  scripts/ │  │                        │
│   │                 │   sync.ps1    │  └───────────┘  │                        │
│   │                 │ ────────────► │  ┌───────────┐  │                        │
│   │                 │   (updates)   │  │  .claude/ │  │                        │
│   │                 │               │  │  agents/  │  │                        │
│   │                 │               │  │  skills/  │  │                        │
│   └─────────────────┘               │  └───────────┘  │                        │
│                                     └─────────────────┘                        │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## AI Connections

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           AI CONNECTIONS                                        │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│   SLOT    PROVIDER                    MODEL                   ROLE             │
│   ────    ────────                    ─────                   ────             │
│   native  Claude Code                 claude-opus-4-5         Orchestrator     │
│   ai1     Azure AI Foundry Anthropic  claude-opus-4-5         Worker-Heavy     │
│   ai1     Azure AI Foundry Anthropic  claude-sonnet-4-5       Validator        │
│   ai2     Azure OpenAI                gpt-4o                  (available)      │
│   ai3     Azure OpenAI                gpt-5.1-codex-mini      Critic           │
│   ai4     Local (OpenAI-compatible)   deepseek-coder-v2       Worker-Lite      │
│   ai5-10  Configurable                ...                     (available)      │
│                                                                                 │
│   Connection Types:                                                            │
│   • azure_ai_foundry_anthropic  - Claude via Azure                             │
│   • azure_openai                - GPT via Azure                                │
│   • openai_compatible           - Local models (Ollama, vLLM, llama.cpp)       │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Agent Role Summary

| Agent | Communication | Model | Primary Responsibility |
|-------|---------------|-------|------------------------|
| **Orchestrator Claude** | Native | Claude Opus | Coordinate work, consult Validator, delegate to Workers |
| **Worker Claude Heavy** | MCP | Opus/Sonnet | Implement features, fix bugs, refactor (T2+ tasks) |
| **Worker Claude Lite** | REST | DeepSeek | Search, format, simple queries (T1 tasks) |
| **Validator Claude** | MCP | Sonnet | Verify claims, enforce testing, approve decisions |
| **Critic Claude** | MCP | Sonnet/Codex | Run tests, check coverage, quality gate |

---

## Summary Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              WOF IN ONE PICTURE                                 │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│                                  USER                                           │
│                                    │                                            │
│                                    ▼                                            │
│   ┌────────────────────────────────────────────────────────────────────────┐   │
│   │                      ORCHESTRATOR CLAUDE                                │   │
│   │                   "Coordinate, Validate, Complete"                      │   │
│   └───────────────────────────────┬────────────────────────────────────────┘   │
│                                   │                                             │
│              ┌────────────────────┼────────────────────┐                       │
│              │                    │                    │                        │
│              ▼                    ▼                    ▼                        │
│   ┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐              │
│   │     WORKERS      │ │    VALIDATOR     │ │      CRITIC      │              │
│   │  (Heavy + Lite)  │ │                  │ │                  │              │
│   │                  │ │  "Is this safe?" │ │ "Did tests pass?"│              │
│   │ "Do the work     │ │  "Test strategy?"│ │ "Coverage OK?"   │              │
│   │  WITH tests"     │ │  "Approve?"      │ │ "Ship it?"       │              │
│   └──────────────────┘ └──────────────────┘ └──────────────────┘              │
│                                   │                                             │
│                                   ▼                                             │
│   ┌────────────────────────────────────────────────────────────────────────┐   │
│   │                     TEST-DRIVEN IMPROVEMENT                             │   │
│   │                                                                         │   │
│   │    Law 1: No plan without test strategy                                │   │
│   │    Law 2: No commit without tests                                      │   │
│   │    Law 3: No closure without repeatable validation                     │   │
│   └────────────────────────────────────────────────────────────────────────┘   │
│                                   │                                             │
│                                   ▼                                             │
│                            ✅ SHIPPED WITH                                     │
│                               CONFIDENCE                                        │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Related Documentation

- `core/agents/orchestrator-claude.md` - Orchestrator role definition
- `core/agents/validator-claude.md` - Validator role definition
- `core/agents/critic-claude.md` - Critic role definition
- `core/philosophy/test-driven-improvement.md` - Testing philosophy
- `core/workflows/task-execution-workflow.md` - Detailed workflow
- `docs/agent-communication-methods.md` - Communication methods

---

*Document Version: 1.0.0*
*Last Updated: 2026-01-31*
