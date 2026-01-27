# Changelog

All notable changes to the Workload Orchestration Framework will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[1.1.0]: https://github.com/ndrezza/wof?version=GTv1.1.0
[1.0.0]: https://github.com/ndrezza/wof?version=GTv1.0.0
