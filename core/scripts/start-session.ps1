# ============================================================================
# WOF MANAGED FILE - DO NOT EDIT MANUALLY
# This file is managed by the Workload Orchestration Framework.
# Changes will be overwritten on the next WOF sync/update.
# To customize behavior, use configuration files in .ai/config/
# ============================================================================

<#
.SYNOPSIS
    Initializes a WOF session with health checks and context loading.

.DESCRIPTION
    Performs warmup checks at session start:
    - Tests MCP server connectivity
    - Tests AI endpoint connectivity for each configured role
    - Loads memory bank context (current sprint, conventions)
    - Acknowledges orchestrator role and rules

.PARAMETER Verbose
    Show detailed output for each check.

.PARAMETER JsonOutput
    Return results as JSON for programmatic use.

.EXAMPLE
    .\start-session.ps1

.EXAMPLE
    .\start-session.ps1 -Verbose
#>

param(
    [switch]$Verbose,
    [switch]$JsonOutput
)

$ErrorActionPreference = "SilentlyContinue"

# ============================================================================
# PATHS & INITIALIZATION
# ============================================================================
$aiDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$configDir = Join-Path $aiDir "config"
$memoryDir = Join-Path $aiDir "memory"
$projectRoot = Split-Path $aiDir -Parent
$mcpConfigPath = Join-Path $projectRoot ".mcp.json"

# Credential and config storage
$aiCredentials = @{}
$aiConnections = @{}
$roleConfig = @{}

# Results tracking
$results = @{
    mcp = @{}
    roles = @{}
    context = @{}
    warnings = @()
}

# ============================================================================
# LOAD CONFIGURATION
# ============================================================================
$credentialsJsonPath = Join-Path $configDir "credentials.local.json"
$connectionsJsonPath = Join-Path $configDir "connections.json"
$rolesJsonPath = Join-Path $configDir "roles.json"

# Load credentials
if (Test-Path $credentialsJsonPath) {
    try {
        $creds = Get-Content $credentialsJsonPath -Raw | ConvertFrom-Json
        if ($creds.credentials) {
            1..10 | ForEach-Object {
                $id = "AI$_"
                $endpointKey = "${id}_ENDPOINT"
                $apiKeyKey = "${id}_API_KEY"
                if ($creds.credentials.$endpointKey) {
                    $aiCredentials[$id] = @{
                        Endpoint = $creds.credentials.$endpointKey
                        ApiKey = $creds.credentials.$apiKeyKey
                    }
                }
            }
        }
    } catch { }
}

# Load connections
if (Test-Path $connectionsJsonPath) {
    try {
        $connJson = Get-Content $connectionsJsonPath -Raw | ConvertFrom-Json
        if ($connJson.connections) {
            $connJson.connections.PSObject.Properties | ForEach-Object {
                $aiConnections[$_.Name] = @{
                    Alias = $_.Value.alias
                    Type = $_.Value.type
                }
            }
        }
    } catch { }
}

# Load roles
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
    } catch { }
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================
function Get-ConnectionTypeFromUrl {
    param([string]$Url)
    if (-not $Url) { return "openai_compatible" }
    if ($Url -match "\.services\.ai\.azure\.com/anthropic" -or $Url -match "/anthropic$") {
        return "azure_ai_foundry_anthropic"
    }
    if ($Url -match "\.openai\.azure\.com" -or $Url -match "\.cognitiveservices\.azure\.com") {
        return "azure_openai"
    }
    if ($Url -match "localhost:11434" -or $Url -match ":11434") {
        return "ollama"
    }
    return "openai_compatible"
}

function Test-Endpoint {
    param(
        [string]$Url,
        [string]$Type,
        [hashtable]$Headers = @{},
        [int]$TimeoutSec = 5
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $Method = "GET"
        $Body = $null

        # Build test URL and method based on type
        $testUrl = switch ($Type) {
            "azure_ai_foundry_anthropic" { "$Url/v1/messages" }
            "azure_openai" { "$Url/openai/models?api-version=2025-01-01-preview" }
            "ollama" { "$Url/api/tags" }
            default { "$Url/v1/models" }
        }

        # Anthropic requires POST
        if ($Type -eq "azure_ai_foundry_anthropic") {
            $Method = "POST"
            $Body = '{"model":"claude-sonnet-4-20250514","max_tokens":1,"messages":[{"role":"user","content":"ping"}]}'
            $Headers["anthropic-version"] = "2023-06-01"
            $Headers["Content-Type"] = "application/json"
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

        $null = Invoke-WebRequest @params
        $stopwatch.Stop()

        return @{ Status = "ON"; Latency = $stopwatch.ElapsedMilliseconds }
    }
    catch {
        $stopwatch.Stop()
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq 401 -or $statusCode -eq 403) {
            return @{ Status = "AUTH"; Latency = $stopwatch.ElapsedMilliseconds }
        }
        return @{ Status = "OFF"; Latency = $stopwatch.ElapsedMilliseconds }
    }
}

