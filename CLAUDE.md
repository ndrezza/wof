# WOF - Workload Orchestration Framework

> Auto-loaded by Claude Code. This document describes the WOF framework itself.

## What is WOF?

**WOF** (Workload Orchestration Framework) is a framework for AI-assisted software development. It provides:

- Multi-agent orchestration (Primary, Worker, Validator, Critic)
- Task routing (T1 lightweight vs T2+ complex)
- Memory management (architecture, conventions, current-sprint)
- Azure DevOps integration
- Configurable AI connections and role mappings

When WOF is installed in a project, it creates a **WOI** (Workload Orchestration Instance) - a local installation with `.ai/` and `.claude/` directories.

## Terminology

| Term | Full Name | Description |
|------|-----------|-------------|
| **WOF** | Workload Orchestration **Framework** | This repository - the source code and product |
| **WOI** | Workload Orchestration **Instance** | A local installation of WOF in a target project |

## Repository Structure

```
wof/
├── core/                    # Framework core (agents, scripts, config)
├── templates/               # Templates copied to WOI installations
├── extensions/              # Optional extensions (Azure DevOps, etc.)
├── examples/                # Example projects
├── setup.ps1                # Installation script
├── sync.ps1                 # Framework sync/update script
├── validate.ps1             # Validation script
├── CLAUDE.md                # This file (framework docs)
├── README.md                # Project documentation
├── CHANGELOG.md             # Version history
└── VERSION                  # Current version
```

## This Repository

This repository contains **WOF source code only**. No WOI is installed here.

| Path | Purpose | Git Status |
|------|---------|------------|
| `core/` | Framework scripts and agents | Tracked |
| `templates/` | Templates for WOI installations | Tracked |
| `setup.ps1`, `sync.ps1` | Installation and sync scripts | Tracked |
| `CLAUDE.md`, `README.md` | Documentation | Tracked |
| `examples/` | Sample projects for testing WOI | Tracked |

**Why no WOI here?** Installing WOI in the WOF repo creates an "inception paradox"—the same files exist as both source (in `core/`) and instance (in `.ai/`). This causes confusion about which files to edit. To keep WOF development clean, test WOI in separate projects or in `examples/`.

## Development Guidelines

### Core Principles

These are not suggestions. They are requirements.

1. **Understand the assignment before starting work.** If requirements are unclear, ask. A 2-minute clarification costs less than a 2-hour redo. Do not assume—validate.

2. **Work must be verifiable.** If you cannot describe how to test that your work is correct, you do not yet understand the requirement. Define acceptance criteria before implementation.

3. **Multi-agent validation exists for a reason.** The Validator and Critic are not bureaucracy—they catch errors that self-review misses. Engage them honestly; do not game the process.

4. **Objective verification builds trust.** Your confidence is not evidence. Passing tests, meeting acceptance criteria, and surviving skeptical review—these build trust.

5. **Automated testing is non-negotiable for anything that will be maintained.** Every new feature needs tests that will catch regressions. Manual testing does not scale; agile projects die without automation.

### Critical Behavioral Rules

**DO, don't suggest:**
- NEVER say "you might want to run tests" - RUN the tests
- NEVER leave work half-done - COMPLETE the workflow
- ALWAYS run builds and report results
- ALWAYS finish what you start
- ASK before committing or pushing - user controls git operations

**No AI attribution:**
- NEVER add `Co-Authored-By: Claude...` to commits
- NEVER add "Generated with Claude Code" or similar to PRs
- Keep commits and PRs clean - no AI branding

### Pre-Work Checklist

Before ANY code changes:

```bash
# 1. Check branch status
git status

# 2. If on main, create feature branch
git checkout -b feature/[meaningful-name]

# 3. Never commit directly to main
```

**Zero tolerance for main branch modifications.**

### Version Bumping

Before committing and pushing to main, bump the version:

1. Update `VERSION` file (semantic versioning: MAJOR.MINOR.PATCH)
2. Add entry to `CHANGELOG.md` describing the changes

```powershell
# Example: bump patch version
$v = [version](Get-Content VERSION); "$($v.Major).$($v.Minor).$($v.Build + 1)" | Set-Content VERSION
```

### Quality Gates

Every deliverable must pass:

1. **Build** - Solution compiles without errors
2. **Tests** - Relevant tests pass
3. **Security** - No exposed secrets
4. **Documentation** - Memory bank updated (if WOI installed)
5. **Git** - Proper branch, proper commit format

### Error Recovery

If something fails:

1. **Build fails** → Fix errors, don't proceed until green
2. **Tests fail** → Investigate, fix, re-run
3. **Security issue** → Block commit, report to user
4. **Unclear requirement** → Ask user, don't assume

## Testing WOI

To test WOI installations, use a separate project or the `examples/` directory:

```powershell
# Create a test project
mkdir C:\code\test-project
.\setup.ps1 -TargetPath "C:\code\test-project" -SolutionName "TestProject"
```

**Not recommended:** Installing WOI in this repo (`.\setup.ps1 -TargetPath .`) creates duplicate files and confusion. If you do this anyway, remove it with `.\.ai\scripts\remove.ps1`.
