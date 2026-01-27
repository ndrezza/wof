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

# Load credentials and connections
$configDir = Join-Path $PSScriptRoot "..\config"
$credentialsJsonPath = Join-Path $configDir "credentials.local.json"
$connectionsJsonPath = Join-Path $configDir "connections.json"
$rolesJsonPath = Join-Path $configDir "roles.json"
$credentialsPs1Path = Join-Path $configDir "credentials.local.ps1"

# Initialize credential storage
$aiCredentials = @{}
$aiConnections = @{}
$roleConfig = @{}

# Load v2 JSON credentials
if (Test-Path $credentialsJsonPath) {
    try {
        $creds = Get-Content $credentialsJsonPath -Raw | ConvertFrom-Json
        if ($creds.credentials) {
            # Dynamically load AI1-AI10 credentials
            1..10 | ForEach-Object {
                $id = "AI$_"
                $endpointKey = "${id}_ENDPOINT"
                $apiKeyKey = "${id}_API_KEY"

                if ($creds.credentials.$endpointKey) {
                    $aiCredentials[$id] = @{
                        Endpoint = $creds.credentials.$endpointKey
                        ApiKey = $creds.credentials.$apiKeyKey
                    }
                    # Also set environment variables for backward compatibility
                    Set-Variable -Name "env:${endpointKey}" -Value $creds.credentials.$endpointKey -Scope Script
                    if ($creds.credentials.$apiKeyKey) {
                        Set-Variable -Name "env:${apiKeyKey}" -Value $creds.credentials.$apiKeyKey -Scope Script
                    }
                }
            }
        }
    } catch {
        Write-Host "Warning: Could not parse credentials.local.json" -ForegroundColor Yellow
    }
} elseif (Test-Path $credentialsPs1Path) {
    # v1 format: PowerShell credentials (legacy)
    . $credentialsPs1Path
}

# Load connections configuration
if (Test-Path $connectionsJsonPath) {
    try {
        $connJson = Get-Content $connectionsJsonPath -Raw | ConvertFrom-Json
        if ($connJson.connections) {
            $connJson.connections.PSObject.Properties | ForEach-Object {
                $aiConnections[$_.Name] = @{
                    Alias = $_.Value.alias
                    Type = $_.Value.type
                    Description = $_.Value.description
                }
            }
        }
    } catch {
        Write-Host "Warning: Could not parse connections.json" -ForegroundColor Yellow
    }
}

# Load roles configuration
if (Test-Path $rolesJsonPath) {
    try {
        $rolesJson = Get-Content $rolesJsonPath -Raw | ConvertFrom-Json
        if ($rolesJson.roles) {
            $rolesJson.roles.PSObject.Properties | ForEach-Object {
                $roleConfig[$_.Name] = @{
                    Connection = $_.Value.connection
                    Model = $_.Value.model
                }
            }
        }
    } catch {
        Write-Host "Warning: Could not parse roles.json" -ForegroundColor Yellow
    }
}

# Health check results - dynamically built from roles
$healthStatus = @{
    Primary = @{ Name = "Primary"; Status = "ONLINE"; Latency = 0; Connection = "native" }
}

# Add role-based health status entries
$roleNames = @("worker-heavy", "worker-lite", "validator", "critic")
foreach ($roleName in $roleNames) {
    $conn = if ($roleConfig.ContainsKey($roleName)) { $roleConfig[$roleName].Connection } else { "" }
    $displayName = switch ($roleName) {
        "worker-heavy" { "Worker-Heavy" }
        "worker-lite" { "Worker-Lite" }
        "validator" { "Validator" }
        "critic" { "Critic" }
    }

    $connDisplay = if ($conn) { $conn.ToUpper() } else { "N/C" }
    $healthStatus[$roleName] = @{
        Name = "$displayName ($connDisplay)"
        Status = "UNKNOWN"
        Latency = 0
        Connection = $conn
    }
}

