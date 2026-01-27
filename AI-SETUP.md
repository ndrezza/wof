# WOF AI Installation Protocol

<!-- AI-READABLE: Structured instructions for AI coding assistants -->
<!-- Version: 1.0 | Last Updated: 2026-01-27 -->

## METADATA

```yaml
name: Workload Orchestration Framework (WOF)
version: 1.2.4
repository: https://github.com/ndrezza/wof
setup_script: setup.ps1
config_location: .ai/config/credentials.local.ps1
health_check: .ai/scripts/check-orchestration-health.ps1
```

## QUICK_REFERENCE

```
Clone:    git clone https://github.com/ndrezza/wof.git
Setup:    .\setup.ps1 -TargetPath "{TARGET}" -Mode "{MODE}"
Config:   .ai/config/credentials.local.ps1
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

### Step 3: SELECT_MODE

**Ask user to choose installation mode:**

| Mode | Description | Best For |
|------|-------------|----------|
| **SourceControlled** (default) | Framework committed to git, shared with team | Teams using AI workflows together |
| **LocalOnly** | Framework completely gitignored | Personal use, trying it out, teams not ready for AI |

**Interview prompt:**
> "How would you like to install WOF?
> 1. **SourceControlled** (Recommended) - Framework is committed to your repo and shared with your team
> 2. **LocalOnly** - Framework is gitignored, only you can see it, invisible to other developers"

### Step 4: RUN_SETUP

```powershell
# Navigate to cloned framework
cd "$env:TEMP\wof-install"

# Run setup (adjust Mode based on user choice)
.\setup.ps1 -TargetPath "{TARGET}" -Mode "{MODE}"
```

**Parameters:**
- `TargetPath`: Absolute path to target project root
- `Mode`: `SourceControlled` or `LocalOnly`
- `SolutionName`: (Optional) Defaults to directory name
- `Force`: Add if updating existing installation

### Step 5: CONFIGURE_CREDENTIALS

See [CREDENTIAL_INTERVIEW](#credential_interview) section below.

After collecting credentials, write them to `.ai/config/credentials.local.ps1` in the target project.

### Step 6: SETUP_MCP

Register the secondary-claude MCP server for Worker delegation:

```bash
claude mcp add --scope local secondary-claude -- claude mcp serve
```

**Note:** This step requires Claude Code CLI to be available.

### Step 7: VERIFY

Run the health check to verify installation:

```powershell
# From target project directory
.\.ai\scripts\check-orchestration-health.ps1
```

**Expected output:** Status dashboard showing which components are configured.

### Step 8: CLEANUP

```powershell
# Remove temporary clone
Remove-Item -Recurse -Force "$env:TEMP\wof-install"
```

## CREDENTIAL_INTERVIEW

For each credential, interview the user. Only write values that are provided (skip placeholders for empty ones).

### Required Credentials

#### AZURE_ANTHROPIC_ENDPOINT
```yaml
id: AZURE_ANTHROPIC_ENDPOINT
prompt: "What is your Azure AI Foundry Anthropic endpoint URL?"
required: true
format: "https://{resource-name}.services.ai.azure.com/anthropic"
help: |
  Find this in Azure Portal:
  1. Go to Azure AI Foundry resource
  2. Navigate to Keys and Endpoint
  3. Copy the Anthropic endpoint URL
sensitive: false
enables: "Worker-Heavy, Validator agents"
```

#### AZURE_ANTHROPIC_API_KEY
```yaml
id: AZURE_ANTHROPIC_API_KEY
prompt: "What is your Azure AI Foundry API key?"
required: true
format: "32-character alphanumeric string"
help: |
  Find this in Azure Portal:
  1. Go to Azure AI Foundry resource
  2. Navigate to Keys and Endpoint
  3. Copy Key 1 or Key 2
sensitive: true
enables: "Worker-Heavy, Validator agents"
depends_on: AZURE_ANTHROPIC_ENDPOINT
```

### Optional Credentials

#### AZURE_OPENAI_ENDPOINT
```yaml
id: AZURE_OPENAI_ENDPOINT
prompt: "What is your Azure OpenAI endpoint URL? (Press Enter to skip)"
required: false
format: "https://{resource-name}.cognitiveservices.azure.com"
help: |
  Find this in Azure Portal:
  1. Go to Azure OpenAI resource
  2. Navigate to Keys and Endpoint
  3. Copy the endpoint URL
sensitive: false
enables: "Friend agent (GPT-4o rules guardian)"
skip_message: "Friend agent will be disabled. You can add this later."
```

#### AZURE_OPENAI_API_KEY
```yaml
id: AZURE_OPENAI_API_KEY
prompt: "What is your Azure OpenAI API key?"
required: false
format: "32-character alphanumeric string"
help: "Same location as endpoint - copy Key 1 or Key 2"
sensitive: true
enables: "Friend agent (GPT-4o rules guardian)"
depends_on: AZURE_OPENAI_ENDPOINT
```

#### AZURE_CODEX_ENDPOINT
```yaml
id: AZURE_CODEX_ENDPOINT
prompt: "What is your Azure Codex endpoint URL? (Press Enter to skip)"
required: false
format: "https://{resource-name}.cognitiveservices.azure.com/openai/responses"
help: |
  Find this in Azure Portal:
  1. Go to Azure OpenAI resource with Codex model deployed
  2. Navigate to Keys and Endpoint
  3. Append /openai/responses to the endpoint
