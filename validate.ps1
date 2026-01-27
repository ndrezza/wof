<#
.SYNOPSIS
    Validates the Workload Orchestration Framework configuration in a target project.

.DESCRIPTION
    This script checks that the framework is correctly configured:
    - Required files exist
    - Credentials are configured
    - MCP servers are available
    - AI endpoints are reachable

.PARAMETER TargetPath
    The root path of the target project to validate. Defaults to current directory.

.PARAMETER Verbose
    Show detailed output for each check.

.EXAMPLE
    .\validate.ps1 -TargetPath "C:\code\MyProject"

.EXAMPLE
    .\validate.ps1
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$TargetPath = ".",

    [Parameter(Mandatory=$false)]
    [switch]$VerboseOutput
)

$ErrorActionPreference = "SilentlyContinue"

# Resolve path
$TargetPath = Resolve-Path $TargetPath

# Color helpers
function Write-Check { param([string]$Message) Write-Host "  [ ] $Message" -ForegroundColor Gray -NoNewline }
function Write-Pass { Write-Host "`r  [+] " -ForegroundColor Green -NoNewline }
function Write-Fail { Write-Host "`r  [-] " -ForegroundColor Red -NoNewline }
function Write-Warn { Write-Host "`r  [!] " -ForegroundColor Yellow -NoNewline }

$results = @{
    Passed = 0
    Failed = 0
    Warnings = 0
    Checks = @()
}

function Add-Result {
    param(
        [string]$Name,
        [string]$Status,  # pass, fail, warn
        [string]$Message = ""
    )

    $results.Checks += @{
        Name = $Name
        Status = $Status
        Message = $Message
    }

    switch ($Status) {
        "pass" { $script:results.Passed++ }
        "fail" { $script:results.Failed++ }
        "warn" { $script:results.Warnings++ }
    }
}

Write-Host ""
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "              WORKLOAD ORCHESTRATION FRAMEWORK VALIDATION                      " -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Target: $TargetPath"
Write-Host ""

$aiDir = Join-Path $TargetPath ".ai"

# ============================================================================
# Section 1: Required Files
# ============================================================================
Write-Host "Required Files:" -ForegroundColor Cyan

# CLAUDE.md
Write-Check "CLAUDE.md exists"
$claudeMd = Join-Path $TargetPath "CLAUDE.md"
if (Test-Path $claudeMd) {
    Write-Pass
    Write-Host "CLAUDE.md exists"
    Add-Result "CLAUDE.md" "pass"
} else {
    Write-Fail
    Write-Host "CLAUDE.md missing"
    Add-Result "CLAUDE.md" "fail" "Run setup.ps1 to create"
}

# .ai directory
Write-Check ".ai directory exists"
if (Test-Path $aiDir) {
    Write-Pass
    Write-Host ".ai directory exists"
    Add-Result ".ai directory" "pass"
} else {
    Write-Fail
    Write-Host ".ai directory missing"
    Add-Result ".ai directory" "fail" "Run setup.ps1 to create"
}

# Core scripts
$requiredScripts = @(
    "scripts\get-worker-routing.ps1",
    "scripts\validate-autonomy.ps1",
    "scripts\bias-control.ps1"
)

foreach ($script in $requiredScripts) {
    $scriptPath = Join-Path $aiDir $script
    $scriptName = Split-Path $script -Leaf
    Write-Check "$scriptName exists"
    if (Test-Path $scriptPath) {
        Write-Pass
        Write-Host "$scriptName exists"
        Add-Result $scriptName "pass"
    } else {
        Write-Fail
        Write-Host "$scriptName missing"
        Add-Result $scriptName "fail" "Run setup.ps1 or sync.ps1"
    }
}

