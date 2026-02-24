# ============================================================================
# WOF MANAGED FILE - DO NOT EDIT MANUALLY
# This file is managed by the Workload Orchestration Framework.
# Changes will be overwritten on the next WOF sync/update.
# To customize behavior, use configuration files in .ai/config/
# ============================================================================

<#
.SYNOPSIS
    Unified AI invocation script for WOF.

.DESCRIPTION
    Consolidates all API call logic into a single entry point. Supports:
    - Direct REST API calls (anthropic, azure-openai, openai-compatible)
    - Process delegation (claude --print)
    - Script delegation (PowerShell scripts with -InputJson)

    Native and MCP delegation methods are handled by Claude Code itself,
    not by this script. If a role uses native/mcp delegation, this script
    returns an informational error directing the caller to use Claude Code.

.PARAMETER Role
    The WOF role to invoke (e.g., "validator", "critic", "worker-lite").
    Mutually exclusive with -ConnectionId.

.PARAMETER ConnectionId
    A connection ID from connections.json (e.g., "ai1", "ai4").
    Mutually exclusive with -Role.

.PARAMETER Prompt
    The user prompt to send to the AI.

.PARAMETER SystemPrompt
    Optional system prompt. If omitted, no system message is sent.

.PARAMETER Model
    Override the model from the role/connection config.

.PARAMETER MaxTokens
    Maximum tokens for the response. Default: 1024.

.PARAMETER Temperature
    Temperature for sampling. Default: -1 (use API default).

.PARAMETER AsJson
    Output the result as a JSON string instead of a PowerShell object.

.PARAMETER ConfigPath
    Path to the .ai/config directory. Defaults to .ai/config in the current directory.

.EXAMPLE
    .\invoke-ai.ps1 -Role "validator" -Prompt "Should I refactor this?" -AsJson

.EXAMPLE
    .\invoke-ai.ps1 -ConnectionId "ai4" -Prompt "Hello" -MaxTokens 256

.EXAMPLE
    .\invoke-ai.ps1 -Role "worker-lite" -Prompt "Find files with ILogger" -SystemPrompt "You are a code search assistant."
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("primary", "worker-heavy", "worker-lite", "validator", "critic")]
    [string]$Role,

    [Parameter(Mandatory=$false)]
    [string]$ConnectionId,

    [Parameter(Mandatory=$true)]
    [string]$Prompt,

    [Parameter(Mandatory=$false)]
    [string]$SystemPrompt,

    [Parameter(Mandatory=$false)]
    [string]$Model,

    [Parameter(Mandatory=$false)]
    [int]$MaxTokens = 1024,

    [Parameter(Mandatory=$false)]
    [double]$Temperature = -1,

    [Parameter(Mandatory=$false)]
    [switch]$AsJson,

    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = ".ai\config"
)

$ErrorActionPreference = "Stop"

# =============================================================================
# PARAMETER VALIDATION
# =============================================================================

if ($Role -and $ConnectionId) {
    $result = @{
        Success = $false
        Content = $null
        Model = $null
        TokensUsed = 0
        ConnectionType = $null
        ConnectionId = $null
        Latency = 0
        Error = "Specify either -Role or -ConnectionId, not both."
    }
    if ($AsJson) { return $result | ConvertTo-Json -Depth 10 }
    return [PSCustomObject]$result
}

if (-not $Role -and -not $ConnectionId) {
    $result = @{
        Success = $false
        Content = $null
        Model = $null
        TokensUsed = 0
        ConnectionType = $null
        ConnectionId = $null
        Latency = 0
        Error = "Specify either -Role or -ConnectionId."
    }
    if ($AsJson) { return $result | ConvertTo-Json -Depth 10 }
    return [PSCustomObject]$result
}

# =============================================================================
# HELPER: Build standardized result
# =============================================================================

function New-AiResult {
    param(
        [bool]$Success,
        [string]$Content,
        [string]$ModelName,
        [int]$TokensUsed = 0,
        [string]$ConnType,
        [string]$ConnId,
        [long]$Latency = 0,
        [string]$Error
    )
    return @{
        Success = $Success
        Content = $Content
        Model = $ModelName
        TokensUsed = $TokensUsed
        ConnectionType = $ConnType
        ConnectionId = $ConnId
        Latency = $Latency
        Error = $Error
    }
}

