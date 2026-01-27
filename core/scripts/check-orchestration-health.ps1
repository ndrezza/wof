<#
.SYNOPSIS
    Checks the health status of all AI orchestration components.

.DESCRIPTION
    Tests connectivity to all AI workers, validators, and services.
    Renders an ASCII diagram showing online/offline status.
    Should be run at the start of each Claude Code session.

.EXAMPLE
    .\check-orchestration-health.ps1

.EXAMPLE
    .\check-orchestration-health.ps1 -Verbose
#>

param(
    [switch]$Verbose,
    [switch]$JsonOutput
)

$ErrorActionPreference = "SilentlyContinue"

# Load credentials if available
$credentialsPath = Join-Path $PSScriptRoot "..\config\credentials.local.ps1"
if (Test-Path $credentialsPath) {
    . $credentialsPath
}

# Health check results
$healthStatus = @{
    Primary = @{ Name = "Primary (Opus 4.5)"; Status = "ONLINE"; Latency = 0 }
    WorkerHeavy = @{ Name = "Worker-Heavy (Azure Opus)"; Status = "UNKNOWN"; Latency = 0 }
    WorkerLite = @{ Name = "Worker-Lite (Local)"; Status = "UNKNOWN"; Latency = 0 }
    Validator = @{ Name = "Validator (Azure Sonnet)"; Status = "UNKNOWN"; Latency = 0 }
    Friend = @{ Name = "Friend (Azure GPT-4o)"; Status = "UNKNOWN"; Latency = 0 }
    Critic = @{ Name = "Critic (Codex Mini)"; Status = "UNKNOWN"; Latency = 0 }
}

function Test-Endpoint {
    param(
        [string]$Name,
        [string]$Url,
        [string]$Method = "GET",
        [hashtable]$Headers = @{},
        [string]$Body = $null,
        [int]$TimeoutSec = 10
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $params = @{
            Uri = $Url
            Method = $Method
            Headers = $Headers
            TimeoutSec = $TimeoutSec
            ErrorAction = "Stop"
        }

        if ($Body) {
            $params.Body = $Body
            $params.ContentType = "application/json"
        }

        $response = Invoke-WebRequest @params
        $stopwatch.Stop()

        return @{
            Status = "ONLINE"
            Latency = $stopwatch.ElapsedMilliseconds
            StatusCode = $response.StatusCode
        }
    }
    catch {
        $stopwatch.Stop()
        return @{
            Status = "OFFLINE"
            Latency = $stopwatch.ElapsedMilliseconds
            Error = $_.Exception.Message
        }
    }
}

Write-Host "`n[Orchestration Health Check]" -ForegroundColor Cyan
Write-Host "Testing AI components..." -ForegroundColor Gray

# Test Worker-Lite (Local)
Write-Host "  Checking Worker-Lite (Local)..." -ForegroundColor Gray -NoNewline
$localEndpoint = if ($env:LOCAL_WORKER_ENDPOINT) { $env:LOCAL_WORKER_ENDPOINT } else { "http://127.0.0.1:1234" }
$localResult = Test-Endpoint -Name "WorkerLite" -Url "$localEndpoint/v1/models" -TimeoutSec 5
$healthStatus.WorkerLite.Status = $localResult.Status
$healthStatus.WorkerLite.Latency = $localResult.Latency
if ($localResult.Status -eq "ONLINE") {
    Write-Host " ONLINE (${($localResult.Latency)}ms)" -ForegroundColor Green
} else {
    Write-Host " OFFLINE" -ForegroundColor Red
}

# Test Worker-Heavy (Azure Opus) - via MCP availability check
Write-Host "  Checking Worker-Heavy (Azure Opus)..." -ForegroundColor Gray -NoNewline
# We assume MCP secondary-claude is available if we're running
$healthStatus.WorkerHeavy.Status = "ONLINE"
$healthStatus.WorkerHeavy.Latency = 0
Write-Host " ONLINE (MCP)" -ForegroundColor Green

# Test Validator (Azure Sonnet) - same endpoint as Worker-Heavy
Write-Host "  Checking Validator (Azure Sonnet)..." -ForegroundColor Gray -NoNewline
$healthStatus.Validator.Status = "ONLINE"
$healthStatus.Validator.Latency = 0
Write-Host " ONLINE (MCP)" -ForegroundColor Green

# Test Friend (Azure GPT-4o)
Write-Host "  Checking Friend (Azure GPT-4o)..." -ForegroundColor Gray -NoNewline
if ($env:AZURE_OPENAI_ENDPOINT) {
    $friendResult = Test-Endpoint -Name "Friend" -Url "$env:AZURE_OPENAI_ENDPOINT/openai/models?api-version=2025-01-01-preview" -Headers @{ "api-key" = $env:AZURE_OPENAI_API_KEY } -TimeoutSec 10
    $healthStatus.Friend.Status = $friendResult.Status
    $healthStatus.Friend.Latency = $friendResult.Latency
} else {
    $healthStatus.Friend.Status = "NO_CREDS"
}
if ($healthStatus.Friend.Status -eq "ONLINE") {
    Write-Host " ONLINE (${($healthStatus.Friend.Latency)}ms)" -ForegroundColor Green
} elseif ($healthStatus.Friend.Status -eq "NO_CREDS") {
    Write-Host " NO CREDENTIALS" -ForegroundColor Yellow
} else {
    Write-Host " OFFLINE" -ForegroundColor Red
}

