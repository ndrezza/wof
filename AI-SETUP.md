# WOF AI Installation Protocol

<!-- AI-READABLE: Structured instructions for AI coding assistants -->
<!-- Version: 2.0 | Last Updated: 2026-01-27 -->

## METADATA

```yaml
name: Workload Orchestration Framework (WOF)
version: 2.0.0
repository: https://github.com/ndrezza/wof
setup_script: setup.ps1
config_format: v2 (JSON-based)
config_files:
  connections: .ai/config/connections.json
  roles: .ai/config/roles.json
  credentials: .ai/config/credentials.local.json
health_check: .ai/scripts/check-orchestration-health.ps1
```

## QUICK_REFERENCE

**One-liner for Claude Code (use single quotes to prevent $ escaping):**
```
powershell -NoProfile -ExecutionPolicy Bypass -Command '$p = Join-Path $env:TEMP "wof-install"; Remove-Item -Recurse -Force $p -ErrorAction SilentlyContinue; git clone https://github.com/ndrezza/wof.git $p; Set-Location $p; ./setup.ps1 -TargetPath "{TARGET}" -Force -Cleanup'
```

**Manual steps:**
```
Clone:    git clone https://github.com/ndrezza/wof.git $env:TEMP/wof-install
Setup:    ./setup.ps1 -TargetPath "{TARGET}" -Cleanup
Config:   .ai/config/credentials.local.json
Verify:   ./.ai/scripts/check-orchestration-health.ps1
```

## PREREQUISITES

Before installation, verify:

| Requirement | Check Command | Expected |
|-------------|---------------|----------|
| PowerShell 5.1+ | `$PSVersionTable.PSVersion` | Major >= 5 |
| Git installed | `git --version` | Any version |
| Target is git repo | `git rev-parse --git-dir` in target | `.git` or path |
| Write access | N/A | Can create files in target |

## INSTALLATION_STEPS

### Step 1: CLONE_AND_SETUP

**IMPORTANT for Claude Code:** Use single quotes around the PowerShell command to prevent `$` escaping:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -Command '$p = Join-Path $env:TEMP "wof-install"; Remove-Item -Recurse -Force $p -ErrorAction SilentlyContinue; git clone https://github.com/ndrezza/wof.git $p; Set-Location $p; ./setup.ps1 -TargetPath "{TARGET}" -Force -Cleanup'
```

Replace `{TARGET}` with the actual target path (e.g., `C:/code/MyProject`).

**What this does:**
1. Removes any previous temp clone
2. Clones WOF to `$env:TEMP\wof-install`
3. Runs setup with `-Force` (overwrites existing) and `-Cleanup` (removes temp clone after)

### Step 2: DETECT_EXISTING (Optional)

If you want to check first before overwriting:

```bash
powershell -Command 'Test-Path "{TARGET}/.ai"'
```

If true, ask user: "WOF is already installed. Update it? (Credentials and memory are preserved)"

**Parameters:**
- `TargetPath`: Absolute path to target project root
- `SolutionName`: (Optional) Defaults to directory name
- `Force`: Add if updating existing installation
- `Cleanup`: Remove WOF source directory after successful installation

### Step 4: CONFIGURE_CREDENTIALS

See [CREDENTIAL_INTERVIEW](#credential_interview) section below.

After collecting credentials, write them to `.ai/config/credentials.local.json` in the target project.

### Step 5: SETUP_MCP

Register the secondary-claude MCP server for Worker delegation:

```bash
claude mcp add --scope local secondary-claude -- claude mcp serve
```

**Note:** This step requires Claude Code CLI to be available.

### Step 6: VERIFY

Run the health check to verify installation:

```powershell
# From target project directory
.\.ai\scripts\check-orchestration-health.ps1
```

**Expected output:** Status dashboard showing which components are configured.

### Step 7: CLEANUP

**Note:** If you used `-Cleanup` in Step 3, this step is automatic.

```powershell
# Remove temporary clone (only needed if -Cleanup was not used)
Remove-Item -Recurse -Force "$env:TEMP\wof-install"
```

## CREDENTIAL_INTERVIEW

For each credential, interview the user. Only write values that are provided (skip placeholders for empty ones).

**Note:** WOF v2.0 uses generic connection IDs (AI1-AI10) instead of provider-specific names.
This allows role reassignment without changing credentials.

### AI Connection Credentials

WOF supports up to 10 AI connections (AI1-AI10). At minimum, one connection (AI1) is required.
After collecting credentials, use the configuration wizard or `roles.json` to map connections to roles.

#### AI1_ENDPOINT
```yaml
id: AI1_ENDPOINT
prompt: "What is your AI1 endpoint URL?"
required: true
format: "URL to your AI service"
help: |
  Enter the endpoint URL for your first AI connection.