sensitive: false
enables: "Critic agent (quality gate)"
skip_message: "Critic agent will be disabled. Quality gates will be skipped."
```

#### AZURE_CODEX_API_KEY
```yaml
id: AZURE_CODEX_API_KEY
prompt: "What is your Azure Codex API key?"
required: false
format: "32-character alphanumeric string"
help: "Same location as Codex endpoint"
sensitive: true
enables: "Critic agent (quality gate)"
depends_on: AZURE_CODEX_ENDPOINT
```

#### LOCAL_WORKER_ENDPOINT
```yaml
id: LOCAL_WORKER_ENDPOINT
prompt: "What is your local model endpoint? (Press Enter for default: http://localhost:1234)"
required: false
format: "http://localhost:{port}"
default: "http://localhost:1234"
help: |
  For local models via LM Studio, Ollama, or similar:
  - LM Studio default: http://localhost:1234
  - Ollama default: http://localhost:11434
sensitive: false
enables: "Worker-Lite agent (lightweight tasks)"
skip_message: "Worker-Lite disabled. All tasks will route to Worker-Heavy."
```

## CREDENTIAL_FILE_FORMAT

After collecting credentials, generate `.ai/config/credentials.local.ps1`:

```powershell
# WOF Credentials - Auto-generated
# This file is gitignored and contains sensitive values

# Azure AI Foundry (Anthropic Models)
$env:AZURE_ANTHROPIC_ENDPOINT = '{AZURE_ANTHROPIC_ENDPOINT}'
$env:AZURE_ANTHROPIC_API_KEY = '{AZURE_ANTHROPIC_API_KEY}'

# Azure OpenAI (Friend - GPT-4o)
$env:AZURE_OPENAI_ENDPOINT = '{AZURE_OPENAI_ENDPOINT}'
$env:AZURE_OPENAI_API_KEY = '{AZURE_OPENAI_API_KEY}'

# Azure Codex (Critic)
$env:AZURE_CODEX_ENDPOINT = '{AZURE_CODEX_ENDPOINT}'
$env:AZURE_CODEX_API_KEY = '{AZURE_CODEX_API_KEY}'

# Local Worker
$env:LOCAL_WORKER_ENDPOINT = '{LOCAL_WORKER_ENDPOINT}'

# Verification
Write-Host "WOF Credentials loaded" -ForegroundColor Cyan
```

**Notes:**
- Only include lines for credentials the user provided
- Leave out or comment out credentials they skipped
- The file is automatically gitignored by setup.ps1

## EXISTING_CONFIG_DETECTION

Before interviewing for credentials, check these locations for reusable values:

### Location 1: Target Project
```powershell
$existingCreds = "{TARGET}/.ai/config/credentials.local.ps1"
if (Test-Path $existingCreds) {
    # Parse and extract existing values
    # Ask: "Found existing credentials. Reuse them?"
}
```

### Location 2: Environment Variables
```powershell
# Check if credentials are already in environment
$hasAzureAnthropic = $env:AZURE_ANTHROPIC_ENDPOINT -and $env:AZURE_ANTHROPIC_API_KEY
if ($hasAzureAnthropic) {
    # Ask: "Found Azure Anthropic credentials in environment. Use these?"
}
```

**Reuse prompt:**
> "I found existing credentials at {location}. Would you like to reuse them?
> - Yes: Use existing credentials (recommended if this is an update)
> - No: Enter new credentials"

## MODE_SELECTION_DETAILS

### SourceControlled Mode (Default)

**What gets committed:**
- `CLAUDE.md` - Main orchestration document
- `.claude/settings.json` - Claude Code hooks
- `.claude/skills/` - Slash commands
- `.ai/scripts/` - Core automation scripts
- `.ai/config/` - Configuration (except credentials)
- `.ai/memory/` - Architecture and conventions
- `.ai/agents/` - Agent persona definitions
- `.ai/workflows/` - Process definitions

**What gets gitignored:**
- `.ai/config/credentials.local.ps1` - Sensitive credentials
- `.ai/state/` - Runtime state
- `.ai/logs/` - Operation logs

### LocalOnly Mode

**Everything gitignored:**
- `.ai/` - Entire framework directory
- `.claude/` - Claude Code settings
- `CLAUDE.md` - Orchestration document

**Use cases:**
- Trying WOF without team buy-in
- Personal AI workflows
- Projects where team doesn't use AI tooling yet

## VERIFICATION_CHECKLIST

After installation, verify these items:

| Check | Command | Expected Result |
|-------|---------|-----------------|
| Framework installed | `Test-Path "{TARGET}/.ai"` | `True` |
| CLAUDE.md exists | `Test-Path "{TARGET}/CLAUDE.md"` | `True` |
| Credentials file | `Test-Path "{TARGET}/.ai/config/credentials.local.ps1"` | `True` |
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
| Azure Anthropic | "NOT SET" | Add AZURE_ANTHROPIC_ENDPOINT and API_KEY |
| Azure OpenAI | "NOT SET" | Optional - add if you want Friend agent |
| Azure Codex | "NOT SET" | Optional - add if you want Critic agent |
| Local Worker | "NOT SET" | Optional - start LM Studio on port 1234 |

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
