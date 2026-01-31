<!-- WOI-SECTION-START - Do not edit this section manually, managed by WOF -->
## Workload Orchestration Instance (WOI)

> **WOI v{{WOI_VERSION}}** installed

This project has the Workload Orchestration Framework installed as a local instance (WOI).

### CRITICAL: How to Invoke External Agents

**External agents are invoked via MCP servers using DIRECT TOOLS, NOT the Task tool.**

Each agent role runs as a separate Claude Code MCP server with full tool access. Use direct tools:

| Role | MCP Server | Available Tools |
|------|------------|-----------------|
| **Validator** | `validator-claude` | `mcp__validator-claude__Read`, `mcp__validator-claude__Bash`, `mcp__validator-claude__Glob`, `mcp__validator-claude__Grep` |
| **Critic** | `critic-claude` | `mcp__critic-claude__Bash`, `mcp__critic-claude__Read`, `mcp__critic-claude__Glob`, `mcp__critic-claude__Grep` |
| **Worker-Heavy** | `worker-claude-heavy` | `mcp__worker-claude-heavy__Edit`, `mcp__worker-claude-heavy__Write`, `mcp__worker-claude-heavy__Bash`, `mcp__worker-claude-heavy__Read` |
| **Worker-Lite** | N/A (REST) | `powershell -File ".ai/scripts/delegate-to-local-worker.ps1"` |

**Why direct tools, not Task?** The `mcp__*__Task` tool requires subagent types that aren't configured in `claude mcp serve` instances. Direct tools (Read, Bash, Glob, etc.) work correctly.

**Why MCP, not scripts?** MCP servers have **independent tool access** - they can read files, run tests, and verify claims themselves. REST scripts only see what you tell them.

### MCP Server Setup

If MCP servers aren't configured yet, run these commands:

**Basic setup (all use Anthropic API):**
```bash
claude mcp add --scope local validator-claude -- claude mcp serve
claude mcp add --scope local critic-claude -- claude mcp serve
claude mcp add --scope local worker-claude-heavy -- claude mcp serve
```

**Hybrid setup (Local LLM + Cloud API):**
```bash
# First start the proxy: uv run uvicorn server:app --host 0.0.0.0 --port 8082

# Validator/Critic → Local LLM (cost-free)
claude mcp add --scope local validator-claude \
  -e ANTHROPIC_BASE_URL=http://localhost:8082 -e ANTHROPIC_API_KEY=local \
  -- claude mcp serve

claude mcp add --scope local critic-claude \
  -e ANTHROPIC_BASE_URL=http://localhost:8082 -e ANTHROPIC_API_KEY=local \
  -- claude mcp serve

# Worker Heavy → Azure Foundry (enterprise)
claude mcp add --scope local worker-claude-heavy \
  -e CLAUDE_CODE_USE_FOUNDRY=1 \
  -e ANTHROPIC_FOUNDRY_BASE_URL=https://your-resource.services.ai.azure.com/anthropic \
  -e ANTHROPIC_FOUNDRY_API_KEY=your-key \
  -- claude mcp serve
```

Then **restart Claude Code** to load the servers.

### Example: Validate a Decision

Use direct tools to perform validation yourself:

```
# Step 1: Read the file independently using Validator's tools
mcp__validator-claude__Read with file_path: "src/auth.js"
→ Returns: File contents (verify size and complexity yourself)

# Step 2: Check git history for context
mcp__validator-claude__Bash with command: "git log --oneline -5 src/auth.js"
→ Returns: Recent commits showing activity level

# Step 3: Assess risk based on YOUR findings, not Orchestrator's claims
→ Large security-critical file with active development = high risk = need user approval
```

### Example: Run Critic Quality Gate

Use direct tools to verify claims independently:

```
# Step 1: Run tests yourself (don't trust Worker's claims)
mcp__critic-claude__Bash with command: "dotnet test --no-build"
→ Returns: Actual test results (3/12 passing, not "all pass")

# Step 2: Check coverage
mcp__critic-claude__Bash with command: "dotnet test --collect:'XPlat Code Coverage'"
→ Returns: Coverage report (34%)

# Step 3: Assess viability based on YOUR findings
→ Worker claimed "all tests pass" but only 3/12 pass = viability 0.4 = block commit
```

### Why NOT the Task Tool?

The `mcp__*__Task` tool fails with: `Error: Agent type 'general-purpose' not found`

This happens because `claude mcp serve` instances don't have subagent types configured.
**Always use direct tools** (Read, Bash, Glob, Grep, Edit, Write) instead.

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
