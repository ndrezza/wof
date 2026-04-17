# ============================================================================
# WOF MANAGED FILE - DO NOT EDIT MANUALLY
# This file is managed by the Workload Orchestration Framework.
# Changes will be overwritten on the next WOF sync/update.
# To customize behavior, use configuration files in .ai/config/
# ============================================================================

<#
.SYNOPSIS
    Interactive configuration wizard for WOF AI connections.

.DESCRIPTION
    Allows users to:
    - Add/manage up to 10 AI connections (AI1-AI10)
    - Test connections in real-time
    - Map roles to specific AI connections

    All connections are uniform - no special "local" category.
    Connection type determines behavior (cloud vs local, key required vs optional).

    Menu-based navigation with back option at every level.

.PARAMETER Help
    Show usage information.

.PARAMETER TestOnly
    Only test existing connections, skip configuration.

.PARAMETER Quick
    Skip confirmations for faster configuration.

.EXAMPLE
    .\configure-wizard.ps1

.EXAMPLE
    .\configure-wizard.ps1 -TestOnly

.EXAMPLE
    .\configure-wizard.ps1 -Quick
#>

param(
    [switch]$Help,
    [switch]$TestOnly,
    [switch]$Quick
)

$ErrorActionPreference = "SilentlyContinue"

# Track unsaved changes
$script:hasUnsavedChanges = $false

# ============================================================================
# Output Helpers
# ============================================================================