# ============================================================================
# PHASE 1: MCP HEALTH CHECK
# ============================================================================
Write-Host ""
Write-Host "WOF Session Start" -ForegroundColor Cyan
Write-Host "=================" -ForegroundColor Cyan

if (Test-Path $mcpConfigPath) {
    try {
        $mcpConfig = Get-Content $mcpConfigPath -Raw | ConvertFrom-Json
        if ($mcpConfig.mcpServers) {
            $mcpConfig.mcpServers.PSObject.Properties | ForEach-Object {
                $serverName = $_.Name
                # MCP servers are managed by Claude Code - we just note they're configured
                $results.mcp[$serverName] = @{ Status = "CFG"; Note = "Configured" }
            }
        }
    } catch {
        $results.warnings += "Could not parse .mcp.json"
    }
} else {
    $results.warnings += "No .mcp.json found"
}

# ============================================================================
# PHASE 2: AI ENDPOINT HEALTH CHECK
# ============================================================================
$roleNames = @("primary", "worker-heavy", "worker-lite", "validator", "critic")

foreach ($roleName in $roleNames) {
    $conn = if ($roleConfig.ContainsKey($roleName)) { $roleConfig[$roleName].Connection } else { $null }

    if (-not $conn -or $conn -eq "native") {
        $results.roles[$roleName] = @{ Status = "ON"; Connection = "native"; Latency = 0 }
        continue
    }

    # Get AI number from connection (ai1 -> AI1)
    $aiNum = $conn -replace 'ai', ''
    $aiId = "AI$aiNum"

    if ($aiCredentials.ContainsKey($aiId)) {
        $cred = $aiCredentials[$aiId]
        $connType = if ($aiConnections.ContainsKey($conn) -and $aiConnections[$conn].Type) {
            $aiConnections[$conn].Type
        } else {
            Get-ConnectionTypeFromUrl -Url $cred.Endpoint
        }

        $headers = @{}
        if ($connType -eq "azure_openai") {
            $headers["api-key"] = $cred.ApiKey
        } elseif ($connType -ne "ollama" -and $cred.ApiKey) {
            $headers["Authorization"] = "Bearer $($cred.ApiKey)"
        }

        $result = Test-Endpoint -Url $cred.Endpoint -Type $connType -Headers $headers -TimeoutSec 5
        $results.roles[$roleName] = @{
            Status = $result.Status
            Connection = $conn.ToUpper()
            Latency = $result.Latency
        }
    } else {
        $results.roles[$roleName] = @{ Status = "N/C"; Connection = $conn.ToUpper(); Latency = 0 }
    }
}

# ============================================================================
# PHASE 3: CONTEXT LOADING
# ============================================================================
$sprintPath = Join-Path $memoryDir "current-sprint.md"
$conventionsPath = Join-Path $memoryDir "conventions.md"
$archPath = Join-Path $memoryDir "architecture.md"

$results.context.sprint = Test-Path $sprintPath
$results.context.conventions = Test-Path $conventionsPath
$results.context.architecture = Test-Path $archPath

# Extract sprint summary for verbose mode
$sprintSummary = ""
if ($results.context.sprint) {
    $sprintContent = Get-Content $sprintPath -Raw
    $sprintLines = $sprintContent -split "`n" | Where-Object { $_ -and $_.Trim() -and -not $_.StartsWith("#") } | Select-Object -First 2
    $sprintSummary = ($sprintLines -join " | ").Substring(0, [Math]::Min(60, ($sprintLines -join " | ").Length))
}

# ============================================================================
# OUTPUT: COMPACT TABLE
# ============================================================================

# Role status table
Write-Host ""
Write-Host "Roles" -ForegroundColor White
Write-Host "+----------------+------+--------+--------+" -ForegroundColor DarkGray
Write-Host "| Role           | Conn | Status | Latency|" -ForegroundColor DarkGray
Write-Host "+----------------+------+--------+--------+" -ForegroundColor DarkGray

