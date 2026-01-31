# MCP Agent Setup Guide

This document explains how to set up MCP servers for each agent role in WOF.

## Why MCP Servers?

The analysis in `agent-communication-methods.md` concluded that **MCP servers are required** for Validator and Critic because:

1. **Independent Verification**: They need tool access to verify claims (read files, run tests, check git)
2. **Not "Blind"**: REST-based validation only sees what the Orchestrator tells it - bias passes through unchecked
3. **Sighted Validation**: MCP servers can independently check if "small change to utils.js" is actually a 2000-line critical file

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Claude Code Process                                   │
│                                                                               │
│  ┌───────────────────────┐                                                   │
│  │  ORCHESTRATOR CLAUDE  │  (Native Claude Code - you)                       │
│  │  Model: Opus 4.5      │                                                   │
│  └───────────┬───────────┘                                                   │
│              │                                                                │
│              │  MCP Tool Calls                                                │
│              │                                                                │
│  ┌───────────┴───────────────────────────────────────────────────────────┐  │
│  │                                                                        │  │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────┐   │  │
│  │  │ validator-claude │  │  critic-claude  │  │ worker-claude-heavy │   │  │
│  │  │ (MCP Server)     │  │  (MCP Server)   │  │ (MCP Server)        │   │  │
│  │  │                  │  │                 │  │                     │   │  │
│  │  │ Tools:           │  │ Tools:          │  │ Tools:              │   │  │
│  │  │ • Read files     │  │ • Run tests     │  │ • Read/Write files  │   │  │
│  │  │ • Check git      │  │ • Check coverage│  │ • Run builds        │   │  │
│  │  │ • Verify claims  │  │ • Run linters   │  │ • Execute code      │   │  │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────────┘   │  │
│  │                                                                        │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                                                               │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Microsoft Foundry Configuration (Optional)

By default, MCP servers use direct Anthropic API. To use **Microsoft Foundry (Azure)** instead, set these environment variables before starting Claude Code:

```bash
# Enable Microsoft Foundry integration
export CLAUDE_CODE_USE_FOUNDRY=1

# Azure resource name (replace with your resource name)
export ANTHROPIC_FOUNDRY_RESOURCE=your-resource-name
# Or provide the full base URL:
# export ANTHROPIC_FOUNDRY_BASE_URL=https://your-resource.services.ai.azure.com/anthropic

# Authentication (choose one):
# Option A: API Key
export ANTHROPIC_FOUNDRY_API_KEY=your-azure-api-key

# Option B: Microsoft Entra ID (Azure AD)
# If ANTHROPIC_FOUNDRY_API_KEY is not set, Claude Code uses Azure AD
# Run: az login

# Model deployment names (optional - uses defaults if not set)
export ANTHROPIC_DEFAULT_SONNET_MODEL='claude-sonnet-4-5'
export ANTHROPIC_DEFAULT_HAIKU_MODEL='claude-haiku-4-5'
export ANTHROPIC_DEFAULT_OPUS_MODEL='claude-opus-4-1'
```

**Why use Foundry?**
- Enterprise compliance (data stays in your Azure tenant)
- Unified billing through Azure
- Azure RBAC for access control
- Same models, same capabilities

**Required Azure Permissions:**
- `Azure AI User` or `Cognitive Services User` role
- Or custom role with `Microsoft.CognitiveServices/accounts/providers/*` dataAction

When these variables are set, both the main Claude Code instance AND all MCP servers will connect through Microsoft Foundry.

## Setup Commands

Run these commands in your project directory to register the MCP servers:

```bash
# Validator - for independent decision verification
claude mcp add --scope local validator-claude -- claude mcp serve

# Critic - for independent quality verification
claude mcp add --scope local critic-claude -- claude mcp serve

# Worker Heavy - for complex implementation tasks
claude mcp add --scope local worker-claude-heavy -- claude mcp serve
```

After running these commands, restart Claude Code to load the new MCP servers.

## Verification

Check that MCP servers are registered:

```bash
claude mcp list
```

Expected output should show:
- `validator-claude`
- `critic-claude`
- `worker-claude-heavy`

