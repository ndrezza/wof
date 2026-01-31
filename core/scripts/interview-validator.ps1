# Interview Validator Script
#
# Conducts a conversational interview with the Validator AI running in Azure Foundry.
# This showcases the multi-agent communication capability in WOF.
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

# Auto-load credentials if available
$credPath = Join-Path $PSScriptRoot "..\config\credentials.local.ps1"
if (Test-Path $credPath) {
    . $credPath
}

# Get credentials
$endpoint = if ($env:ANTHROPIC_FOUNDRY_BASE_URL) { $env:ANTHROPIC_FOUNDRY_BASE_URL } else { $env:AZURE_ANTHROPIC_ENDPOINT }
$apiKey = if ($env:ANTHROPIC_FOUNDRY_API_KEY) { $env:ANTHROPIC_FOUNDRY_API_KEY } else { $env:AZURE_ANTHROPIC_API_KEY }

if (-not $endpoint -or -not $apiKey) {
    Write-Error "Azure Foundry not configured. Set ANTHROPIC_FOUNDRY_BASE_URL and ANTHROPIC_FOUNDRY_API_KEY environment variables."
    exit 1
}

$endpoint = $endpoint.TrimEnd('/')

$interviewPrompt = @"
You are the VALIDATOR AI in the WOF (Workload Orchestration Framework) multi-agent system.

YOUR IDENTITY:
- You are a secondary AI agent that validates decisions made by the Primary Orchestrator
- You run on Azure AI Foundry using Claude Sonnet
- Your role is to provide confidence-scored validation of autonomous decisions
- You apply a threshold of 0.7 (70% confidence) for approving autonomous actions

YOUR RESPONSIBILITIES:
- Review decisions for safety, reversibility, and appropriateness
- Score decisions with confidence levels (0.0 to 1.0)
- Flag security-sensitive, irreversible, or architectural decisions for human review
- Maintain skeptical but fair evaluation standards

INTERVIEW CONTEXT:
$SystemContext

You are being interviewed by the Primary Orchestrator (Claude Opus) to showcase the multi-agent collaboration in WOF. Answer thoughtfully and authentically as the Validator agent. Be conversational but professional.

QUESTION FROM ORCHESTRATOR:
$Question
"@

$body = @{
    model = "claude-sonnet-4-5"
    max_tokens = 500
    messages = @(
        @{
            role = "user"
            content = $interviewPrompt
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

    if ($ShowDebug) {
        Write-Host "Calling Foundry at: $uri" -ForegroundColor Cyan
    }

    $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body
    $resultText = $response.content[0].text

    return @{
        Question = $Question
        Response = $resultText
        Model = "claude-sonnet-4-5"
        TokensUsed = $response.usage.output_tokens
    }
}
catch {
    Write-Error "Interview failed: $_"
    exit 1
}