sensitive: false
maps_to: "ai1 connection in connections.json"
```

#### AI1_API_KEY
```yaml
id: AI1_API_KEY
prompt: "What is your AI1 API key?"
required: true
format: "API key string"
help: |
  Enter the API key for AI1.
sensitive: true
depends_on: AI1_ENDPOINT
```

#### AI2_ENDPOINT (Optional)
```yaml
id: AI2_ENDPOINT
prompt: "What is your AI2 endpoint URL? (Press Enter to skip)"
required: false
format: "URL to your AI service"
help: |
  Enter the endpoint URL for your second AI connection.
sensitive: false
skip_message: "AI2 will remain unconfigured. You can add this later."
maps_to: "ai2 connection in connections.json"
```

#### AI2_API_KEY
```yaml
id: AI2_API_KEY
prompt: "What is your AI2 API key?"
required: false
format: "API key string"
help: "Enter the API key for AI2."
sensitive: true
depends_on: AI2_ENDPOINT
```

#### AI3_ENDPOINT (Optional)
```yaml
id: AI3_ENDPOINT
prompt: "What is your AI3 endpoint URL? (Press Enter to skip)"
required: false
format: "URL to your AI service"
help: |
  Enter the endpoint URL for your third AI connection.
sensitive: false
skip_message: "AI3 will remain unconfigured. You can add this later."
maps_to: "ai3 connection in connections.json"
```

#### AI3_API_KEY
```yaml
id: AI3_API_KEY
prompt: "What is your AI3 API key?"
required: false
format: "API key string"
help: "Enter the API key for AI3."
sensitive: true
depends_on: AI3_ENDPOINT
```

#### AI4_ENDPOINT (Optional)
```yaml
id: AI4_ENDPOINT
prompt: "What is your AI4 endpoint URL? (Press Enter to skip)"
required: false
format: "URL to your AI service"
help: |
  Enter the endpoint URL for your fourth AI connection.
  Can be local (vLLM, LM Studio, Ollama), network, or cloud.
sensitive: false
skip_message: "AI4 will remain unconfigured. You can add this later."
maps_to: "ai4 connection in connections.json"
```

## CREDENTIAL_FILE_FORMAT

After collecting credentials, generate `.ai/config/credentials.local.json`:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "version": "2.0.0",
  "description": "WOF Credentials - Auto-generated. This file is gitignored.",
  "credentials": {
    "AI1_ENDPOINT": "{AI1_ENDPOINT}",
    "AI1_API_KEY": "{AI1_API_KEY}",
    "AI2_ENDPOINT": "{AI2_ENDPOINT}",
    "AI2_API_KEY": "{AI2_API_KEY}",
    "AI3_ENDPOINT": "{AI3_ENDPOINT}",
    "AI3_API_KEY": "{AI3_API_KEY}",
    "AI4_ENDPOINT": "{AI4_ENDPOINT}"
  }
}
```

