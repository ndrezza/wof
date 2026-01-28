# Changelog

All notable changes to the Workload Orchestration Framework (WOF) will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
