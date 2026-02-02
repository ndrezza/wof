---
name: wof
description: Workload Orchestration Framework commands - update, status, configure, model, route, remove
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - AskUserQuestion
---

# WOF - Workload Orchestration Framework Commands

Parse the arguments to determine which WOF command to run.

**Arguments received:** $ARGUMENTS

## Available Commands

| Command | Description |
|---------|-------------|
| `update` | Update WOF to latest version from repository |
| `update --dry-run` | Preview update changes without applying |
| `status` | Check orchestration health and component status |
| `configure` | Interactive AI configuration (add connections, map roles) |
| `configure --test-only` | Only test existing connections |
| `configure-ado` | Configure Azure DevOps integration (MCP server, filters) |
| `model` | Show current backend and model info |
| `model list` | List available Ollama models |
| `model <name>` | Switch to a specific Ollama model |
| `model pull <name>` | Pull/download an Ollama model |
| `model status` | Show comprehensive backend status |
| `route <task>` | Classify a task and show routing decision |
| `finish` | Complete current work: update WI, bump version, commit, push |
| `finish --work-item <id>` | Finish with specific work item ID |
| `configure finish` | Configure finish workflow behavior |
| `remove` | Remove WOF scripts (preserves config & memory) |
| `help` | Show this help information |

## Command Handling

Based on the arguments, execute the appropriate action:

---

### If arguments contain "configure"

**DO NOT run configure-wizard.ps1 directly** - it uses Read-Host prompts that don't work well non-interactively.

Instead, follow this interactive flow:

#### Step 1: Test Current Connections

Run the test-only check:
```bash
powershell -ExecutionPolicy Bypass -File "./.ai/scripts/configure-wizard.ps1" -TestOnly
```

This shows which AI connections are configured and their status (ONLINE/OFFLINE/N/C).

#### Step 2: Ask User What To Do

Use AskUserQuestion to ask:
- Question: "What would you like to configure?"
- Options:
  1. "Add/modify an AI connection" - Add a new AI or update existing
  2. "Configure role mappings" - Map roles to AI connections
  3. "Local AI (Ollama)" - Configure local Ollama instance and generate launcher
  4. "Done" - Finish configuration

#### Step 3a: If Adding/Modifying AI Connection

Ask which slot (AI1-AI10) to configure. Then ask for:
1. **Alias** (friendly name, e.g., "Azure Anthropic", "Local Ollama")
2. **Endpoint URL** (e.g., `https://xxx.services.ai.azure.com/anthropic`)
3. **API Key** (if required - can be empty for local models)

Auto-detect connection type from URL:
- Contains `.services.ai.azure.com/anthropic` or ends with `/anthropic` → `azure_ai_foundry_anthropic`
- Contains `.openai.azure.com` or `.cognitiveservices.azure.com` → `azure_openai`
- Otherwise → `openai_compatible`

Then update the config files:

**Update `.ai/config/credentials.local.json`:**
```json
{
  "credentials": {
    "AI1_ENDPOINT": "https://...",
    "AI1_API_KEY": "...",
    ...
  }
}
```

**Update `.ai/config/connections.json`:**
```json
{
  "connections": {
    "ai1": {
      "alias": "Azure Anthropic",
      "description": "Azure AI Foundry with Anthropic models",
      "type": "azure_ai_foundry_anthropic",
      "endpoint": "${AI1_ENDPOINT}",
      "api_key": "${AI1_API_KEY}"
    },
    ...
  }
}
```

After adding, loop back to Step 2 to ask if they want to do more.

#### Step 3b: If Configuring Local AI (Ollama)

Configure a local Ollama instance and generate launcher scripts.

##### Step B1: Detect Ollama

First, check if Ollama is running at localhost:
```bash
curl -s http://localhost:11434/api/version
```

If successful, show:
```
✓ Ollama found at localhost:11434
  Version: <version>
```

