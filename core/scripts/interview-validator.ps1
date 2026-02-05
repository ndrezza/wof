# ============================================================================
# WOF MANAGED FILE - DO NOT EDIT MANUALLY
# This file is managed by the Workload Orchestration Framework.
# Changes will be overwritten on the next WOF sync/update.
# To customize behavior, use configuration files in .ai/config/
# ============================================================================

# Interview Validator Script
#
# Conducts a conversational interview with the Validator AI.
# Uses resolve-role.ps1 for connection configuration.
#
# Usage:
#   .\interview-validator.ps1 -Question "What is your role?"
#   .\interview-validator.ps1 -Question "How do you decide?" -SystemContext "You are being interviewed for a demo"

param(
    [Parameter(Mandatory=$true)]
    [string]$Question,

    [Parameter(Mandatory=$false)]
    [string]$SystemContext = "",

    [Parameter(Mandatory=$false)]
    [switch]$ShowDebug
)

# Resolve validator connection using v2 config
$resolveScript = Join-Path $PSScriptRoot "resolve-role.ps1"
if (-not (Test-Path $resolveScript)) {
    Write-Error "STOP: resolve-role.ps1 not found. WOF installation may be corrupted."
    return @{ ConfigError = $true; Error = "resolve-role.ps1 not found" }
}

$config = & $resolveScript -Role "validator"

if ($config.ConfigError) {
    Write-Error "STOP: Validator AI not configured. $($config.Error)"
    return @{ ConfigError = $true; Error = $config.Error }
}

$endpoint = $config.Endpoint.TrimEnd('/')
$apiKey = $config.ApiKey
$apiType = $config.Type
$model = $config.Model

if ($ShowDebug) {
    Write-Host "Using connection: $($config.ConnectionId) ($apiType)" -ForegroundColor Cyan
    Write-Host "Model: $model" -ForegroundColor Cyan
}

$interviewPrompt = @"
You are the VALIDATOR AI in the WOF (Workload Orchestration Framework) multi-agent system.

YOUR IDENTITY:
- You are a secondary AI agent that validates decisions made by the Primary Orchestrator
- Your role is to provide confidence-scored validation of autonomous decisions
- You apply a threshold of 0.7 (70% confidence) for approving autonomous actions

YOUR RESPONSIBILITIES:
- Review decisions for safety, reversibility, and appropriateness
- Score decisions with confidence levels (0.0 to 1.0)
- Flag security-sensitive, irreversible, or architectural decisions for human review
- Maintain skeptical but fair evaluation standards

INTERVIEW CONTEXT:
$SystemContext

You are being interviewed by the Primary Orchestrator to showcase the multi-agent collaboration in WOF. Answer thoughtfully and authentically as the Validator agent. Be conversational but professional.

QUESTION FROM ORCHESTRATOR:
$Question
"@

# Build request based on API type
$headers = @{ "Content-Type" = "application/json" }

switch ($apiType) {
    "anthropic" {
        $uri = "$endpoint/v1/messages"
        $headers["x-api-key"] = $apiKey
        $headers["anthropic-version"] = "2023-06-01"
        $body = @{
            model = $model
            max_tokens = 500
            messages = @(@{ role = "user"; content = $interviewPrompt })
        } | ConvertTo-Json -Depth 10
    }
    "azure-openai" {
        $uri = "$endpoint/openai/deployments/$model/chat/completions?api-version=2025-01-01-preview"
        $headers["api-key"] = $apiKey
        $body = @{
            max_tokens = 500
            messages = @(@{ role = "user"; content = $interviewPrompt })
        } | ConvertTo-Json -Depth 10
    }
    "openai-compatible" {
        $uri = "$endpoint/v1/chat/completions"
        if ($apiKey -and $apiKey -ne "not-needed") {
            $headers["Authorization"] = "Bearer $apiKey"
        }
        $body = @{
            model = $model
            max_tokens = 500
            messages = @(@{ role = "user"; content = $interviewPrompt })
        } | ConvertTo-Json -Depth 10
    }
    default {
        Write-Error "STOP: Unsupported API type: $apiType"
        return @{ ConfigError = $true; Error = "Unsupported API type: $apiType" }
    }
}

try {
    if ($ShowDebug) {
        Write-Host "Calling: $uri" -ForegroundColor Cyan
    }

    $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body

    # Extract response text based on API type
    $resultText = switch ($apiType) {
        "anthropic" { $response.content[0].text }
        default { $response.choices[0].message.content }
    }

    return @{
        Question = $Question
        Response = $resultText
        Model = $model
        ConnectionId = $config.ConnectionId
    }
}
catch {
    Write-Error "Interview failed: $_"
    return @{ Error = $_.Exception.Message }
}
