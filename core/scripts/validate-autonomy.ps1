# Autonomy Validation Script
#
# This script delegates a decision to Azure Foundry (Sonnet) to determine
# if the primary orchestrator should proceed autonomously or ask the user.
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

# Auto-load credentials if available
$credPath = Join-Path $PSScriptRoot "..\config\credentials.local.ps1"
if (Test-Path $credPath) {
    . $credPath
}

# Get credentials
$endpoint = if ($env:ANTHROPIC_FOUNDRY_BASE_URL) { $env:ANTHROPIC_FOUNDRY_BASE_URL } else { $env:AZURE_ANTHROPIC_ENDPOINT }
$apiKey = if ($env:ANTHROPIC_FOUNDRY_API_KEY) { $env:ANTHROPIC_FOUNDRY_API_KEY } else { $env:AZURE_ANTHROPIC_API_KEY }

if (-not $endpoint -or -not $apiKey) {
    # No Azure credentials - fall back to asking user
    return @{
        Proceed = $false
        Reason = "Azure Foundry not configured - requires user decision. Run: copy .ai\config\credentials.template.ps1 .ai\config\credentials.local.ps1 and fill in your Azure credentials."
        Confidence = 0
    }
}

$endpoint = $endpoint.TrimEnd('/')

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

$body = @{
    model = "claude-sonnet-4-5"
    max_tokens = 200
    messages = @(
        @{
            role = "user"
            content = $validatorPrompt
        }
    )
} | ConvertTo-Json -Depth 10

$headers = @{
    "api-key" = $apiKey
    "x-api-key" = $apiKey
    "Content-Type" = "application/json"
    "anthropic-version" = "2023-06-01"
}

try {
    $uri = "$endpoint/v1/messages?api-version=2025-01-01-preview"
    $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body
    $resultText = $response.content[0].text

    # Parse JSON response
    $jsonMatch = [regex]::Match($resultText, '\{[^}]+\}')
    if ($jsonMatch.Success) {
        $parsed = $jsonMatch.Value | ConvertFrom-Json
        return @{
            Proceed = $parsed.proceed
            Confidence = $parsed.confidence
            Reason = $parsed.reason
        }
    }

    # Fallback if parsing fails
    return @{
        Proceed = $false
        Reason = "Could not parse validator response - asking user"
        Confidence = 0
    }
}
catch {
    return @{
        Proceed = $false
        Reason = "Validator error: $_ - asking user"
        Confidence = 0
    }
}