If connection fails, use AskUserQuestion:
- Question: "Cannot connect to Ollama at localhost:11434. What would you like to do?"
- Header: "Ollama"
- Options:
  1. "Try again" - Retry localhost connection
  2. "Different host" - Enter custom host/IP
  3. "Cancel" - Return to configure menu

If user selects "Different host":
- Ask: "Enter Ollama host (IP or hostname):"
- Ask: "Enter port [11434]:"
- Test connection at the provided address

##### Step B2: List and Analyze Available Models

Once connected, list models:
```bash
curl -s http://<host>:<port>/api/tags
```

**Analyze each model's capabilities:**

1. First, check WOF's model capabilities cache:
   - Read `core/data/model-capabilities.json` (or `.ai/data/model-capabilities.json` in WOI)
   - Look up each model by name

2. For models NOT in cache:
   - Use WebSearch: "<model-name> capabilities context window coding reasoning"
   - Extract: strengths, weaknesses, context window, RAM requirements
   - Inform user this is a new/unknown model

3. Display analyzed results:
```
Available Models (analyzed):
| Model              | Size    | RAM   | Quality | Speed  | Best For              |
|--------------------|---------|-------|---------|--------|----------------------|
| qwen3-coder:30b    | 18.6 GB | ~20GB | High    | Slow   | Worker-Heavy          |
| deepseek-r1:8b     | 5.2 GB  | ~5GB  | High    | Medium | Validator, Critic     |
| codellama:7b       | 4.1 GB  | ~4GB  | Medium  | Fast   | Worker-Lite           |

Total RAM if all loaded simultaneously: ~29GB
Note: Ollama loads models on-demand; not all need to be in RAM at once.
```

If no models found:
```
No models found in Ollama.

Recommended models to pull:
  ollama pull qwen3-coder:30b    # Complex code tasks (~20GB RAM)
  ollama pull deepseek-r1:8b     # Reasoning/validation (~5GB RAM)
  ollama pull codellama:7b       # Fast simple tasks (~4GB RAM)
```

##### Step B3: Role Mapping with Delegation Choice

For each WOF role, ask the user to:
1. Select a model (or skip/use cloud)
2. Choose delegation method

**Use AskUserQuestion for each role:**

```
Role: Worker-Heavy
Description: Complex code generation, refactoring, large changes
Recommended: qwen3-coder:30b (High quality, code generation)

"Which model for Worker-Heavy?"
  1. qwen3-coder:30b (Recommended)
  2. deepseek-r1:8b
  3. Skip (use cloud API for this role)
  4. Pull a different model
```

**After model selection, ask delegation method:**

```
"How should Worker-Heavy be invoked?"
  1. MCP Server (Recommended) - Separate Claude Code process, parallel execution
  2. PS Script delegation - Sequential, simpler, uses delegate-to-local-worker.ps1
```

**Repeat for each role:**
- Orchestrator (if user wants local orchestrator)
- Worker-Heavy
- Worker-Lite
- Validator
- Critic

**Show RAM summary after all selections:**
```
Role Configuration Summary:
| Role         | Model           | Delegation | RAM    |
|--------------|-----------------|------------|--------|
| Orchestrator | mistral:7b      | (main)     | ~4GB   |
| Worker-Heavy | qwen3-coder:30b | MCP Server | ~20GB  |
| Worker-Lite  | codellama:7b    | PS Script  | ~4GB   |
| Validator    | deepseek-r1:8b  | MCP Server | ~5GB   |
| Critic       | deepseek-r1:8b  | MCP Server | (shared)|

Estimated peak RAM: ~33GB (if all models loaded simultaneously)
Note: Ollama manages memory dynamically. Models unload when not in use.

"Proceed with this configuration?"
```

##### Step B4: Choose Launcher Location

##### Step B4: Choose Launcher Location

Use AskUserQuestion:
- Question: "Where should I save the launcher script?"
- Header: "Location"
- Options:
  1. "User profile (~/.claude/)" - Recommended
  2. "Desktop" - Easy access
  3. "Current directory" - Project-specific
  4. "Custom location" - Specify path

