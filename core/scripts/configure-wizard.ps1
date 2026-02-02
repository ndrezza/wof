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
1. Adding AI connections (AI1-AI10)
2. Testing connectivity
3. Mapping roles to connections

Connection Types:
    azure_ai_foundry_anthropic  - Claude on Azure (key required)
    azure_openai                - GPT on Azure (key required)
    openai_compatible           - OpenAI-compatible API (Ollama, vLLM, llama.cpp)

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
    param([hashtable]$Roles)

    $rolesObj = [ordered]@{
        '$schema' = "https://json-schema.org/draft/2020-12/schema"
        version = "2.0.0"
        description = "Role-to-connection mapping. Defines which AI connection each role uses."
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
# Interactive Add Connection
# ============================================================================

function Add-AIConnection {
    param(
        [int]$SlotNumber,
        [hashtable]$Config
    )

    $id = "ai$SlotNumber"
    Write-Host ""
    Write-Host "--- Adding AI$SlotNumber ---" -ForegroundColor Cyan
    Write-Host ""

    # Alias
    Write-Host "Alias (friendly name): " -NoNewline
    $alias = Read-Host
    if (-not $alias) {
        $alias = "AI$SlotNumber"
    }

    # Endpoint first - so we can auto-detect type
    Write-Host ""
    Write-Host "Endpoint URL: " -NoNewline
    $endpoint = Read-Host

    # Auto-detect type from URL
    $detectedType = Get-ConnectionTypeFromUrl -Url $endpoint
    $detectedLabel = switch ($detectedType) {
        "azure_ai_foundry_anthropic" { "Azure AI Foundry Anthropic" }
        "azure_openai" { "Azure OpenAI" }
        "openai_compatible" { "OpenAI-compatible" }
        default { "OpenAI-compatible" }
    }

    # Type selection with auto-detected default
    Write-Host ""
    Write-Host "Type (auto-detected: $detectedLabel):" -ForegroundColor Cyan
    Write-Host "  [1] azure_ai_foundry_anthropic (Claude on Azure)"
    Write-Host "  [2] azure_openai (GPT on Azure)"
    Write-Host "  [3] openai_compatible (Ollama, vLLM, llama.cpp)"
    Write-Host ""
    $defaultChoice = switch ($detectedType) {
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
        default { $detectedType }
    }

    # API Key (optional for openai_compatible)
    Write-Host ""
    if ($type -eq "openai_compatible") {
        Write-Host "API Key (optional, press Enter to skip): " -NoNewline
    } else {
        Write-Host "API Key: " -NoNewline
    }
    $apiKey = Read-Host

    # Model
    Write-Host ""
    $defaultModel = switch ($type) {
        "azure_ai_foundry_anthropic" { "claude-opus-4-5-20251101" }
        "azure_openai" { "gpt-4o" }
        "openai_compatible" { "deepseek-coder-v2-lite-instruct" }
        default { "" }
    }
    Write-Host "Model [$defaultModel]: " -NoNewline
    $model = Read-Host
    if (-not $model) {
        $model = $defaultModel
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
    $Config.credentials["AI${SlotNumber}_ENDPOINT"] = $endpoint
    if ($apiKey) {
        $Config.credentials["AI${SlotNumber}_API_KEY"] = $apiKey
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

    return $Config
}

# ============================================================================
# Role Mapping Wizard
# ============================================================================

function Start-RoleMappingWizard {
    param([hashtable]$Config)

    Write-Host ""
    Write-Host "--- Role Mapping ---" -ForegroundColor Cyan
    Write-Host ""

    # Build list of available connections
    $availableConns = @()
    $connDisplay = @()

    1..10 | ForEach-Object {
        $id = "ai$_"
        $endpointKey = "AI${_}_ENDPOINT"

        if ($Config.credentials[$endpointKey]) {
            $conn = $Config.connections[$id]
            $alias = if ($conn -and $conn.alias) { $conn.alias } else { "AI$_" }
            $availableConns += $id
            $connDisplay += "  [$($availableConns.Count)] $($id.ToUpper()) - $alias"
        }
    }

    if ($availableConns.Count -eq 0) {
        Write-Warn "No AI connections configured. Please add connections first."
        return $Config
    }

    Write-Host "Available AIs:" -ForegroundColor Cyan
    $connDisplay | ForEach-Object { Write-Host $_ }
    Write-Host ""

    # Map each role (except primary which is always native)
    $rolesToMap = @("worker-heavy", "worker-lite", "validator", "critic")

    foreach ($roleName in $rolesToMap) {
        $currentConn = if ($Config.roles.ContainsKey($roleName)) { $Config.roles[$roleName].connection } else { "" }
        $currentIndex = $availableConns.IndexOf($currentConn) + 1
        $default = if ($currentIndex -gt 0) { $currentIndex } else { "1" }

        Write-Host "Map $roleName to [1-$($availableConns.Count), current=$default]: " -NoNewline
        $choice = Read-Host

        if (-not $choice) {
            $choice = $default
        }

        $choiceInt = [int]$choice
        if ($choiceInt -ge 1 -and $choiceInt -le $availableConns.Count) {
            $selectedConn = $availableConns[$choiceInt - 1]

            # Update or create role
            if (-not $Config.roles.ContainsKey($roleName)) {
                $Config.roles[$roleName] = @{}
            }
            $Config.roles[$roleName].connection = $selectedConn

            # Set default model based on connection type
            $connConfig = $Config.connections[$selectedConn]
            if ($connConfig -and $connConfig.default_model) {
                $Config.roles[$roleName].model = $connConfig.default_model
            }
        }
    }

    return $Config
}

# ============================================================================
# Main Wizard Flow
# ============================================================================

Write-Header "WOF CONFIGURATION WIZARD"

# Load existing configuration
Write-Check "Loading configuration..."
$config = Load-Configuration

if ($TestOnly) {
    Write-Host ""
    Write-Host "Testing existing connections..." -ForegroundColor Cyan
    $count = Show-ConnectionsTable -Config $config
    Write-Host ""
    Write-Host "Tested $count configured connections." -ForegroundColor Gray
    exit 0
}

# Show current state
Write-Host "Checking AI connections..." -ForegroundColor Cyan
$configuredCount = Show-ConnectionsTable -Config $config

# If no connections, prompt to add
if ($configuredCount -eq 0) {
    Write-Host "No AI connections configured. Add one now? [Y/n]: " -NoNewline
    $addFirst = Read-Host
    if (-not $addFirst -or $addFirst.ToLower() -eq "y") {
        $config = Add-AIConnection -SlotNumber 1 -Config $config
    }
} else {
    Write-Host "Add or modify a connection? [y/N]: " -NoNewline
    $modify = Read-Host
    if ($modify -and $modify.ToLower() -eq "y") {
        Write-Host "Enter slot number (1-10): " -NoNewline
        $slotInput = Read-Host
        if ($slotInput) {
            $slot = [int]$slotInput
            if ($slot -ge 1 -and $slot -le 10) {
                $config = Add-AIConnection -SlotNumber $slot -Config $config
            }
        }
    }
}

# Loop to add more
$addMore = $true
while ($addMore) {
    Write-Host ""
    Write-Host "Add another connection? [y/N]: " -NoNewline
    $response = Read-Host

    if ($response -and $response.ToLower() -eq "y") {
        # Find next available slot
        $nextSlot = 0
        1..10 | ForEach-Object {
            $endpointKey = "AI${_}_ENDPOINT"
            if (-not $config.credentials[$endpointKey] -and $nextSlot -eq 0) {
                $nextSlot = $_
            }
        }

        if ($nextSlot -eq 0) {
            Write-Warn "All 10 AI slots are configured."
            $addMore = $false
        } else {
            Write-Host "Enter slot number [$nextSlot]: " -NoNewline
            $slotInput = Read-Host
            $slot = if ($slotInput) { [int]$slotInput } else { $nextSlot }

            if ($slot -ge 1 -and $slot -le 10) {
                $config = Add-AIConnection -SlotNumber $slot -Config $config
            }
        }
    } else {
        $addMore = $false
    }
}

# Show all configured connections
Write-Host ""
Write-Host "Final Connection Status:" -ForegroundColor Cyan
Show-ConnectionsTable -Config $config | Out-Null

# Role mapping
Write-Host ""
Write-Host "Configure role mappings? [Y/n]: " -NoNewline
$doRoles = Read-Host
if (-not $doRoles -or $doRoles.ToLower() -eq "y") {
    $config = Start-RoleMappingWizard -Config $config
}

# Save configuration
Write-Host ""
Write-Check "Saving configuration..."

try {
    # Ensure config directory exists
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    Save-Connections -Connections $config.connections
    Save-Credentials -Credentials $config.credentials
    Save-Roles -Roles $config.roles

    Write-Pass "Configuration saved!"
    Write-Info "connections.json - AI connection definitions"
    Write-Info "credentials.local.json - API keys (gitignored)"
    Write-Info "roles.json - Role-to-connection mappings"
} catch {
    Write-Fail "Failed to save configuration: $_"
    exit 1
}

# Show final role mappings
Show-RoleMappings -Config $config

# Run health check
Write-Host ""
Write-Host "Run full health check? [Y/n]: " -NoNewline
$doHealth = Read-Host
if (-not $doHealth -or $doHealth.ToLower() -eq "y") {
    $healthScript = Join-Path $PSScriptRoot "check-orchestration-health.ps1"
    if (Test-Path $healthScript) {
        & $healthScript
    }
}

Write-Host ""
Write-Pass "Configuration complete!"
Write-Host ""
