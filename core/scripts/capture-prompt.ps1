# ============================================================================
# WOF MANAGED FILE - DO NOT EDIT MANUALLY
# This file is managed by the Workload Orchestration Framework.
# Changes will be overwritten on the next WOF sync/update.
# To customize behavior, use configuration files in .ai/config/
# ============================================================================

# Prompt Capture Script
#
# Appends a summary of user prompts to .ai/state/prompt-history.json
# for pattern detection. Called silently by the orchestrator after each
# substantive user message.
#
# Usage:
#   & '.\capture-prompt.ps1' -Prompt "Run tests after every change"
#   & '.\capture-prompt.ps1' -Prompt "Fix bug in auth module" -WorkItemId "1234"

param(
    [Parameter(Mandatory=$true)]
    [string]$Prompt,

    [Parameter(Mandatory=$false)]
    [string]$WorkItemId = "",

    [Parameter(Mandatory=$false)]
    [int]$MaxEntries = 200
)

# Skip short prompts (greetings, confirmations, etc.)
if ($Prompt.Length -lt 10) {
    return @{ Captured = $false; Reason = "Prompt too short (< 10 chars)" }
}

# Truncate overly long prompts
if ($Prompt.Length -gt 200) {
    $Prompt = $Prompt.Substring(0, 200)
}

# Resolve repo path
$repoPath = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { (Get-Item $PSScriptRoot).Parent.Parent.FullName }
$stateDir = Join-Path $repoPath ".ai\state"
$historyFile = Join-Path $stateDir "prompt-history.json"

# Ensure state directory exists
if (-not (Test-Path $stateDir)) {
    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
}

# Load or create history
if (Test-Path $historyFile) {
    $history = Get-Content $historyFile -Raw | ConvertFrom-Json
} else {
    $history = [PSCustomObject]@{
        version = "1.0.0"
        entries = @()
    }
}

# Ensure entries is an array we can work with
$entries = @($history.entries)

# Create new entry
$entry = [PSCustomObject]@{
    timestamp    = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ")
    prompt       = $Prompt
    work_item_id = $WorkItemId
}

# Append entry
$entries += $entry

# Trim oldest entries if over limit
if ($entries.Count -gt $MaxEntries) {
    $entries = $entries[($entries.Count - $MaxEntries)..($entries.Count - 1)]
}

# Build output object and save
$output = [PSCustomObject]@{
    version = "1.0.0"
    entries = $entries
}

$output | ConvertTo-Json -Depth 5 | Set-Content -Path $historyFile -Encoding UTF8

return @{
    Captured   = $true
    EntryCount = $entries.Count
    File       = $historyFile
}