Determine paths based on OS:
- **Windows:**
  - User profile: `$env:USERPROFILE\.claude\Start-ClaudeLocal.ps1`
  - Desktop: `$env:USERPROFILE\Desktop\Start-ClaudeLocal.ps1`
- **macOS/Linux:**
  - User profile: `~/.claude/start-claude-local.sh`
  - Desktop: `~/Desktop/start-claude-local.sh`

##### Step B5: Generate Launcher Scripts

Create the launcher script(s) using the templates from `.ai/templates/`:

**For Windows (always generate):**
Read template from `.ai/templates/Start-ClaudeLocal.ps1.template` and replace:
- `{{OLLAMA_HOST}}` → detected host
- `{{OLLAMA_PORT}}` → detected port
- `{{DEFAULT_MODEL}}` → selected model

Write to chosen location.

**For macOS/Linux (always generate alongside Windows):**
Read template from `.ai/templates/start-claude-local.sh.template` and replace same variables.

Write to equivalent Unix path.

##### Step B6: Register MCP Servers and AI Slots

Based on the role mapping from Step B3, register the necessary components:

**For each role configured with MCP Server delegation:**

```bash
# Example: Worker-Heavy with qwen3-coder:30b via MCP
claude mcp add --scope local worker-heavy \
  -e ANTHROPIC_BASE_URL=http://<host>:<port> \
  -e ANTHROPIC_API_KEY=ollama \
  -e OLLAMA_MODEL=qwen3-coder:30b \
  -- claude mcp serve

# Example: Validator with deepseek-r1:8b via MCP
claude mcp add --scope local validator \
  -e ANTHROPIC_BASE_URL=http://<host>:<port> \
  -e ANTHROPIC_API_KEY=ollama \
  -e OLLAMA_MODEL=deepseek-r1:8b \
  -- claude mcp serve
```

**For roles configured with PS Script delegation:**

No MCP registration needed. The role will use `delegate-to-local-worker.ps1` with the configured model.

**Register Ollama as AI slot:**

Update `.ai/config/connections.json`:
```json
"ai4": {
  "alias": "Local Ollama",
  "description": "Local Ollama instance at <host>:<port>",
  "type": "ollama",
  "host": "<host>",
  "port": <port>,
  "capability": "high",
  "endpoint": "http://<host>:<port>",
  "api_key": "ollama",
  "requires_proxy": false,
  "models": {
    "<model1>": { "ram_gb": <ram>, "roles": ["worker-heavy"] },
    "<model2>": { "ram_gb": <ram>, "roles": ["validator", "critic"] }
  }
}
```

**Update `.ai/config/roles.json` with delegation method:**
```json
{
  "roles": {
    "worker-heavy": {
      "connection": "ai4",
      "model": "qwen3-coder:30b",
      "delegation": "mcp",
      "mcp_server": "worker-heavy"
    },
    "worker-lite": {
      "connection": "ai4",
      "model": "codellama:7b",
      "delegation": "script",
      "script": ".ai/scripts/delegate-to-local-worker.ps1"
    },
    "validator": {
      "connection": "ai4",
      "model": "deepseek-r1:8b",
      "delegation": "mcp",
      "mcp_server": "validator"
    }
  }
}
```

##### Step B7: Save Configuration

Write to `.ai/config/local-ai.json`:
```json
{
  "ollama": {
    "host": "<host>",
    "port": <port>,
    "defaultModel": "<model>",
    "verified": true,
    "lastChecked": "<ISO timestamp>"
  },
  "launcher": {
    "windows": "<windows-path>",
    "unix": "<unix-path>",
    "created": "<ISO timestamp>"
  },
  "registeredAsSlot": "<ai4 or null>"
}
```

##### Step B8: Show Summary