# =============================================================================
# RESOLVE CONNECTION
# =============================================================================

# Resolve config path
if (-not [System.IO.Path]::IsPathRooted($ConfigPath)) {
    $ConfigPath = Join-Path (Get-Location) $ConfigPath
}

$delegation = $null
$scriptPath = $null
$connConfig = $null
$resolvedModel = $null
$resolvedConnId = $null
$resolvedType = $null
$resolvedEndpoint = $null
$resolvedApiKey = $null
$resolvedDeployment = $null
$resolvedApiVersion = $null

if ($Role) {
    # Resolve via resolve-role.ps1
    $resolveScript = Join-Path $PSScriptRoot "resolve-role.ps1"
    if (-not (Test-Path $resolveScript)) {
        $result = New-AiResult -Success $false -Error "resolve-role.ps1 not found at $PSScriptRoot. WOF installation may be incomplete."
        if ($AsJson) { return $result | ConvertTo-Json -Depth 10 }
        return [PSCustomObject]$result
    }

    try {
        $connConfig = & $resolveScript -Role $Role -ConfigPath $ConfigPath
    }
    catch {
        $result = New-AiResult -Success $false -Error "Failed to resolve role '$Role': $_"
        if ($AsJson) { return $result | ConvertTo-Json -Depth 10 }
        return [PSCustomObject]$result
    }

    $delegation = $connConfig.delegation
    $scriptPath = $connConfig.script
    $resolvedModel = if ($Model) { $Model } else { $connConfig.model }
    $resolvedConnId = $connConfig.connection_id
    $resolvedType = $connConfig.type
    $resolvedEndpoint = if ($connConfig.endpoint) { $connConfig.endpoint.TrimEnd('/') } else { $null }
    $resolvedApiKey = $connConfig.api_key
    $resolvedDeployment = $connConfig.deployment
    $resolvedApiVersion = $connConfig.api_version
}
else {
    # Resolve via ConnectionId — load connections.json + credentials directly
    $connectionsFile = Join-Path $ConfigPath "connections.json"
    $credentialsFile = Join-Path $ConfigPath "credentials.local.json"

    if (-not (Test-Path $connectionsFile)) {
        $result = New-AiResult -Success $false -Error "connections.json not found at: $connectionsFile"
        if ($AsJson) { return $result | ConvertTo-Json -Depth 10 }
        return [PSCustomObject]$result
    }

    $connections = (Get-Content $connectionsFile -Raw | ConvertFrom-Json).connections
    $connection = $connections.$ConnectionId
    if (-not $connection) {
        $result = New-AiResult -Success $false -Error "Connection '$ConnectionId' not found in connections.json."
        if ($AsJson) { return $result | ConvertTo-Json -Depth 10 }
        return [PSCustomObject]$result
    }

    # Load credentials for env variable resolution
    $credentials = @{}
    if (Test-Path $credentialsFile) {
        $credJson = Get-Content $credentialsFile -Raw | ConvertFrom-Json
        if ($credJson.credentials) {
            $credJson.credentials.PSObject.Properties | ForEach-Object {
                $credentials[$_.Name] = $_.Value
            }
        }
    }

    # Resolve env placeholders
    function Resolve-Placeholder {
        param([string]$Value)
        if (-not $Value) { return $Value }
        $pattern = '\$\{(\w+)\}'
        $resolved = $Value
        $matches = [regex]::Matches($Value, $pattern)
        foreach ($match in $matches) {
            $varName = $match.Groups[1].Value
            $varValue = if ($credentials.ContainsKey($varName)) {
                $credentials[$varName]
            } elseif (Test-Path "env:$varName") {
                (Get-Item "env:$varName").Value
            } else { $null }
            if ($varValue) {
                $resolved = $resolved -replace [regex]::Escape($match.Value), $varValue
            }
        }
        return $resolved
    }

    $resolvedModel = if ($Model) { $Model } else { $connection.default_model }
    $resolvedConnId = $ConnectionId
    $resolvedType = $connection.type
    $resolvedEndpoint = if ($connection.endpoint) { (Resolve-Placeholder $connection.endpoint).TrimEnd('/') } else { $null }
    $resolvedApiKey = if ($connection.api_key) { Resolve-Placeholder $connection.api_key } else { $null }

    # Get deployment from model config
    if ($connection.models -and $connection.models.$resolvedModel -and $connection.models.$resolvedModel.deployment) {
        $resolvedDeployment = $connection.models.$resolvedModel.deployment
    }
    $resolvedApiVersion = $connection.api_version
}

