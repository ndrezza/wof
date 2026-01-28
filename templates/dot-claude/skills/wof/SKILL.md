---
name: wof
description: Workload Orchestration Framework commands - update, status, configure, route, remove
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
| `route <task>` | Classify a task and show routing decision |
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
  3. "Done" - Finish configuration

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

#### Step 3b: If Configuring Role Mappings

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

Run the remove-framework script:
```bash
powershell -ExecutionPolicy Bypass -File "./.ai/scripts/remove-framework.ps1"
```
Add flags as needed: -DryRun, -Force, -IncludeConfig, -RemoveAll

---

### If arguments contain "configure-ado"

Configure Azure DevOps integration with MCP server.

#### Step 1: Check Current Configuration

Read `.ai/config/ado.json` to see current settings:
```bash
cat .ai/config/ado.json 2>/dev/null || echo "No ADO config found"
```

#### Step 2: Ask for Connection Info

Use AskUserQuestion to gather connection details:

**Question 1: Organization URL**
- Question: "What is your Azure DevOps organization URL?"
- Header: "ADO Org"
- Options:
  1. "https://dev.azure.com/myorg" (example format)
  2. "Other" (let user type)
- Note: User should provide full URL or just org name

**Question 2: Project Name**
- Question: "What is your Azure DevOps project name?"
- Header: "Project"
- Let user type the project name

**Question 3: Authentication Method**
- Question: "How do you want to authenticate?"
- Header: "Auth"
- Options:
  1. "Browser login (Recommended)" - Uses Microsoft account via browser
  2. "Personal Access Token (PAT)" - For automation/CI scenarios
  3. "Azure CLI" - Use existing `az login` session

If PAT selected, ask for the PAT value (will be stored in ado.json).

#### Step 3: Configure Filters

Use AskUserQuestion with proposed defaults:

**Question 4: Value Area Filter**
- Question: "Filter work items by Value Area?"
- Header: "Value Area"
- Options:
  1. "Architectural (Recommended)" - Focus on architectural work items
  2. "Business" - Business value items
  3. "No filter" - Show all value areas
  4. "Other" - Custom value area

**Question 5: Work Item Types**
- Question: "Which work item types to include?"
- Header: "Types"
- MultiSelect: true
- Options:
  1. "User Story"
  2. "Task"
  3. "Bug"
  4. "Feature"
- Default: All selected

**Question 6: Work Item States**
- Question: "Which states to include?"
- Header: "States"
- MultiSelect: true
- Options:
  1. "New"
  2. "Active"
  3. "Resolved"
  4. "Closed"
- Default: New, Active, Resolved

#### Step 4: Update Configuration Files

**Update `.ai/config/ado.json`:**
```json
{
  "connection": {
    "organizationUrl": "<user-provided>",
    "project": "<user-provided>",
    "pat": "<if-provided-or-empty>"
  },
  "filters": {
    "valueArea": "<selected>",
    "workItemTypes": ["<selected-types>"],
    "states": ["<selected-states>"]
  }
}
```

#### Step 5: Configure MCP Server

Extract organization name from URL (e.g., `https://dev.azure.com/myorg` -> `myorg`).

Add/update the MCP server using Claude CLI:
```bash
claude mcp add --scope project azure-devops -- npx -y @azure-devops/mcp <org-name> -d core work work-items
```

Or update `.mcp.json` directly:
```json
{
  "mcpServers": {
    "azure-devops": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@azure-devops/mcp", "<org-name>", "-d", "core", "work", "work-items"]
    }
  }
}
```

#### Step 6: Test Connection

Inform user:
- "MCP server configured. Restart Claude Code to activate."
- "First use will prompt for Microsoft account login in browser."
- If PAT was provided: "PAT authentication configured for non-interactive use."

---

### If arguments are empty or contain "help"

Display the available commands table above and explain each option.

## Config File Locations

| File | Purpose |
|------|---------|
| `.ai/config/credentials.local.json` | API keys and endpoints (gitignored) |
| `.ai/config/connections.json` | AI connection definitions |
| `.ai/config/roles.json` | Role-to-connection mappings |
| `.ai/config/ado.json` | Azure DevOps connection & filters (gitignored) |
| `.mcp.json` | MCP server configuration (gitignored) |

## Important Notes

- Use AskUserQuestion for all user input during configure - don't rely on PowerShell prompts
- The configure flow should be conversational and guide the user through options
- Always show current status before asking for changes
- After any config change, offer to run the health check