Display:
```
✓ Local AI Configuration Complete

Ollama:
  Host: localhost:11434
  Default Model: qwen3-coder:30b

Launcher Scripts:
  Windows: ~/.claude/Start-ClaudeLocal.ps1
  Unix:    ~/.claude/start-claude-local.sh

To start Claude Code with local Ollama:
  Windows:  ~/.claude/Start-ClaudeLocal.ps1
  macOS:    ~/.claude/start-claude-local.sh

Registered as: AI4 (can be mapped to roles)
```

Loop back to Step 2 to ask if they want to do more.

#### Step 3d: If Configuring Role Mappings

First read the current connections to see which are available (have endpoints configured).

Use AskUserQuestion for each role that needs mapping:
- **worker-heavy**: "Which AI should handle complex tasks (code gen, tests)?"
- **worker-lite**: "Which AI should handle simple tasks (search, format)?"
- **validator**: "Which AI should validate decisions?"
- **critic**: "Which AI should be the quality gate?"

Options should be the available AI connections (e.g., "AI1 - Azure Anthropic", "AI2 - Azure OpenAI").

Then update `.ai/config/roles.json`:
```json
{
  "roles": {
    "primary": { "connection": "native", ... },
    "worker-heavy": { "connection": "ai1", ... },
    "worker-lite": { "connection": "ai2", ... },
    ...
  }
}
```

#### Step 4: Run Health Check

After configuration, run the health check to verify:
```bash
powershell -ExecutionPolicy Bypass -File "./.ai/scripts/check-orchestration-health.ps1"
```

---

### If arguments contain "configure --test-only"

Just run the test:
```bash
powershell -ExecutionPolicy Bypass -File "./.ai/scripts/configure-wizard.ps1" -TestOnly
```

---

### If arguments contain "model"

Manage models and detect current Claude Code backend.

#### Step 1: Detect Current Backend

First, detect which backend Claude Code is currently using by checking environment variables.

**Detection logic:**
```bash
# Check ANTHROPIC_BASE_URL environment variable
# Windows: $env:ANTHROPIC_BASE_URL
# Unix: $ANTHROPIC_BASE_URL
```

**Determine backend type:**
- If `ANTHROPIC_BASE_URL` is not set or empty → **Anthropic API (cloud)**
- If `ANTHROPIC_BASE_URL` contains `localhost:11434` or port 11434 → **Ollama (local)**
- If `ANTHROPIC_BASE_URL` contains `.services.ai.azure.com` → **Azure Foundry**
- If `ANTHROPIC_BASE_URL` contains other localhost/IP → **Other local server**

#### If arguments are exactly "model" (show current backend & model)

Display current backend information:

**If on Anthropic API (cloud):**
```
Current Backend: Anthropic API (cloud)
  Endpoint: https://api.anthropic.com
  Model: claude-opus-4-5-20251101 (or current model)

This session is using Anthropic's cloud API.

To switch to local Ollama:
  Windows:  ~/.claude/Start-ClaudeLocal.ps1
  macOS:    ~/.claude/start-claude-local.sh

Or run: /wof configure → "Local AI (Ollama)" to set up first.
```

**If on Ollama (local):**
First check Ollama connectivity:
```bash
curl -s http://localhost:11434/api/tags
```

Then display:
```
Current Backend: Ollama (local)
  Endpoint: http://localhost:11434

Available Models:
| Model              | Size    | Quantization | Status  |
|--------------------|---------|--------------|---------|
| qwen3-coder:30b    | 18.6 GB | Q4_K_M       | ready   |
| deepseek-r1:8b     | 5.2 GB  | Q4_K_M       | ready   |

Commands:
  /wof model list              - List all models
  /wof model <name>            - Switch to model
  /wof model pull <name>       - Download new model

To switch back to Anthropic cloud:
  Start a new terminal and run: claude
```

**If on Azure Foundry:**
```
Current Backend: Azure Foundry
  Endpoint: https://<resource>.services.ai.azure.com/anthropic
  Model: claude-sonnet-4-5

This session is using Azure-hosted Claude.
```