function Test-Endpoint {
    param(
        [string]$Name,
        [string]$Url,
        [string]$Type,
        [string]$Method = "GET",
        [hashtable]$Headers = @{},
        [string]$Body = $null,
        [int]$TimeoutSec = 10
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        # Build test URL based on type
        $testUrl = switch ($Type) {
            "azure_ai_foundry_anthropic" { "$Url/models?api-version=2023-06-01" }
            "azure_openai" { "$Url/openai/models?api-version=2025-01-01-preview" }
            "openai_compatible" { "$Url/v1/models" }
            default { "$Url/v1/models" }
        }

        $params = @{
            Uri = $testUrl
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

        # Check for auth errors
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq 401 -or $statusCode -eq 403) {
            return @{
                Status = "AUTH_ERR"
                Latency = $stopwatch.ElapsedMilliseconds
                Error = "Authentication failed"
            }
        }

        return @{
            Status = "OFFLINE"
            Latency = $stopwatch.ElapsedMilliseconds
            Error = $_.Exception.Message
        }
    }
}

Write-Host "`n[Orchestration Health Check]" -ForegroundColor Cyan
Write-Host "Testing AI components..." -ForegroundColor Gray

# Test each role's connection
foreach ($roleName in $roleNames) {
    $roleStatus = $healthStatus[$roleName]
    $conn = $roleStatus.Connection

    Write-Host "  Checking $($roleStatus.Name)..." -ForegroundColor Gray -NoNewline

    if (-not $conn -or $conn -eq "native") {
        $healthStatus[$roleName].Status = "ONLINE"
        $healthStatus[$roleName].Latency = 0
        Write-Host " ONLINE (native)" -ForegroundColor Green
        continue
    }

    # Get AI number from connection (ai1 -> AI1, ai2 -> AI2, etc.)
    $aiNum = $conn -replace 'ai', ''
    $aiId = "AI$aiNum"

    if ($aiCredentials.ContainsKey($aiId)) {
        $cred = $aiCredentials[$aiId]
        $connType = if ($aiConnections.ContainsKey($conn)) { $aiConnections[$conn].Type } else { "openai_compatible" }

        $headers = @{}
        if ($connType -eq "azure_ai_foundry_anthropic" -or $connType -eq "azure_openai") {
            $headers["api-key"] = $cred.ApiKey
        } elseif ($cred.ApiKey) {
            $headers["Authorization"] = "Bearer $($cred.ApiKey)"
        }

        $result = Test-Endpoint -Name $roleName -Url $cred.Endpoint -Type $connType -Headers $headers -TimeoutSec 10
        $healthStatus[$roleName].Status = $result.Status
        $healthStatus[$roleName].Latency = $result.Latency

        if ($result.Status -eq "ONLINE") {
            Write-Host " ONLINE ($($result.Latency)ms)" -ForegroundColor Green
        } elseif ($result.Status -eq "AUTH_ERR") {
            Write-Host " AUTH ERROR" -ForegroundColor Yellow
        } else {
            Write-Host " OFFLINE" -ForegroundColor Red
        }
    } else {
        $healthStatus[$roleName].Status = "NO_CREDS"
        Write-Host " NO CREDENTIALS" -ForegroundColor Yellow
    }
}

# Generate status indicators
function Get-StatusIndicator {
    param([string]$Status)
    switch ($Status) {
        "ONLINE" { return "[ON ]" }
        "OFFLINE" { return "[OFF]" }
        "NO_CREDS" { return "[N/C]" }
        "AUTH_ERR" { return "[AUT]" }
        default { return "[???]" }
    }
}

function Get-StatusColor {
    param([string]$Status)
    switch ($Status) {
        "ONLINE" { return "Green" }
        "OFFLINE" { return "Red" }
        "NO_CREDS" { return "Yellow" }
        "AUTH_ERR" { return "Yellow" }
        default { return "Gray" }
    }
}

$primaryInd = Get-StatusIndicator $healthStatus.Primary.Status
$workerHeavyInd = Get-StatusIndicator $healthStatus["worker-heavy"].Status
$workerLiteInd = Get-StatusIndicator $healthStatus["worker-lite"].Status
$validatorInd = Get-StatusIndicator $healthStatus["validator"].Status
$criticInd = Get-StatusIndicator $healthStatus["critic"].Status