# =============================================================================
# DELEGATION ROUTING
# =============================================================================

$sw = [System.Diagnostics.Stopwatch]::StartNew()

# Check delegation method
if ($delegation -eq "native" -or $delegation -eq "mcp") {
    $sw.Stop()
    $result = New-AiResult -Success $false `
        -ConnType $resolvedType -ConnId $resolvedConnId -ModelName $resolvedModel `
        -Error "Role '$Role' uses '$delegation' delegation, which is handled by Claude Code natively (not by invoke-ai.ps1). Use Claude Code's built-in capabilities or MCP tools instead."
    if ($AsJson) { return $result | ConvertTo-Json -Depth 10 }
    return [PSCustomObject]$result
}

# --- Process delegation: claude --print ---
if ($delegation -eq "process") {
    try {
        $claudeArgs = @("--print", "--prompt", $Prompt)
        if ($resolvedModel) {
            $claudeArgs += @("--model", $resolvedModel)
        }
        if ($SystemPrompt) {
            $claudeArgs += @("--system-prompt", $SystemPrompt)
        }
        if ($MaxTokens -and $MaxTokens -ne 1024) {
            $claudeArgs += @("--max-tokens", $MaxTokens.ToString())
        }

        $output = & claude @claudeArgs 2>&1
        $sw.Stop()

        $content = ($output | Where-Object { $_ -is [string] -or $_.GetType().Name -ne 'ErrorRecord' }) -join "`n"

        $result = New-AiResult -Success $true -Content $content `
            -ModelName $resolvedModel -ConnType "process" -ConnId $resolvedConnId `
            -Latency $sw.ElapsedMilliseconds
        if ($AsJson) { return $result | ConvertTo-Json -Depth 10 }
        return [PSCustomObject]$result
    }
    catch {
        $sw.Stop()
        $result = New-AiResult -Success $false `
            -ConnType "process" -ConnId $resolvedConnId -ModelName $resolvedModel `
            -Latency $sw.ElapsedMilliseconds `
            -Error "Process delegation failed: $_"
        if ($AsJson) { return $result | ConvertTo-Json -Depth 10 }
        return [PSCustomObject]$result
    }
}

# --- Script delegation: PowerShell script with -InputJson ---
if ($delegation -eq "script") {
    if (-not $scriptPath) {
        $sw.Stop()
        $result = New-AiResult -Success $false `
            -ConnType "script" -ConnId $resolvedConnId -ModelName $resolvedModel `
            -Error "Role '$Role' uses script delegation but no 'script' path is configured in roles.json."
        if ($AsJson) { return $result | ConvertTo-Json -Depth 10 }
        return [PSCustomObject]$result
    }

    # Build the standardized InputJson contract
    $inputPayload = @{
        prompt = $Prompt
        systemPrompt = $SystemPrompt
        model = $resolvedModel
        maxTokens = $MaxTokens
        connection = @{
            id = $resolvedConnId
            type = $resolvedType
            endpoint = $resolvedEndpoint
            apiKey = $resolvedApiKey
            deployment = $resolvedDeployment
            apiVersion = $resolvedApiVersion
        }
    } | ConvertTo-Json -Depth 10

    try {
        $scriptFullPath = if ([System.IO.Path]::IsPathRooted($scriptPath)) {
            $scriptPath
        } else {
            Join-Path (Get-Location) $scriptPath
        }

        if (-not (Test-Path $scriptFullPath)) {
            $sw.Stop()
            $result = New-AiResult -Success $false `
                -ConnType "script" -ConnId $resolvedConnId -ModelName $resolvedModel `
                -Error "Script not found: $scriptFullPath"
            if ($AsJson) { return $result | ConvertTo-Json -Depth 10 }
            return [PSCustomObject]$result
        }

        $scriptOutput = & $scriptFullPath -InputJson $inputPayload
        $sw.Stop()

        # Try parsing script output as JSON
        $parsed = $null
        try {
            $rawOutput = if ($scriptOutput -is [array]) { $scriptOutput -join "" } else { "$scriptOutput" }
            $parsed = $rawOutput | ConvertFrom-Json
        } catch {
            # Not JSON — treat raw output as content
        }

        if ($parsed -and $null -ne $parsed.Success) {
            # Script returned our standard format
            $parsedModel = if ($parsed.Model) { $parsed.Model } else { $resolvedModel }
            $parsedTokens = if ($parsed.TokensUsed) { $parsed.TokensUsed } else { 0 }
            $result = New-AiResult -Success $parsed.Success `
                -Content $parsed.Content `
                -ModelName $parsedModel `
                -TokensUsed $parsedTokens `
                -ConnType "script" -ConnId $resolvedConnId `
                -Latency $sw.ElapsedMilliseconds `
                -Error $parsed.Error
            if ($AsJson) { return $result | ConvertTo-Json -Depth 10 }
            return [PSCustomObject]$result
        }

        # Raw output
        $result = New-AiResult -Success $true `
            -Content $rawOutput `
            -ModelName $resolvedModel `
            -ConnType "script" -ConnId $resolvedConnId `
            -Latency $sw.ElapsedMilliseconds
        if ($AsJson) { return $result | ConvertTo-Json -Depth 10 }
        return [PSCustomObject]$result
    }
    catch {
        $sw.Stop()
        $result = New-AiResult -Success $false `
            -ConnType "script" -ConnId $resolvedConnId -ModelName $resolvedModel `
            -Latency $sw.ElapsedMilliseconds `
            -Error "Script delegation failed: $_"
        if ($AsJson) { return $result | ConvertTo-Json -Depth 10 }
        return [PSCustomObject]$result
    }
}