**If on other local server:**
```
Current Backend: Local Server (custom)
  Endpoint: <ANTHROPIC_BASE_URL value>

Note: This appears to be a custom local server.
For Ollama support, ensure it's running on port 11434.
```

#### If arguments contain "model list"

**If on Ollama:** List all available models:
```bash
curl -s http://localhost:11434/api/tags
```

Parse and display as table:
```
Available Ollama Models:
| Model              | Size    | Quantization | Modified           |
|--------------------|---------|--------------|-------------------|
| qwen3-coder:30b    | 18.6 GB | Q4_K_M       | 2026-02-02 19:19 |
| deepseek-r1:8b     | 5.2 GB  | Q4_K_M       | 2026-02-02 19:17 |
```

**If NOT on Ollama:**
```
Note: You're currently on <backend-name>, not Ollama.
Model listing is only available when connected to Ollama.

To check Ollama models anyway:
```bash
curl -s http://localhost:11434/api/tags
```

Then offer to run that command to show Ollama models regardless.

#### If arguments contain "model pull <name>"

**If on Ollama:** Pull the model:
```bash
curl -X POST http://localhost:11434/api/pull -d '{"name": "<model-name>", "stream": false}'
```

Inform user:
```
Pulling model '<model-name>' from Ollama registry...
This may take a while depending on model size and internet speed.
```

After completion:
```
✓ Model '<model-name>' downloaded successfully.
Use '/wof model <model-name>' to switch to it.
```

**If NOT on Ollama:**
```
Note: You're currently on <backend-name>.
Pulling models is only supported when connected to Ollama.

However, I can still pull the model to Ollama for future use:
```
Then offer to pull anyway (Ollama can accept pull requests even when Claude Code isn't connected to it).

**Recommended models for coding:**
- `qwen3-coder:30b` - Excellent code generation (~20GB)
- `deepseek-r1:8b` - Good reasoning, lighter (~5GB)
- `codellama:34b` - Strong code completion (~20GB)
- `deepseek-coder-v2:16b` - Good balance (~10GB)

#### If arguments contain "model <name>" (switch model)

**If on Ollama:** Switch to the specified model by loading it:
```bash
curl -s http://localhost:11434/api/generate -d '{"model": "<model-name>", "prompt": "test", "stream": false}'
```

If successful:
```
✓ Switched to Ollama model: <model-name>
```

If model doesn't exist:
```
✗ Model '<model-name>' not found in Ollama.

Available models:
  - qwen3-coder:30b
  - deepseek-r1:8b

Use '/wof model pull <name>' to download a new model.
```

**If NOT on Ollama:**
```
Note: You're currently on <backend-name>.
Model switching is only available when connected to Ollama.

To use Ollama with model '<model-name>':
  1. Start Claude Code with Ollama backend:
     Windows: ~/.claude/Start-ClaudeLocal.ps1 -Model "<model-name>"
     macOS:   ~/.claude/start-claude-local.sh --model "<model-name>"

  2. Or set environment and restart:
     $env:ANTHROPIC_BASE_URL = "http://localhost:11434"
     $env:ANTHROPIC_API_KEY = "ollama"
     claude
```

#### If arguments contain "model status"

Show comprehensive status of all backends:
```
Backend Status:

Current Session:
  Backend: <detected backend>
  Endpoint: <endpoint>

Ollama (localhost:11434):
  Status: <Online/Offline>
  Models: <count> available

Configured in WOF:
  AI4: Local Ollama @ localhost:11434 (if configured)

Launcher Scripts:
  Windows: ~/.claude/Start-ClaudeLocal.ps1 <exists/not found>
  Unix:    ~/.claude/start-claude-local.sh <exists/not found>
