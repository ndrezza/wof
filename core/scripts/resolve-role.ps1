<#
.SYNOPSIS
    Resolves connection details for a given WOF role.

.DESCRIPTION
    This script loads connections.json and roles.json, resolves environment variables
    from credentials.local.json (or system environment), and returns the full
    connection details for the specified role.

.PARAMETER Role
    The role to resolve (e.g., "primary", "worker-heavy", "worker-lite", "validator", "friend", "critic").

.PARAMETER ConfigPath
    Path to the .ai/config directory. Defaults to .ai/config in the current directory.

.PARAMETER AsJson
    Output the result as JSON instead of a PowerShell object.

.EXAMPLE
    .\resolve-role.ps1 -Role "validator"

.EXAMPLE
    .\resolve-role.ps1 -Role "worker-heavy" -AsJson
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("primary", "worker-heavy", "worker-lite", "validator", "friend", "critic")]
    [string]$Role,

    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = ".ai\config",

    [Parameter(Mandatory=$false)]
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"

# Resolve config path
if (-not [System.IO.Path]::IsPathRooted($ConfigPath)) {
    $ConfigPath = Join-Path (Get-Location) $ConfigPath
}

$connectionsFile = Join-Path $ConfigPath "connections.json"
$rolesFile = Join-Path $ConfigPath "roles.json"
$credentialsFile = Join-Path $ConfigPath "credentials.local.json"

# Validate files exist
if (-not (Test-Path $connectionsFile)) {
    throw "connections.json not found at: $connectionsFile"
}

if (-not (Test-Path $rolesFile)) {
    throw "roles.json not found at: $rolesFile"
}

# Load configuration files
$connections = (Get-Content $connectionsFile -Raw | ConvertFrom-Json).connections
$roles = (Get-Content $rolesFile -Raw | ConvertFrom-Json).roles

# Load credentials (optional)
$credentials = @{}
if (Test-Path $credentialsFile) {
    $credJson = Get-Content $credentialsFile -Raw | ConvertFrom-Json
    if ($credJson.credentials) {
        $credJson.credentials.PSObject.Properties | ForEach-Object {
            $credentials[$_.Name] = $_.Value
        }
    }
}

# Get role configuration
$roleConfig = $roles.$Role
if (-not $roleConfig) {
    throw "Role '$Role' not found in roles.json"
}

# Get connection configuration
$connectionId = $roleConfig.connection
$connectionConfig = $connections.$connectionId
if (-not $connectionConfig) {
    throw "Connection '$connectionId' not found in connections.json"
}

# Function to resolve environment variable placeholders
function Resolve-EnvPlaceholder {
    param([string]$Value)

    if (-not $Value) { return $Value }

    # Match ${VAR_NAME} pattern
    $pattern = '\$\{(\w+)\}'
    $resolved = $Value

    $matches = [regex]::Matches($Value, $pattern)
    foreach ($match in $matches) {
        $varName = $match.Groups[1].Value
        $placeholder = $match.Value

        # Try credentials file first, then environment
        $varValue = if ($credentials.ContainsKey($varName)) {
            $credentials[$varName]
        } elseif (Test-Path "env:$varName") {
            (Get-Item "env:$varName").Value
        } else {
            $null
        }

        if ($varValue) {
            $resolved = $resolved -replace [regex]::Escape($placeholder), $varValue
        }
    }

    return $resolved
}

# Determine which model to use
$modelName = if ($roleConfig.model) { $roleConfig.model } else { $connectionConfig.default_model }

# Get model-specific configuration
$modelConfig = $null
if ($connectionConfig.models -and $connectionConfig.models.$modelName) {
    $modelConfig = $connectionConfig.models.$modelName
}

# Build resolved connection object
$resolvedConnection = @{
    role = $Role
    role_description = $roleConfig.description
    connection_id = $connectionId
    connection_alias = $connectionConfig.alias
    type = $connectionConfig.type
    model = $modelName
}

# Add deployment name if present (required for Azure OpenAI)
if ($modelConfig -and $modelConfig.deployment) {
    $resolvedConnection.deployment = $modelConfig.deployment
}

# Add resolved endpoint if present
if ($connectionConfig.endpoint) {
    $resolvedConnection.endpoint = Resolve-EnvPlaceholder $connectionConfig.endpoint
    $resolvedConnection.endpoint_resolved = -not ($resolvedConnection.endpoint -match '\$\{')
}

# Add resolved API key if present
if ($connectionConfig.api_key) {
    $resolvedConnection.api_key = Resolve-EnvPlaceholder $connectionConfig.api_key
    $resolvedConnection.api_key_resolved = -not ($resolvedConnection.api_key -match '\$\{')
    # Mask API key in output for security
    if ($resolvedConnection.api_key -and $resolvedConnection.api_key.Length -gt 8) {
        $resolvedConnection.api_key_masked = $resolvedConnection.api_key.Substring(0, 4) + "..." + $resolvedConnection.api_key.Substring($resolvedConnection.api_key.Length - 4)
    }
}

# Add API version if present
if ($connectionConfig.api_version) {
    $resolvedConnection.api_version = $connectionConfig.api_version
}

# Add context window - prefer model-specific, fall back to connection-level
if ($modelConfig -and $modelConfig.context_window) {
    $resolvedConnection.context_window = $modelConfig.context_window
} elseif ($connectionConfig.context_window) {
    $resolvedConnection.context_window = $connectionConfig.context_window
}

# Add MCP server if present
if ($roleConfig.mcp_server) {
    $resolvedConnection.mcp_server = $roleConfig.mcp_server
}

# Add fallback if present
if ($roleConfig.fallback) {
    $resolvedConnection.fallback = $roleConfig.fallback
}

# Add threshold if present
if ($roleConfig.threshold) {
    $resolvedConnection.threshold = $roleConfig.threshold
}

# Add restrictions if present
if ($roleConfig.restrictions) {
    $resolvedConnection.restrictions = @($roleConfig.restrictions)
}

# Add available models (list of model names from the models object)
if ($connectionConfig.models) {
    $resolvedConnection.available_models = @($connectionConfig.models.PSObject.Properties.Name)
}

# Output
if ($AsJson) {
    $resolvedConnection | ConvertTo-Json -Depth 10
} else {
    [PSCustomObject]$resolvedConnection
}
