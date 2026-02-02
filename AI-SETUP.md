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

**Step-by-step (use `powershell` not `pwsh` for consistent escaping):**

```bash
# Step 1: Clone to temp
powershell -Command 'git clone --depth 1 https://github.com/ndrezza/wof.git "$env:TEMP\wof-install"'

# Step 2: Run setup
powershell -ExecutionPolicy Bypass -Command '& "$env:TEMP\wof-install\setup.ps1" -TargetPath "{TARGET}" -Force -Cleanup'
```

**Config files after install:**
```
.ai/config/credentials.local.json  - API keys (edit this)
.ai/config/connections.json        - AI connection definitions
.ai/config/roles.json              - Role mappings
```

**Verify:** `powershell -File "./.ai/scripts/check-orchestration-health.ps1"`

## PREREQUISITES

Before installation, verify:

| Requirement | Check Command | Expected |
|-------------|---------------|----------|
| PowerShell 5.1+ | `$PSVersionTable.PSVersion` | Major >= 5 |
| Git installed | `git --version` | Any version |
| Target is git repo | `git rev-parse --git-dir` in target | `.git` or path |
| Write access | N/A | Can create files in target |

## INSTALLATION_STEPS

### Step 1: CLONE_FRAMEWORK

Clone WOF to temp folder. **Use single quotes** around the PowerShell command to preserve `$env:TEMP`:

```bash
powershell -Command 'Remove-Item -Recurse -Force "$env:TEMP\wof-install" -ErrorAction SilentlyContinue; git clone --depth 1 https://github.com/ndrezza/wof.git "$env:TEMP\wof-install"'
```

**Note:** Use `powershell` (Windows PowerShell), not `pwsh` (PowerShell Core) - escaping behavior differs.

### Step 2: CHECK_EXISTING (Optional)

Check if WOF is already installed:

```bash
powershell -Command 'Test-Path "{TARGET}/.ai"'
```

If true, inform user: "WOF is already installed. Running setup with -Force will update it while preserving your credentials and memory files."

### Step 3: RUN_SETUP

```bash
powershell -ExecutionPolicy Bypass -Command '& "$env:TEMP\wof-install\setup.ps1" -TargetPath "{TARGET}" -Force -Cleanup'
```

Replace `{TARGET}` with the actual target path (e.g., `C:/code/MyProject`).

**Parameters:**
- `-TargetPath`: Absolute path to target project root
- `-Force`: Overwrite existing files (preserves credentials, connections, roles, memory)
- `-Cleanup`: Automatically removes the temp clone after successful setup

### Step 4: CONFIGURE_CREDENTIALS

See [CREDENTIAL_INTERVIEW](#credential_interview) section below.

After collecting credentials, write them to `.ai/config/credentials.local.json` in the target project.

### Step 5: SETUP_MCP

Register the role-specific MCP servers:

```bash
claude mcp add --scope local validator-claude -- claude mcp serve
claude mcp add --scope local critic-claude -- claude mcp serve
claude mcp add --scope local worker-claude-heavy -- claude mcp serve
```

**Note:** This step requires Claude Code CLI to be available.

#### Microsoft Foundry Configuration (Optional)

To route MCP servers through **Microsoft Foundry (Azure)** instead of direct Anthropic API, set these environment variables BEFORE starting Claude Code:

```bash
# Enable Microsoft Foundry integration
export CLAUDE_CODE_USE_FOUNDRY=1

# Azure resource name
export ANTHROPIC_FOUNDRY_RESOURCE=your-resource-name
# Or full base URL:
# export ANTHROPIC_FOUNDRY_BASE_URL=https://your-resource.services.ai.azure.com/anthropic

# Authentication (choose one):
# Option A: API Key
export ANTHROPIC_FOUNDRY_API_KEY=your-azure-api-key

# Option B: Microsoft Entra ID (Azure AD) - if no API key set
# az login
```

When these variables are set, both the main Claude Code instance AND all MCP servers (`validator-claude`, `critic-claude`, `worker-claude-heavy`) will connect through Microsoft Foundry.

**Benefits of Foundry:**
- Enterprise compliance (data stays in your Azure tenant)
- Unified billing through Azure
- Azure RBAC for access control

### Step 6: VERIFY

Run the health check to verify installation:

```bash
powershell -ExecutionPolicy Bypass -File "./.ai/scripts/check-orchestration-health.ps1"
```

**Expected output:** Status dashboard showing which components are configured.

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
  Recommended: Ollama (http://localhost:11434) - native Anthropic API support.
  Alternative: vLLM/llama.cpp with proxy (http://localhost:8082).
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
| MCP servers registered | `claude mcp list` | Shows `validator-claude`, `critic-claude`, `worker-claude-heavy` |

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

** RESTART CLAUDE CODE to load the new /wof skills and commands **

Next steps:
1. Restart Claude Code (exit and re-open, or start a new session)
2. Open Claude Code in your project: cd "{TARGET}" && claude
3. The AI orchestrator is now active - it will route tasks to appropriate workers
4. Use "Finish up #XXXX" to complete work items with proper workflow

Optional:
- Run /wof configure to set up AI connections interactively
- Run /wof status to see component status
```