```

---

### If arguments contain "status"

Run the orchestration health check:
```bash
powershell -ExecutionPolicy Bypass -File "./.ai/scripts/check-orchestration-health.ps1"
```

---

### If arguments contain "update"

Run the update-framework script:
```bash
powershell -ExecutionPolicy Bypass -File "./.ai/scripts/update-framework.ps1"
```
If arguments also contain "--dry-run", add the -DryRun flag.

---

### If arguments contain "route"

Extract the task description (everything after "route") and run:
```bash
powershell -ExecutionPolicy Bypass -File "./.ai/scripts/get-worker-routing.ps1" -TaskDescription "<task>"
```

---

### If arguments contain "remove"

Run the remove script:
```bash
powershell -ExecutionPolicy Bypass -File "./.ai/scripts/remove.ps1"
```
Add flags as needed: -DryRun, -Force, -IncludeConfig, -RemoveAll

---

### If arguments contain "finish"

Execute the finish workflow to complete current work.

#### Step 1: Load Configuration

Read finish config from `.ai/config/finish.json`. If not found, use defaults:
- updateWorkItem: true
- bumpVersion: true
- updateChangelog: true
- commit: true
- push: true

#### Step 2: Determine Work Item

If `--work-item <id>` is provided, use that ID.

Otherwise, check for an active work item by:
1. Looking at recent git commits for `(#XXXX)` pattern
2. Checking `.ai/memory/current-sprint.md` for active work items
3. If no work item found and ADO is configured, ask user which work item to finish

#### Step 3: Execute Finish Steps

Based on configuration, execute enabled steps in order:

**Step 3a: Bump Version** (if `bumpVersion: true`)
```bash
# Read current version
$version = Get-Content VERSION
# Bump patch version
$parts = $version -split '\.'
$parts[2] = [int]$parts[2] + 1
$newVersion = $parts -join '.'
Set-Content VERSION $newVersion
```

**Step 3b: Update Changelog** (if `updateChangelog: true`)
- Read CHANGELOG.md
- Add entry for new version with work item reference
- Use work item title as description

**Step 3c: Commit** (if `commit: true`)
- Stage changed files (VERSION, CHANGELOG.md, and any other modified files)
- Create commit with message from template: `{description} (#{workItemId})`

**Step 3d: Push** (if `push: true`)
```bash
git push
```

**Step 3e: Update Work Item** (if `updateWorkItem: true`)
- Set state to configured `resolveState` (default: "Resolved")
- Add comment with commit hash if `addComment: true`

#### Step 4: Report Results

Display summary:
- Version bumped: X.Y.Z → X.Y.Z+1
- Work item #XXXX resolved
- Commit: <hash>
- Pushed to: origin/main

---

### If arguments contain "configure finish"

Configure the finish workflow behavior.

#### Step 1: Load Current Configuration

Read `.ai/config/finish.json` or show defaults if not found.

#### Step 2: Ask User What To Configure

Use AskUserQuestion:
- Question: "Which finish steps should be enabled?"
- Header: "Steps"
- MultiSelect: true
- Options:
  1. "Update work item" - Set WI to Resolved
  2. "Bump version" - Increment VERSION file
  3. "Update changelog" - Add entry to CHANGELOG.md
  4. "Commit changes" - Git commit
  5. "Push to remote" - Git push

#### Step 3: Configure Work Item Settings

If "Update work item" is enabled:
- Question: "What state should work items be set to?"
- Header: "WI State"
- Options: "Resolved", "Closed", "Done"

#### Step 4: Configure Version Settings

If "Bump version" is enabled:
- Question: "What type of version bump?"
- Header: "Bump Type"
- Options: "patch (x.y.Z)", "minor (x.Y.0)", "manual (ask each time)"

#### Step 5: Save Configuration

Write to `.ai/config/finish.json`:
```json
{
  "steps": {
    "updateWorkItem": true/false,
    "bumpVersion": true/false,
    "updateChangelog": true/false,
    "commit": true/false,
    "push": true/false
  },
  "workItem": {
    "resolveState": "Resolved",
    "addComment": true
  },
  "version": {
    "file": "VERSION",
    "bumpType": "patch"
  }
}
```

#### Step 6: Confirm

Display saved configuration and inform user they can now use `/wof finish`.

---

### If arguments contain "configure-ado"

Configure Azure DevOps integration with MCP server.

#### Step 1: Check Current Configuration

Check existing settings:
```bash
cat .ai/config/ado.json 2>/dev/null || echo "No ADO filter config found"
cat .mcp.json 2>/dev/null || echo "No MCP config found"
```

#### Step 2: Ask for Connection Info

Use AskUserQuestion to gather:

**Question 1: Organization URL**
- Question: "What is your Azure DevOps organization URL?"
- Header: "ADO Org"
- Options:
  1. "https://dev.azure.com/myorg" (example format)
  2. "Other" (let user type)

**Question 2: Project Name**
- Question: "What is your Azure DevOps project name?"
- Header: "Project"
- Let user type the project name

**Question 3: Personal Access Token**
- Question: "Enter your Azure DevOps PAT (Personal Access Token)"
- Header: "PAT"
- Let user type the PAT value
- Note: PAT is stored only in .mcp.json (gitignored), not in ado.json

#### Step 3: Configure Filters

Use AskUserQuestion with proposed defaults:

**Question 4: Value Area Filter**
- Question: "Filter work items by Value Area?"
- Header: "Value Area"
- Options:
  1. "Architectural (Recommended)" - Focus on architectural work items
  2. "Business" - Business value items
  3. "No filter" - Show all value areas

**Question 5: Work Item Types**
- Question: "Which work item types to include?"
- Header: "Types"
- MultiSelect: true
- Options: "User Story", "Task", "Bug", "Feature"
- Default: All selected

**Question 6: Work Item States**
- Question: "Which states to include?"
- Header: "States"
- MultiSelect: true
- Options: "New", "Active", "Resolved", "Closed"
- Default: New, Active, Resolved

#### Step 4: Update Filter Config

**Update `.ai/config/ado.json`** (filters only, no credentials):
```json
{
  "project": {
    "organizationUrl": "<user-provided>",
    "name": "<user-provided>"
  },
  "filters": {
    "valueArea": "<selected>",
    "workItemTypes": ["<selected-types>"],
    "states": ["<selected-states>"]
  }
}
```

#### Step 5: Update MCP Server Config

**Update `.mcp.json`** (credentials stored here only):

On **Windows**, use `cmd /c` wrapper:
```json
{
  "mcpServers": {
    "azure-devops": {
      "type": "stdio",
      "command": "cmd",
      "args": ["/c", "npx", "-y", "@tiberriver256/mcp-server-azure-devops"],
      "env": {
        "AZURE_DEVOPS_ORG_URL": "<organization-url>",
        "AZURE_DEVOPS_AUTH_METHOD": "pat",
        "AZURE_DEVOPS_PAT": "<pat-value>",
        "AZURE_DEVOPS_DEFAULT_PROJECT": "<project-name>"
      }
    }
  }
}
```

On **Linux/macOS**, use `npx` directly:
```json
{
  "mcpServers": {
    "azure-devops": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@tiberriver256/mcp-server-azure-devops"],
      "env": {
        "AZURE_DEVOPS_ORG_URL": "<organization-url>",
        "AZURE_DEVOPS_AUTH_METHOD": "pat",
        "AZURE_DEVOPS_PAT": "<pat-value>",
        "AZURE_DEVOPS_DEFAULT_PROJECT": "<project-name>"
      }
    }
  }
}
```

#### Step 6: Test Connection

Inform user:
- "MCP server configured with PAT authentication. Restart Claude Code to activate."
- "No browser popup required - PAT provides silent authentication."

---

### If arguments are empty

Present an interactive menu using AskUserQuestion:

**Question:** "What would you like to do?"
**Header:** "WOF Action"
**Options:**
1. "Check status" - Run orchestration health check
2. "Update WOF" - Update to latest framework version
3. "Manage models" - List, switch, or pull Ollama models
4. "Finish work" - Complete current work (bump, commit, push)
5. "Configure" - Configure AI connections, ADO, or finish workflow
6. "Show help" - Display all available commands

Based on user selection:
- **Check status** → Execute the `status` command flow
- **Update WOF** → Execute the `update` command flow
- **Manage models** → Execute the `model list` command flow
- **Finish work** → Execute the `finish` command flow
- **Configure** → Ask follow-up: "What would you like to configure?" with options: "AI connections", "Azure DevOps", "Finish workflow", then execute appropriate configure flow
- **Show help** → Display the Available Commands table

---

### If arguments contain "help"

Display the available commands table above and explain each option.

## Config File Locations

| File | Purpose |
|------|---------|
| `.ai/config/credentials.local.json` | API keys and endpoints (gitignored) |
| `.ai/config/connections.json` | AI connection definitions |
| `.ai/config/roles.json` | Role-to-connection mappings |
| `.ai/config/ado.json` | Azure DevOps connection & filters (gitignored) |
| `.mcp.json` | MCP server configuration (gitignored) |

## ADO Work Item Query Behavior

**CRITICAL: Always apply filters from `.ai/config/ado.json` when querying work items.**

### Before Querying Work Items

1. **Read the ado.json configuration:**
   ```
   Read .ai/config/ado.json to get project name, filters, and behavior settings
   ```

2. **Build WIQL query with ALL configured filters:**
   ```sql
   SELECT [System.Id], [System.Title], [System.State], [Microsoft.VSTS.Common.Priority]
   FROM WorkItems
   WHERE [System.TeamProject] = '<project.name>'
     AND [Microsoft.VSTS.Common.ValueArea] = '<filters.valueArea>'
     AND [System.State] IN ('<filters.states>')
     AND [System.WorkItemType] IN ('<filters.workItemTypes>')
   ORDER BY [Microsoft.VSTS.Common.Priority] ASC, [System.ChangedDate] DESC
   ```

3. **Skip items with "Blocked" tag** (if `behavior.skipBlockedItems` is true):
   - Items tagged with the configured `tags.blocked` value should be deprioritized
   - Inform user: "Skipping blocked items. Use 'show blocked' to include them."

### When Starting a Work Item

If `behavior.setActiveOnStart` is true (default):
1. **Set work item state to "Active"** using `mcp__azure-devops__update_work_item`
2. **Create feature branch** with pattern: `feature/<id>-<short-title>`
3. **Add phase tag** if configured: Start with "Implementation" phase by default

### Tag Conventions

| Tag | Purpose | When Applied |
|-----|---------|--------------|
| `Blocked` | Work item has questions pending user response | When questions are asked in comments |
| `Analysis` | Understanding requirements phase | Initial work item review |
| `Design` | Planning implementation approach | After analysis, before coding |
| `Implementation` | Active development | When coding starts |
| `Validation` | Testing and verification | After implementation |
| `QA` | Quality assurance review | Before completion |

### Updating Work Item Phase

When transitioning between phases:
1. **Remove previous phase tag** (if any)
2. **Add new phase tag**
3. Use `mcp__azure-devops__update_work_item` with appropriate tag changes

### Marking Work Item as Blocked

When you need user input and cannot proceed:
1. **Add "Blocked" tag** to the work item
2. **Add a comment** explaining what information is needed
3. Inform user: "Work item #<id> marked as Blocked pending your response"

### Unblocking Work Items

When user provides requested information:
1. **Remove "Blocked" tag**
2. **Resume work** on the item

## Important Notes

- Use AskUserQuestion for all user input during configure - don't rely on PowerShell prompts
- The configure flow should be conversational and guide the user through options
- Always show current status before asking for changes
- After any config change, offer to run the health check
- **Always apply ado.json filters** - never query without project and valueArea filters