## How the Orchestrator Uses MCP Servers

Once registered, the Orchestrator has access to MCP tools for each role:

### Validator Tools
```
mcp__validator-claude__Task - Spawn a validation task
mcp__validator-claude__Read - Read files for verification
mcp__validator-claude__Bash - Run commands for verification
```

### Critic Tools
```
mcp__critic-claude__Task - Spawn a critique task
mcp__critic-claude__Bash - Run tests, coverage checks
mcp__critic-claude__Read - Read code for quality review
```

### Worker Heavy Tools
```
mcp__worker-claude-heavy__Task - Spawn implementation task
mcp__worker-claude-heavy__Edit - Edit files
mcp__worker-claude-heavy__Write - Create files
mcp__worker-claude-heavy__Bash - Run builds, tests
```

## Example: Validation via MCP

Instead of calling a REST endpoint, the Orchestrator uses MCP:

```
Orchestrator: "I want to validate my plan to modify auth.js"

→ Calls mcp__validator-claude__Task with prompt:
  "You are the Validator. Verify this plan is safe:
   - Plan: Modify auth.js to add logout functionality
   - Context: User requested logout feature

   IMPORTANT: Don't just trust my description.
   Use the Read tool to check auth.js yourself.
   Verify the file size, complexity, and risk level independently."

→ Validator Claude (MCP Server):
  1. Reads auth.js using Read tool
  2. Checks git history using Bash tool
  3. Independently assesses risk
  4. Returns: {confidence: 0.85, reasoning: "File is 150 lines, well-tested..."}
```

## Example: Critique via MCP

```
Orchestrator: "Worker says tests pass. Verify before commit."

→ Calls mcp__critic-claude__Task with prompt:
  "You are the Critic. Verify the Worker's claims:
   - Claim: All tests pass
   - Claim: Coverage is good

   IMPORTANT: Don't trust these claims.
   Run the tests yourself using Bash.
   Check coverage yourself.
   Report what you actually find."

→ Critic Claude (MCP Server):
  1. Runs `dotnet test` using Bash tool
  2. Runs coverage check
  3. Compares actual results to claims
  4. Returns: {viability: 0.4, findings: "Only 3/12 tests pass..."}
```

## Worker-Lite Exception

Worker-Lite remains REST-based because:
- T1 tasks are simple queries (search, format, lint)
- No tool access needed
- Local model = zero API cost
- High volume, low latency required

Use `.ai/scripts/delegate-to-local-worker.ps1` for Worker-Lite tasks.

## Troubleshooting

### "MCP server not found"
```bash
# Re-add the server
claude mcp add --scope local validator-claude -- claude mcp serve

# Restart Claude Code
```

### "Permission denied"
```bash
# Check Claude Code is properly authenticated
claude auth status
```

### "Too many MCP servers"
Each MCP server is a separate process. On resource-constrained systems:
- Use fewer roles (combine Validator + Critic)
- Use REST fallback for non-critical validation

## Role Personas

When invoking an MCP server, include the role persona in your prompt:

### Validator Persona
```
You are the VALIDATOR in the WOF multi-agent system.

Your job is INDEPENDENT VERIFICATION:
- Don't trust what the Orchestrator tells you
- Use tools to verify claims yourself
- Read files, check git history, assess risk independently
- Return confidence score (0.0-1.0) based on YOUR findings

Threshold: confidence >= 0.7 to approve
```

### Critic Persona
```
You are the CRITIC in the WOF multi-agent system.

Your job is INDEPENDENT QUALITY VERIFICATION:
- Don't trust what the Worker claims
- Run tests yourself, check coverage yourself
- Verify code quality independently
- Return viability score (0.0-1.0) based on YOUR findings

Threshold: viability >= 0.8 to approve commit
```

### Worker Heavy Persona
```
You are WORKER-HEAVY in the WOF multi-agent system.

Your job is IMPLEMENTATION:
- Receive task specifications from Orchestrator
- Implement code changes with tests
- Run builds and verify your work
- Return complete implementation with test results
```