**Notes:**
- Only include keys for credentials the user provided
- Omit keys they skipped (don't include empty values)
- The file is automatically gitignored by setup.ps1
- Connection types are defined in `connections.json`, not here

## EXISTING_CONFIG_DETECTION

Before interviewing for credentials, check these locations for reusable values:

### Location 1: Target Project (v2 format)
```powershell
$existingCreds = "{TARGET}/.ai/config/credentials.local.json"
if (Test-Path $existingCreds) {
    # Parse JSON and extract existing values
    $creds = Get-Content $existingCreds | ConvertFrom-Json
    # Ask: "Found existing credentials. Reuse them?"
}
```

### Location 2: Target Project (legacy v1 format)
```powershell
$legacyCreds = "{TARGET}/.ai/config/credentials.local.ps1"
if (Test-Path $legacyCreds) {
    # Parse PS1 and extract existing values
    # Note: Will be auto-migrated to v2 format on sync
    # Ask: "Found legacy credentials. Migrate and reuse them?"
}
```

### Location 3: Environment Variables
```powershell
# Check for v2 format first
$hasAI1 = $env:AI1_ENDPOINT -and $env:AI1_API_KEY
# Fallback to legacy format
$hasLegacy = $env:AZURE_ANTHROPIC_ENDPOINT -and $env:AZURE_ANTHROPIC_API_KEY
if ($hasAI1 -or $hasLegacy) {
    # Ask: "Found credentials in environment. Use these?"
}
```

**Reuse prompt:**
> "I found existing credentials at {location}. Would you like to reuse them?
> - Yes: Use existing credentials (recommended if this is an update)
> - No: Enter new credentials"

## GIT_BEHAVIOR

WOI files are gitignored using **two managed sections** in `.gitignore`:

```gitignore
# <!-- WOI-FRAMEWORK-START - Managed by WOF, removed with framework -->
# WOF Framework Files (deleted when WOF is removed)
/.ai/scripts/approve-command.ps1
/.ai/agents/worker.md
/.ai/.framework-version
/.claude/settings.json
/CLAUDE.md
# <!-- WOI-FRAMEWORK-END -->

# <!-- WOI-USERDATA-START - Managed by WOF, preserved after removal -->
# WOI User Data (kept after WOF removal - contains secrets/customizations)
/.ai/config/credentials.local.json
/.ai/config/connections.json
/.ai/config/roles.json
/.ai/config/models.yaml
/.ai/memory/architecture.md
/.ai/state/
/.ai/logs/
# <!-- WOI-USERDATA-END -->
```

**Why two sections?**
- **FRAMEWORK**: Removed when WOF is uninstalled (scripts, agents, CLAUDE.md)
- **USERDATA**: Preserved after uninstall (credentials, memory stay gitignored)

This ensures `credentials.local.json` remains gitignored even after removing WOF.

**To share files with team:** Remove specific entries from either section, then commit those files

## VERIFICATION_CHECKLIST

After installation, verify these items:

| Check | Command | Expected Result |
|-------|---------|-----------------|
| Framework installed | `Test-Path "{TARGET}/.ai"` | `True` |
| CLAUDE.md exists | `Test-Path "{TARGET}/CLAUDE.md"` | `True` |
| Connections config | `Test-Path "{TARGET}/.ai/config/connections.json"` | `True` |
| Roles config | `Test-Path "{TARGET}/.ai/config/roles.json"` | `True` |
| Credentials file | `Test-Path "{TARGET}/.ai/config/credentials.local.json"` | `True` |
| Health check passes | `.\.ai\scripts\check-orchestration-health.ps1` | Status output |
| MCP server registered | `claude mcp list` | Shows `secondary-claude` |

## TROUBLESHOOTING

### Common Issues

#### "Permission denied" during clone
```
Cause: Git SSH keys not configured for GitHub
Fix: Use HTTPS clone or configure SSH keys
```

#### "Setup script not found"
```
Cause: Clone failed or path is wrong
Fix: Verify $env:TEMP\wof-install exists and contains setup.ps1
```

#### "TargetPath does not exist"
```
Cause: Invalid target path provided
Fix: Ensure target path exists and is accessible
```

#### "Azure endpoint validation failed"
```
Cause: Incorrect endpoint format or typo
Fix: Verify endpoint matches format: https://{name}.services.ai.azure.com/anthropic
```

#### "MCP server registration failed"
```
Cause: Claude Code CLI not installed or not in PATH
Fix: Install Claude Code CLI or add to PATH
```

### Health Check Failures

| Connection | Status Red | Fix |
|------------|------------|-----|
| AI1 | "NOT SET" | Add AI1_ENDPOINT and AI1_API_KEY in credentials.local.json |
| AI2 | "NOT SET" | Optional - add AI2_ENDPOINT and AI2_API_KEY |
| AI3 | "NOT SET" | Optional - add AI3_ENDPOINT and AI3_API_KEY |
| AI4 | "NOT SET" | Optional - add AI4_ENDPOINT (and AI4_API_KEY if required) |

> **Note:** AI slots are generic. Use `roles.json` to map connections to roles (Worker-Heavy, Worker-Lite, Validator, Critic).

## POST_INSTALLATION

After successful installation, inform the user:

```
WOF has been installed successfully!

Next steps:
1. Open Claude Code in your project: cd "{TARGET}" && claude
2. The AI orchestrator is now active - it will route tasks to appropriate workers
3. Use "Finish up #XXXX" to complete work items with proper workflow

Optional:
- Configure Worker-Lite (AI4) using local models, vLLMs, network deployments, or cloud providers
- Run .\.ai\scripts\check-orchestration-health.ps1 to see component status
```
