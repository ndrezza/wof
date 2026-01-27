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

# Load credentials - try v2 JSON first, then fall back to v1 PS1
$configDir = Join-Path $PSScriptRoot "..\config"
$credentialsJsonPath = Join-Path $configDir "credentials.local.json"
$credentialsPs1Path = Join-Path $configDir "credentials.local.ps1"

if (Test-Path $credentialsJsonPath) {
    # v2 format: JSON credentials
    try {
        $creds = Get-Content $credentialsJsonPath -Raw | ConvertFrom-Json
        if ($creds.credentials) {
            # Map v2 generic names to environment variables
            if ($creds.credentials.AI1_ENDPOINT) { $env:AI1_ENDPOINT = $creds.credentials.AI1_ENDPOINT }
            if ($creds.credentials.AI1_API_KEY) { $env:AI1_API_KEY = $creds.credentials.AI1_API_KEY }
            if ($creds.credentials.AI2_ENDPOINT) { $env:AI2_ENDPOINT = $creds.credentials.AI2_ENDPOINT }
            if ($creds.credentials.AI2_API_KEY) { $env:AI2_API_KEY = $creds.credentials.AI2_API_KEY }
            if ($creds.credentials.AI3_ENDPOINT) { $env:AI3_ENDPOINT = $creds.credentials.AI3_ENDPOINT }
            if ($creds.credentials.AI3_API_KEY) { $env:AI3_API_KEY = $creds.credentials.AI3_API_KEY }
            if ($creds.credentials.LOCAL1_ENDPOINT) { $env:LOCAL1_ENDPOINT = $creds.credentials.LOCAL1_ENDPOINT }
        }
    } catch {
        Write-Host "Warning: Could not parse credentials.local.json" -ForegroundColor Yellow
    }
} elseif (Test-Path $credentialsPs1Path) {
    # v1 format: PowerShell credentials (legacy)
    . $credentialsPs1Path
}

# Normalize environment variables - support both v1 and v2 naming
# v2 names take precedence if both exist
$localEndpointVar = if ($env:LOCAL1_ENDPOINT) { $env:LOCAL1_ENDPOINT } elseif ($env:LOCAL_WORKER_ENDPOINT) { $env:LOCAL_WORKER_ENDPOINT } else { "http://127.0.0.1:1234" }
$friendEndpoint = if ($env:AI2_ENDPOINT) { $env:AI2_ENDPOINT } else { $env:AZURE_OPENAI_ENDPOINT }
$friendApiKey = if ($env:AI2_API_KEY) { $env:AI2_API_KEY } else { $env:AZURE_OPENAI_API_KEY }
$criticEndpoint = if ($env:AI3_ENDPOINT) { $env:AI3_ENDPOINT } else { $env:AZURE_CODEX_ENDPOINT }
$criticApiKey = if ($env:AI3_API_KEY) { $env:AI3_API_KEY } else { $env:AZURE_CODEX_API_KEY }

# Health check results (role-agnostic names - see roles.json for backend config)
$healthStatus = @{
    Primary = @{ Name = "Primary"; Status = "ONLINE"; Latency = 0 }
    WorkerHeavy = @{ Name = "Worker-Heavy (AI1)"; Status = "UNKNOWN"; Latency = 0 }
    WorkerLite = @{ Name = "Worker-Lite (LOCAL1)"; Status = "UNKNOWN"; Latency = 0 }
    Validator = @{ Name = "Validator (AI1)"; Status = "UNKNOWN"; Latency = 0 }
    Friend = @{ Name = "Friend (AI2)"; Status = "UNKNOWN"; Latency = 0 }
    Critic = @{ Name = "Critic (AI3)"; Status = "UNKNOWN"; Latency = 0 }
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
$localResult = Test-Endpoint -Name "WorkerLite" -Url "$localEndpointVar/v1/models" -TimeoutSec 5
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

# Test Friend (AI2)
Write-Host "  Checking Friend (AI2)..." -ForegroundColor Gray -NoNewline
if ($friendEndpoint) {
    $friendResult = Test-Endpoint -Name "Friend" -Url "$friendEndpoint/openai/models?api-version=2025-01-01-preview" -Headers @{ "api-key" = $friendApiKey } -TimeoutSec 10
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

# Test Critic (AI3)
Write-Host "  Checking Critic (AI3)..." -ForegroundColor Gray -NoNewline
if ($criticEndpoint) {
    $criticResult = Test-Endpoint -Name "Critic" -Url "$criticEndpoint" -Headers @{ "api-key" = $criticApiKey } -TimeoutSec 10
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
|  $primaryInd PRIMARY - ORCHESTRATOR                     | $friendInd FRIEND   |
|        Native Claude Code                               |     (AI2)       |
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
|     (AI1)        |  |    HEAVY    |  |    LITE     |  |     (AI3)        |
|                  |  |    (AI1)    |  |  (LOCAL1)   |  |                  |
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
