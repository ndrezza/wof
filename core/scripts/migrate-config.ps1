<#
.SYNOPSIS
    Migrates WOF configuration from v1 (YAML/PS1) to v2 (JSON) format.

.DESCRIPTION
    This script detects the old configuration format (providers.yaml + credentials.local.ps1)
    and migrates it to the new JSON-based format (connections.json, roles.json, credentials.local.json).

    Old files are backed up to .ai/.deprecated/ before migration.

.PARAMETER TargetPath
    The root path of the target project where WOF is installed.

.PARAMETER DryRun
    Show what would be migrated without making changes.

.PARAMETER Force
    Overwrite existing v2 config files if they exist.

.EXAMPLE
    .\migrate-config.ps1 -TargetPath "C:\code\MyProject"

.EXAMPLE
    .\migrate-config.ps1 -TargetPath "C:\code\MyProject" -DryRun
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$TargetPath,

    [Parameter(Mandatory=$false)]
    [switch]$DryRun,

    [Parameter(Mandatory=$false)]
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# Color helpers
function Write-Step { param([string]$Message) Write-Host "[*] $Message" -ForegroundColor Cyan }
function Write-Success { param([string]$Message) Write-Host "[+] $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "[!] $Message" -ForegroundColor Yellow }
function Write-Info { param([string]$Message) Write-Host "    $Message" -ForegroundColor Gray }

$aiDir = Join-Path $TargetPath ".ai"
$configDir = Join-Path $aiDir "config"
$deprecatedDir = Join-Path $aiDir ".deprecated"

# Old format files
$oldProvidersYaml = Join-Path $configDir "providers.yaml"
$oldCredentialsPs1 = Join-Path $configDir "credentials.local.ps1"

# New format files
$newConnectionsJson = Join-Path $configDir "connections.json"
$newRolesJson = Join-Path $configDir "roles.json"
$newCredentialsJson = Join-Path $configDir "credentials.local.json"

Write-Host ""
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "            WOF CONFIGURATION MIGRATION (v1 -> v2)                            " -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Target: $TargetPath"
if ($DryRun) { Write-Host "  Mode:   DRY RUN" -ForegroundColor Yellow }
Write-Host ""

# Check if migration is needed
$hasOldFormat = (Test-Path $oldProvidersYaml) -or (Test-Path $oldCredentialsPs1)
$hasNewFormat = (Test-Path $newConnectionsJson) -and (Test-Path $newRolesJson)

if (-not $hasOldFormat) {
    Write-Info "No v1 configuration files found. Migration not needed."
    return @{ Success = $true; Migrated = $false; Reason = "NoOldFormat" }
}

if ($hasNewFormat -and -not $Force) {
    Write-Warn "v2 configuration files already exist. Use -Force to overwrite."
    return @{ Success = $true; Migrated = $false; Reason = "AlreadyMigrated" }
}

Write-Step "Detecting v1 configuration..."

# Parse old providers.yaml to extract connection and role info
$connections = @{}
$roles = @{}

if (Test-Path $oldProvidersYaml) {
    Write-Info "Found: providers.yaml"
    $yamlContent = Get-Content $oldProvidersYaml -Raw

    # Simple YAML parsing for our known structure
    # Extract provider blocks
    $providerMatches = [regex]::Matches($yamlContent, '(?ms)^\s{2}(\w+):\s*$(.+?)(?=^\s{2}\w+:|^orchestration:|^task_delegation:|$)')

    $connectionIndex = 1
    $connectionIdMap = @{} # Maps old provider name to new connection ID

    foreach ($match in $providerMatches) {
        $providerName = $match.Groups[1].Value
        $providerBlock = $match.Groups[2].Value

        # Skip non-provider sections
        if ($providerName -in @('orchestration', 'task_delegation', 'roles', 'delegation_routing')) { continue }

        # Extract type
        $typeMatch = [regex]::Match($providerBlock, 'type:\s*(\S+)')
        $type = if ($typeMatch.Success) { $typeMatch.Groups[1].Value } else { "unknown" }

        # Determine connection ID based on type
        $connectionId = switch ($type) {
            "claude_code_native" { "native" }
            "azure_ai_foundry_anthropic" {
                if (-not $connectionIdMap.ContainsValue("ai1")) { "ai1" } else { "ai$connectionIndex" }
            }
            "azure_openai" {
                # Check if this is codex (has codex in name or endpoint)
                if ($providerName -match "codex|critic") {
                    "ai3"
                } else {
                    "ai2"
                }
            }
            "openai_compatible" { "ai4" }
            default { "ai$connectionIndex" }
        }

        if ($connectionId -notmatch "^(native|ai[1-9]|ai10)$") {
            $connectionIndex++
        }

        $connectionIdMap[$providerName] = $connectionId

        # Extract endpoint and api_key patterns
        $endpointMatch = [regex]::Match($providerBlock, 'endpoint:\s*["'']?\$\{(\w+)\}["'']?')
        $apiKeyMatch = [regex]::Match($providerBlock, 'api_key:\s*["'']?\$\{(\w+)\}["'']?')
        $apiVersionMatch = [regex]::Match($providerBlock, 'api_version:\s*["'']?([^"''\s]+)["'']?')
        $contextWindowMatch = [regex]::Match($providerBlock, 'context_window:\s*(\d+)')

        # Extract models
        $modelMatches = [regex]::Matches($providerBlock, '(?:opus|sonnet|gpt4o|codex_mini|deepseek):\s*["'']?([^"''\s]+)["'']?')
        $models = @()
        foreach ($m in $modelMatches) {
            $models += $m.Groups[1].Value
        }

        # Extract name/alias
        $nameMatch = [regex]::Match($providerBlock, 'name:\s*["'']?([^"''\r\n]+)["'']?')
        $alias = if ($nameMatch.Success) { $nameMatch.Groups[1].Value.Trim() } else { $providerName }

        # Extract description
        $descMatch = [regex]::Match($providerBlock, 'description:\s*["'']?([^"''\r\n]+)["'']?')
        $description = if ($descMatch.Success) { $descMatch.Groups[1].Value.Trim() } else { "" }

        # Build connection object (skip native as it doesn't need full config)
        if ($type -ne "claude_code_native" -and -not $connections.ContainsKey($connectionId)) {
            $conn = @{
                alias = $alias -replace '\s*\([^)]+\)', '' # Remove role hints like "(GPT-4o)"
                description = $description
                type = $type
            }

            if ($endpointMatch.Success) {
                # Map old env var to new generic format
                $oldEnvVar = $endpointMatch.Groups[1].Value
                $newEnvVar = switch ($connectionId) {
                    "ai1" { "AI1_ENDPOINT" }
                    "ai2" { "AI2_ENDPOINT" }
                    "ai3" { "AI3_ENDPOINT" }
                    "ai4" { "AI4_ENDPOINT" }
                    default { $oldEnvVar }
                }
                $conn.endpoint = "`${$newEnvVar}"
            }

            if ($apiKeyMatch.Success) {
                $oldEnvVar = $apiKeyMatch.Groups[1].Value
                $newEnvVar = switch ($connectionId) {
                    "ai1" { "AI1_API_KEY" }
                    "ai2" { "AI2_API_KEY" }
                    "ai3" { "AI3_API_KEY" }
                    default { "" }
                }
                $conn.api_key = if ($newEnvVar) { "`${$newEnvVar}" } else { "" }
            }

            if ($apiVersionMatch.Success) {
                $conn.api_version = $apiVersionMatch.Groups[1].Value
            }

            if ($models.Count -gt 0) {
                $conn.models = $models
            }

            if ($contextWindowMatch.Success) {
                $conn.context_window = [int]$contextWindowMatch.Groups[1].Value
            }

            $connections[$connectionId] = $conn
        }

        # Extract role info
        $roleMatch = [regex]::Match($providerBlock, 'role:\s*(\w+)')
        if ($roleMatch.Success) {
            $oldRoleName = $roleMatch.Groups[1].Value
            $newRoleName = switch ($oldRoleName) {
                "primary_orchestrator" { "primary" }
                "worker" { "worker-heavy" }
                "worker_lite" { "worker-lite" }
                default { $oldRoleName }
            }

            $role = @{
                description = $description
                connection = $connectionId
            }

            if ($models.Count -gt 0) {
                $role.model = $models[0]
            }

            # Extract threshold
            $thresholdMatch = [regex]::Match($providerBlock, 'threshold:\s*([\d.]+)')
            if ($thresholdMatch.Success) {
                $role.threshold = [double]$thresholdMatch.Groups[1].Value
            }

            # Extract restrictions
            $restrictionsMatch = [regex]::Match($providerBlock, '(?ms)restrictions:\s*$(.*?)(?=^\s{4}\w+:|^\s{2}\w+:|$)')
            if ($restrictionsMatch.Success) {
                $restrictionLines = $restrictionsMatch.Groups[1].Value -split "`n" |
                    Where-Object { $_ -match '^\s*-\s*"([^"]+)"' } |
                    ForEach-Object { [regex]::Match($_, '"([^"]+)"').Groups[1].Value }
                if ($restrictionLines.Count -gt 0) {
                    $role.restrictions = @($restrictionLines)
                }
            }

            $roles[$newRoleName] = $role
        }
    }

    # Extract MCP server and fallback info from task_delegation section
    $taskDelegationMatch = [regex]::Match($yamlContent, '(?ms)^task_delegation:\s*$(.+?)(?=^[^\s]|$)')
    if ($taskDelegationMatch.Success) {
        $delegationBlock = $taskDelegationMatch.Groups[1].Value

        # WorkerHeavy
        $heavyMcpMatch = [regex]::Match($delegationBlock, 'WorkerHeavy:.*?mcp_server:\s*(\S+)', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if ($heavyMcpMatch.Success -and $roles.ContainsKey("worker-heavy")) {
            $roles["worker-heavy"].mcp_server = $heavyMcpMatch.Groups[1].Value
        }

        # WorkerLite
        $liteMcpMatch = [regex]::Match($delegationBlock, 'WorkerLite:.*?mcp_server:\s*(\S+)', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        $liteFallbackMatch = [regex]::Match($delegationBlock, 'WorkerLite:.*?fallback:\s*(\S+)', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if ($roles.ContainsKey("worker-lite")) {
            if ($liteMcpMatch.Success) {
                $roles["worker-lite"].mcp_server = $liteMcpMatch.Groups[1].Value
            }
            if ($liteFallbackMatch.Success) {
                $fallback = $liteFallbackMatch.Groups[1].Value
                $roles["worker-lite"].fallback = if ($fallback -eq "WorkerHeavy") { "worker-heavy" } else { $fallback }
            }
        }
    }

    # Ensure native connection exists
    if (-not $connections.ContainsKey("native")) {
        $connections["native"] = @{
            alias = "Claude Code Native"
            description = "Native Claude Code connection (no external API)"
            type = "claude_code_native"
            models = @("claude-opus-4-5-20251101")
        }
    }
}

# Parse old credentials.local.ps1 to extract actual values
$credentialValues = @{}

if (Test-Path $oldCredentialsPs1) {
    Write-Info "Found: credentials.local.ps1"
    $ps1Content = Get-Content $oldCredentialsPs1 -Raw

    # Extract env var assignments
    $envVarMatches = [regex]::Matches($ps1Content, '\$env:(\w+)\s*=\s*[''"]([^''"]+)[''"]')

    foreach ($match in $envVarMatches) {
        $varName = $match.Groups[1].Value
        $varValue = $match.Groups[2].Value

        # Skip template placeholders
        if ($varValue -match '^\{\{.*\}\}$') { continue }

        # Map old env var names to new generic names
        $newVarName = switch ($varName) {
            "AZURE_ANTHROPIC_ENDPOINT" { "AI1_ENDPOINT" }
            "AZURE_ANTHROPIC_API_KEY" { "AI1_API_KEY" }
            "ANTHROPIC_FOUNDRY_BASE_URL" { $null } # Skip alias
            "ANTHROPIC_FOUNDRY_API_KEY" { $null } # Skip alias
            "AZURE_OPENAI_ENDPOINT" { "AI2_ENDPOINT" }
            "AZURE_OPENAI_API_KEY" { "AI2_API_KEY" }
            "AZURE_CODEX_ENDPOINT" { "AI3_ENDPOINT" }
            "AZURE_CODEX_API_KEY" { "AI3_API_KEY" }
            "LOCAL_WORKER_ENDPOINT" { "AI4_ENDPOINT" }
            default { $varName }
        }

        if ($newVarName -and -not $credentialValues.ContainsKey($newVarName)) {
            $credentialValues[$newVarName] = $varValue
        }
    }
}

Write-Step "Migration Summary..."
Write-Info "Connections found: $($connections.Count)"
Write-Info "Roles found: $($roles.Count)"
Write-Info "Credentials found: $($credentialValues.Count)"

if ($DryRun) {
    Write-Host ""
    Write-Step "Would create the following files:"
    Write-Info "connections.json with: $($connections.Keys -join ', ')"
    Write-Info "roles.json with: $($roles.Keys -join ', ')"
    Write-Info "credentials.local.json with: $($credentialValues.Keys -join ', ')"
    Write-Host ""
    Write-Step "Would backup the following files to .deprecated/:"
    if (Test-Path $oldProvidersYaml) { Write-Info "providers.yaml" }
    if (Test-Path $oldCredentialsPs1) { Write-Info "credentials.local.ps1" }

    return @{ Success = $true; Migrated = $false; Reason = "DryRun" }
}

# Create deprecated directory
if (-not (Test-Path $deprecatedDir)) {
    New-Item -ItemType Directory -Path $deprecatedDir -Force | Out-Null
}

Write-Step "Backing up old configuration files..."

# Backup old files
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
if (Test-Path $oldProvidersYaml) {
    $backupPath = Join-Path $deprecatedDir "providers.yaml.$timestamp.bak"
    Copy-Item $oldProvidersYaml $backupPath
    Write-Info "Backed up: providers.yaml"
}

if (Test-Path $oldCredentialsPs1) {
    $backupPath = Join-Path $deprecatedDir "credentials.local.ps1.$timestamp.bak"
    Copy-Item $oldCredentialsPs1 $backupPath
    Write-Info "Backed up: credentials.local.ps1"
}

Write-Step "Creating v2 configuration files..."

# Create connections.json
$connectionsObj = @{
    '$schema' = "https://json-schema.org/draft/2020-12/schema"
    version = "2.0.0"
    description = "Role-agnostic AI connection definitions. Migrated from providers.yaml."
    connections = $connections
}
$connectionsJson = $connectionsObj | ConvertTo-Json -Depth 10
Set-Content -Path $newConnectionsJson -Value $connectionsJson -Encoding UTF8
Write-Info "Created: connections.json"

# Create roles.json
$rolesObj = @{
    '$schema' = "https://json-schema.org/draft/2020-12/schema"
    version = "2.0.0"
    description = "Role-to-connection mapping. Migrated from providers.yaml."
    roles = $roles
}
$rolesJson = $rolesObj | ConvertTo-Json -Depth 10
Set-Content -Path $newRolesJson -Value $rolesJson -Encoding UTF8
Write-Info "Created: roles.json"

# Create credentials.local.json
$credentialsObj = @{
    '$schema' = "https://json-schema.org/draft/2020-12/schema"
    version = "2.0.0"
    description = "Local credentials. Migrated from credentials.local.ps1."
    credentials = $credentialValues
}
$credentialsJson = $credentialsObj | ConvertTo-Json -Depth 10
Set-Content -Path $newCredentialsJson -Value $credentialsJson -Encoding UTF8
Write-Info "Created: credentials.local.json"

Write-Host ""
Write-Host "================================================================================" -ForegroundColor Green
Write-Host "                           MIGRATION COMPLETE                                  " -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Green
Write-Host ""
Write-Success "Configuration migrated from v1 to v2 format"
Write-Host ""
Write-Host "  New files created:" -ForegroundColor Cyan
Write-Host "    - .ai/config/connections.json"
Write-Host "    - .ai/config/roles.json"
Write-Host "    - .ai/config/credentials.local.json"
Write-Host ""
Write-Host "  Old files backed up to:" -ForegroundColor Yellow
Write-Host "    - .ai/.deprecated/"
Write-Host ""
Write-Warn "Review the migrated files and verify the configuration is correct."
Write-Host ""

return @{
    Success = $true
    Migrated = $true
    ConnectionsCount = $connections.Count
    RolesCount = $roles.Count
    CredentialsCount = $credentialValues.Count
}
