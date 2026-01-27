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

```
Clone:    git clone https://github.com/ndrezza/wof.git "$env:TEMP\wof-install"
Setup:    .\setup.ps1 -TargetPath "{TARGET}"
Config:   .ai/config/credentials.local.json
Verify:   .\.ai\scripts\check-orchestration-health.ps1
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

### Step 1: CLONE_FRAMEWORK

```powershell
# Clone WOF to a temporary location
git clone https://github.com/ndrezza/wof.git "$env:TEMP\wof-install"
```

### Step 2: DETECT_EXISTING

Check if WOF is already installed in the target project:

```powershell
# Check for existing installation
$aiFolder = Join-Path "{TARGET}" ".ai"
$existingInstall = Test-Path $aiFolder
```

**If existing installation found:**
- Ask user: "WOF is already installed. Do you want to update it? (This preserves your credentials and memory files)"
- If yes: Run setup with `-Force` flag
- If no: Abort installation

### Step 3: RUN_SETUP

```powershell
# Navigate to cloned framework
cd "$env:TEMP\wof-install"

# Run setup
.\setup.ps1 -TargetPath "{TARGET}"
```

**Parameters:**
- `TargetPath`: Absolute path to target project root
- `SolutionName`: (Optional) Defaults to directory name
- `Force`: Add if updating existing installation

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

```powershell
# Remove temporary clone
Remove-Item -Recurse -Force "$env:TEMP\wof-install"
```

## CREDENTIAL_INTERVIEW

For each credential, interview the user. Only write values that are provided (skip placeholders for empty ones).

**Note:** WOF v2.0 uses generic connection IDs (AI1-AI10) instead of provider-specific names.
This allows role reassignment without changing credentials.

### Required Credentials

#### AI1_ENDPOINT (Primary AI - typically Azure AI Foundry Anthropic)
```yaml
id: AI1_ENDPOINT
prompt: "What is your primary AI endpoint URL? (Azure AI Foundry Anthropic recommended)"
required: true
format: "https://{resource-name}.services.ai.azure.com/anthropic"
help: |
  Find this in Azure Portal:
  1. Go to Azure AI Foundry resource
  2. Navigate to Keys and Endpoint
  3. Copy the Anthropic endpoint URL
sensitive: false
enables: "Worker-Heavy, Validator roles (via connections.json)"
maps_to: "ai1 connection in connections.json"
```

#### AI1_API_KEY
```yaml
id: AI1_API_KEY
prompt: "What is your primary AI API key?"
required: true
format: "32-character alphanumeric string"
help: |
  Find this in Azure Portal:
  1. Go to Azure AI Foundry resource
  2. Navigate to Keys and Endpoint
  3. Copy Key 1 or Key 2
sensitive: true
enables: "Worker-Heavy, Validator roles"
depends_on: AI1_ENDPOINT
```

### Optional Credentials

#### AI2_ENDPOINT (Secondary AI - optional, for additional services)
```yaml
id: AI2_ENDPOINT
prompt: "What is your secondary AI endpoint URL? (Press Enter to skip)"
required: false
format: "https://{resource-name}.cognitiveservices.azure.com"
help: |
  Find this in Azure Portal:
  1. Go to Azure OpenAI resource
  2. Navigate to Keys and Endpoint
  3. Copy the endpoint URL
sensitive: false
enables: "Additional AI services (optional)"
skip_message: "AI2 slot will remain empty. You can add this later."
maps_to: "ai2 connection in connections.json"
```

#### AI2_API_KEY
```yaml
id: AI2_API_KEY
prompt: "What is your secondary AI API key?"
required: false
format: "32-character alphanumeric string"
help: "Same location as endpoint - copy Key 1 or Key 2"
sensitive: true
enables: "Additional AI services"
depends_on: AI2_ENDPOINT
```

#### AI3_ENDPOINT (Tertiary AI - typically Azure OpenAI for Codex)
```yaml
id: AI3_ENDPOINT
prompt: "What is your tertiary AI endpoint URL? (Press Enter to skip)"
required: false
format: "https://{resource-name}.cognitiveservices.azure.com/openai/responses"
help: |
  Find this in Azure Portal:
  1. Go to Azure OpenAI resource with Codex model deployed
  2. Navigate to Keys and Endpoint
  3. Append /openai/responses to the endpoint
sensitive: false
enables: "Critic role (quality gate)"
skip_message: "Critic role will be disabled. Quality gates will be skipped."
maps_to: "ai3 connection in connections.json"
```

#### AI3_API_KEY
```yaml
id: AI3_API_KEY
prompt: "What is your tertiary AI API key?"
required: false
format: "32-character alphanumeric string"
help: "Same location as endpoint"
sensitive: true
enables: "Critic role"
depends_on: AI3_ENDPOINT
```

#### AI4_ENDPOINT (Local model server / Worker-Lite)
```yaml
id: AI4_ENDPOINT
prompt: "What is your AI4/Worker-Lite endpoint? (Press Enter for default: http://localhost:1234)"
required: false
format: "http://localhost:{port}"
default: "http://localhost:1234"
help: |
  For local models via LM Studio, Ollama, or similar:
  - LM Studio default: http://localhost:1234
  - Ollama default: http://localhost:11434
  Or use a cloud provider for Worker-Lite tasks.
sensitive: false
enables: "Worker-Lite role (lightweight tasks)"
skip_message: "Worker-Lite disabled. All tasks will route to Worker-Heavy."
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

| Component | Status Red | Fix |
|-----------|------------|-----|
| AI1 (Primary) | "NOT SET" | Add AI1_ENDPOINT and AI1_API_KEY in credentials.local.json |
| AI2 (Secondary) | "NOT SET" | Optional - add AI2_* for additional services |
| AI3 (Tertiary) | "NOT SET" | Optional - add AI3_* if you want Critic role |
| AI4 (Worker-Lite) | "NOT SET" | Optional - add AI4_ENDPOINT or start LM Studio on port 1234 |

## POST_INSTALLATION

After successful installation, inform the user:

```
WOF has been installed successfully!

Next steps:
1. Open Claude Code in your project: cd "{TARGET}" && claude
2. The AI orchestrator is now active - it will route tasks to appropriate workers
3. Use "Finish up #XXXX" to complete work items with proper workflow

Optional:
- Start LM Studio with DeepSeek for Worker-Lite (lightweight tasks)
- Run .\.ai\scripts\check-orchestration-health.ps1 to see component status
```