# Get connection IDs for display (used in mapping table)
$workerHeavyConn = if ($roleConfig.ContainsKey("worker-heavy")) { $roleConfig["worker-heavy"].Connection.ToUpper() } else { $null }
$workerLiteConn = if ($roleConfig.ContainsKey("worker-lite")) { $roleConfig["worker-lite"].Connection.ToUpper() } else { $null }
$validatorConn = if ($roleConfig.ContainsKey("validator")) { $roleConfig["validator"].Connection.ToUpper() } else { $null }
$criticConn = if ($roleConfig.ContainsKey("critic")) { $roleConfig["critic"].Connection.ToUpper() } else { $null }

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
+-----------------------------------------------------------------------+
|  $primaryInd PRIMARY - ORCHESTRATOR                                       |
|        Native Claude Code                                             |
|                                                                       |
|  Responsibilities:                                                    |
|  * Understand requirements                                            |
|  * Classify task complexity (T1 vs T2+)                               |
|  * Route to appropriate Worker                                        |
|  * Consult Validator for decisions                                    |
|  * Synthesize and respond                                             |
|                                                                       |
|    PRIMARY DOES NOT CODE                                              |
+-----------------------------------------------------------------------+
            |                    |                    |
            |             +------+------+             |
            v             v             v             v
+------------------+  +-------------+  +-------------+  +------------------+
| $validatorInd VALIDATOR  |  |$workerHeavyInd WORKER- |  |$workerLiteInd WORKER- |  | $criticInd CRITIC      |
|                  |  |    HEAVY    |  |    LITE     |  |                  |
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
Write-Host " No Credentials  " -NoNewline
Write-Host "[AUT]" -ForegroundColor Yellow -NoNewline
Write-Host " Auth Error"
Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Gray

# Role Mapping Table
Write-Host ""
Write-Host "  Role Mapping:" -ForegroundColor Cyan
Write-Host "  +-----------------+------------+--------+" -ForegroundColor Gray
Write-Host "  | Role            | Connection | Status |" -ForegroundColor Gray
Write-Host "  +-----------------+------------+--------+" -ForegroundColor Gray

# Helper to format table row
function Write-TableRow {
    param([string]$Role, [string]$Conn, [string]$Status)
    $connDisplay = if ($Conn) { $Conn.PadRight(10) } else { "(none)".PadRight(10) }
    $statusColor = switch ($Status) {
        "ONLINE" { "Green" }
        "OFFLINE" { "Red" }
        "NO_CREDS" { "Yellow" }
        "AUTH_ERROR" { "Yellow" }
        default { "Gray" }
    }
    $statusDisplay = switch ($Status) {
        "ONLINE" { "ON " }
        "OFFLINE" { "OFF" }
        "NO_CREDS" { "N/C" }
        "AUTH_ERROR" { "AUT" }
        default { "???" }
    }
    Write-Host "  | $($Role.PadRight(15)) | " -NoNewline -ForegroundColor Gray
    Write-Host "$connDisplay" -NoNewline -ForegroundColor $(if ($Conn) { "White" } else { "DarkGray" })
    Write-Host " | " -NoNewline -ForegroundColor Gray
    Write-Host "$statusDisplay" -NoNewline -ForegroundColor $statusColor
    Write-Host "    |" -ForegroundColor Gray
}

Write-TableRow "Worker-Heavy" $workerHeavyConn $healthStatus["worker-heavy"].Status
Write-TableRow "Worker-Lite" $workerLiteConn $healthStatus["worker-lite"].Status
Write-TableRow "Validator" $validatorConn $healthStatus["validator"].Status
Write-TableRow "Critic" $criticConn $healthStatus["critic"].Status

Write-Host "  +-----------------+------------+--------+" -ForegroundColor Gray

# Summary
$onlineCount = ($healthStatus.Values | Where-Object { $_.Status -eq "ONLINE" }).Count
$totalCount = $healthStatus.Count

Write-Host "`n  Status: $onlineCount/$totalCount components online" -ForegroundColor $(if ($onlineCount -eq $totalCount) { "Green" } elseif ($onlineCount -ge 3) { "Yellow" } else { "Red" })

# Worker routing recommendation
if ($healthStatus["worker-lite"].Status -eq "ONLINE") {
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
