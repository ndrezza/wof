# Autonomy Validation Script
#
# This script delegates a decision to the configured Validator AI to determine
# if the primary orchestrator should proceed autonomously or ask the user.
#
# Uses resolve-role.ps1 to get connection details from connections.json + roles.json
#
# Usage:
#   $result = & .\validate-autonomy.ps1 -Decision "Should I refactor this code?" -Context "User asked to improve performance"
#   if ($result.Proceed) { # do it } else { # ask user: $result.Reason }

param(
    [Parameter(Mandatory=$true)]
    [string]$Decision,

    [Parameter(Mandatory=$false)]
    [string]$Context = "",

    [Parameter(Mandatory=$false)]
    [string]$RiskLevel = "medium"  # low, medium, high
)

$ErrorActionPreference = "Stop"

# Resolve validator connection using v2 config
$resolveScript = Join-Path $PSScriptRoot "resolve-role.ps1"
if (-not (Test-Path $resolveScript)) {
    return @{
        Proceed = $false
        Reason = "STOP: resolve-role.ps1 not found. WOF installation may be incomplete."
        Confidence = 0
        ConfigError = $true
    }
}

try {
    $validatorConfig = & $resolveScript -Role "validator" -ConfigPath (Join-Path $PSScriptRoot "..\config")
}
catch {
    return @{
        Proceed = $false
        Reason = "STOP: Could not resolve validator role - $_"
        Confidence = 0
        ConfigError = $true
    }
}

# Check if credentials are resolved
if (-not $validatorConfig.endpoint_resolved -or -not $validatorConfig.api_key_resolved) {
    return @{
        Proceed = $false
        Reason = "STOP: Validator AI not configured. Edit .ai/config/credentials.local.json and fill in the credentials for connection '$($validatorConfig.connection_id)'. DO NOT attempt to work around this - tell the user to configure credentials."
        Confidence = 0
        ConfigError = $true
        Connection = $validatorConfig.connection_id
        Type = $validatorConfig.type
    }
}

$endpoint = $validatorConfig.endpoint.TrimEnd('/')
$apiKey = $validatorConfig.api_key
$model = $validatorConfig.model
$apiType = $validatorConfig.type

# Build the validation prompt
$validatorPrompt = @"
You are an AUTONOMY VALIDATOR for an AI orchestration system.

Your role: Decide if the primary AI orchestrator should proceed autonomously OR ask the user.

CONTEXT:
- Risk Level: $RiskLevel
- User Context: $Context

DECISION REQUESTED:
$Decision

GUIDELINES:
- PROCEED if: The action is safe, reversible, follows standard patterns, or is explicitly within scope
- ASK USER if: Security-sensitive, irreversible, architectural change, ambiguous requirement, or high-risk

Respond in this EXACT JSON format only:
{"proceed": true/false, "confidence": 0.0-1.0, "reason": "brief explanation"}
"@

# Build request based on API type
$headers = @{
    "Content-Type" = "application/json"
}

switch ($apiType) {
    "anthropic" {
        # Azure AI Foundry Anthropic API
        $headers["api-key"] = $apiKey
        $headers["x-api-key"] = $apiKey
        $headers["anthropic-version"] = "2023-06-01"

        $body = @{
            model = $model
            max_tokens = 200
            messages = @(
                @{ role = "user"; content = $validatorPrompt }
            )
        } | ConvertTo-Json -Depth 10

        $uri = "$endpoint/v1/messages"
        if ($validatorConfig.api_version) {
            $uri = "$uri`?api-version=$($validatorConfig.api_version)"
        }
    }

    "azure-openai" {
        # Azure OpenAI API
        $headers["api-key"] = $apiKey

        $deployment = if ($validatorConfig.deployment) { $validatorConfig.deployment } else { $model }

        $body = @{
            messages = @(
                @{ role = "user"; content = $validatorPrompt }
            )
            max_tokens = 200
        } | ConvertTo-Json -Depth 10

        $apiVersion = if ($validatorConfig.api_version) { $validatorConfig.api_version } else { "2024-02-15-preview" }
        $uri = "$endpoint/openai/deployments/$deployment/chat/completions?api-version=$apiVersion"
    }

    "openai-compatible" {
        # OpenAI-compatible API (local models, etc.)
        if ($apiKey -and $apiKey -ne "not-needed") {
            $headers["Authorization"] = "Bearer $apiKey"
        }

        $body = @{
            model = $model
            messages = @(
                @{ role = "user"; content = $validatorPrompt }
            )
            max_tokens = 200
        } | ConvertTo-Json -Depth 10

        $uri = "$endpoint/v1/chat/completions"
    }

    default {
        return @{
            Proceed = $false
            Reason = "STOP: Unknown API type '$apiType' for validator connection. Supported: anthropic, azure-openai, openai-compatible"
            Confidence = 0
            ConfigError = $true
        }
    }
}

try {
    $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -TimeoutSec 30

    # Extract response text based on API type
    $resultText = switch ($apiType) {
        "anthropic" { $response.content[0].text }
        "azure-openai" { $response.choices[0].message.content }
        "openai-compatible" { $response.choices[0].message.content }
    }

    # Parse JSON response
    $jsonMatch = [regex]::Match($resultText, '\{[^}]+\}')
    if ($jsonMatch.Success) {
        $parsed = $jsonMatch.Value | ConvertFrom-Json
        return @{
            Proceed = $parsed.proceed
            Confidence = $parsed.confidence
            Reason = $parsed.reason
            ValidatorModel = $model
            ValidatorType = $apiType
        }
    }

    # Fallback if parsing fails
    return @{
        Proceed = $false
        Reason = "Could not parse validator response - asking user. Raw: $resultText"
        Confidence = 0
    }
}
catch {
    return @{
        Proceed = $false
        Reason = "Validator API error: $_ - asking user"
        Confidence = 0
        ApiError = $true
    }
}