# =============================================================================
# DIRECT REST API CALL
# =============================================================================

# Validate we have endpoint and API key for direct calls
if (-not $resolvedEndpoint) {
    $sw.Stop()
    $result = New-AiResult -Success $false `
        -ConnType $resolvedType -ConnId $resolvedConnId -ModelName $resolvedModel `
        -Error "No endpoint configured for connection '$resolvedConnId'. Check connections.json and credentials.local.json."
    if ($AsJson) { return $result | ConvertTo-Json -Depth 10 }
    return [PSCustomObject]$result
}

if ($resolvedEndpoint -match '\$\{') {
    $sw.Stop()
    $result = New-AiResult -Success $false `
        -ConnType $resolvedType -ConnId $resolvedConnId -ModelName $resolvedModel `
        -Error "Endpoint contains unresolved variables. Check credentials.local.json for connection '$resolvedConnId'."
    if ($AsJson) { return $result | ConvertTo-Json -Depth 10 }
    return [PSCustomObject]$result
}

# Build request
$headers = @{
    "Content-Type" = "application/json"
}

$uri = $null
$body = $null

switch ($resolvedType) {
    "anthropic" {
        # Anthropic / Azure AI Foundry Anthropic API
        $headers["api-key"] = $resolvedApiKey
        $headers["x-api-key"] = $resolvedApiKey
        $headers["anthropic-version"] = "2023-06-01"

        $messages = @(
            @{ role = "user"; content = $Prompt }
        )

        $bodyObj = @{
            model = $resolvedModel
            max_tokens = $MaxTokens
            messages = $messages
        }

        if ($SystemPrompt) {
            $bodyObj.system = $SystemPrompt
        }

        if ($Temperature -ge 0) {
            $bodyObj.temperature = $Temperature
        }

        $body = $bodyObj | ConvertTo-Json -Depth 10

        $uri = "$resolvedEndpoint/v1/messages"
        if ($resolvedApiVersion) {
            $uri = "$uri`?api-version=$resolvedApiVersion"
        }
    }

    "azure-openai" {
        # Azure OpenAI API
        $headers["api-key"] = $resolvedApiKey

        $deployment = if ($resolvedDeployment) { $resolvedDeployment } else { $resolvedModel }

        $messages = @()
        if ($SystemPrompt) {
            $messages += @{ role = "system"; content = $SystemPrompt }
        }
        $messages += @{ role = "user"; content = $Prompt }

        $bodyObj = @{
            messages = $messages
            max_tokens = $MaxTokens
        }

        if ($Temperature -ge 0) {
            $bodyObj.temperature = $Temperature
        }

        $body = $bodyObj | ConvertTo-Json -Depth 10

        $apiVersion = if ($resolvedApiVersion) { $resolvedApiVersion } else { "2024-02-15-preview" }
        $uri = "$resolvedEndpoint/openai/deployments/$deployment/chat/completions?api-version=$apiVersion"
    }

    "openai-compatible" {
        # OpenAI-compatible API (Ollama, local models, etc.)
        if ($resolvedApiKey -and $resolvedApiKey -ne "not-needed" -and $resolvedApiKey -ne "ollama") {
            $headers["Authorization"] = "Bearer $resolvedApiKey"
        }

        $messages = @()
        if ($SystemPrompt) {
            $messages += @{ role = "system"; content = $SystemPrompt }
        }
        $messages += @{ role = "user"; content = $Prompt }

        $bodyObj = @{
            model = $resolvedModel
            messages = $messages
            max_tokens = $MaxTokens
        }

        if ($Temperature -ge 0) {
            $bodyObj.temperature = $Temperature
        }

        $body = $bodyObj | ConvertTo-Json -Depth 10

        $uri = "$resolvedEndpoint/v1/chat/completions"
    }

    default {
        $sw.Stop()
        $result = New-AiResult -Success $false `
            -ConnType $resolvedType -ConnId $resolvedConnId -ModelName $resolvedModel `
            -Error "Unknown connection type '$resolvedType'. Supported: anthropic, azure-openai, openai-compatible"
        if ($AsJson) { return $result | ConvertTo-Json -Depth 10 }
        return [PSCustomObject]$result
    }
}

