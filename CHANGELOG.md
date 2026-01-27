# Changelog

All notable changes to the Workload Orchestration Framework (WOF) will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[1.2.3]: https://github.com/ndrezza/wof?version=GTv1.2.3
[1.2.2]: https://github.com/ndrezza/wof?version=GTv1.2.2
[1.2.0]: https://github.com/ndrezza/wof?version=GTv1.2.0
[1.1.1]: https://github.com/ndrezza/wof?version=GTv1.1.1
[1.1.0]: https://github.com/ndrezza/wof?version=GTv1.1.0
[1.0.0]: https://github.com/ndrezza/wof?version=GTv1.0.0