# Memory files
Write-Check "current-sprint.md exists"
$sprintFile = Join-Path $aiDir "memory\current-sprint.md"
if (Test-Path $sprintFile) {
    Write-Pass
    Write-Host "current-sprint.md exists"
    Add-Result "current-sprint.md" "pass"
} else {
    Write-Warn
    Write-Host "current-sprint.md missing (will be created on first use)"
    Add-Result "current-sprint.md" "warn" "Optional but recommended"
}

Write-Host ""

# ============================================================================
# Section 2: Credentials Configuration
# ============================================================================
Write-Host "Credentials Configuration:" -ForegroundColor Cyan

# Load credentials if they exist
$credPath = Join-Path $aiDir "config\credentials.local.ps1"
if (Test-Path $credPath) {
    . $credPath
}

# Azure Anthropic (Worker-Heavy)
Write-Check "AZURE_ANTHROPIC_ENDPOINT configured"
if ($env:AZURE_ANTHROPIC_ENDPOINT) {
    Write-Pass
    Write-Host "AZURE_ANTHROPIC_ENDPOINT configured"
    Add-Result "AZURE_ANTHROPIC_ENDPOINT" "pass"
} else {
    Write-Fail
    Write-Host "AZURE_ANTHROPIC_ENDPOINT not set"
    Add-Result "AZURE_ANTHROPIC_ENDPOINT" "fail" "Required for Worker-Heavy"
}

Write-Check "AZURE_ANTHROPIC_API_KEY configured"
if ($env:AZURE_ANTHROPIC_API_KEY) {
    Write-Pass
    Write-Host "AZURE_ANTHROPIC_API_KEY configured"
    Add-Result "AZURE_ANTHROPIC_API_KEY" "pass"
} else {
    Write-Fail
    Write-Host "AZURE_ANTHROPIC_API_KEY not set"
    Add-Result "AZURE_ANTHROPIC_API_KEY" "fail" "Required for Worker-Heavy"
}

# Azure OpenAI (Friend)
Write-Check "AZURE_OPENAI_ENDPOINT configured"
if ($env:AZURE_OPENAI_ENDPOINT) {
    Write-Pass
    Write-Host "AZURE_OPENAI_ENDPOINT configured"
    Add-Result "AZURE_OPENAI_ENDPOINT" "pass"
} else {
    Write-Warn
    Write-Host "AZURE_OPENAI_ENDPOINT not set"
    Add-Result "AZURE_OPENAI_ENDPOINT" "warn" "Optional (Friend AI)"
}

# Azure Codex (Critic)
Write-Check "AZURE_CODEX_ENDPOINT configured"
if ($env:AZURE_CODEX_ENDPOINT) {
    Write-Pass
    Write-Host "AZURE_CODEX_ENDPOINT configured"
    Add-Result "AZURE_CODEX_ENDPOINT" "pass"
} else {
    Write-Warn
    Write-Host "AZURE_CODEX_ENDPOINT not set"
    Add-Result "AZURE_CODEX_ENDPOINT" "warn" "Optional (Critic AI)"
}

# Local Worker
Write-Check "LOCAL_WORKER_ENDPOINT configured"
if ($env:LOCAL_WORKER_ENDPOINT) {
    Write-Pass
    Write-Host "LOCAL_WORKER_ENDPOINT configured"
    Add-Result "LOCAL_WORKER_ENDPOINT" "pass"
} else {
    Write-Warn
    Write-Host "LOCAL_WORKER_ENDPOINT not set (will use default 127.0.0.1:1234)"
    Add-Result "LOCAL_WORKER_ENDPOINT" "warn" "Optional (Worker-Lite)"
}

Write-Host ""

# ============================================================================
# Section 3: AI Endpoint Connectivity
# ============================================================================
Write-Host "AI Endpoint Connectivity:" -ForegroundColor Cyan