# Execute REST call
try {
    $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -TimeoutSec 60
    $sw.Stop()

    # Normalize response based on API type
    $content = switch ($resolvedType) {
        "anthropic" { $response.content[0].text }
        "azure-openai" { $response.choices[0].message.content }
        "openai-compatible" { $response.choices[0].message.content }
    }

    # Extract token usage
    $tokensUsed = 0
    if ($response.usage) {
        $tokensUsed = if ($response.usage.total_tokens) {
            $response.usage.total_tokens
        } elseif ($response.usage.input_tokens -and $response.usage.output_tokens) {
            $response.usage.input_tokens + $response.usage.output_tokens
        } else { 0 }
    }

    $result = New-AiResult -Success $true -Content $content `
        -ModelName $resolvedModel -TokensUsed $tokensUsed `
        -ConnType $resolvedType -ConnId $resolvedConnId `
        -Latency $sw.ElapsedMilliseconds
    if ($AsJson) { return $result | ConvertTo-Json -Depth 10 }
    return [PSCustomObject]$result
}
catch {
    $sw.Stop()
    $errorMsg = $_.Exception.Message

    # Try to extract more detail from the response
    if ($_.Exception.Response) {
        try {
            $stream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $responseBody = $reader.ReadToEnd()
            if ($responseBody) {
                $errorMsg = "$errorMsg | Response: $responseBody"
            }
        } catch {
            # Ignore errors reading error response
        }
    }

    $result = New-AiResult -Success $false `
        -ConnType $resolvedType -ConnId $resolvedConnId -ModelName $resolvedModel `
        -Latency $sw.ElapsedMilliseconds `
        -Error "REST API call failed: $errorMsg"
    if ($AsJson) { return $result | ConvertTo-Json -Depth 10 }
    return [PSCustomObject]$result
}
