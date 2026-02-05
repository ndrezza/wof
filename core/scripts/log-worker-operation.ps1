# ============================================================================
# WOF MANAGED FILE - DO NOT EDIT MANUALLY
# This file is managed by the Workload Orchestration Framework.
# Changes will be overwritten on the next WOF sync/update.
# To customize behavior, use configuration files in .ai/config/
# ============================================================================

# Worker Operation Logger
#
# Logs all Worker operations for audit and debugging.
# Called by Primary before/after delegating to Worker.
#
# Usage:
#   & '.\log-worker-operation.ps1' -Operation "Write" -Target "path/to/file" -Status "started"
#   & '.\log-worker-operation.ps1' -Operation "Write" -Target "path/to/file" -Status "completed" -Result "success"

param(
    [Parameter(Mandatory=$true)]
    [string]$Operation,  # Bash, Read, Write, Edit, Task

    [Parameter(Mandatory=$true)]
    [string]$Target,     # File path, command, or task description

    [Parameter(Mandatory=$true)]
    [ValidateSet('started', 'completed', 'failed')]
    [string]$Status,

    [Parameter(Mandatory=$false)]
    [string]$Result = "",

    [Parameter(Mandatory=$false)]
    [string]$ErrorMessage = ""
)

# Use $CLAUDE_PROJECT_DIR if available, otherwise derive from script location
$repoPath = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { (Get-Item $PSScriptRoot).Parent.Parent.FullName }
$logDir = Join-Path $repoPath ".ai\logs"
$logFile = Join-Path $logDir "worker-operations.log"

# Ensure log directory exists
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
}

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
$entry = @{
    timestamp = $timestamp
    operation = $Operation
    target = $Target
    status = $Status
    result = $Result
    error = $ErrorMessage
}

# Format log line (JSON for easy parsing)
$logLine = $entry | ConvertTo-Json -Compress

# Append to log
Add-Content -Path $logFile -Value $logLine

# Also write human-readable summary
$readableLine = "[$timestamp] [$Status.ToUpper().PadRight(9)] $Operation : $Target"
if ($Result) { $readableLine += " -> $Result" }
if ($ErrorMessage) { $readableLine += " ERROR: $ErrorMessage" }

Add-Content -Path "$logDir\worker-operations-readable.log" -Value $readableLine

# Return for verification
return @{
    Logged = $true
    Timestamp = $timestamp
    LogFile = $logFile
}
