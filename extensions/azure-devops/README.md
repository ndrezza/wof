# Azure DevOps Extension

Optional Azure DevOps integration scripts for work item management.

## Setup

1. Copy the `.template` files to your project's `.ai/scripts/` directory
2. Replace placeholders with your ADO organization and project:
   - `{{ADO_ORGANIZATION}}` - Your ADO organization name
   - `{{ADO_PROJECT}}` - Your ADO project name

3. Set environment variable for authentication:
   ```bash
   export AZURE_DEVOPS_PAT="your-personal-access-token"
   ```
   Or use Azure CLI: `az login`

## Scripts

### ado-utils.ps1

Utility functions for work item management:
- `Set-WorkItemActiveWithParent` - Activates a work item and its parent
- `Set-WorkItemClosed` - Closes a work item
- `Get-WorkItem` - Retrieves work item details

### Usage in CLAUDE.md

Add to your project's CLAUDE.md to enable ADO integration:

```markdown
## Azure DevOps Integration

Work items follow format: `#XXXX`

- Always ask for work item ID before commits
- Reference in commit messages: `#123 Description`
- Update work item status when appropriate

**ADO Configuration:**
- Organization: `your-organization`
- Project: `Your Project Name`
```

## Authentication

The scripts support two authentication methods:

1. **Environment Variable** (recommended for automation):
   ```powershell
   $env:AZURE_DEVOPS_PAT = "your-pat-here"
   ```

2. **Azure CLI** (for interactive use):
   ```bash
   az login
   ```

## API Version

Uses Azure DevOps REST API version 7.1.