function Write-Header {
    param([string]$Title)
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "               $Title" -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Check {
    param([string]$Message)
    Write-Host "[*] $Message" -ForegroundColor Gray
}

function Write-Pass {
    param([string]$Message)
    Write-Host "[+] $Message" -ForegroundColor Green
}

function Write-Fail {
    param([string]$Message)
    Write-Host "[-] $Message" -ForegroundColor Red
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[!] $Message" -ForegroundColor Yellow
}

function Write-Info {
    param([string]$Message)
    Write-Host "    $Message" -ForegroundColor Gray
}

# ============================================================================
# URL Pattern Auto-Detection
# ============================================================================

function Get-ConnectionTypeFromUrl {
    param([string]$Url)

    if (-not $Url) { return "openai_compatible" }

    # Azure AI Foundry with Anthropic models
    if ($Url -match "\.services\.ai\.azure\.com/anthropic" -or $Url -match "/anthropic$") {
        return "azure_ai_foundry_anthropic"
    }
    # Azure OpenAI Service
    if ($Url -match "\.openai\.azure\.com" -or $Url -match "\.cognitiveservices\.azure\.com") {
        return "azure_openai"
    }
    # Default to OpenAI-compatible
    return "openai_compatible"
}

# ============================================================================
# Configuration Paths
# ============================================================================

$configDir = Join-Path $PSScriptRoot "..\config"
$connectionsPath = Join-Path $configDir "connections.json"
$rolesPath = Join-Path $configDir "roles.json"
$credentialsPath = Join-Path $configDir "credentials.local.json"

# MCP configuration - look for .mcp.json in repo root or WOI root
$repoRoot = (Get-Item $PSScriptRoot).Parent.Parent.FullName
$mcpPath = Join-Path $repoRoot ".mcp.json"

# ============================================================================
# Show Help
# ============================================================================

if ($Help) {
    Write-Host @"

WOF Configuration Wizard
========================

Usage: .\configure-wizard.ps1 [options]

Options:
    -Help       Show this help message
    -TestOnly   Only test existing connections
    -Quick      Skip confirmations

The wizard will guide you through:
1. Managing AI connections (AI1-AI10)
2. Configuring role mappings
3. Setting up Azure DevOps MCP server
4. Setting up Notifications (Teams/email)
5. Testing connectivity

AI Connection Types:
    azure_ai_foundry_anthropic  - Claude on Azure (key required)
    azure_openai                - GPT on Azure (key required)
    openai_compatible           - OpenAI-compatible API (Ollama, vLLM, llama.cpp)

MCP Servers:
    azure-devops                - Azure DevOps work items, repos, PRs
    wof-notifications           - Teams chat and email notifications

"@
    exit 0
}

# ============================================================================
# Configuration Loading/Saving
# ============================================================================

function Load-Configuration {
    $config = @{
        connections = @{}
        roles = @{}
        credentials = @{}
    }

    # Load connections
    if (Test-Path $connectionsPath) {
        try {
            $connJson = Get-Content $connectionsPath -Raw | ConvertFrom-Json
            if ($connJson.connections) {
                # Convert PSObject to hashtable
                $connJson.connections.PSObject.Properties | ForEach-Object {
                    $config.connections[$_.Name] = @{
                        alias = $_.Value.alias
                        description = $_.Value.description
                        type = $_.Value.type
                        endpoint = $_.Value.endpoint
                        api_key = $_.Value.api_key
                        api_version = $_.Value.api_version
                        models = $_.Value.models
                        default_model = $_.Value.default_model
                    }
                }
            }
        } catch {
            Write-Warn "Could not parse connections.json: $_"
        }
    }

    # Load roles
    if (Test-Path $rolesPath) {
        try {
            $rolesJson = Get-Content $rolesPath -Raw | ConvertFrom-Json
            if ($rolesJson.roles) {
                $rolesJson.roles.PSObject.Properties | ForEach-Object {
                    $config.roles[$_.Name] = @{
                        description = $_.Value.description
                        connection = $_.Value.connection
                        model = $_.Value.model
                        mcp_server = $_.Value.mcp_server
                        fallback = $_.Value.fallback
                        threshold = $_.Value.threshold
                        restrictions = $_.Value.restrictions
                    }
                }
            }
            if ($rolesJson.orchestration_mode) {
                $config.orchestration_mode = $rolesJson.orchestration_mode
            }
            if ($rolesJson.orchestration_custom_priority) {
                $config.orchestration_custom_priority = $rolesJson.orchestration_custom_priority
            }
        } catch {
            Write-Warn "Could not parse roles.json: $_"
        }
    }

    # Load credentials
    if (Test-Path $credentialsPath) {
        try {
            $credsJson = Get-Content $credentialsPath -Raw | ConvertFrom-Json
            if ($credsJson.credentials) {
                $credsJson.credentials.PSObject.Properties | ForEach-Object {
                    $config.credentials[$_.Name] = $_.Value
                }
            }
        } catch {
            Write-Warn "Could not parse credentials.local.json: $_"
        }
    }

    return $config
}

function Save-Connections {
    param([hashtable]$Connections)

    # Build connections object
    $connectionsObj = [ordered]@{
        '$schema' = "https://json-schema.org/draft/2020-12/schema"
        version = "2.0.0"
        description = "Role-agnostic AI connection definitions. See roles.json for role-to-connection mapping."
        connections = [ordered]@{}
    }

    # Add each connection in order (ai1-ai10, then native)
    1..10 | ForEach-Object {
        $id = "ai$_"
        if ($Connections.ContainsKey($id)) {
            $conn = $Connections[$id]
            $connectionsObj.connections[$id] = [ordered]@{
                alias = $conn.alias
                description = $conn.description
                type = $conn.type
                endpoint = $conn.endpoint
                api_key = $conn.api_key
            }
            if ($conn.api_version) {
                $connectionsObj.connections[$id].api_version = $conn.api_version
            }
            if ($conn.models) {
                $connectionsObj.connections[$id].models = $conn.models
            }
            if ($conn.default_model) {
                $connectionsObj.connections[$id].default_model = $conn.default_model
            }
        }
    }

    # Always include native
    $connectionsObj.connections["native"] = [ordered]@{
        alias = "Claude Code Native"
        description = "Native Claude Code connection (no external API)"
        type = "claude_code_native"
        models = @{
            "claude-opus-4-5-20251101" = @{}
        }
        default_model = "claude-opus-4-5-20251101"
    }

    $json = $connectionsObj | ConvertTo-Json -Depth 10
    Set-Content -Path $connectionsPath -Value $json -Encoding UTF8
}

function Save-Credentials {
    param([hashtable]$Credentials)

    $credsObj = [ordered]@{
        '$schema' = "https://json-schema.org/draft/2020-12/schema"
        version = "2.0.0"
        description = "Local credentials file. This file is gitignored."
        credentials = [ordered]@{}
    }

    # Add credentials in order (AI1-AI10)
    1..10 | ForEach-Object {
        $endpointKey = "AI${_}_ENDPOINT"
        $apiKeyKey = "AI${_}_API_KEY"

        if ($Credentials.ContainsKey($endpointKey) -and $Credentials[$endpointKey]) {
            $credsObj.credentials[$endpointKey] = $Credentials[$endpointKey]
        }
        if ($Credentials.ContainsKey($apiKeyKey) -and $Credentials[$apiKeyKey]) {
            $credsObj.credentials[$apiKeyKey] = $Credentials[$apiKeyKey]
        }
    }

    $json = $credsObj | ConvertTo-Json -Depth 10
    Set-Content -Path $credentialsPath -Value $json -Encoding UTF8
}

function Save-Roles {
    param(
        [hashtable]$Roles,
        [string]$OrchestrationMode,
        [string]$OrchestrationCustomPriority
    )

    $rolesObj = [ordered]@{
        '$schema' = "https://json-schema.org/draft/2020-12/schema"
        version = "2.0.0"
        description = "Role-to-connection mapping. Defines which AI connection each role uses."
        orchestration_mode = $OrchestrationMode
        orchestration_custom_priority = $OrchestrationCustomPriority
        roles = [ordered]@{}
    }

    # Define role order
    $roleOrder = @("primary", "worker-heavy", "worker-lite", "validator", "critic")

    foreach ($roleName in $roleOrder) {
        if ($Roles.ContainsKey($roleName)) {
            $role = $Roles[$roleName]
            $roleEntry = [ordered]@{
                description = $role.description
                connection = $role.connection
            }
            if ($role.model) { $roleEntry.model = $role.model }
            if ($role.mcp_server) { $roleEntry.mcp_server = $role.mcp_server }
            if ($role.fallback) { $roleEntry.fallback = $role.fallback }
            if ($role.threshold) { $roleEntry.threshold = $role.threshold }
            if ($role.restrictions) { $roleEntry.restrictions = $role.restrictions }

            $rolesObj.roles[$roleName] = $roleEntry
        }
    }

    $json = $rolesObj | ConvertTo-Json -Depth 10
    Set-Content -Path $rolesPath -Value $json -Encoding UTF8
}

# ============================================================================
# Connection Testing
# ============================================================================

function Test-AIEndpoint {
    param(
        [string]$Endpoint,
        [string]$ApiKey,
        [string]$Type
    )

    $result = @{
        Status = "OFFLINE"
        Latency = 0
        Error = $null
    }

    if (-not $Endpoint) {
        $result.Status = "N/C"
        return $result
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $headers = @{}
        $testUrl = $Endpoint
        $method = "GET"
        $body = $null

        switch ($Type) {
            "azure_ai_foundry_anthropic" {
                # Azure AI Foundry Anthropic uses Bearer token and requires POST to /v1/messages
                if ($ApiKey) {
                    $headers["Authorization"] = "Bearer $ApiKey"
                }
                $headers["anthropic-version"] = "2023-06-01"
                $headers["Content-Type"] = "application/json"
                $testUrl = "$Endpoint/v1/messages"
                $method = "POST"
                $body = '{"model":"claude-opus-4-5-20251101","max_tokens":1,"messages":[{"role":"user","content":"ping"}]}'
            }
            "azure_openai" {
                # Azure OpenAI uses api-key header
                $headers["api-key"] = $ApiKey
                $testUrl = "$Endpoint/openai/models?api-version=2025-01-01-preview"
            }
            "openai_compatible" {
                # OpenAI-compatible APIs typically have /v1/models
                if ($ApiKey) {
                    $headers["Authorization"] = "Bearer $ApiKey"
                }
                $testUrl = "$Endpoint/v1/models"
            }
            default {
                $testUrl = "$Endpoint/v1/models"
            }
        }

        $params = @{
            Uri = $testUrl
            Method = $method
            Headers = $headers
            TimeoutSec = 10
            ErrorAction = "Stop"
        }

        if ($body) {
            $params.Body = $body
            $params.ContentType = "application/json"
        }

        $response = Invoke-WebRequest @params
        $stopwatch.Stop()

        $result.Status = "ONLINE"
        $result.Latency = $stopwatch.ElapsedMilliseconds
    }
    catch {
        $stopwatch.Stop()
        $result.Latency = $stopwatch.ElapsedMilliseconds
        $result.Error = $_.Exception.Message

        # Check for specific error codes that indicate the service is reachable
        if ($_.Exception.Response.StatusCode.value__ -eq 401 -or
            $_.Exception.Response.StatusCode.value__ -eq 403) {
            $result.Status = "AUTH_ERR"
            $result.Error = "Authentication failed - check API key"
        }
    }

    return $result
}

# ============================================================================
# Display Functions
# ============================================================================

function Show-ConnectionsTable {
    param([hashtable]$Config)

    Write-Host ""
    Write-Host "+------+-------------------+----------------------------------+------------------------+----------+" -ForegroundColor Gray
    Write-Host "| ID   | Alias             | Endpoint                         | Type                   | Status   |" -ForegroundColor Gray
    Write-Host "+------+-------------------+----------------------------------+------------------------+----------+" -ForegroundColor Gray

    $configuredCount = 0

    1..10 | ForEach-Object {
        $id = "ai$_"
        $displayId = "AI$_".PadRight(4)

        $conn = $Config.connections[$id]
        $endpointKey = "AI${_}_ENDPOINT"
        $apiKeyKey = "AI${_}_API_KEY"

        $endpoint = $Config.credentials[$endpointKey]
        $apiKey = $Config.credentials[$apiKeyKey]

        if ($conn -and $conn.alias -and $endpoint) {
            $alias = $conn.alias
            if ($alias.Length -gt 17) { $alias = $alias.Substring(0, 14) + "..." }
            $alias = $alias.PadRight(17)

            $displayEndpoint = $endpoint
            if ($displayEndpoint.Length -gt 32) { $displayEndpoint = $displayEndpoint.Substring(0, 29) + "..." }
            $displayEndpoint = $displayEndpoint.PadRight(32)

            $type = if ($conn.type) { $conn.type } else { "-" }
            if ($type.Length -gt 22) { $type = $type.Substring(0, 19) + "..." }
            $type = $type.PadRight(22)

            # Test connection
            $testResult = Test-AIEndpoint -Endpoint $endpoint -ApiKey $apiKey -Type $conn.type
            $status = switch ($testResult.Status) {
                "ONLINE"   { "[ONLINE]" }
                "AUTH_ERR" { "[AUTH!]" }
                default    { "[OFFLINE]" }
            }
            $statusColor = switch ($testResult.Status) {
                "ONLINE"   { "Green" }
                "AUTH_ERR" { "Yellow" }
                default    { "Red" }
            }

            Write-Host "| $displayId | $alias | $displayEndpoint | $type | " -NoNewline
            Write-Host $status.PadRight(8) -ForegroundColor $statusColor -NoNewline
            Write-Host " |"

            $configuredCount++
        } else {
            $alias = "(not configured)".PadRight(17)
            $displayEndpoint = "-".PadRight(32)
            $type = "-".PadRight(22)
            $status = "[N/C]".PadRight(8)

            Write-Host "| $displayId | " -NoNewline
            Write-Host $alias -ForegroundColor DarkGray -NoNewline
            Write-Host " | " -NoNewline
            Write-Host $displayEndpoint -ForegroundColor DarkGray -NoNewline
            Write-Host " | " -NoNewline
            Write-Host $type -ForegroundColor DarkGray -NoNewline
            Write-Host " | " -NoNewline
            Write-Host $status -ForegroundColor Yellow -NoNewline
            Write-Host " |"
        }
    }

    Write-Host "+------+-------------------+----------------------------------+------------------------+----------+" -ForegroundColor Gray
    Write-Host ""

    return $configuredCount
}

function Show-RoleMappings {
    param([hashtable]$Config)

    Write-Host ""
    Write-Host "Current Role Mappings:" -ForegroundColor Cyan

    if ($Config.orchestration_mode) {
        Write-Host "  Orchestration Mode: $($Config.orchestration_mode)" -ForegroundColor Gray
        if ($Config.orchestration_custom_priority) {
            Write-Host "  Custom Priority:    $($Config.orchestration_custom_priority)" -ForegroundColor DarkGray
        }
    }

    Write-Host ""

    $roleOrder = @("primary", "worker-heavy", "worker-lite", "validator", "critic")

    foreach ($roleName in $roleOrder) {
        if ($Config.roles.ContainsKey($roleName)) {
            $role = $Config.roles[$roleName]
            $conn = $role.connection

            # Get alias if available
            $alias = ""
            if ($conn -eq "native") {
                $alias = "Claude Code Native"
            } elseif ($Config.connections.ContainsKey($conn)) {
                $alias = $Config.connections[$conn].alias
            }

            $displayName = $roleName.PadRight(14)
            $connDisplay = $conn.ToUpper().PadRight(8)

            Write-Host "    $displayName -> " -NoNewline
            Write-Host $connDisplay -ForegroundColor Cyan -NoNewline
            if ($alias) {
                Write-Host " ($alias)" -ForegroundColor Gray
            } else {
                Write-Host ""
            }
        }
    }
    Write-Host ""
}

# ============================================================================
# Interactive Add/Edit Connection
# ============================================================================

function Edit-AIConnection {
    param(
        [int]$SlotNumber,
        [hashtable]$Config
    )

    $id = "ai$SlotNumber"
    $endpointKey = "AI${SlotNumber}_ENDPOINT"
    $apiKeyKey = "AI${SlotNumber}_API_KEY"
    $existingConn = $Config.connections[$id]
    $existingEndpoint = $Config.credentials[$endpointKey]
    $existingApiKey = $Config.credentials[$apiKeyKey]

    Write-Host ""
    Write-Host "--- Configuring AI$SlotNumber ---" -ForegroundColor Cyan
    Write-Host ""

    # Alias
    $currentAlias = if ($existingConn -and $existingConn.alias) { $existingConn.alias } else { "AI$SlotNumber" }
    Write-Host "Alias (friendly name) [$currentAlias]: " -NoNewline
    $alias = Read-Host
    if (-not $alias) {
        $alias = $currentAlias
    }

    # Endpoint first - so we can auto-detect type
    $currentEndpoint = if ($existingEndpoint) { $existingEndpoint } else { "" }
    Write-Host ""
    if ($currentEndpoint) {
        Write-Host "Endpoint URL [$currentEndpoint]: " -NoNewline
    } else {
        Write-Host "Endpoint URL: " -NoNewline
    }
    $endpoint = Read-Host
    if (-not $endpoint -and $currentEndpoint) {
        $endpoint = $currentEndpoint
    }

    if (-not $endpoint) {
        Write-Warn "Endpoint is required. Aborting."
        return $Config
    }

    # Auto-detect type from URL
    $detectedType = Get-ConnectionTypeFromUrl -Url $endpoint
    $currentType = if ($existingConn -and $existingConn.type) { $existingConn.type } else { $detectedType }
    $detectedLabel = switch ($currentType) {
        "azure_ai_foundry_anthropic" { "Azure AI Foundry Anthropic" }
        "azure_openai" { "Azure OpenAI" }
        "openai_compatible" { "OpenAI-compatible" }
        default { "OpenAI-compatible" }
    }

    # Type selection with current/auto-detected default
    Write-Host ""
    Write-Host "Type (current: $detectedLabel):" -ForegroundColor Cyan
    Write-Host "  [1] azure_ai_foundry_anthropic (Claude on Azure)"
    Write-Host "  [2] azure_openai (GPT on Azure)"
    Write-Host "  [3] openai_compatible (Ollama, vLLM, llama.cpp)"
    Write-Host ""
    $defaultChoice = switch ($currentType) {
        "azure_ai_foundry_anthropic" { "1" }
        "azure_openai" { "2" }
        "openai_compatible" { "3" }
        default { "3" }
    }
    Write-Host "Select [1-3, default=$defaultChoice]: " -NoNewline
    $typeChoice = Read-Host

    if (-not $typeChoice) {
        $typeChoice = $defaultChoice
    }

    $type = switch ($typeChoice) {
        "1" { "azure_ai_foundry_anthropic" }
        "2" { "azure_openai" }
        "3" { "openai_compatible" }
        default { $currentType }
    }

    # API Key (optional for openai_compatible)
    Write-Host ""
    $hasExistingKey = if ($existingApiKey) { "(has existing key)" } else { "" }
    if ($type -eq "openai_compatible") {
        Write-Host "API Key (optional, Enter to keep existing) ${hasExistingKey}: " -NoNewline
    } else {
        Write-Host "API Key (Enter to keep existing) ${hasExistingKey}: " -NoNewline
    }
    $apiKey = Read-Host
    if (-not $apiKey -and $existingApiKey) {
        $apiKey = $existingApiKey
    }

    # Model
    Write-Host ""
    $currentModel = if ($existingConn -and $existingConn.default_model) {
        $existingConn.default_model
    } else {
        switch ($type) {
            "azure_ai_foundry_anthropic" { "claude-opus-4-5-20251101" }
            "azure_openai" { "gpt-4o" }
            "openai_compatible" { "deepseek-coder-v2-lite-instruct" }
            default { "" }
        }
    }
    Write-Host "Model [$currentModel]: " -NoNewline
    $model = Read-Host
    if (-not $model) {
        $model = $currentModel
    }

    # Description
    $description = switch ($type) {
        "azure_ai_foundry_anthropic" { "Azure AI Foundry with Anthropic models" }
        "azure_openai" { "Azure OpenAI Service" }
        "openai_compatible" { "OpenAI-compatible API server" }
        default { "AI connection" }
    }

    # Update config
    $Config.connections[$id] = @{
        alias = $alias
        description = $description
        type = $type
        endpoint = "`${AI${SlotNumber}_ENDPOINT}"
        api_key = if ($apiKey) { "`${AI${SlotNumber}_API_KEY}" } else { "" }
        models = @{
            $model = @{
                context_window = 128000
            }
        }
        default_model = $model
    }

    # Add API version for Azure
    if ($type -eq "azure_ai_foundry_anthropic") {
        $Config.connections[$id].api_version = "2023-06-01"
    } elseif ($type -eq "azure_openai") {
        $Config.connections[$id].api_version = "2025-01-01-preview"
    }

    # Update credentials
    $Config.credentials[$endpointKey] = $endpoint
    if ($apiKey) {
        $Config.credentials[$apiKeyKey] = $apiKey
    }

    # Test connection
    Write-Host ""
    Write-Check "Testing connection..."
    $testResult = Test-AIEndpoint -Endpoint $endpoint -ApiKey $apiKey -Type $type

    if ($testResult.Status -eq "ONLINE") {
        Write-Pass "ONLINE ($($testResult.Latency)ms)"
    } elseif ($testResult.Status -eq "AUTH_ERR") {
        Write-Warn "AUTH ERROR - $($testResult.Error)"
    } else {
        Write-Fail "OFFLINE - $($testResult.Error)"
    }

    $script:hasUnsavedChanges = $true
    return $Config
}

function Rename-AIConnection {
    param(
        [int]$SlotNumber,
        [hashtable]$Config
    )

    $id = "ai$SlotNumber"
    $existingConn = $Config.connections[$id]

    if (-not $existingConn) {
        Write-Warn "AI$SlotNumber is not configured."
        return $Config
    }

    $currentAlias = if ($existingConn.alias) { $existingConn.alias } else { "AI$SlotNumber" }
    Write-Host ""
    Write-Host "Current alias: $currentAlias" -ForegroundColor Gray
    Write-Host "New alias: " -NoNewline
    $newAlias = Read-Host

    if ($newAlias) {
        $Config.connections[$id].alias = $newAlias
        Write-Pass "Renamed AI$SlotNumber to '$newAlias'"
        $script:hasUnsavedChanges = $true
    } else {
        Write-Info "No change made."
    }

    return $Config
}

function Remove-AIConnection {
    param(
        [int]$SlotNumber,
        [hashtable]$Config
    )

    $id = "ai$SlotNumber"
    $endpointKey = "AI${SlotNumber}_ENDPOINT"
    $apiKeyKey = "AI${SlotNumber}_API_KEY"
    $existingConn = $Config.connections[$id]

    if (-not $existingConn -or -not $Config.credentials[$endpointKey]) {
        Write-Warn "AI$SlotNumber is not configured."
        return $Config
    }

    $alias = if ($existingConn.alias) { $existingConn.alias } else { "AI$SlotNumber" }
    Write-Host ""
    Write-Host "Delete AI$SlotNumber ($alias)? This cannot be undone." -ForegroundColor Yellow
    Write-Host "Type 'DELETE' to confirm: " -NoNewline
    $confirm = Read-Host

    if ($confirm -eq "DELETE") {
        $Config.connections.Remove($id)
        $Config.credentials.Remove($endpointKey)
        $Config.credentials.Remove($apiKeyKey)

        # Check if any roles use this connection and warn
        $affectedRoles = @()
        foreach ($roleName in $Config.roles.Keys) {
            if ($Config.roles[$roleName].connection -eq $id) {
                $affectedRoles += $roleName
            }
        }
        if ($affectedRoles.Count -gt 0) {
            Write-Warn "The following roles used this connection and need reassignment: $($affectedRoles -join ', ')"
        }

        Write-Pass "AI$SlotNumber deleted."
        $script:hasUnsavedChanges = $true
    } else {
        Write-Info "Deletion cancelled."
    }

    return $Config
}

function Test-SingleConnection {
    param(
        [int]$SlotNumber,
        [hashtable]$Config
    )

    $id = "ai$SlotNumber"
    $endpointKey = "AI${SlotNumber}_ENDPOINT"
    $apiKeyKey = "AI${SlotNumber}_API_KEY"

    $endpoint = $Config.credentials[$endpointKey]
    $apiKey = $Config.credentials[$apiKeyKey]
    $conn = $Config.connections[$id]

    if (-not $endpoint) {
        Write-Warn "AI$SlotNumber is not configured."
        return
    }

    $alias = if ($conn -and $conn.alias) { $conn.alias } else { "AI$SlotNumber" }
    $type = if ($conn -and $conn.type) { $conn.type } else { "openai_compatible" }

    Write-Host ""
    Write-Check "Testing AI$SlotNumber ($alias)..."
    $testResult = Test-AIEndpoint -Endpoint $endpoint -ApiKey $apiKey -Type $type

    if ($testResult.Status -eq "ONLINE") {
        Write-Pass "ONLINE - $($testResult.Latency)ms latency"
    } elseif ($testResult.Status -eq "AUTH_ERR") {
        Write-Warn "AUTH ERROR - $($testResult.Error)"
    } else {
        Write-Fail "OFFLINE - $($testResult.Error)"
    }
}

# ============================================================================
# Model Capability Matching
# ============================================================================

function Find-CapabilityMatch {
    param(
        [string]$ModelName,
        [hashtable]$CapabilityModels
    )

    if (-not $ModelName) { return $null }

    # Exact match
    if ($CapabilityModels.ContainsKey($ModelName)) { return $ModelName }

    # Strip date suffix (e.g., claude-opus-4-5-20251101 -> claude-opus-4-5)
    $stripped = $ModelName -replace '-\d{8,}$', ''
    if ($stripped -ne $ModelName -and $CapabilityModels.ContainsKey($stripped)) { return $stripped }

    # Longest prefix match (minimum 8 chars)
    $bestMatch = $null
    $bestLen = 0
    foreach ($capName in $CapabilityModels.Keys) {
        $minLen = [math]::Min($stripped.Length, $capName.Length)
        $prefixLen = 0
        for ($i = 0; $i -lt $minLen; $i++) {
            if ($stripped[$i] -eq $capName[$i]) { $prefixLen++ } else { break }
        }
        if ($prefixLen -ge 8 -and $prefixLen -gt $bestLen) {
            $bestLen = $prefixLen
            $bestMatch = $capName
        }
    }

    return $bestMatch
}

function Get-AvailableModelMap {
    param(
        [hashtable]$Config,
        [hashtable]$CapabilityModels
    )

    $modelMap = @{}  # capabilityModelName -> connectionId

    # Check ai1-ai10 connections
    1..10 | ForEach-Object {
        $id = "ai$_"
        $endpointKey = "AI${_}_ENDPOINT"
        if ($Config.credentials[$endpointKey] -and $Config.connections.ContainsKey($id)) {
            $conn = $Config.connections[$id]
            if ($conn.default_model) {
                $capMatch = Find-CapabilityMatch -ModelName $conn.default_model -CapabilityModels $CapabilityModels
                if ($capMatch -and -not $modelMap.ContainsKey($capMatch)) {
                    $modelMap[$capMatch] = $id
                }
            }
        }
    }

    # Add native connection (Claude Code's built-in model)
    # Native maps to the best available Claude model
    $nativeModels = @('claude-opus-4-6', 'claude-sonnet-4-6')
    foreach ($nm in $nativeModels) {
        if ($CapabilityModels.ContainsKey($nm) -and -not $modelMap.ContainsKey($nm)) {
            $modelMap[$nm] = 'native'
        }
    }

    return $modelMap
}

function Show-RecommendationResult {
    param(
        [hashtable]$Assignments,
        [hashtable]$ModelToConnection,
        [hashtable]$Config,
        [string]$Mode
    )

    Write-Host ""
    Write-Host "Recommended Role Mapping (mode: $($Mode.ToUpper()))" -ForegroundColor Cyan
    Write-Host ""

    $roleOrder = @("primary", "worker-heavy", "worker-lite", "validator", "critic")

    Write-Host "+---------------+----------+---------------------------+-------+" -ForegroundColor Gray
    Write-Host "| Role          | Conn     | Model                     | Score |" -ForegroundColor Gray
    Write-Host "+---------------+----------+---------------------------+-------+" -ForegroundColor Gray

    foreach ($roleName in $roleOrder) {
        if (-not $Assignments.ContainsKey($roleName)) { continue }
        $a = $Assignments[$roleName]
        $modelName = $a.model
        $score = $a.score
        $connId = if ($ModelToConnection.ContainsKey($modelName)) { $ModelToConnection[$modelName] } else { "?" }

        # Get alias
        $connDisplay = $connId.ToUpper().PadRight(8)
        $roleDisplay = $roleName.PadRight(13)
        $modelDisplay = $modelName.PadRight(25)
        $scoreDisplay = $score.ToString('0.00').PadLeft(5)

        $scoreColor = if ($score -ge 8.0) { 'Green' } elseif ($score -ge 6.0) { 'Yellow' } else { 'White' }

        Write-Host "| $roleDisplay | $connDisplay | $modelDisplay | " -NoNewline
        Write-Host $scoreDisplay -ForegroundColor $scoreColor -NoNewline
        Write-Host " |"
    }

    Write-Host "+---------------+----------+---------------------------+-------+" -ForegroundColor Gray
    Write-Host ""
}

function Show-OrchestrationModeMenu {
    param([hashtable]$Config)

    while ($true) {
        Write-Host ""
        Write-Host "--- Select Orchestration Mode ---" -ForegroundColor Cyan
        Write-Host ""

        if ($Config.orchestration_mode) {
            Write-Host "  Current mode: $($Config.orchestration_mode)" -ForegroundColor Gray
            Write-Host ""
        }

        Write-Host "  [1] Autonomy" -ForegroundColor White
        Write-Host "      Prioritize reasoning and instruction following for maximum agent independence" -ForegroundColor DarkGray
        Write-Host "  [2] Cost" -ForegroundColor White
        Write-Host "      Prioritize cost efficiency and speed, prefer local models where possible" -ForegroundColor DarkGray
        Write-Host "  [3] Quality" -ForegroundColor White
        Write-Host "      Prioritize coding and reasoning quality above all else" -ForegroundColor DarkGray
        Write-Host "  [4] Other" -ForegroundColor White
        Write-Host "      Balanced mode with custom priority description" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  [B] Back" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Choice: " -NoNewline
        $choice = Read-Host

        if ($choice -eq "B" -or $choice -eq "b") {
            return $Config
        }

        $mode = switch ($choice) {
            "1" { "autonomy" }
            "2" { "cost" }
            "3" { "quality" }
            "4" { "balanced" }
            default { $null }
        }

        if (-not $mode) { continue }

        # Handle "Other" - prompt for custom priority
        $customPriority = $null
        if ($choice -eq "4") {
            Write-Host ""
            Write-Host "Describe your priority (e.g., 'fast iteration with good code quality'): " -NoNewline
            $customPriority = Read-Host
            if (-not $customPriority) { $customPriority = "balanced" }
        }

        # Load model capabilities
        $capFile = Join-Path $PSScriptRoot '..\data\model-capabilities.json'
        if (-not (Test-Path $capFile)) {
            Write-Warn "Model capabilities file not found. Cannot generate recommendations."
            Write-Host "Press Enter to continue..." -NoNewline
            Read-Host
            continue
        }

        $capData = Get-Content $capFile -Raw | ConvertFrom-Json
        $capModels = @{}
        $capData.models.PSObject.Properties | ForEach-Object {
            $capModels[$_.Name] = $_.Value
        }

        # Build model-to-connection map
        $modelMap = Get-AvailableModelMap -Config $Config -CapabilityModels $capModels

        if ($modelMap.Count -eq 0) {
            Write-Warn "No connections could be matched to known models."
            Write-Warn "Configure AI connections first, or use manual role mapping."
            Write-Host ""
            Write-Host "Press Enter to continue..." -NoNewline
            Read-Host
            continue
        }

        $availableModelNames = @($modelMap.Keys)

        # Call recommendation engine
        $recScript = Join-Path $PSScriptRoot "get-model-recommendation.ps1"
        if (-not (Test-Path $recScript)) {
            Write-Warn "Recommendation engine not found."
            Write-Host "Press Enter to continue..." -NoNewline
            Read-Host
            continue
        }

        Write-Check "Generating recommendations for '$mode' mode..."
        Write-Host ""

        try {
            $jsonResult = & $recScript -RecommendAll -Mode $mode -AvailableModels $availableModelNames -JsonOutput
            $recommendation = $jsonResult | ConvertFrom-Json
        } catch {
            Write-Warn "Recommendation engine failed: $_"
            Write-Host "Press Enter to continue..." -NoNewline
            Read-Host
            continue
        }

        # Convert assignments from PSObject to hashtable
        $assignments = @{}
        $recommendation.assignments.PSObject.Properties | ForEach-Object {
            $assignments[$_.Name] = @{
                model        = $_.Value.model
                score        = $_.Value.score
                role_fitness = $_.Value.role_fitness
                provider     = $_.Value.provider
                type         = $_.Value.type
            }
        }

        # Display recommendation table
        Show-RecommendationResult -Assignments $assignments -ModelToConnection $modelMap -Config $Config -Mode $mode

        if ($customPriority) {
            Write-Host "  Custom priority: $customPriority" -ForegroundColor Gray
            Write-Host ""
        }

        Write-Host "  [A] Accept recommendations" -ForegroundColor Green
        Write-Host "  [M] Modify manually (open role mapping)"
        Write-Host "  [B] Back"
        Write-Host ""
        Write-Host "Choice: " -NoNewline
        $actionChoice = Read-Host

        switch ($actionChoice.ToUpper()) {
            "A" {
                # Apply recommendations to roles (skip primary - always native)
                $nonPrimaryRoles = @("worker-heavy", "worker-lite", "validator", "critic")
                foreach ($roleName in $nonPrimaryRoles) {
                    if ($assignments.ContainsKey($roleName)) {
                        $recModel = $assignments[$roleName].model
                        $connId = if ($modelMap.ContainsKey($recModel)) { $modelMap[$recModel] } else { "native" }

                        # Ensure role exists
                        if (-not $Config.roles.ContainsKey($roleName)) {
                            $Config.roles[$roleName] = @{
                                description = "WOF $roleName agent"
                            }
                        }

                        # Update connection and model, preserve other fields
                        $Config.roles[$roleName].connection = $connId
                        $Config.roles[$roleName].model = $recModel
                    }
                }

                # Persist orchestration mode
                $Config.orchestration_mode = $mode
                $Config.orchestration_custom_priority = $customPriority

                $script:hasUnsavedChanges = $true
                Write-Pass "Orchestration mode set to '$mode'. Role mappings updated."
                Write-Host ""
                Write-Host "Press Enter to continue..." -NoNewline
                Read-Host
                return $Config
            }
            "M" {
                # Set mode metadata even when going to manual
                $Config.orchestration_mode = $mode
                $Config.orchestration_custom_priority = $customPriority
                $script:hasUnsavedChanges = $true
                $Config = Show-RoleMenu -Config $Config
                return $Config
            }
            default {
                # Back - loop again
            }
        }
    }
}

function Show-OrchestrationSubMenu {
    param([hashtable]$Config)

    while ($true) {
        Write-Host ""
        Write-Host "--- Orchestration & Roles ---" -ForegroundColor Cyan
        Write-Host ""

        # Show current state
        if ($Config.orchestration_mode) {
            Write-Host "  Current orchestration mode: $($Config.orchestration_mode)" -ForegroundColor Gray
        }
        Show-RoleMappings -Config $Config

        Write-Host "  [1] Select Orchestration Mode (recommended)"
        Write-Host "  [2] Manual Role Mapping"
        Write-Host ""
        Write-Host "  [B] Back to main menu" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Choice: " -NoNewline
        $choice = Read-Host

        switch ($choice.ToUpper()) {
            "1" { $Config = Show-OrchestrationModeMenu -Config $Config }
            "2" { $Config = Show-RoleMenu -Config $Config }
            "B" { return $Config }
            default { }
        }
    }
}

# ============================================================================
# Role Mapping Menu
# ============================================================================

function Show-RoleMenu {
    param([hashtable]$Config)

    while ($true) {
        Write-Host ""
        Write-Host "--- Role Mapping ---" -ForegroundColor Cyan
        Write-Host ""

        # Show current mappings
        Show-RoleMappings -Config $Config

        # Build list of available connections
        $availableConns = @()
        1..10 | ForEach-Object {
            $id = "ai$_"
            $endpointKey = "AI${_}_ENDPOINT"
            if ($Config.credentials[$endpointKey]) {
                $availableConns += $id
            }
        }

        if ($availableConns.Count -eq 0) {
            Write-Warn "No AI connections configured. Please add connections first."
            Write-Host ""
            Write-Host "Press Enter to go back..." -NoNewline
            Read-Host
            return $Config
        }

        Write-Host "Select role to modify:" -ForegroundColor Cyan
        Write-Host "  [1] worker-heavy"
        Write-Host "  [2] worker-lite"
        Write-Host "  [3] validator"
        Write-Host "  [4] critic"
        Write-Host ""
        Write-Host "  [B] Back to main menu" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Choice: " -NoNewline
        $choice = Read-Host

        if ($choice -eq "B" -or $choice -eq "b") {
            return $Config
        }

        $roleName = switch ($choice) {
            "1" { "worker-heavy" }
            "2" { "worker-lite" }
            "3" { "validator" }
            "4" { "critic" }
            default { $null }
        }

        if ($roleName) {
            $Config = Edit-RoleMapping -Config $Config -RoleName $roleName -AvailableConns $availableConns
        }
    }
}

function Edit-RoleMapping {
    param(
        [hashtable]$Config,
        [string]$RoleName,
        [array]$AvailableConns
    )

    Write-Host ""
    Write-Host "--- Configure $RoleName ---" -ForegroundColor Cyan
    Write-Host ""

    # Show available connections
    Write-Host "Available connections:" -ForegroundColor Gray
    $i = 1
    foreach ($connId in $AvailableConns) {
        $conn = $Config.connections[$connId]
        $alias = if ($conn -and $conn.alias) { $conn.alias } else { $connId.ToUpper() }
        $current = ""
        if ($Config.roles.ContainsKey($RoleName) -and $Config.roles[$RoleName].connection -eq $connId) {
            $current = " (current)"
        }
        Write-Host "  [$i] $($connId.ToUpper()) - $alias$current"
        $i++
    }
    Write-Host ""
    Write-Host "  [B] Back without changes" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Select connection for ${RoleName}: " -NoNewline
    $choice = Read-Host

    if ($choice -eq "B" -or $choice -eq "b") {
        return $Config
    }

    $choiceInt = 0
    if ([int]::TryParse($choice, [ref]$choiceInt) -and $choiceInt -ge 1 -and $choiceInt -le $AvailableConns.Count) {
        $selectedConn = $AvailableConns[$choiceInt - 1]

        # Update or create role
        if (-not $Config.roles.ContainsKey($RoleName)) {
            $Config.roles[$RoleName] = @{
                description = "WOF $RoleName agent"
            }
        }
        $Config.roles[$RoleName].connection = $selectedConn

        # Set default model based on connection type
        $connConfig = $Config.connections[$selectedConn]
        if ($connConfig -and $connConfig.default_model) {
            $Config.roles[$RoleName].model = $connConfig.default_model
        }

        $alias = if ($connConfig -and $connConfig.alias) { $connConfig.alias } else { $selectedConn.ToUpper() }
        Write-Pass "$RoleName now uses $($selectedConn.ToUpper()) ($alias)"
        $script:hasUnsavedChanges = $true
    }

    return $Config
}

# ============================================================================
# Azure DevOps MCP Configuration
# ============================================================================

function Load-McpConfiguration {
    $mcp = @{
        servers = @{}
    }

    if (Test-Path $mcpPath) {
        try {
            $mcpJson = Get-Content $mcpPath -Raw | ConvertFrom-Json
            if ($mcpJson.mcpServers) {
                $mcpJson.mcpServers.PSObject.Properties | ForEach-Object {
                    $serverName = $_.Name
                    $serverConfig = $_.Value
                    $mcp.servers[$serverName] = @{
                        type = $serverConfig.type
                        command = $serverConfig.command
                        args = $serverConfig.args
                        env = @{}
                    }
                    if ($serverConfig.env) {
                        $serverConfig.env.PSObject.Properties | ForEach-Object {
                            $mcp.servers[$serverName].env[$_.Name] = $_.Value
                        }
                    }
                }
            }
        } catch {
            Write-Warn "Could not parse .mcp.json: $_"
        }
    }

    return $mcp
}

function Save-McpConfiguration {
    param([hashtable]$Mcp)

    $mcpObj = [ordered]@{
        mcpServers = [ordered]@{}
    }

    foreach ($serverName in $Mcp.servers.Keys) {
        $server = $Mcp.servers[$serverName]
        $serverEntry = [ordered]@{
            type = $server.type
            command = $server.command
            args = $server.args
        }
        if ($server.env -and $server.env.Count -gt 0) {
            $serverEntry.env = [ordered]@{}
            foreach ($envKey in $server.env.Keys) {
                $serverEntry.env[$envKey] = $server.env[$envKey]
            }
        }
        $mcpObj.mcpServers[$serverName] = $serverEntry
    }

    $json = $mcpObj | ConvertTo-Json -Depth 10
    Set-Content -Path $mcpPath -Value $json -Encoding UTF8
}

function Test-AdoConnection {
    param(
        [string]$OrgUrl,
        [string]$Pat
    )

    $result = @{
        Status = "OFFLINE"
        Latency = 0
        Error = $null
        User = $null
    }

    if (-not $OrgUrl -or -not $Pat) {
        $result.Status = "N/C"
        $result.Error = "Missing organization URL or PAT"
        return $result
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $base64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$Pat"))
        $headers = @{
            "Authorization" = "Basic $base64Auth"
            "Content-Type" = "application/json"
        }

        # Test by getting connection data (who am I)
        $testUrl = "$OrgUrl/_apis/connectionData?api-version=7.1"
        $response = Invoke-RestMethod -Uri $testUrl -Headers $headers -Method Get -TimeoutSec 10 -ErrorAction Stop

        $stopwatch.Stop()
        $result.Status = "ONLINE"
        $result.Latency = $stopwatch.ElapsedMilliseconds

        if ($response.authenticatedUser -and $response.authenticatedUser.providerDisplayName) {
            $result.User = $response.authenticatedUser.providerDisplayName
        }
    }
    catch {
        $stopwatch.Stop()
        $result.Latency = $stopwatch.ElapsedMilliseconds
        $result.Error = $_.Exception.Message

        if ($_.Exception.Response.StatusCode.value__ -eq 401 -or
            $_.Exception.Response.StatusCode.value__ -eq 403) {
            $result.Status = "AUTH_ERR"
            $result.Error = "Authentication failed - check PAT permissions"
        }
    }

    return $result
}

function Show-AdoMenu {
    param([hashtable]$Mcp)

    while ($true) {
        Write-Host ""
        Write-Host "--- Azure DevOps MCP Configuration ---" -ForegroundColor Cyan
        Write-Host ""

        # Check current configuration
        $adoConfig = $Mcp.servers["azure-devops"]
        $isConfigured = $adoConfig -and $adoConfig.env -and ($adoConfig.env["AZURE_DEVOPS_ORG"] -or $adoConfig.env["AZURE_DEVOPS_ORG_URL"])

        if ($isConfigured) {
            $orgUrl = ($adoConfig.env["AZURE_DEVOPS_ORG"] -or $adoConfig.env["AZURE_DEVOPS_ORG_URL"])
            $hasPat = $adoConfig.env["AZURE_DEVOPS_PAT"] -and $adoConfig.env["AZURE_DEVOPS_PAT"].Length -gt 0
            $patDisplay = if ($hasPat) { "(configured)" } else { "(not set)" }

            Write-Host "  Organization URL: $orgUrl" -ForegroundColor Gray
            Write-Host "  PAT:              $patDisplay" -ForegroundColor Gray
            Write-Host "  Auth Method:      $($adoConfig.env["AZURE_DEVOPS_AUTH_METHOD"])" -ForegroundColor Gray
            Write-Host ""
        } else {
            Write-Host "  (not configured)" -ForegroundColor DarkGray
            Write-Host ""
        }

        Write-Host "Options:" -ForegroundColor Cyan
        if ($isConfigured) {
            Write-Host "  [1] Edit ADO connection"
            Write-Host "  [2] Test connection"
            Write-Host "  [3] Delete configuration" -ForegroundColor Red
        } else {
            Write-Host "  [1] Configure ADO MCP server"
        }
        Write-Host ""
        Write-Host "  [B] Back to main menu" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Choice: " -NoNewline
        $choice = Read-Host

        switch ($choice.ToUpper()) {
            "B" { return $Mcp }
            "1" { $Mcp = Edit-AdoConnection -Mcp $Mcp }
            "2" {
                if ($isConfigured) {
                    Write-Host ""
                    Write-Check "Testing ADO connection..."
                    $testResult = Test-AdoConnection -OrgUrl ($adoConfig.env["AZURE_DEVOPS_ORG"] -or $adoConfig.env["AZURE_DEVOPS_ORG_URL"]) -Pat $adoConfig.env["AZURE_DEVOPS_PAT"]

                    if ($testResult.Status -eq "ONLINE") {
                        Write-Pass "ONLINE - $($testResult.Latency)ms"
                        if ($testResult.User) {
                            Write-Info "Authenticated as: $($testResult.User)"
                        }
                    } elseif ($testResult.Status -eq "AUTH_ERR") {
                        Write-Warn "AUTH ERROR - $($testResult.Error)"
                    } else {
                        Write-Fail "OFFLINE - $($testResult.Error)"
                    }
                    Write-Host ""
                    Write-Host "Press Enter to continue..." -NoNewline
                    Read-Host
                }
            }
            "3" {
                if ($isConfigured) {
                    $Mcp = Remove-AdoConfiguration -Mcp $Mcp
                }
            }
        }

        # Refresh state
        $adoConfig = $Mcp.servers["azure-devops"]
        $isConfigured = $adoConfig -and $adoConfig.env -and ($adoConfig.env["AZURE_DEVOPS_ORG"] -or $adoConfig.env["AZURE_DEVOPS_ORG_URL"])
    }
}

function Edit-AdoConnection {
    param([hashtable]$Mcp)

    $existingConfig = $Mcp.servers["azure-devops"]
    # Support both old and new env var formats
    $existingOrg = if ($existingConfig -and $existingConfig.env) { $existingConfig.env["AZURE_DEVOPS_ORG"] } else { "" }
    $existingOrgUrl = if ($existingConfig -and $existingConfig.env) { $existingConfig.env["AZURE_DEVOPS_ORG_URL"] } else { "" }
    $existingPat = if ($existingConfig -and $existingConfig.env) { $existingConfig.env["AZURE_DEVOPS_PAT"] } else { "" }
    $existingProject = if ($existingConfig -and $existingConfig.env) { $existingConfig.env["AZURE_DEVOPS_DEFAULT_PROJECT"] } else { "" }

    Write-Host ""
    Write-Host "--- Configure Azure DevOps MCP Server ---" -ForegroundColor Cyan
    Write-Host ""

    # Organization name
    Write-Host "Organization name (e.g., 'myorg' from https://dev.azure.com/myorg):" -ForegroundColor Gray
    Write-Host ""

    # Derive existing org name from URL if we only have old format
    if (-not $existingOrg -and $existingOrgUrl) {
        if ($existingOrgUrl -match "dev\.azure\.com/([^/]+)") {
            $existingOrg = $Matches[1]
        } elseif ($existingOrgUrl -match "^https?://([^.]+)\.visualstudio\.com") {
            $existingOrg = $Matches[1]
        }
    }

    if ($existingOrg) {
        Write-Host "Organization [$existingOrg]: " -NoNewline
    } else {
        Write-Host "Organization: " -NoNewline
    }
    $org = Read-Host
    if (-not $org -and $existingOrg) {
        $org = $existingOrg
    }

    if (-not $org) {
        Write-Warn "Organization name is required. Aborting."
        return $Mcp
    }

    # Build org URL for connection testing
    $orgUrl = "https://dev.azure.com/$org"

    # PAT
    Write-Host ""
    Write-Host "Personal Access Token (PAT):" -ForegroundColor Gray
    Write-Host "  Create at: $orgUrl/_usersSettings/tokens" -ForegroundColor DarkGray
    Write-Host "  Required scopes: Work Items (Read/Write), Code (Read)" -ForegroundColor DarkGray
    Write-Host ""

    $patPrompt = if ($existingPat) { "(has existing PAT, Enter to keep)" } else { "" }
    Write-Host "PAT ${patPrompt}: " -NoNewline
    $pat = Read-Host
    if (-not $pat -and $existingPat) {
        $pat = $existingPat
    }

    if (-not $pat) {
        Write-Warn "PAT is required for MCP server authentication."
        Write-Host "Continue without PAT? [y/N]: " -NoNewline
        $continueWithoutPat = Read-Host
        if ($continueWithoutPat -ne "y" -and $continueWithoutPat -ne "Y") {
            return $Mcp
        }
    }

    # Test connection before saving
    if ($pat) {
        Write-Host ""
        Write-Check "Testing connection..."
        $testResult = Test-AdoConnection -OrgUrl $orgUrl -Pat $pat

        if ($testResult.Status -eq "ONLINE") {
            Write-Pass "ONLINE - $($testResult.Latency)ms"
            if ($testResult.User) {
                Write-Info "Authenticated as: $($testResult.User)"
            }
        } elseif ($testResult.Status -eq "AUTH_ERR") {
            Write-Warn "AUTH ERROR - $($testResult.Error)"
            Write-Host "Save anyway? [y/N]: " -NoNewline
            $saveAnyway = Read-Host
            if ($saveAnyway -ne "y" -and $saveAnyway -ne "Y") {
                return $Mcp
            }
        } else {
            Write-Warn "OFFLINE - $($testResult.Error)"
            Write-Host "Save anyway? [y/N]: " -NoNewline
            $saveAnyway = Read-Host
            if ($saveAnyway -ne "y" -and $saveAnyway -ne "Y") {
                return $Mcp
            }
        }
    }

    # Default project
    Write-Host ""
    Write-Host "Default project (optional, saves typing project name each time):" -ForegroundColor Gray
    if ($existingProject) {
        Write-Host "Default project [$existingProject]: " -NoNewline
    } else {
        Write-Host "Default project: " -NoNewline
    }
    $defaultProject = Read-Host
    if (-not $defaultProject -and $existingProject) {
        $defaultProject = $existingProject
    }

    # Build MCP server configuration (native WOF server)
    $Mcp.servers["azure-devops"] = @{
        type = "stdio"
        command = "node"
        args = @("core/mcp/wof-azure-devops/dist/index.js")
        env = @{
            "AZURE_DEVOPS_ORG" = $org
        }
    }

    if ($pat) {
        $Mcp.servers["azure-devops"].env["AZURE_DEVOPS_PAT"] = $pat
    }
    if ($defaultProject) {
        $Mcp.servers["azure-devops"].env["AZURE_DEVOPS_DEFAULT_PROJECT"] = $defaultProject
    }

    Write-Host ""
    Write-Pass "ADO MCP configuration saved"
    $script:hasUnsavedChanges = $true

    return $Mcp
}

function Remove-AdoConfiguration {
    param([hashtable]$Mcp)

    Write-Host ""
    Write-Host "Delete Azure DevOps MCP configuration? This cannot be undone." -ForegroundColor Yellow
    Write-Host "Type 'DELETE' to confirm: " -NoNewline
    $confirm = Read-Host

    if ($confirm -eq "DELETE") {
        $Mcp.servers.Remove("azure-devops")
        Write-Pass "ADO MCP configuration deleted"
        $script:hasUnsavedChanges = $true
    } else {
        Write-Info "Deletion cancelled."
    }

    return $Mcp
}

# ============================================================================
# Notification MCP Configuration
# ============================================================================

function Show-NotificationMenu {
    param([hashtable]$Mcp)

    $notificationsJsonPath = Join-Path $configDir "notifications.json"

    while ($true) {
        Write-Host ""
        Write-Host "--- Notification Configuration ---" -ForegroundColor Cyan
        Write-Host ""

        # Check current configuration
        $notifyMcpConfig = $Mcp.servers["wof-notifications"]
        $isConfigured = $notifyMcpConfig -and $notifyMcpConfig.env -and $notifyMcpConfig.env["WOF_NOTIFICATIONS_CONFIG"]

        # Also check if notifications.json exists and has content
        $hasNotificationsJson = Test-Path $notificationsJsonPath
        $notifyDetails = $null

        if ($hasNotificationsJson) {
            try {
                $notifyDetails = Get-Content $notificationsJsonPath -Raw | ConvertFrom-Json
            } catch { }
        }

        if ($isConfigured -and $notifyDetails) {
            $dUser = if ($notifyDetails.dUser.upn) { $notifyDetails.dUser.upn } else { "(not set)" }
            $targetUser = if ($notifyDetails.targetUser.upn) { $notifyDetails.targetUser.upn } else { "(not set)" }
            $tenantId = if ($notifyDetails.tenantId) { $notifyDetails.tenantId } else { "(not set)" }
            $clientId = if ($notifyDetails.clientId) { $notifyDetails.clientId } else { "(not set)" }
            $primaryChannel = if ($notifyDetails.channels.primary) { $notifyDetails.channels.primary } else { "teams" }

            Write-Host "  D-User:          $dUser" -ForegroundColor Gray
            Write-Host "  Target User:     $targetUser" -ForegroundColor Gray
            Write-Host "  Tenant ID:       $tenantId" -ForegroundColor Gray
            Write-Host "  Client ID:       $clientId" -ForegroundColor Gray
            Write-Host "  Primary Channel: $primaryChannel" -ForegroundColor Gray
            Write-Host "  MCP Server:      configured" -ForegroundColor Gray
            Write-Host ""
        } elseif ($hasNotificationsJson) {
            Write-Host "  notifications.json exists but MCP server not configured" -ForegroundColor Yellow
            Write-Host ""
        } else {
            Write-Host "  (not configured)" -ForegroundColor DarkGray
            Write-Host ""
        }

        Write-Host "Options:" -ForegroundColor Cyan
        if ($isConfigured -and $hasNotificationsJson) {
            Write-Host "  [1] Edit notification settings"
            Write-Host "  [2] Run graph-auth.ps1 (authenticate d-user)"
            Write-Host "  [3] Send test notification"
            Write-Host "  [4] Delete configuration" -ForegroundColor Red
        } else {
            Write-Host "  [1] Configure notifications"
        }
        Write-Host ""
        Write-Host "  [B] Back to main menu" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Choice: " -NoNewline
        $choice = Read-Host

        switch ($choice.ToUpper()) {
            "B" { return $Mcp }
            "1" { $Mcp = Edit-NotificationConfiguration -Mcp $Mcp }
            "2" {
                if ($isConfigured -and $hasNotificationsJson) {
                    Write-Host ""
                    $authScript = Join-Path $PSScriptRoot "graph-auth.ps1"
                    if (Test-Path $authScript) {
                        & $authScript -ConfigPath $notificationsJsonPath
                    } else {
                        Write-Fail "graph-auth.ps1 not found at $authScript"
                    }
                    Write-Host ""
                    Write-Host "Press Enter to continue..." -NoNewline
                    Read-Host
                }
            }
            "3" {
                if ($isConfigured -and $hasNotificationsJson) {
                    Write-Host ""
                    $sendScript = Join-Path $PSScriptRoot "send-notification.ps1"
                    if (Test-Path $sendScript) {
                        Write-Check "Sending test notification..."
                        & $sendScript -Message "Test notification from WOF configuration wizard." -Type "completed" -ConfigPath $notificationsJsonPath
                        Write-Host ""
                    } else {
                        Write-Fail "send-notification.ps1 not found at $sendScript"
                    }
                    Write-Host ""
                    Write-Host "Press Enter to continue..." -NoNewline
                    Read-Host
                }
            }
            "4" {
                if ($isConfigured) {
                    $Mcp = Remove-NotificationConfiguration -Mcp $Mcp
                }
            }
        }

        # Refresh state
        $notifyMcpConfig = $Mcp.servers["wof-notifications"]
        $isConfigured = $notifyMcpConfig -and $notifyMcpConfig.env -and $notifyMcpConfig.env["WOF_NOTIFICATIONS_CONFIG"]
        $hasNotificationsJson = Test-Path $notificationsJsonPath
    }
}

function Edit-NotificationConfiguration {
    param([hashtable]$Mcp)

    $notificationsJsonPath = Join-Path $configDir "notifications.json"
    $templatePath = Join-Path $PSScriptRoot "..\..\templates\config\notifications.json.template"

    # Load existing or create from template
    $notifyConfig = $null
    if (Test-Path $notificationsJsonPath) {
        try {
            $notifyConfig = Get-Content $notificationsJsonPath -Raw | ConvertFrom-Json
        } catch {
            Write-Warn "Failed to parse existing notifications.json: $_"
        }
    }

    if (-not $notifyConfig) {
        if (Test-Path $templatePath) {
            $notifyConfig = Get-Content $templatePath -Raw | ConvertFrom-Json
            Write-Info "Created from template"
        } else {
            Write-Fail "notifications.json template not found"
            return $Mcp
        }
    }

    Write-Host ""
    Write-Host "--- Configure Notifications ---" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "The notification system sends messages from a d-user (AI service account)" -ForegroundColor Gray
    Write-Host "to the target user (you) via Teams chat or email." -ForegroundColor Gray
    Write-Host ""

    # Tenant ID
    $existingTenant = $notifyConfig.tenantId
    if ($existingTenant) {
        Write-Host "Azure AD Tenant ID [$existingTenant]: " -NoNewline
    } else {
        Write-Host "Azure AD Tenant ID: " -NoNewline
    }
    $tenantId = Read-Host
    if (-not $tenantId -and $existingTenant) { $tenantId = $existingTenant }

    if (-not $tenantId) {
        Write-Warn "Tenant ID is required."
        return $Mcp
    }
    $notifyConfig.tenantId = $tenantId

    # D-User UPN
    $existingDUser = $notifyConfig.dUser.upn
    if ($existingDUser) {
        Write-Host "D-User UPN (e.g. d-anr@company.com) [$existingDUser]: " -NoNewline
    } else {
        Write-Host "D-User UPN (e.g. d-anr@company.com): " -NoNewline
    }
    $dUserUpn = Read-Host
    if (-not $dUserUpn -and $existingDUser) { $dUserUpn = $existingDUser }

    if (-not $dUserUpn) {
        Write-Warn "D-User UPN is required."
        return $Mcp
    }
    $notifyConfig.dUser.upn = $dUserUpn

    # Target User UPN
    $existingTarget = $notifyConfig.targetUser.upn
    if ($existingTarget) {
        Write-Host "Target User UPN (e.g. anr@company.com) [$existingTarget]: " -NoNewline
    } else {
        Write-Host "Target User UPN (e.g. anr@company.com): " -NoNewline
    }
    $targetUpn = Read-Host
    if (-not $targetUpn -and $existingTarget) { $targetUpn = $existingTarget }

    if (-not $targetUpn) {
        Write-Warn "Target User UPN is required."
        return $Mcp
    }
    $notifyConfig.targetUser.upn = $targetUpn

    # Client ID (optional)
    $existingClientId = $notifyConfig.clientId
    Write-Host ""
    Write-Host "Custom App Client ID (optional - leave blank to use default):" -ForegroundColor Gray
    Write-Host "  Run register-notification-app.ps1 to create a custom app." -ForegroundColor DarkGray
    if ($existingClientId) {
        Write-Host "Client ID [$existingClientId]: " -NoNewline
    } else {
        Write-Host "Client ID: " -NoNewline
    }
    $clientId = Read-Host
    if (-not $clientId -and $existingClientId) { $clientId = $existingClientId }
    $notifyConfig.clientId = if ($clientId) { $clientId } else { "" }

    # Primary channel
    Write-Host ""
    $existingChannel = if ($notifyConfig.channels.primary) { $notifyConfig.channels.primary } else { "teams" }
    Write-Host "Primary channel (teams/email) [$existingChannel]: " -NoNewline
    $channel = Read-Host
    if (-not $channel) { $channel = $existingChannel }
    if ($channel -ne "teams" -and $channel -ne "email") { $channel = "teams" }
    $notifyConfig.channels.primary = $channel
    $notifyConfig.channels.fallback = if ($channel -eq "teams") { "email" } else { "teams" }

    # Save notifications.json
    Write-Host ""
    Write-Check "Saving notifications.json..."

    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    $notifyConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $notificationsJsonPath -Encoding UTF8
    Write-Pass "notifications.json saved"

    # Configure MCP server entry
    $mcpServerPath = Join-Path $PSScriptRoot "..\mcp\wof-notifications\dist\index.js"
    $resolvedMcpPath = if (Test-Path $mcpServerPath) { (Resolve-Path $mcpServerPath).Path } else { $mcpServerPath }

    $Mcp.servers["wof-notifications"] = @{
        type = "stdio"
        command = "node"
        args = @($resolvedMcpPath)
        env = @{
            "WOF_NOTIFICATIONS_CONFIG" = (Resolve-Path $notificationsJsonPath).Path
        }
    }

    Write-Pass "MCP server configured"
    $script:hasUnsavedChanges = $true

    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Save configuration (S from main menu)" -ForegroundColor Gray
    Write-Host "  2. Run graph-auth.ps1 to authenticate the d-user" -ForegroundColor Gray
    Write-Host "  3. Restart Claude Code to load the MCP server" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Press Enter to continue..." -NoNewline
    Read-Host

    return $Mcp
}

function Remove-NotificationConfiguration {
    param([hashtable]$Mcp)

    Write-Host ""
    Write-Host "Delete notification configuration? This removes the MCP server entry." -ForegroundColor Yellow
    Write-Host "notifications.json will be preserved." -ForegroundColor Gray
    Write-Host "Type 'DELETE' to confirm: " -NoNewline
    $confirm = Read-Host

    if ($confirm -eq "DELETE") {
        $Mcp.servers.Remove("wof-notifications")
        Write-Pass "Notification MCP configuration deleted"
        $script:hasUnsavedChanges = $true
    } else {
        Write-Info "Deletion cancelled."
    }

    return $Mcp
}

# ============================================================================
# Cowork MCP Bridge Configuration
# ============================================================================

function Show-CoworkMenu {
    while ($true) {
        Write-Host ""
        Write-Host "--- Cowork MCP Bridge Configuration ---" -ForegroundColor Cyan
        Write-Host ""
        Write-Info "Bridges Claude Desktop to a headless 'claude -p' subprocess."
        Write-Info "Writes into claude_desktop_config.json. See docs/cowork-bootstrap.md."
        Write-Host ""

        $isWin = $env:OS -eq "Windows_NT" -or $PSVersionTable.Platform -eq "Win32NT" -or (-not $PSVersionTable.Platform)
        $setupScript = if ($isWin) {
            Join-Path $PSScriptRoot "setup-cowork.ps1"
        } else {
            Join-Path $PSScriptRoot "setup-cowork.sh"
        }
        $mcpPkg = Join-Path $repoRoot "core/mcp/wof-cowork"

        if (Test-Path $setupScript) {
            Write-Host "  Setup script: $setupScript" -ForegroundColor Gray
        } else {
            Write-Host "  Setup script: (missing) $setupScript" -ForegroundColor Red
        }
        if (Test-Path $mcpPkg) {
            Write-Host "  MCP package:  $mcpPkg" -ForegroundColor Gray
        } else {
            Write-Host "  MCP package:  (not found) expected at $mcpPkg" -ForegroundColor Yellow
            Write-Info "Cowork must be configured from the WOF source tree."
        }
        Write-Host ""

        Write-Host "Options:" -ForegroundColor Cyan
        Write-Host "  [1] Install / update cowork in Claude Desktop"
        Write-Host "  [2] Dry-run (print planned config change only)"
        Write-Host ""
        Write-Host "  [B] Back to main menu" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Choice: " -NoNewline
        $choice = Read-Host

        switch ($choice.ToUpper()) {
            "B" { return }
            "1" { Invoke-CoworkSetup -OnWindows:$isWin -SetupScript $setupScript -DryRun:$false }
            "2" { Invoke-CoworkSetup -OnWindows:$isWin -SetupScript $setupScript -DryRun:$true }
        }
    }
}

function Invoke-CoworkSetup {
    param(
        [bool]$OnWindows,
        [string]$SetupScript,
        [switch]$DryRun
    )

    if (-not (Test-Path $SetupScript)) {
        Write-Fail "Cowork setup script not found: $SetupScript"
        Write-Host ""
        Write-Host "Press Enter to continue..." -NoNewline
        Read-Host
        return
    }

    # Prompt for project dir; default to repoRoot when the WOF MCP package is present.
    $mcpPkg = Join-Path $repoRoot "core/mcp/wof-cowork"
    $defaultProject = if (Test-Path $mcpPkg) { $repoRoot } else { "" }

    Write-Host ""
    Write-Host "Absolute path to the repo the headless subprocess works against:" -ForegroundColor Gray
    if ($defaultProject) {
        Write-Host "Project dir [$defaultProject]: " -NoNewline
    } else {
        Write-Host "Project dir: " -NoNewline
    }
    $projectDir = Read-Host
    if (-not $projectDir -and $defaultProject) {
        $projectDir = $defaultProject
    }
    if (-not $projectDir) {
        Write-Warn "Project dir is required. Aborting."
        Write-Host ""
        Write-Host "Press Enter to continue..." -NoNewline
        Read-Host
        return
    }
    if (-not (Test-Path $projectDir -PathType Container)) {
        Write-Fail "Project dir does not exist: $projectDir"
        Write-Host ""
        Write-Host "Press Enter to continue..." -NoNewline
        Read-Host
        return
    }

    # Prompt for server name.
    $defaultName = "wof-cowork"
    Write-Host ""
    Write-Host "Key under mcpServers in Claude Desktop config:" -ForegroundColor Gray
    Write-Host "Server name [$defaultName]: " -NoNewline
    $serverName = Read-Host
    if (-not $serverName) { $serverName = $defaultName }

    Write-Host ""
    Write-Check "Invoking setup-cowork (this builds the MCP server and merges the config)..."
    Write-Host ""

    try {
        if ($OnWindows) {
            if ($DryRun) {
                & $SetupScript -ProjectDir $projectDir -ServerName $serverName -DryRun
            } else {
                & $SetupScript -ProjectDir $projectDir -ServerName $serverName
            }
        } else {
            $shArgs = @($SetupScript, "--project-dir", $projectDir, "--server-name", $serverName)
            if ($DryRun) { $shArgs += "--dry-run" }
            & bash @shArgs
        }
        $exit = $LASTEXITCODE
    } catch {
        Write-Fail "Setup script errored: $_"
        Write-Host ""
        Write-Host "Press Enter to continue..." -NoNewline
        Read-Host
        return
    }

    Write-Host ""
    if ($exit -eq 0) {
        Write-Pass "Cowork setup completed."
        if (-not $DryRun) {
            Write-Info "Fully quit Claude Desktop (tray/menu -> Quit) and relaunch to load the new config."
            Write-Info "Then ask Claude Desktop: 'list your available MCP tools' to verify."
        }
    } else {
        Write-Fail "Setup script exited with code $exit. See output above."
    }
    Write-Host ""
    Write-Host "Press Enter to continue..." -NoNewline
    Read-Host
}

# ============================================================================
# Connection Slot Menu (for individual AI slot)
# ============================================================================

function Show-ConnectionSlotMenu {
    param(
        [int]$SlotNumber,
        [hashtable]$Config
    )

    $id = "ai$SlotNumber"
    $endpointKey = "AI${SlotNumber}_ENDPOINT"
    $conn = $Config.connections[$id]
    $endpoint = $Config.credentials[$endpointKey]
    $isConfigured = $conn -and $endpoint

    while ($true) {
        Write-Host ""
        Write-Host "--- AI$SlotNumber Configuration ---" -ForegroundColor Cyan
        Write-Host ""

        if ($isConfigured) {
            $alias = if ($conn.alias) { $conn.alias } else { "AI$SlotNumber" }
            $type = if ($conn.type) { $conn.type } else { "unknown" }
            Write-Host "  Alias:    $alias" -ForegroundColor Gray
            Write-Host "  Type:     $type" -ForegroundColor Gray
            Write-Host "  Endpoint: $endpoint" -ForegroundColor Gray
            Write-Host ""
        } else {
            Write-Host "  (not configured)" -ForegroundColor DarkGray
            Write-Host ""
        }

        Write-Host "Options:" -ForegroundColor Cyan
        if ($isConfigured) {
            Write-Host "  [1] Edit connection settings"
            Write-Host "  [2] Rename (change alias)"
            Write-Host "  [3] Test connection"
            Write-Host "  [4] Delete connection" -ForegroundColor Red
        } else {
            Write-Host "  [1] Configure new connection"
        }
        Write-Host ""
        Write-Host "  [B] Back to connections list" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Choice: " -NoNewline
        $choice = Read-Host

        switch ($choice.ToUpper()) {
            "B" { return $Config }
            "1" {
                $Config = Edit-AIConnection -SlotNumber $SlotNumber -Config $Config
                # Refresh state
                $conn = $Config.connections[$id]
                $endpoint = $Config.credentials[$endpointKey]
                $isConfigured = $conn -and $endpoint
            }
            "2" {
                if ($isConfigured) {
                    $Config = Rename-AIConnection -SlotNumber $SlotNumber -Config $Config
                    $conn = $Config.connections[$id]
                }
            }
            "3" {
                if ($isConfigured) {
                    Test-SingleConnection -SlotNumber $SlotNumber -Config $Config
                    Write-Host ""
                    Write-Host "Press Enter to continue..." -NoNewline
                    Read-Host
                }
            }
            "4" {
                if ($isConfigured) {
                    $Config = Remove-AIConnection -SlotNumber $SlotNumber -Config $Config
                    # Refresh state
                    $conn = $Config.connections[$id]
                    $endpoint = $Config.credentials[$endpointKey]
                    $isConfigured = $conn -and $endpoint
                    if (-not $isConfigured) {
                        return $Config
                    }
                }
            }
        }
    }
}

# ============================================================================
# Connections Menu
# ============================================================================

function Show-ConnectionsMenu {
    param([hashtable]$Config)

    while ($true) {
        Write-Host ""
        Write-Host "--- Manage AI Connections ---" -ForegroundColor Cyan

        # Show table without testing (for speed)
        Write-Host ""
        Write-Host "+------+-------------------+----------------------------------+------------------------+" -ForegroundColor Gray
        Write-Host "| Slot | Alias             | Endpoint                         | Type                   |" -ForegroundColor Gray
        Write-Host "+------+-------------------+----------------------------------+------------------------+" -ForegroundColor Gray

        1..10 | ForEach-Object {
            $id = "ai$_"
            $displayId = "AI$_".PadRight(4)

            $conn = $Config.connections[$id]
            $endpointKey = "AI${_}_ENDPOINT"
            $endpoint = $Config.credentials[$endpointKey]

            if ($conn -and $conn.alias -and $endpoint) {
                $alias = $conn.alias
                if ($alias.Length -gt 17) { $alias = $alias.Substring(0, 14) + "..." }
                $alias = $alias.PadRight(17)

                $displayEndpoint = $endpoint
                if ($displayEndpoint.Length -gt 32) { $displayEndpoint = $displayEndpoint.Substring(0, 29) + "..." }
                $displayEndpoint = $displayEndpoint.PadRight(32)

                $type = if ($conn.type) { $conn.type } else { "-" }
                if ($type.Length -gt 22) { $type = $type.Substring(0, 19) + "..." }
                $type = $type.PadRight(22)

                Write-Host "| $displayId | $alias | $displayEndpoint | $type |"
            } else {
                $alias = "(not configured)".PadRight(17)
                $displayEndpoint = "-".PadRight(32)
                $type = "-".PadRight(22)

                Write-Host "| $displayId | " -NoNewline
                Write-Host $alias -ForegroundColor DarkGray -NoNewline
                Write-Host " | " -NoNewline
                Write-Host $displayEndpoint -ForegroundColor DarkGray -NoNewline
                Write-Host " | " -NoNewline
                Write-Host $type -ForegroundColor DarkGray -NoNewline
                Write-Host " |"
            }
        }

        Write-Host "+------+-------------------+----------------------------------+------------------------+" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Enter slot number (1-10) to configure, or:" -ForegroundColor Cyan
        Write-Host "  [T] Test all connections"
        Write-Host "  [B] Back to main menu" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Choice: " -NoNewline
        $choice = Read-Host

        switch ($choice.ToUpper()) {
            "B" { return $Config }
            "T" {
                Write-Host ""
                Show-ConnectionsTable -Config $Config | Out-Null
                Write-Host ""
                Write-Host "Press Enter to continue..." -NoNewline
                Read-Host
            }
            default {
                $slotNum = 0
                if ([int]::TryParse($choice, [ref]$slotNum) -and $slotNum -ge 1 -and $slotNum -le 10) {
                    $Config = Show-ConnectionSlotMenu -SlotNumber $slotNum -Config $Config
                }
            }
        }
    }
}

# ============================================================================
# Save Configuration
# ============================================================================

function Save-Configuration {
    param(
        [hashtable]$Config,
        [hashtable]$Mcp
    )

    Write-Host ""
    Write-Check "Saving configuration..."

    try {
        # Ensure config directory exists
        if (-not (Test-Path $configDir)) {
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        }

        Save-Connections -Connections $Config.connections
        Save-Credentials -Credentials $Config.credentials
        Save-Roles -Roles $Config.roles -OrchestrationMode $Config.orchestration_mode -OrchestrationCustomPriority $Config.orchestration_custom_priority

        # Save MCP configuration if provided
        if ($Mcp -and $Mcp.servers.Count -gt 0) {
            Save-McpConfiguration -Mcp $Mcp
            Write-Info ".mcp.json - MCP server configuration"
        }

        Write-Pass "Configuration saved!"
        Write-Info "connections.json - AI connection definitions"
        Write-Info "credentials.local.json - API keys (gitignored)"
        Write-Info "roles.json - Role-to-connection mappings"
        $script:hasUnsavedChanges = $false
    } catch {
        Write-Fail "Failed to save configuration: $_"
    }
}

# ============================================================================
# Main Menu
# ============================================================================

function Show-MainMenu {
    param(
        [hashtable]$Config,
        [hashtable]$Mcp
    )

    while ($true) {
        Write-Header "WOF CONFIGURATION WIZARD"

        # Count configured connections
        $configuredCount = 0
        1..10 | ForEach-Object {
            $endpointKey = "AI${_}_ENDPOINT"
            if ($Config.credentials[$endpointKey]) {
                $configuredCount++
            }
        }

        # Check ADO status
        $adoConfigured = $Mcp.servers["azure-devops"] -and $Mcp.servers["azure-devops"].env -and $Mcp.servers["azure-devops"].env["AZURE_DEVOPS_ORG_URL"]
        $adoStatus = if ($adoConfigured) { "configured" } else { "not configured" }

        # Check Notification status
        $notifyConfigured = $Mcp.servers["wof-notifications"] -and $Mcp.servers["wof-notifications"].env -and $Mcp.servers["wof-notifications"].env["WOF_NOTIFICATIONS_CONFIG"]
        $notifyStatus = if ($notifyConfigured) { "configured" } else { "not configured" }

        Write-Host "  AI connections:  $configuredCount/10" -ForegroundColor Gray
        Write-Host "  Azure DevOps:    $adoStatus" -ForegroundColor Gray
        Write-Host "  Notifications:   $notifyStatus" -ForegroundColor Gray
        if ($script:hasUnsavedChanges) {
            Write-Host "  Unsaved changes: Yes" -ForegroundColor Yellow
        }
        Write-Host ""
        Write-Host "Main Menu:" -ForegroundColor Cyan
        Write-Host "  [1] Manage AI Connections"
        Write-Host "  [2] Orchestration & Roles"
        Write-Host "  [3] Configure Azure DevOps MCP"
        Write-Host "  [4] Configure Notifications"
        Write-Host "  [5] Configure Cowork (Claude Desktop bridge)"
        Write-Host ""
        Write-Host "  [6] Test All AI Connections"
        Write-Host "  [7] View Current Configuration"
        Write-Host "  [8] Orchestration Patterns"
        Write-Host ""
        if ($script:hasUnsavedChanges) {
            Write-Host "  [S] Save changes" -ForegroundColor Green
        }
        Write-Host "  [H] Run health check"
        Write-Host "  [Q] Quit" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Choice: " -NoNewline
        $choice = Read-Host

        switch ($choice.ToUpper()) {
            "1" { $Config = Show-ConnectionsMenu -Config $Config }
            "2" { $Config = Show-OrchestrationSubMenu -Config $Config }
            "3" { $Mcp = Show-AdoMenu -Mcp $Mcp }
            "4" { $Mcp = Show-NotificationMenu -Mcp $Mcp }
            "5" { Show-CoworkMenu }
            "6" {
                Write-Host ""
                Write-Host "Testing all AI connections..." -ForegroundColor Cyan
                Show-ConnectionsTable -Config $Config | Out-Null
                Write-Host ""
                Write-Host "Press Enter to continue..." -NoNewline
                Read-Host
            }
            "8" {
                $orchScript = Join-Path $PSScriptRoot "configure-orchestration.ps1"
                if (Test-Path $orchScript) {
                    & $orchScript
                } else {
                    Write-Warn "Orchestration configuration script not found."
                }
                Write-Host ""
                Write-Host "Press Enter to continue..." -NoNewline
                Read-Host
            }
            "7" {
                Write-Host ""
                Show-RoleMappings -Config $Config

                # Show ADO config
                if ($adoConfigured) {
                    Write-Host "Azure DevOps MCP:" -ForegroundColor Cyan
                    Write-Host "    Organization: $($Mcp.servers["azure-devops"].env["AZURE_DEVOPS_ORG_URL"])" -ForegroundColor Gray
                    Write-Host ""
                }

                # Show Notification config
                if ($notifyConfigured) {
                    $notifyJsonPath = Join-Path $configDir "notifications.json"
                    if (Test-Path $notifyJsonPath) {
                        try {
                            $nd = Get-Content $notifyJsonPath -Raw | ConvertFrom-Json
                            Write-Host "Notifications MCP:" -ForegroundColor Cyan
                            Write-Host "    D-User:      $($nd.dUser.upn)" -ForegroundColor Gray
                            Write-Host "    Target User: $($nd.targetUser.upn)" -ForegroundColor Gray
                            Write-Host "    Channel:     $($nd.channels.primary)" -ForegroundColor Gray
                            Write-Host ""
                        } catch { }
                    }
                }

                Write-Host "Press Enter to continue..." -NoNewline
                Read-Host
            }
            "S" {
                if ($script:hasUnsavedChanges) {
                    Save-Configuration -Config $Config -Mcp $Mcp
                    Write-Host ""
                    Write-Host "Press Enter to continue..." -NoNewline
                    Read-Host
                }
            }
            "H" {
                $healthScript = Join-Path $PSScriptRoot "check-orchestration-health.ps1"
                if (Test-Path $healthScript) {
                    & $healthScript
                } else {
                    Write-Warn "Health check script not found."
                }
                Write-Host ""
                Write-Host "Press Enter to continue..." -NoNewline
                Read-Host
            }
            "Q" {
                if ($script:hasUnsavedChanges) {
                    Write-Host ""
                    Write-Host "You have unsaved changes. Save before quitting? [Y/n]: " -NoNewline
                    $saveFirst = Read-Host
                    if (-not $saveFirst -or $saveFirst.ToLower() -eq "y") {
                        Save-Configuration -Config $Config -Mcp $Mcp
                    }
                }
                Write-Host ""
                Write-Pass "Configuration wizard closed."
                Write-Host ""
                return
            }
        }
    }
}

# ============================================================================
# Main Entry Point
# ============================================================================

# Load existing configuration
Write-Check "Loading configuration..."
$config = Load-Configuration
$mcp = Load-McpConfiguration

if ($TestOnly) {
    Write-Header "WOF CONNECTION TEST"
    Write-Host "Testing AI connections..." -ForegroundColor Cyan
    $count = Show-ConnectionsTable -Config $config
    Write-Host ""

    # Also test ADO if configured
    $adoConfig = $mcp.servers["azure-devops"]
    if ($adoConfig -and $adoConfig.env -and ($adoConfig.env["AZURE_DEVOPS_ORG"] -or $adoConfig.env["AZURE_DEVOPS_ORG_URL"])) {
        Write-Host "Testing Azure DevOps..." -ForegroundColor Cyan
        $adoResult = Test-AdoConnection -OrgUrl ($adoConfig.env["AZURE_DEVOPS_ORG"] -or $adoConfig.env["AZURE_DEVOPS_ORG_URL"]) -Pat $adoConfig.env["AZURE_DEVOPS_PAT"]
        if ($adoResult.Status -eq "ONLINE") {
            Write-Pass "ADO: ONLINE ($($adoResult.Latency)ms)"
            if ($adoResult.User) {
                Write-Info "  Authenticated as: $($adoResult.User)"
            }
        } elseif ($adoResult.Status -eq "AUTH_ERR") {
            Write-Warn "ADO: AUTH ERROR - $($adoResult.Error)"
        } else {
            Write-Fail "ADO: OFFLINE - $($adoResult.Error)"
        }
    }

    # Also check notification config
    $notifyMcpConfig = $mcp.servers["wof-notifications"]
    if ($notifyMcpConfig -and $notifyMcpConfig.env -and $notifyMcpConfig.env["WOF_NOTIFICATIONS_CONFIG"]) {
        $notifyJsonPath = $notifyMcpConfig.env["WOF_NOTIFICATIONS_CONFIG"]
        if (Test-Path $notifyJsonPath) {
            try {
                $nd = Get-Content $notifyJsonPath -Raw | ConvertFrom-Json
                Write-Pass "Notifications: configured ($($nd.dUser.upn) -> $($nd.targetUser.upn))"
            } catch {
                Write-Warn "Notifications: config file exists but failed to parse"
            }
        } else {
            Write-Warn "Notifications: MCP configured but config file not found at $notifyJsonPath"
        }
    }

    Write-Host ""
    Write-Host "Tested $count AI connections." -ForegroundColor Gray
    exit 0
}

# Start main menu
Show-MainMenu -Config $config -Mcp $mcp
