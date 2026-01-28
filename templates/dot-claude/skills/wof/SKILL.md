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
- Remove any phase tags (Analysis, Design, Implementation, Validation, QA)
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
3. "Finish work" - Complete current work (bump, commit, push)
4. "Configure" - Configure AI connections, ADO, or finish workflow
5. "Show help" - Display all available commands

Based on user selection:
- **Check status** → Execute the `status` command flow
- **Update WOF** → Execute the `update` command flow
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
