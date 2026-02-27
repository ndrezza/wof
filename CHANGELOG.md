# Changelog

All notable changes to the Workload Orchestration Framework (WOF) will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.7.0] - 2026-02-27

### Added

- **Native Azure DevOps MCP server** (`core/mcp/wof-azure-devops`) (#2972)
  - 44 tools across 9 categories: identity, projects, repositories, git, work items, pull requests, pipelines, wiki, search
  - Two-layer architecture: `src/api/` (REST client) + `src/tools/` (MCP registration)
  - Single runtime dependency (`@modelcontextprotocol/sdk`) — no external repos needed
  - PAT-based auth via env vars or config file
  - Supports core, VSSPS, and search API hosts

### Changed

- Replaced `@tiberriver256/mcp-server-azure-devops` third-party dependency with native WOF server
- Configure wizard now prompts for org name and default project (instead of full URL)
- Updated README, SKILL.md template, and docs to reference native server
- Added `node_modules/` to `.gitignore`

## [3.6.1] - 2026-02-26

### Added

- **Notification menu in configuration wizard** — New `[4] Configure Notifications` option with full CRUD: edit settings, run graph-auth, send test notification, delete config
- **Architecture diagram updated** — README now shows ADO and Notification MCP servers in the overview drawing
- **MCP Servers documentation** — New section in README replacing old Extensions, with setup instructions for both Azure DevOps and Notifications MCP servers

### Changed

- Configuration wizard main menu renumbered: Test → `[5]`, View → `[6]`
- README project structure, core scripts table, and post-setup steps updated with notification files

## [3.6.0] - 2026-02-26

### Added

- **MCP notification server** (`core/mcp/wof-notifications`) (#2989)
  - Node.js/TypeScript MCP server with 4 tools: `authenticate`, `send_notification`, `read_messages`, `get_status`
  - Enables AI agents to send Teams/email notifications and read inbound messages natively via MCP
  - Device code authentication with in-memory token caching and silent refresh
  - Rate limiting, trigger filtering, and channel fallback support

- **App registration script** `register-notification-app.ps1` (#2989)
  - Automates custom Entra ID app registration with minimum delegated permissions
  - Creates service principal and grants tenant-wide admin consent
  - Updates `notifications.json` with the new client ID

- **Read notification script** `read-notification.ps1` (#2989)
  - Reads inbound Teams messages from the target user
  - Timestamp-based state tracking for incremental reads
  - HTML stripping for plain text output

### Fixed

- **`graph-auth.ps1`** — Persistent MSAL file cache for cross-session silent auth, custom `clientId` support from config, direct MSAL.NET device code API (fixes "Sequence contains no elements" error), UTF-8 encoded request bodies, bracket notation for `@odata` keys in chat member payloads (#2989)
- **`send-notification.ps1`** — Persistent file cache for silent auth, rate limiting with per-type cooldowns, UTF-8 encoded request bodies, custom `clientId` support (#2989)

### Changed

- `notifications.json.template` — Added `clientId` field and `rateLimit` configuration block
- Graph scopes now include `User.ReadBasic.All` for user resolution

## [3.5.0] - 2026-02-24

### Added

- **Unified AI invocation script** `invoke-ai.ps1` (#2991)
  - Single entry point for all AI API calls — consolidates duplicated logic from 5 scripts
  - Supports 3 connection types: `anthropic`, `azure-openai`, `openai-compatible`
  - Supports 4 delegation methods: `native`, `mcp`, `process`, `script`
  - Standardized JSON response format: `{Success, Content, Model, TokensUsed, ConnectionType, ConnectionId, Latency, Error}`
  - Invoke by `-Role` (resolves via roles.json) or `-ConnectionId` (direct connection)
  - Parameters: `-Prompt`, `-SystemPrompt`, `-Model` (override), `-MaxTokens`, `-Temperature`, `-AsJson`

- **Process delegation method** (#2991)
  - New delegation type: `"delegation": "process"` in roles.json
  - Spawns `claude --print --prompt "..." --model <model>` for quick AI queries
  - No tool access, no MCP overhead — lighter than MCP, heavier than REST
  - Uses Claude Code's own authentication — no API key management needed
  - Supports `--system-prompt` and `--max-tokens` flags

- **Generic script delegation contract** (#2991)
  - Scripts can accept `-InputJson` parameter with standardized payload
  - Payload includes: prompt, systemPrompt, model, maxTokens, connection details
  - Scripts return JSON: `{Success, Content, Model, TokensUsed, Error}`
  - `delegate-to-local-worker.ps1` updated to support `-InputJson` alongside existing `-Task`
  - Backward compatible — existing callers unaffected

- **Flexible AI connections documentation** (#2991)
  - New `core/docs/flexible-ai-connections.md` — comprehensive guide to invoke-ai.ps1
  - Covers all delegation methods, connection types, OpenAI API compatibility
  - Documents generic script delegation contract (input/output JSON format)
  - Migration guide from duplicated API calls to invoke-ai.ps1
  - OpenAI compatibility matrix: OpenAI, Ollama 0.14+, vLLM, llama.cpp, LM Studio

### Changed

- **resolve-role.ps1** now includes `delegation` and `script` fields in resolved output (#2991)
- **roles.json.template** bumped to v3.2.0 (#2991)
  - Documents all 4 delegation types: native, mcp, process, script
  - Includes `_script_contract` documentation key with input/output JSON format
- **agent-communication-methods.md** updated to v1.5.0 (#2991)
  - New Method 3: Claude Process Delegation (architecture, pros/cons, WOF files)
  - Methods renumbered: SSH Remote → 4, Task Tool → 5, Message Queue → 6, etc.
  - Comparison matrix updated with Process Delegation row
- **SKILL.md** — `/wof configure` wizard now offers process delegation (#2991)
  - Step B3 delegation choice expanded: MCP Server, Process delegation, PS Script
  - Delegation types reference added after roles.json example

## [3.4.4] - 2026-02-24

### Added

- **Import config from another project** in `/wof configure` (#2997)
  - New menu option "Import config from another project" in the configure wizard
  - Copies `connections.json`, `roles.json`, and optionally `ado.json` from an existing WOI installation
  - 7-step interactive flow: source path → validate → preview → scope → ADO handling → execute → summary
  - Preview shows all connections, role mappings, and ADO settings before import
  - ADO import prompts for this project's project name (keeps org URL and filters)
  - Security: never copies credentials (`credentials.local.json`, `.mcp.json`, `local-ai.json`, `index.json`, `finish.json`)
  - Explicit warnings about missing credentials at preview and summary steps
  - Back navigation at every step
  - Edge cases: same-project detection, missing files, no configured connections, different ADO org

## [3.4.3] - 2026-02-24

### Changed

- **Mandatory plan mode on ADO work item start** (#2999)
  - "When Starting a Work Item" expanded from 3 steps to 4-step plan-mode-first flow
  - Step 1: Read full work item details (title, description, acceptance criteria, comments)
  - Step 2: Set Active, create branch, tag with "Analysis" (not "Implementation")
  - Step 3: Enter plan mode (MANDATORY) — analyze requirements, design approach, get user approval
  - Step 4: Implement only after plan approval (update tag to "Implementation")
  - Tag Conventions updated: work items now start in "Analysis" phase, not "Implementation"

- **Validator-first question escalation** (#2999)
  - New "Question Escalation Order" in WOI-SECTION.md: self-resolve → Validator → User
  - Validator has independent tool access and should be consulted before escalating to user
  - Question type table shows which questions go to Validator vs User
  - CLAUDE.md.base.template updated with validator-first escalation rule after validation section
  - Phase 1 INTAKE now includes mandatory plan mode step for ADO work items

- **Work Item Start Protocol** added to WOI-SECTION.md
  - CRITICAL section documenting the 6-step plan-mode-first protocol
  - Explains why planning first prevents wasted effort and catches misunderstandings

## [3.4.2] - 2026-02-23

### Added

- **`/wof configure-index` command** - Configure code index for semantic search via Qdrant
  - Interactive flow (7 questions) with Back navigation at every step
  - Connects to existing Qdrant vector database (local or Qdrant Cloud)
  - Supports Azure OpenAI, OpenAI, and local Ollama embedding providers
  - Critical: uses the same embedding model that created the vectors (required for similarity search)
  - Non-sensitive config stored in `.ai/config/index.json`
  - MCP server credentials stored in `.mcp.json` (`code-index` entry via `uvx mcp-server-qdrant`)
  - Platform-aware: Windows uses `cmd /c uvx`, Linux/macOS uses `uvx` directly
  - New `index.json.template` deployed during WOI setup
  - `setup.ps1` updated: deploys template, protected in `$neverOverwrite`
  - `sync-manifest.json` updated: `index.json` in `template_only`
  - After restart, `mcp__code-index__qdrant-find` tool available for semantic code search

## [3.4.1] - 2026-02-22

### Added

- **Index Database Research Report** (#2971)
  - Comprehensive analysis at `core/docs/research-index-database.md`
  - Finding: Claude Code has no native index database (uses on-the-fly Glob/Grep)
  - Competitor analysis: Cursor, GitHub Copilot, Continue.dev, Windsurf, RooCode
  - Embedding models comparison: voyage-code-3, OpenAI, local models (MiniLM, nomic)
  - MCP server landscape: 10 servers analyzed (Claude Context, CodeGrok, CocoIndex, etc.)
  - Azure-native options: AI Search, Cosmos DB, PostgreSQL+pgvector with pricing
  - Local options: sqlite-vec, ChromaDB, Qdrant, FAISS, LanceDB
  - Tiered recommendation: Tier 1 (adopt MCP server), Tier 2 (WOF-native module), Tier 3 (Azure enterprise)
  - Recommended quick win: Claude Context MCP (5.4k stars, hybrid BM25+vector search)

## [3.4.0] - 2026-02-22

### Added

- **ADO Tag-Based Work Item Filtering** (#2988)
  - New `filters.tags` array in `ado.json` for tag-based query filtering
  - Empty array (default) = no filter, preserving backward compatibility
  - Multiple tags use AND logic (all must be present on a work item)
  - `behavior.skipBlockedItems` now enforced in WIQL with `NOT CONTAINS '<tags.blocked>'`
  - `scan-workitems.ps1` updated with `-Tag`, `-SkipBlocked`, and `-BlockedTag` parameters
  - Tags field added to scan results output
  - New Question 7 in `/wof configure-ado` flow: "Filter work items by tags?"
  - WIQL guidance updated with tag inclusion and blocked exclusion examples
  - WOI-SECTION.md checklist updated with tag filter step

## [3.3.0] - 2026-02-21

### Added

- **D-User Notification System (Teams Chat & Email)** (#2989)
  - New `graph-auth.ps1` script for one-time device code flow authentication via MSAL.PS
  - New `send-notification.ps1` script for sending notifications via Teams chat or email
  - New `notifications.json.template` for d-user identity, target user, and notification preferences
  - Uses Microsoft Graph PowerShell SDK client ID (no custom Azure AD app registration)
  - Supports trigger-based filtering (needsInput, blocked, completed, progress)
  - Graceful fallback from Teams to email if primary channel fails
  - Silent token refresh via MSAL.PS cached tokens
  - Teams messages include color-coded type badges (orange/red/green/blue)
  - `setup.ps1` updated to deploy notifications.json template during WOI installation
  - `sync-manifest.json` updated with notifications.json in template_only patterns

## [3.2.6] - 2026-02-18

### Added

- **Inception mode protection for setup.ps1 and sync.ps1** (#2965)
  - Detects when TargetPath points to the WOF source directory itself
  - Displays prominent red/yellow warning box explaining the risk
  - Requires `-AllowInception` flag to proceed (aborts by default)
  - Prevents accidental WOI installation in the WOF framework repo

## [3.2.5] - 2026-02-05

### Added

- **Pre-Commit Workflow section in CLAUDE.md** (#2970)
  - Mandatory test-before-commit sequence: Code → Build → Test → Review → Commit
  - Explains why order matters (verified commits, no pollution)
  - Defines what counts as "testing" for different change types

## [3.2.4] - 2026-02-05

### Added

- **CLAUDE.md WOF vs WOI editing rules** - Clear guidance for AI agents (#2968)
  - New "CRITICAL: WOF vs WOI Editing Rules" section
  - Table showing which WOF source files to edit vs WOI paths to avoid
  - Instructions for propagating changes to WOI installations
  - Example response format after making WOF changes
  - "Never Do This" checklist to prevent common mistakes

## [3.2.3] - 2026-02-05

### Added

- **WOF managed file warnings** - Clear "DO NOT EDIT" notices (#2964)
  - All 16 core scripts now have header warnings
  - Warning explains files are overwritten on sync/update
  - Directs users to use `.ai/config/` for customization
  - SKILL.md has softer warning (customizations preserved but may need review)
  - WOI-SECTION.md already had start/end markers

## [3.2.2] - 2026-02-05

### Improved

- **`/wof configure-ado` back navigation** - Added "Back" option to all AskUserQuestion prompts
  - Organization URL question: Back returns to configure menu
  - Project name question: Back returns to previous question
  - PAT question: Back returns to previous question, Skip keeps existing
  - Filter questions (Value Area, Types, States): All include Back option

## [3.2.1] - 2026-02-05

### Added

- **Azure DevOps MCP configuration** in `/wof configure`
  - New menu option `[3] Configure Azure DevOps MCP`
  - Set organization URL (dev.azure.com or visualstudio.com formats)
  - Configure Personal Access Token (PAT) with inline testing
  - Test ADO connection with user authentication display
  - Saves to `.mcp.json` for Claude Code MCP server
  - `-TestOnly` flag now also tests ADO connection

### Improved

- **`/wof configure` menu navigation** - Complete UX overhaul
  - Hierarchical menu system with back navigation at every level
  - Main menu: Manage Connections, Configure Roles, ADO MCP, Test All, View Config, Save, Quit
  - Connection slot menu: Edit, Rename, Test, Delete, Back
  - Role mapping menu: Select role to modify, Back to main
  - ADO menu: Edit, Test, Delete, Back
  - Unsaved changes tracking with save prompt on quit
  - Fast connection list (no auto-testing) with explicit "Test All" option
  - Consistent `[B] Back` option throughout all submenus
  - Status display shows both AI connections and ADO status

## [3.2.0] - 2026-02-03

### Added

- **`/wof start` command** - Session initialization with health checks
  - Tests AI endpoint connectivity for each configured role (5s timeout)
  - Reports MCP server configuration status
  - Loads memory bank context (sprint, conventions, architecture)
  - Acknowledges Orchestrator role with key behavioral rules
  - Compact table output showing role status, connection, and latency
  - `-verbose` flag for detailed output including sprint summary
  - Non-blocking warnings - session proceeds even with offline endpoints

## [3.1.0] - 2026-02-02

### Added

- **`/wof configure` → "Local AI (Ollama)"** - New menu option to configure local Ollama instance
  - Auto-detect Ollama at localhost:11434 or custom host/IP
  - **Dynamic model analysis**: Checks WOF's model capabilities cache first, then WebSearch for unknown models
  - Recommends models for each role based on capabilities (reasoning, code gen, speed)
  - Per-role delegation choice: MCP Server (parallel) or PS Script (sequential)
  - RAM requirements shown but user decides (supports everything from laptops to Mac Studio clusters)
  - Generate cross-platform launcher scripts
  - Register as AI slot (AI1-AI10) for role mapping

- **Model capabilities database** - `core/data/model-capabilities.json`
  - Pre-cached capabilities for 20+ popular models (Qwen, DeepSeek, CodeLlama, Llama, Mistral, etc.)
  - Includes: strengths, weaknesses, RAM requirements, recommended roles, quality/speed tiers
  - Role requirements defined: what each role needs (orchestrator, worker-heavy, worker-lite, validator, critic)
  - Unknown models trigger WebSearch for capability analysis

- **`/wof model` command with backend detection** - Enhanced model management
  - `/wof model` - Detect current backend (Anthropic/Ollama/Azure) and show status
  - `/wof model list` - List available Ollama models with capability analysis
  - `/wof model <name>` - Switch to a specific model (when on Ollama)
  - `/wof model pull <name>` - Download a new model
  - `/wof model status` - Comprehensive backend and launcher status

- **Cross-platform launcher scripts** - Start Claude Code with local Ollama backend
  - Windows: `Start-ClaudeLocal.ps1` with `-Model` parameter support
  - macOS/Linux: `start-claude-local.sh` with `--model` flag support
  - Default locations: `~/.claude/` or Desktop
  - Templates in `templates/launchers/`

- **Flexible delegation methods** - Each role can choose:
  - `mcp` - Separate Claude Code process via MCP server (parallel, independent)
  - `script` - Sequential delegation via PowerShell script (simpler)
  - `native` - Direct invocation (orchestrator only)

### Changed

- **Worker-Lite can now use MCP Server** - No longer limited to REST/script delegation
  - User chooses: MCP Server (parallel) or PS Script (sequential) per role
  - `delegate-to-local-worker.ps1` remains available for script delegation

- **roles.json schema updated to v3.1.0** - Added `delegation` field
  - Explicit delegation method per role
  - Backward compatible with existing configs

- **Ollama is now the recommended local LLM solution** - Updated all documentation
  - Ollama v0.14.0+ has native Anthropic Messages API compatibility (no proxy required)
  - Removed LM Studio as primary example; now listed as alternative with vLLM/llama.cpp

### Architecture: Full Local Setup

This release enables running entirely on local models with role-specific model selection:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Start-ClaudeLocal.ps1                                                       │
│                                                                              │
│  ORCHESTRATOR (Claude Code Process #1)                                       │
│  Model: mistral:7b @ localhost:11434 (~4GB RAM)                             │
│  Role: Task routing, coordination, user interaction                         │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  Worker Pool (MCP Servers = separate Claude Code processes)          │   │
│  │                                                                      │   │
│  │  ┌───────────────┐ ┌───────────────┐ ┌───────────────┐ ┌──────────┐│   │
│  │  │ worker-heavy  │ │ worker-lite   │ │ validator     │ │ critic   ││   │
│  │  │ Process #2    │ │ Process #3    │ │ Process #4    │ │ Process #5│   │
│  │  │               │ │               │ │               │ │          ││   │
│  │  │ qwen3-coder   │ │ codellama:7b  │ │ deepseek-r1   │ │ deepseek ││   │
│  │  │ :30b (~20GB)  │ │ (~4GB)        │ │ :8b (~5GB)    │ │ -r1:8b   ││   │
│  │  │               │ │               │ │               │ │          ││   │
│  │  │ Complex code  │ │ Simple tasks  │ │ Verify claims │ │ Quality  ││   │
│  │  │ generation    │ │ Search, fmt   │ │ Check files   │ │ gate     ││   │
│  │  │               │ │ OR: PS Script │ │               │ │          ││   │
│  │  └───────────────┘ └───────────────┘ └───────────────┘ └──────────┘│   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  All connect to Ollama @ localhost:11434                                    │
│  Models loaded on-demand (not all in RAM simultaneously)                    │
│  Peak RAM estimate: ~33GB (if all loaded at once)                           │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Hybrid Architecture: Local Orchestrator + Cloud Workers

For cost optimization with quality fallback:

```
┌─────────────────────────────────────────────────────────────────┐
│  ORCHESTRATOR (Local - mistral:7b)                               │
│  Cost: $0                                                        │
│                                                                  │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │ worker-heavy    │  │ validator       │  │ worker-lite     │ │
│  │ Azure Foundry   │  │ Ollama local    │  │ Ollama local    │ │
│  │ Claude Sonnet   │  │ deepseek-r1:8b  │  │ codellama:7b    │ │
│  │ Cost: $$        │  │ Cost: $0        │  │ Cost: $0        │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```
```

## [3.0.7] - 2026-02-02

### Changed

- **Ollama is now the recommended local LLM solution** - Updated all documentation to prioritize Ollama over other options
  - Removed LM Studio references from primary documentation
  - vLLM/llama.cpp listed as alternatives requiring proxy

### Why Ollama?

| Feature | Ollama | Other Local Servers |
|---------|--------|---------------------|
| Anthropic API native | Yes (v0.14+) | No |
| Auto model switching | Dynamic | Manual |
| CLI/headless | Yes | Limited |
| Proxy required | No | Yes |

## [3.0.6] - 2026-02-01

### Added

- **Environment-aware shell syntax guidance** - WOI section now includes OS/shell detection with explicit syntax guidance
  - Windows/PowerShell users see PowerShell syntax examples (Test-Path, Get-ChildItem, etc.)
  - Unix/macOS users see Bash syntax examples
  - Prevents frequent "I need to use proper bash syntax, not PowerShell" errors

- **Strengthened ADO project filtering** - Added critical guidance for Azure DevOps queries
  - Template now shows configured project name prominently
  - WIQL examples explicitly include `[System.TeamProject]` filter
  - MCP tool calls show required `projectId` parameter
  - Warning about failure mode when filter is omitted

### Changed

- `setup.ps1` now detects OS and shell environment, populates conditional template blocks
- `sync.ps1` now processes conditional blocks when updating WOI section
- Added `Process-ConditionalBlocks` function for Handlebars-style `{{#if}}` / `{{#unless}}` processing

## [3.0.5] - 2026-01-31

### Added

- **Hybrid MCP routing with environment variables** - MCP servers can now be configured to route to different AI backends using the `-e` flag
  - Validator/Critic can use local LLM via proxy for cost-free validation
  - Worker-Heavy can use Azure Foundry for enterprise compliance
  - Each MCP server can have independent API endpoint configuration

### Example Configuration

```bash
# Local LLM routing (via claude-code-proxy)
claude mcp add --scope local validator-claude \
  -e ANTHROPIC_BASE_URL=http://localhost:8082 \
  -e ANTHROPIC_API_KEY=local \
  -- claude mcp serve

# Azure Foundry routing
claude mcp add --scope local worker-claude-heavy \
  -e CLAUDE_CODE_USE_FOUNDRY=1 \
  -e ANTHROPIC_FOUNDRY_BASE_URL=https://your-resource.services.ai.azure.com/anthropic \
  -e ANTHROPIC_FOUNDRY_API_KEY=your-key \
  -- claude mcp serve
```

### Architecture

```
Claude Code (Orchestrator)
├── validator-claude  → Ollama :11434 → Local LLM (no proxy!)
├── critic-claude     → Ollama :11434 → Local LLM (no proxy!)
└── worker-claude-heavy → Azure Foundry → Claude Sonnet
```

This enables cost-optimized workflows where validation uses free local inference while heavy work uses cloud APIs.

## [3.0.4] - 2026-01-31

### Fixed

- **MCP documentation: Task tool does not work** - Fixed incorrect documentation that showed using `mcp__*__Task` tool for agent invocation
  - `claude mcp serve` instances don't have subagent types configured
  - Updated to use direct tools instead: `Read`, `Bash`, `Glob`, `Grep`, `Edit`, `Write`
  - Updated `templates/WOI-SECTION.md` with correct examples
  - Added "Why NOT the Task Tool?" section explaining the error

### Why This Matters

The previous documentation showed examples like `mcp__validator-claude__Task` which fail with:
```
Error: Agent type 'general-purpose' not found. Available agents:
```

Direct tools work correctly and allow independent verification:
- `mcp__validator-claude__Read` - Read files to verify claims
- `mcp__critic-claude__Bash` - Run tests to verify quality
- `mcp__worker-claude-heavy__Edit` - Make code changes

## [3.0.3] - 2026-01-31

### Added

- **Local LLM configuration documentation** - MCP servers can now use local models (Ollama recommended) instead of cloud APIs
  - Recommended: Ollama v0.14.0+ with native Anthropic API compatibility (no proxy required)
  - Alternative: vLLM/llama.cpp with claude-code-proxy translation layer
  - Method 3: Hybrid setup - MCP server with local backend while main session uses cloud
  - Performance considerations and troubleshooting guide
  - Architecture diagrams showing proxy setup

### Why This Matters

Local LLMs provide:
- **Zero API cost** - Free inference after hardware investment
- **Complete privacy** - Code never leaves your machine
- **Offline capability** - Work without internet connection

**Recommended use cases:**
- Worker-Lite tasks (search, format, simple queries)
- Cost-sensitive high-volume operations
- Air-gapped/offline environments

**Setup example:**
```bash
# Add MCP server using local LLM
claude mcp add --scope user local-llm-worker -- \
  bash -c 'ANTHROPIC_BASE_URL=http://localhost:8082 ANTHROPIC_API_KEY=local claude mcp serve'
```

## [3.0.2] - 2026-01-31

### Added

- **Microsoft Foundry configuration documentation** - MCP servers can now connect through Microsoft Foundry (Azure) for enterprise compliance
  - Environment variables: `CLAUDE_CODE_USE_FOUNDRY`, `ANTHROPIC_FOUNDRY_RESOURCE`, `ANTHROPIC_FOUNDRY_API_KEY`
  - Supports both API key and Microsoft Entra ID authentication
  - Updated `docs/mcp-agent-setup.md`, `core/docs/mcp-agent-setup.md`, and `AI-SETUP.md`

### Why This Matters

MCP servers using `claude mcp serve` inherit environment variables from the parent process. When Microsoft Foundry variables are set, all agent roles (Validator, Critic, Worker-Heavy) will connect through Azure instead of direct Anthropic API.

**Benefits:**
- Enterprise compliance (data stays in your Azure tenant)
- Unified billing through Azure
- Azure RBAC for access control
- Same models and capabilities as direct API

**Configuration:**
```bash
export CLAUDE_CODE_USE_FOUNDRY=1
export ANTHROPIC_FOUNDRY_RESOURCE=your-resource-name
export ANTHROPIC_FOUNDRY_API_KEY=your-key  # or use: az login
```

## [3.0.0] - 2026-01-31

### Changed - BREAKING

- **MCP servers replace PowerShell scripts for agent invocation** - Validator, Critic, and Worker-Heavy are now invoked via MCP servers instead of REST scripts
  - `mcp__validator-claude__Task` for validation
  - `mcp__critic-claude__Task` for quality gate
  - `mcp__worker-claude-heavy__Task` for complex tasks
  - Worker-Lite remains REST-based (local model, stateless queries)

### Added

- **MCP Agent Setup Guide** - New `docs/mcp-agent-setup.md` explains architecture and setup commands
- **Independent verification** - MCP servers have tool access to verify claims (read files, run tests) - no more "blind" validation

### Why This Change

Per the analysis in `docs/agent-communication-methods.md`:
- REST-based validation is "confidence theater" - Validator only sees what Orchestrator tells it
- MCP-based validation is "independent verification" - Validator can read files and check claims itself
- Example: Orchestrator says "small change to utils.js" but Validator can READ utils.js and see it's 2000 lines of critical code

### Migration

Run these commands in your project to set up MCP servers:
```bash
claude mcp add --scope local validator-claude -- claude mcp serve
claude mcp add --scope local critic-claude -- claude mcp serve
claude mcp add --scope local worker-claude-heavy -- claude mcp serve
```
Then restart Claude Code.

## [2.7.3] - 2026-01-31

### Changed

- **WOI-SECTION.md includes agent invocation instructions** - Existing installations now get "How to Invoke External Agents" section on sync, with clear Bash + PowerShell examples and when-to-validate guidance

## [2.7.2] - 2026-01-31

### Changed

- **CLAUDE.md template clarifies agent invocation mechanism** - Added explicit "How to Invoke External Agents" section making it unmistakably clear that Bash + PowerShell is the ONLY way to invoke Validator, Critic, and Worker-Lite
- **CLAUDE.md template clarifies when validation is required** - Added table distinguishing autonomous decisions (need validation) from user interactions (don't need validation)
- **Agent Reference section updated to show Bash commands** - All examples now show `powershell -File` invocation via Bash tool
- **interview-validator.ps1 uses v2 config format** - Now uses `resolve-role.ps1` instead of hardcoded legacy environment variables

### Fixed

- **Addressed confusion about validation scope** - Claude was trying to validate questions TO the user; clarified that validation is only for autonomous DECISIONS

## [2.7.1] - 2026-01-31

### Fixed

- **Removed redundant hashtable output from all scripts** - `check-orchestration-health.ps1`, `sync.ps1`, `setup.ps1`, and `validate.ps1` no longer output raw hashtables at the end; visual output is already rendered via Write-Host

## [2.7.0] - 2026-01-31

### Added

- **Capability-aware prompting for Critic** - Models now have a `capability` level (high/medium/low) that determines prompting strategy:
  - `high` - Full skeptical PM persona, open-ended questions, complex JSON responses (Claude, GPT-4)
  - `medium` - Structured questions, simpler JSON format (GPT-3.5, Mistral-7B)
  - `low` - Predefined yes/no checklist, one question at a time, minimal parsing (small local models)

- **Predefined checklists for low-capability models** - Workflow-specific question sets (general, feature, bugfix, finish) that don't require the model to generate questions

- **Per-question evaluation for low-capability models** - Instead of asking for complex JSON, evaluates each answer with a simple "YES or NO" question

### Fixed

- **Fixed hashtable stringification in low-capability evaluation** - Changed `return @{...}` to `return [PSCustomObject]@{...}` in `Evaluate-Answers-Low` to prevent "System.Collections.Hashtable" string conversion error

### Changed

- **connections.json template updated to v2.1.0** - Added `capability` field to all connections:
  - ai1-ai3: `"capability": "high"` (cloud providers)
  - ai4: `"capability": "low"` (local LLM default)
  - ai5-ai10: `"capability": "medium"` (unconfigured slots)
  - native: `"capability": "high"` (Claude Code)

- **resolve-role.ps1 now passes capability** - Scripts can access `$config.capability` to adapt behavior

- **bias-control.ps1 returns capability in results** - All responses now include `CriticCapability` field

- **Fixed type names for consistency** - Changed `azure_ai_foundry_anthropic` to `anthropic`, `azure_openai` to `azure-openai`, `openai_compatible` to `openai-compatible`

## [2.6.4] - 2026-01-31

### Changed

- **Scripts now use v2 config format** - `validate-autonomy.ps1` and `bias-control.ps1` now use `resolve-role.ps1` to read from `connections.json` + `roles.json` instead of hardcoded legacy environment variables
  - Supports multiple API types: `anthropic`, `azure-openai`, `openai-compatible`
  - Clear error messages with `STOP:` prefix when credentials are missing
  - Returns `ConfigError: true` flag for programmatic detection

- **CLAUDE.md template adds STOP behavior** - New "Infrastructure Errors" section with mandatory stop behavior:
  - When scripts return config errors, Claude must STOP and tell the user
  - Explicitly forbids working around missing infrastructure
  - Explicitly forbids roleplaying Validator/Critic with Task tool
  - Explains why independent validation matters

### Fixed

- **Validator/Critic scripts were hardcoded to legacy env vars** - Now properly read from v2 config files

## [2.6.3] - 2026-01-31

### Changed

- **CLAUDE.md template now wires up multi-agent orchestration** - Complete rewrite of `templates/CLAUDE.md.base.template`:
  - Establishes Claude as "Orchestrator Claude" with team identity
  - Defines when and how to invoke each agent (Validator, Critic, Workers)
  - Includes task routing decision tree
  - Documents 6-phase task execution workflow
  - Adds mandatory validation checkpoints (V1-V5)
  - Includes agent command reference (PowerShell invocations)
  - Quick reference card for thresholds and circuit breakers
  - **This makes multi-agent orchestration actually work when WOF is installed**

## [2.6.2] - 2026-01-31

### Changed

- **Setup now copies philosophy and workflows** - WOI installations now include:
  - `.ai/philosophy/` - Core principles (test-driven improvement)
  - `.ai/workflows/` - Process definitions (task execution workflow)
  - New users get full reference documentation locally

- **Updated sync-manifest.json** - Philosophy files now sync with customization protection

- **Updated README.md** - Project structure shows new agent, philosophy, and workflow files

## [2.6.1] - 2026-01-31

### Added

- **Architecture Overview** - `docs/architecture-overview.md`
  - Complete visual guide to WOF structure
  - Multi-agent system diagrams
  - Communication methods summary
  - Workflow visualization
  - AI connections reference
  - Summary "WOF in one picture" diagram

## [2.6.0] - 2026-01-31

### Added

- **Test-Driven Improvement Philosophy** - `core/philosophy/test-driven-improvement.md`
  - Three Laws: No plan without test strategy, no commit without tests, no closure without repeatable validation
  - Pre-commit test protocol (build, test, coverage)
  - Worker completion criteria (tests required)
  - Objective validation requirements

- **Orchestrator Claude role definition** - `core/agents/orchestrator-claude.md`
  - Coordination responsibilities
  - Testing consultation with Validator
  - Worker delegation standards (include test requirements)
  - Task completion protocol

### Changed

- **Validator Claude** - Added testing enforcement responsibilities
  - Must enforce Three Laws at every checkpoint
  - Testing questions added to all validations
  - Task completion enforcement (keep workers busy until tests pass)

- **Critic Claude** - Added testing verification protocol
  - Must run full test suite (not trust claims)
  - Response format includes test verification details
  - Hard requirements for test coverage

- **Task Execution Workflow** - Integrated test-driven requirements
  - All validation checkpoints updated with testing questions
  - V4 (Plan) requires testing strategy
  - V8 (Commit) requires all tests pass
  - V10 (Closure) requires repeatable validation

## [2.5.2] - 2026-01-31

### Added

- **Task Execution Workflow** - `core/workflows/task-execution-workflow.md`
  - 6-phase workflow: Intake, Planning, Implementation, Quality Gate, Commit, Completion
  - 6 validation checkpoints (reduced from initial 10 after Validator review)
  - Risk-tiered validation: auto-approve, batch, and individual tiers
  - Pre-flight snapshot checkpoint for rollback readiness
  - Anomaly detection replacing per-step validation
  - Explicit human escalation triggers (auto-escalate at <0.50 confidence)
  - Progressive autonomy levels: supervised, guided, autonomous
  - Validator-reviewed and approved (score: 0.65 → 0.85 after revisions)

## [2.5.1] - 2026-01-31

### Added

- **Validator Claude role definition** - `core/agents/validator-claude.md`
  - 17 verification questions for validating Orchestrator decisions
  - Structured JSON response format with confidence scoring
  - Examples for approve, escalate, and approve-with-concerns scenarios
  - Anti-patterns to avoid (rubber stamping, obstruction, false precision)

- **Critic Claude role definition** - `core/agents/critic-claude.md`
  - 26 verification questions for critiquing Worker output
  - Structured JSON response format with viability scoring
  - PASS/FAIL/REMEDIATE verdict framework
  - Fix Now vs. Work Item decision framework
  - Examples for pass, fail, and remediate scenarios

## [2.5.0] - 2026-01-31

### Added

- **Agent communication methods documentation** - Comprehensive guide at `docs/agent-communication-methods.md`
  - Documents 8 communication methods: PowerShell REST, MCP Server, SSH Remote, Task Tool, Message Queue, File-Based, WebSockets, Shared Database
  - Context passing capabilities matrix for each method
  - Worker delegation strategy (Worker Claude Heavy vs Lite)
  - Validator and Critic communication strategy

- **Validator interview script** - `core/scripts/interview-validator.ps1` for demonstrating multi-agent communication

### Changed

- **Agent naming convention** - More descriptive names for clarity:
  - Primary → **Orchestrator Claude**
  - secondary-claude → **Worker Claude Heavy** (`worker-claude-heavy`)
  - tertiary-claude-lite → **Worker Claude Lite**
  - Validator → **Validator Claude** (`validator-claude`)
  - Critic → **Critic Claude** (`critic-claude`)

- **Validator method upgraded to MCP** - Changed from REST to MCP Server
  - Enables independent verification of Orchestrator's claims
  - Can read files and check git history to verify decisions
  - Prevents "blind validation" where Validator only sees what Orchestrator chooses to share

- **Critic method upgraded to MCP** - Changed from REST to MCP Server
  - Enables independent verification of Worker output
  - Can run tests, check coverage, run linters
  - Prevents "rubber stamp" quality gates

## [2.4.9] - 2026-01-28

### Changed

- **ADO subagent relay pattern** - Subagents cannot access MCP tools, so changed approach:
  - Primary now calls `mcp__azure-devops__*` tools directly
  - ADO subagent is now a **formatter** only - receives raw JSON, returns human-readable summary
  - Switched back to Haiku (formatting doesn't need Sonnet's capabilities)
  - Removed false claims about subagent having MCP tool access

## [2.4.8] - 2026-01-28

### Changed

- **Switch ADO subagent from Haiku to Sonnet** - Haiku was unreliably calling MCP tools and hallucinating data
  - Updated `ado.md` template: `model: haiku` → `model: sonnet`
  - Updated architecture diagrams and agent tables in WOI-SECTION.md
  - More reliable tool execution at the cost of slightly higher latency/cost

## [2.4.7] - 2026-01-28

### Changed

- **Stronger ADO routing reminder** - Added explicit warning to NEVER call `mcp__azure-devops__*` tools directly
  - Primary must ALWAYS route ADO operations through the `ado` subagent via Task tool
  - Applies to all operations: list, get, create, update work items, PRs, pipelines, etc.

## [2.4.6] - 2026-01-28

### Fixed

- **Eliminate duplicate subagent output (#2967)** - Primary no longer re-echoes formatted subagent responses
  - Added "Handling Subagent Responses" guidance to WOI-SECTION.md template
  - Instructs Primary to acknowledge completion without duplicating tables/summaries

- **Prevent ADO subagent hallucination (#2967)** - Subagent now reports failures instead of fabricating data
  - Added rule #6 to ado.md: "NEVER fabricate data"
  - If MCP tool calls fail, subagent must report error clearly

## [2.4.5] - 2026-01-28

### Added

- **ADO Subagent Routing Instructions (#2966)** - Templates now instruct Claude to use ADO subagent
  - Added "Specialized Agents" section to WOI-SECTION.md template
  - Updated architecture diagram to show ADO subagent alongside Worker system
  - Added ADO subagent to component table
  - Added ADO operations to routing-rules.md task type mapping
  - Added ADO keywords to keyword-based routing section
  - Claude Code now knows to route Azure DevOps operations through the `ado` subagent

## [2.4.4] - 2026-01-28

### Added

- **ADO Subagent (#2956)** - Claude Code subagent for Azure DevOps operations
  - New `.claude/agents/ado.md` template - isolates verbose ADO JSON in subagent context
  - Returns concise, human-readable summaries instead of raw JSON
  - Uses Haiku model for cost-efficient ADO queries
  - Updated `setup.ps1` and `sync.ps1` to handle `.claude/agents/` directory
  - Updated `sync-manifest.json` with `.claude/agents/*.md` pattern

## [2.4.3] - 2026-01-28

### Fixed

- **Platform-specific MCP config** - Windows requires `cmd /c` wrapper to execute npx in MCP server config
  - Updated `/wof configure-ado` docs to show both Windows and Linux/macOS formats
  - Fixes Claude Code `/doctor` warning about npx execution on Windows

## [2.4.2] - 2026-01-28

### Added

- **Line Ending Normalization (#2954)** - Added `.gitattributes` for consistent LF line endings
  - Prevents "LF will be replaced by CRLF" warnings
  - Auto-normalizes all text files to LF in the repository
  - Keeps Windows batch files as CRLF (if any are added)
  - Template included for new WOI installations
  - `setup.ps1` and `sync.ps1` now install/sync `.gitattributes`

- **Improved ADO Tool Behavior (#2955)** - Enhanced Azure DevOps work item handling
  - Added `tags` config to ado.json for blocked status and phase tracking (Analysis, Design, Implementation, Validation, QA)
  - Added `behavior` config with `setActiveOnStart` and `skipBlockedItems` options
  - Added CRITICAL instruction in SKILL.md to always apply ado.json filters when querying work items
  - Documented tag conventions for work item phase tracking and blocked status

## [2.4.1] - 2026-01-28

### Added

- **Interactive /wof Menu (#2963)** - `/wof` with no args now presents an interactive wizard
  - Options: Check status, Update WOF, Finish work, Configure, Show help
  - Configure option leads to sub-menu for AI/ADO/finish configuration
  - Improves discoverability of WOF commands

## [2.4.0] - 2026-01-28

### Added

- **Finish Workflow Skill (#2959)** - New `/wof finish` command to complete work
  - Automates: update work item, bump version, update changelog, commit, push
  - Configurable via `/wof configure finish`
  - New config file: `.ai/config/finish.json`
  - Supports `--work-item <id>` flag for explicit work item selection

## [2.3.9] - 2026-01-28

### Changed

- **Slimmed Memory Templates (#2958)** - Reduced footprint of fresh WOI installations
  - `architecture.md.template`: 126 → 44 lines (-65%) - removed WOF-specific content already in WOI-SECTION
  - `conventions.md.template`: Removed "(WOF)" from header - now project-agnostic
  - Total memory template reduction: 266 → 182 lines (-31%)

## [2.3.8] - 2026-01-28

### Fixed

- **Update Mechanism (#2961)** - Fixed `/wof update` to work correctly with latest changes
  - Updated `WOI-SECTION.md` template to reference v2 config files (connections.json, roles.json) instead of v1 (providers.yaml)
  - Removed obsolete `Workflows` reference from Quick Reference table
  - Added missing `/wof configure` and `/wof configure-ado` commands to WOI Commands table
  - Added ADO template files to `template_only` in sync-manifest.json to prevent orphan deprecation
    - `config/ado.json`, `scripts/ado-utils.ps1`, `scripts/scan-workitems.ps1`

## [2.3.7] - 2026-01-28

### Fixed

- **ADO Browser Popup (#2957)** - Fixed `/wof configure-ado` to use PAT authentication without browser popup
  - Updated `templates/config/ado.json.template` to use `@tiberriver256/mcp-server-azure-devops`
  - Updated `templates/dot-claude/skills/wof/SKILL.md` with PAT-based MCP config
  - PAT is now the recommended auth method (silent, no browser interaction)

## [2.3.6] - 2026-01-28

### Changed

- **CLAUDE.md Refactored** - Split into base framework docs + injectable WOI section
  - Base CLAUDE.md now contains only WOF framework documentation
  - WOI-SECTION injected with markers on setup, removed cleanly on remove
  - Consistent with sync.ps1 and remove.ps1 marker-based approach

- **Renamed** - `remove-framework.ps1` → `remove.ps1` for consistency with `setup.ps1`

### Added

- **Version Bumping Guideline** - Added to CLAUDE.md development guidelines
  - Reminder to bump VERSION and update CHANGELOG before pushing to main

## [2.3.5] - 2026-01-27

### Fixed

- **Credential Preservation** - `setup.ps1 -Force` no longer overwrites user data files
  - Protected files: `credentials.local.json`, `credentials.local.ps1`, `connections.json`, `roles.json`
  - These files are now preserved even when `-Force` flag is used
  - Shows "Preserved: config/... (user data)" message in green

## [2.3.4] - 2026-01-27

### Changed

- **README.md** - Stronger AI installation instructions
  - Added "STOP - Do NOT clone directly!" warning
  - Emphasizes fetching AI-SETUP.md first via WebFetch
  - Explains why: proper escaping and `-Cleanup` flag

## [2.3.3] - 2026-01-27

### Changed

- **README.md** - Updated Environment Variables section
  - Removed hardcoded role assumptions from credential descriptions
  - Added missing `AI4_API_KEY` variable
  - Simplified Requirements section
  - Added reference to `roles.json` for role mapping

## [2.3.2] - 2026-01-27

### Added

- **Restart Reminder** - Setup now prompts user to restart Claude Code after installation
  - Added prominent reminder in `setup.ps1` completion message
  - Updated AI-SETUP.md POST_INSTALLATION section with restart step
  - Required to load new `/wof` skills and commands

## [2.3.1] - 2026-01-27

### Changed

- **AI-SETUP.md** - Use `$env:TEMP` with single quotes for reliable escaping through Bash
- **README.md** - More action-oriented "AI Assistant" section with trigger phrases ("get this", "install this") to prompt immediate installation

## [2.3.0] - 2026-01-27

### Changed

- **Refactored `/wof configure` skill** - Now uses AskUserQuestion for interactive configuration instead of PowerShell Read-Host prompts
  - Step 1: Test current connections and show status
  - Step 2: Ask user what to do (add AI, map roles, or done)
  - Step 3: Gather input via AskUserQuestion and write config files directly
  - Step 4: Run health check to verify
  - This enables proper user interaction when running through Claude Code

### Added

- Skill now has access to Read, Write, Edit, and AskUserQuestion tools for configuration

## [2.2.4] - 2026-01-27

### Fixed

- **AI-SETUP.md Claude Code Compatibility** - Use single quotes around PowerShell commands to prevent `$env:TEMP` escaping issues when running through Bash

## [2.2.3] - 2026-01-27

### Fixed

- **Preserve v2 Config on Remove** - `credentials.local.json`, `connections.json`, and `roles.json` now preserved when running remove.ps1
- **Skill Path Fix** - Changed backslash paths to forward slashes in `/wof` skill for cross-platform compatibility

## [2.2.2] - 2026-01-27

### Changed

- **Generic Provider Names** - Removed all hardcoded provider references
  - Replaced "Azure Opus", "Azure Sonnet", "Codex Mini", "local DeepSeek"
  - Now uses generic role names: Worker-Heavy, Worker-Lite, Validator, Critic
  - Connections are fully configurable via `roles.json`

## [2.2.1] - 2026-01-27

### Added

- **Setup Cleanup Option** - New `-Cleanup` switch for `setup.ps1`
  - Automatically removes WOF source directory after successful installation
  - Auto-deletes temp directories without prompting
  - Prompts for confirmation if source is not in a temp location
  - Skips cleanup in inception mode (when source and target are the same)

## [2.2.0] - 2026-01-27

### Added

- **URL Pattern Auto-Detection** - Connection type is now auto-detected from endpoint URL
  - `*.services.ai.azure.com/anthropic` → `azure_ai_foundry_anthropic`
  - `*.openai.azure.com` or `*.cognitiveservices.azure.com` → `azure_openai`
  - All other URLs → `openai_compatible`
  - Config type takes precedence if specified, auto-detect used as fallback

### Changed

- **Configure Wizard Flow** - Now asks for endpoint URL first, then suggests detected type
  - User can press Enter to accept suggestion or override with manual selection
- **Azure AI Foundry Anthropic Testing** - Fixed health check and wizard tests
  - Uses Bearer token authentication (not api-key header)
  - Tests via POST to `/v1/messages` endpoint (not GET /models)

## [2.1.0] - 2026-01-27

### Removed

- **Friend Role** - Removed the Friend (GPT-4o Rules Guardian) role from the framework
  - Deleted `friend-watchdog.ps1` script
  - Removed friend from role lists in all scripts and templates
  - Updated architecture diagrams to reflect simplified 4-role architecture
  - AI2 connection slot remains available for other purposes
  - The Validator role continues to provide decision validation

### Changed

- **Simplified Architecture** - Now uses 4 roles instead of 5:
  - Primary (Orchestrator)
  - Validator (Decision validation >0.7 confidence)
  - Worker-Heavy / Worker-Lite (Task execution)
  - Critic (Quality gate ≥80%)

## [2.0.0] - 2026-01-27

### Added

- **Configuration Wizard** - Interactive AI connection setup via `/wof configure`
  - Add/manage up to 10 AI connections (AI1-AI10)
  - Real-time connection testing with latency reporting
  - Role mapping wizard (worker-heavy, worker-lite, validator, critic)
  - Support for 3 connection types: `azure_ai_foundry_anthropic`, `azure_openai`, `openai_compatible`
  - `--test-only` flag to only test existing connections
  - `--quick` flag to skip confirmations

### Changed

- **Unified Connection Slots** - All AI connections now use AI1-AI10 naming
  - Removed `LOCAL1`/`local1` special category
  - Any slot can be any connection type (cloud or local)
  - Worker-Lite now defaults to AI4 instead of LOCAL1
- **Dynamic Health Checks** - `check-orchestration-health.ps1` now reads from config files
  - Loads connections from `connections.json` and `roles.json` dynamically
  - Shows actual connection IDs in status diagram
  - Added `[AUT]` status indicator for authentication errors
- **Updated Templates**
  - `connections.json.template` - AI1-AI10 structure with empty slots for AI4-AI10
  - `credentials.local.json.template` - AI1-AI10 credential placeholders
  - `roles.json.template` - worker-lite defaults to ai4
  - `architecture.md.template` - Updated endpoint references to use generic IDs

### Migration

When upgrading from v1.x:
- `LOCAL1_ENDPOINT` → `AI4_ENDPOINT` (if using local models)
- Run `/wof configure` to reconfigure connections
- Or manually update `credentials.local.json` and `roles.json`

## [1.5.1] - 2026-01-27

### Added

- **Breaking Change Guard** - `update-framework.ps1` now blocks updates with major version bumps
  - Detects when remote version has a higher major version than local
  - Provides clear instructions: remove WOF, restart session, fresh setup
  - Exit code 2 indicates breaking change blocked
  - Protects users from incompatible upgrades

## [1.2.7] - 2026-01-27

### Added

- **WOI Section in CLAUDE.md** - New managed section for WOI configuration
  - `sync.ps1` injects/updates `<!-- WOI-SECTION-START -->` ... `<!-- WOI-SECTION-END -->` markers
  - `remove.ps1` removes only the WOI section, preserving project-specific content
  - Includes version, mode, quick reference, and architecture diagram
  - Template: `templates/WOI-SECTION.md`

### Changed

- **Remove command** now preserves CLAUDE.md and only removes the WOI section
  - Legacy CLAUDE.md files without markers are still fully removed

## [1.2.6] - 2026-01-27

### Fixed

- **Remove command confirmation** - Documented that `-Force` flag is required when running `/wof remove` via Claude Code (interactive `Read-Host` doesn't work in non-interactive contexts)

## [1.2.5] - 2026-01-27

### Added

- **WOF/WOI Terminology** - Formalized naming distinction
  - WOF = Workload Orchestration **Framework** (source repo/product)
  - WOI = Workload Orchestration **Instance** (local installation in a project)
- **Inception Mode** - WOF repo now uses LocalOnly WOI for self-orchestration
  - `.ai/` and `.claude/` are gitignored in framework repo
  - Allows using AI orchestration to develop WOF itself

## [1.2.4] - 2026-01-27

### Added

- **`/wof` Slash Command** - Single entry point for all WOF operations
  - `/wof update` - Update framework to latest version
  - `/wof update --dry-run` - Preview update changes
  - `/wof status` - Check orchestration health
  - `/wof route <task>` - Classify task routing (Worker-Lite vs Worker-Heavy)
  - `/wof help` - Show available commands
- Skills are installed to `.claude/skills/wof/SKILL.md`
- Skills are synced with customization preservation (add `# CUSTOMIZED` to preserve)

## [1.2.3] - 2026-01-27

### Added

- **Installed Files Manifest** - Track installed files to detect orphans during sync
  - New `.ai/.installed-files.json` tracks all framework files installed
  - `sync.ps1` now detects files removed from the framework
  - Orphaned files are moved to `.ai/.deprecated/` (not deleted)
  - Customized orphaned files are preserved with a warning
  - Enables safe framework updates even when files are renamed or removed

### Usage

```powershell
# Sync will automatically detect and handle orphaned files
.\sync.ps1 -TargetPath "C:\code\MyProject"

# Preview orphan handling without making changes
.\sync.ps1 -TargetPath "C:\code\MyProject" -DryRun
```

## [1.2.2] - 2026-01-27

### Changed

- **WOF Branding** - Added "WOF" abbreviation across all framework files
  - First mention in each file uses "Workload Orchestration Framework (WOF)"
  - Subsequent mentions use "WOF" for brevity
  - Updated banners in setup.ps1, sync.ps1, validate.ps1, update-framework.ps1
  - Updated templates, config files, and documentation

## [1.2.0] - 2026-01-27

### Added

- **update-framework.ps1** - New self-update script for target projects
  - Distributed to projects via `core/scripts/` during setup
  - Enables any project to pull framework updates with a single command
  - Supports `-DryRun` to preview changes before applying
  - Supports `-Tag` to update to a specific version
  - Supports `-RepoUrl` to use forks or mirrors
  - Respects customization markers (`# CUSTOMIZED`)

### Usage

```powershell
# From any project with the framework installed:
.\.ai\scripts\update-framework.ps1

# Preview changes first:
.\.ai\scripts\update-framework.ps1 -DryRun

# Update to specific version:
.\.ai\scripts\update-framework.ps1 -Tag v1.2.0
```

## [1.1.1] - 2026-01-27

### Added

- **CLAUDE.md** - Added guidance file for Claude Code to understand the framework repository

## [1.1.0] - 2026-01-27

### Added

- **Installation Modes** - Two ways to install the framework:
  - `SourceControlled` (default) - Framework committed to git, shared with team
  - `LocalOnly` - Framework completely gitignored, personal use only

- **Mode Parameter** in `setup.ps1`:
  ```powershell
  # Team collaboration (default)
  .\setup.ps1 -TargetPath "C:\code\MyProject" -SolutionName "MyProject"

  # Personal use, invisible to team
  .\setup.ps1 -TargetPath "C:\code\MyProject" -SolutionName "MyProject" -Mode LocalOnly
  ```

- **Mode tracking** - `.ai/.mode` file records installation mode

### Changed

- Updated README with Quick Start showing both installation options
- Improved `.gitignore` handling to ensure proper newlines

### Fixed

- Fixed sync-manifest.json patterns (removed duplicate `core/` prefix)
- Fixed `.gitignore` concatenation when file lacks trailing newline

## [1.0.0] - 2026-01-27

### Added

- **Multi-Agent Architecture**
  - Primary (Opus 4.5) as orchestrator - does not code, only delegates
  - Worker-Heavy (Azure Opus 4.5) for T2+ complex tasks
  - Worker-Lite (Local DeepSeek) for T1 lightweight tasks
  - Validator (Azure Sonnet 4.5) for decision validation (>0.7 confidence)
  - Friend (Azure GPT-4o) as rules guardian
  - Critic (Azure Codex Mini) as quality gate (>=80% viability)

- **Core Scripts**
  - `get-worker-routing.ps1` - Task complexity analysis and worker routing
  - `validate-autonomy.ps1` - Decision validation with Azure Sonnet
  - `bias-control.ps1` - Skeptical Q&A quality gate with Codex Mini
  - `friend-watchdog.ps1` - CLAUDE.md compliance checking with GPT-4o
  - `phase-gate.ps1` - 9-phase workflow enforcement
  - `check-orchestration-health.ps1` - AI component status dashboard
  - `delegate-to-local-worker.ps1` - Worker-Lite delegation
  - `approve-command.ps1` - Bash command risk classification
  - `approve-write.ps1` - File write validation
  - `log-worker-operation.ps1` - Worker operation audit logging

- **Configuration**
  - `routing-rules.md` - Comprehensive T1/T2+ routing rules
  - `risk-rules.yaml` - Command risk classification (low/medium/high)
  - `providers.yaml.template` - AI provider configuration
  - `models.yaml.template` - Model tier definitions
  - `credentials.local.ps1.template` - Credential template

- **Templates**
  - `CLAUDE.md.template` - Main orchestration document
  - `settings.json.template` - Claude Code hook configuration
  - `architecture.md.template` - Architecture documentation
  - `conventions.md.template` - Coding conventions
  - `current-sprint.md.template` - Sprint tracking

- **Setup & Sync**
  - `setup.ps1` - Initial framework installation
  - `sync.ps1` - Framework update with customization preservation
  - `validate.ps1` - Configuration validation
  - `sync-manifest.json` - Sync behavior rules

- **Extensions**
  - `extensions/azure-devops/` - Optional ADO integration
    - `ado-utils.ps1.template` - Work item management

### Notes

- Extracted from IntegrationHub solution
- Designed for reuse across multiple projects
- Template placeholders use `{{PLACEHOLDER}}` syntax
- Files marked with `# CUSTOMIZED` are preserved during sync

[2.1.0]: https://github.com/ndrezza/wof?version=GTv2.1.0
[2.0.0]: https://github.com/ndrezza/wof?version=GTv2.0.0
[1.5.1]: https://github.com/ndrezza/wof?version=GTv1.5.1
[1.2.7]: https://github.com/ndrezza/wof?version=GTv1.2.7
[1.2.6]: https://github.com/ndrezza/wof?version=GTv1.2.6
[1.2.5]: https://github.com/ndrezza/wof?version=GTv1.2.5
[1.2.4]: https://github.com/ndrezza/wof?version=GTv1.2.4
[1.2.3]: https://github.com/ndrezza/wof?version=GTv1.2.3
[1.2.2]: https://github.com/ndrezza/wof?version=GTv1.2.2
[1.2.0]: https://github.com/ndrezza/wof?version=GTv1.2.0
[1.1.1]: https://github.com/ndrezza/wof?version=GTv1.1.1
[1.1.0]: https://github.com/ndrezza/wof?version=GTv1.1.0
[1.0.0]: https://github.com/ndrezza/wof?version=GTv1.0.0
