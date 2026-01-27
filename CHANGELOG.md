# Changelog

All notable changes to the Workload Orchestration Framework (WOF) will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
  - `remove-framework.ps1` removes only the WOI section, preserving project-specific content
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