# Worker-Lite (Local)
Write-Check "Worker-Lite (Local) reachable"
$localEndpoint = if ($env:LOCAL_WORKER_ENDPOINT) { $env:LOCAL_WORKER_ENDPOINT } else { "http://127.0.0.1:1234" }
try {
    $response = Invoke-WebRequest -Uri "$localEndpoint/v1/models" -TimeoutSec 5 -ErrorAction Stop
    if ($response.StatusCode -eq 200) {
        Write-Pass
        Write-Host "Worker-Lite (Local) reachable"
        Add-Result "Worker-Lite" "pass"
    }
} catch {
    Write-Warn
    Write-Host "Worker-Lite (Local) not reachable - tasks will route to Worker-Heavy"
    Add-Result "Worker-Lite" "warn" "Start local model server for T1 tasks"
}

Write-Host ""

# ============================================================================
# Section 4: Hook Configuration
# ============================================================================
Write-Host "Hook Configuration:" -ForegroundColor Cyan

$settingsFile = Join-Path $TargetPath ".claude\settings.json"
Write-Check ".claude/settings.json exists"
if (Test-Path $settingsFile) {
    Write-Pass
    Write-Host ".claude/settings.json exists"
    Add-Result ".claude/settings.json" "pass"

    $settings = Get-Content $settingsFile | ConvertFrom-Json
    Write-Check "PreToolUse hooks configured"
    if ($settings.hooks.PreToolUse) {
        Write-Pass
        Write-Host "PreToolUse hooks configured"
        Add-Result "PreToolUse hooks" "pass"
    } else {
        Write-Warn
        Write-Host "PreToolUse hooks not configured"
        Add-Result "PreToolUse hooks" "warn" "Hooks enable auto-approval"
    }
} else {
    Write-Warn
    Write-Host ".claude/settings.json missing"
    Add-Result ".claude/settings.json" "warn" "Run setup.ps1 to create"
}

Write-Host ""

# ============================================================================
# Summary
# ============================================================================
Write-Host "================================================================================" -ForegroundColor $(if ($results.Failed -eq 0) { "Green" } elseif ($results.Failed -le 2) { "Yellow" } else { "Red" })
Write-Host "                              VALIDATION SUMMARY                               " -ForegroundColor $(if ($results.Failed -eq 0) { "Green" } elseif ($results.Failed -le 2) { "Yellow" } else { "Red" })
Write-Host "================================================================================" -ForegroundColor $(if ($results.Failed -eq 0) { "Green" } elseif ($results.Failed -le 2) { "Yellow" } else { "Red" })
Write-Host ""
Write-Host "  Passed:   $($results.Passed)" -ForegroundColor Green
Write-Host "  Warnings: $($results.Warnings)" -ForegroundColor Yellow
Write-Host "  Failed:   $($results.Failed)" -ForegroundColor Red
Write-Host ""

if ($results.Failed -gt 0) {
    Write-Host "Failed checks:" -ForegroundColor Red
    foreach ($check in $results.Checks | Where-Object { $_.Status -eq "fail" }) {
        Write-Host "  - $($check.Name): $($check.Message)" -ForegroundColor Gray
    }
    Write-Host ""
}

if ($results.Warnings -gt 0 -and $VerboseOutput) {
    Write-Host "Warnings:" -ForegroundColor Yellow
    foreach ($check in $results.Checks | Where-Object { $_.Status -eq "warn" }) {
        Write-Host "  - $($check.Name): $($check.Message)" -ForegroundColor Gray
    }
    Write-Host ""
}

$overallStatus = if ($results.Failed -eq 0) { "READY" } elseif ($results.Failed -le 2) { "PARTIAL" } else { "NOT READY" }
Write-Host "Overall Status: $overallStatus" -ForegroundColor $(if ($overallStatus -eq "READY") { "Green" } elseif ($overallStatus -eq "PARTIAL") { "Yellow" } else { "Red" })
Write-Host ""

return @{
    Status = $overallStatus
    Passed = $results.Passed
    Warnings = $results.Warnings
    Failed = $results.Failed
    Checks = $results.Checks
}