foreach ($roleName in $roleNames) {
    $r = $results.roles[$roleName]
    $displayName = switch ($roleName) {
        "primary" { "Primary" }
        "worker-heavy" { "Worker-Heavy" }
        "worker-lite" { "Worker-Lite" }
        "validator" { "Validator" }
        "critic" { "Critic" }
    }

    $connDisplay = if ($r.Connection) { $r.Connection.PadRight(4).Substring(0,4) } else { "N/C " }
    $statusColor = switch ($r.Status) {
        "ON" { "Green" }
        "OFF" { "Red" }
        "AUTH" { "Yellow" }
        "N/C" { "DarkGray" }
        default { "Gray" }
    }
    $latencyDisplay = if ($r.Latency -gt 0) { "$($r.Latency)ms".PadLeft(6) } else { "  -   " }

    Write-Host "| $($displayName.PadRight(14)) | " -NoNewline -ForegroundColor Gray
    Write-Host "$connDisplay" -NoNewline -ForegroundColor White
    Write-Host " | " -NoNewline -ForegroundColor Gray
    Write-Host "$($r.Status.PadRight(6))" -NoNewline -ForegroundColor $statusColor
    Write-Host " | " -NoNewline -ForegroundColor Gray
    Write-Host "$latencyDisplay" -NoNewline -ForegroundColor DarkGray
    Write-Host "|" -ForegroundColor Gray
}

Write-Host "+----------------+------+--------+--------+" -ForegroundColor DarkGray

# MCP status (compact)
if ($results.mcp.Count -gt 0) {
    Write-Host ""
    Write-Host "MCP: " -NoNewline -ForegroundColor White
    $mcpNames = $results.mcp.Keys -join ", "
    Write-Host $mcpNames -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "MCP: " -NoNewline -ForegroundColor White
    Write-Host "none configured" -ForegroundColor DarkGray
}

# Context status (compact)
$contextLoaded = @()
if ($results.context.sprint) { $contextLoaded += "sprint" }
if ($results.context.conventions) { $contextLoaded += "conventions" }
if ($results.context.architecture) { $contextLoaded += "architecture" }

Write-Host "Context: " -NoNewline -ForegroundColor White
if ($contextLoaded.Count -gt 0) {
    Write-Host ($contextLoaded -join ", ") -ForegroundColor Green
} else {
    Write-Host "none loaded" -ForegroundColor DarkGray
}

# Sprint summary in verbose mode
if ($Verbose -and $sprintSummary) {
    Write-Host "  Sprint: $sprintSummary" -ForegroundColor DarkGray
}

# ============================================================================
# PHASE 4: ROLE ACKNOWLEDGMENT
# ============================================================================
Write-Host ""
Write-Host "Role: " -NoNewline -ForegroundColor White
Write-Host "Orchestrator" -ForegroundColor Cyan

if ($Verbose) {
    Write-Host "  - Understand before acting" -ForegroundColor DarkGray
    Write-Host "  - Verify work objectively" -ForegroundColor DarkGray
    Write-Host "  - Delegate: T1->Lite, T2+->Heavy" -ForegroundColor DarkGray
    Write-Host "  - Quality gates non-negotiable" -ForegroundColor DarkGray
}

# ============================================================================
# FINAL STATUS
# ============================================================================
$onlineCount = ($results.roles.Values | Where-Object { $_.Status -eq "ON" }).Count
$totalRoles = $results.roles.Count

Write-Host ""
if ($results.warnings.Count -gt 0) {
    Write-Host "Warnings: " -NoNewline -ForegroundColor Yellow
    Write-Host ($results.warnings -join "; ") -ForegroundColor Yellow
}

$ready = ($onlineCount -ge 1)  # At least primary should be online
$statusText = if ($ready) { "Ready ($onlineCount/$totalRoles roles online)" } else { "Degraded" }
$statusColor = if ($onlineCount -eq $totalRoles) { "Green" } elseif ($ready) { "Yellow" } else { "Red" }

Write-Host "Status: " -NoNewline -ForegroundColor White
Write-Host $statusText -ForegroundColor $statusColor
Write-Host ""

# Return JSON if requested
if ($JsonOutput) {
    return $results | ConvertTo-Json -Depth 4
}