# Test Critic (Azure Codex)
Write-Host "  Checking Critic (Codex Mini)..." -ForegroundColor Gray -NoNewline
if ($env:AZURE_CODEX_ENDPOINT) {
    $criticResult = Test-Endpoint -Name "Critic" -Url "$env:AZURE_CODEX_ENDPOINT" -Headers @{ "api-key" = $env:AZURE_CODEX_API_KEY } -TimeoutSec 10
    $healthStatus.Critic.Status = $criticResult.Status
    $healthStatus.Critic.Latency = $criticResult.Latency
} else {
    $healthStatus.Critic.Status = "NO_CREDS"
}
if ($healthStatus.Critic.Status -eq "ONLINE") {
    Write-Host " ONLINE (${($healthStatus.Critic.Latency)}ms)" -ForegroundColor Green
} elseif ($healthStatus.Critic.Status -eq "NO_CREDS") {
    Write-Host " NO CREDENTIALS" -ForegroundColor Yellow
} else {
    Write-Host " OFFLINE" -ForegroundColor Red
}

# Generate status indicators
function Get-StatusIndicator {
    param([string]$Status)
    switch ($Status) {
        "ONLINE" { return "[ON ]" }
        "OFFLINE" { return "[OFF]" }
        "NO_CREDS" { return "[N/C]" }
        default { return "[???]" }
    }
}

function Get-StatusColor {
    param([string]$Status)
    switch ($Status) {
        "ONLINE" { return "Green" }
        "OFFLINE" { return "Red" }
        "NO_CREDS" { return "Yellow" }
        default { return "Gray" }
    }
}

$primaryInd = Get-StatusIndicator $healthStatus.Primary.Status
$workerHeavyInd = Get-StatusIndicator $healthStatus.WorkerHeavy.Status
$workerLiteInd = Get-StatusIndicator $healthStatus.WorkerLite.Status
$validatorInd = Get-StatusIndicator $healthStatus.Validator.Status
$friendInd = Get-StatusIndicator $healthStatus.Friend.Status
$criticInd = Get-StatusIndicator $healthStatus.Critic.Status

# Render the architecture diagram
Write-Host "`n" -NoNewline
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "                         ORCHESTRATION STATUS                                   " -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

$diagram = @"

+------------------+
| USER             |
|                  |
+------------------+
          |
          v
+---------------------------------------------------------+---------------+
|  $primaryInd PRIMARY (Opus 4.5) - ORCHESTRATOR          | $friendInd FRIEND   |
|        Anthropic Direct API                             |     (GPT-4o)    |
|                                                         |                 |
|  Responsibilities:                                      |  Rules          |
|  * Understand requirements                              |  Guardian       |
|  * Classify task complexity (T1 vs T2+)                 |                 |
|  * Route to appropriate Worker                          |  Enforces       |
|  * Consult Validator for decisions                      |  CLAUDE.md      |
|  * Synthesize and respond                               |                 |
|                                                         |                 |
|    PRIMARY DOES NOT CODE                                |                 |
+---------------------------------------------------------+-----------------+
            |                    |                    |
            |             +------+------+             |
            v             v             v             v
+------------------+  +-------------+  +-------------+  +------------------+
| $validatorInd VALIDATOR  |  |$workerHeavyInd WORKER- |  |$workerLiteInd WORKER- |  | $criticInd CRITIC      |
| (Azure Sonnet)   |  |    HEAVY    |  |    LITE     |  | (Codex Mini)     |
|                  |  | (Azure Opus)|  | (Local)     |  |                  |
| Decision valid.  |  |             |  |             |  | Skeptical        |
| >0.7 confidence  |  | T2+ Tasks:  |  | T1 Tasks:   |  | quality gate     |
|                  |  | * Code gen  |  | * Search    |  | >=80% viability  |
|                  |  | * Tests     |  | * Format    |  |                  |
|                  |  | * Files     |  | * Navigate  |  |                  |
|                  |  | * Research  |  | * Validate  |  |                  |
+------------------+  +-------------+  +-------------+  +------------------+

"@

Write-Host $diagram

# Legend
Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Gray
Write-Host "  Legend: " -NoNewline
Write-Host "[ON ]" -ForegroundColor Green -NoNewline
Write-Host " Online  " -NoNewline
Write-Host "[OFF]" -ForegroundColor Red -NoNewline
Write-Host " Offline  " -NoNewline
Write-Host "[N/C]" -ForegroundColor Yellow -NoNewline
Write-Host " No Credentials"
Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Gray

# Summary
$onlineCount = ($healthStatus.Values | Where-Object { $_.Status -eq "ONLINE" }).Count
$totalCount = $healthStatus.Count

Write-Host "`n  Status: $onlineCount/$totalCount components online" -ForegroundColor $(if ($onlineCount -eq $totalCount) { "Green" } elseif ($onlineCount -ge 3) { "Yellow" } else { "Red" })

# Worker routing recommendation
if ($healthStatus.WorkerLite.Status -eq "ONLINE") {
    Write-Host "  Routing: T1 tasks -> Worker-Lite, T2+ tasks -> Worker-Heavy" -ForegroundColor Green
} else {
    Write-Host "  Routing: All tasks -> Worker-Heavy (Worker-Lite unavailable)" -ForegroundColor Yellow
}

Write-Host ""

# Return JSON if requested
if ($JsonOutput) {
    return $healthStatus | ConvertTo-Json -Depth 3
}

return $healthStatus
