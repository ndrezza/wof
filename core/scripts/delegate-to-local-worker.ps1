# ============================================================================
# WOF MANAGED FILE - DO NOT EDIT MANUALLY
# This file is managed by the Workload Orchestration Framework.
# Changes will be overwritten on the next WOF sync/update.
# To customize behavior, use configuration files in .ai/config/
# ============================================================================

<#
.SYNOPSIS
    Delegates tasks to the local Worker-Lite model.

.DESCRIPTION
    Sends requests to the local model (endpoint from LOCAL_WORKER_ENDPOINT env var).
    Used for T1 lightweight tasks: file search, simple formatting, code navigation.
    Falls back gracefully if local model is unavailable.

    Supports two invocation modes:
    1. Legacy: -Task "description" (existing callers)
    2. Generic script contract: -InputJson '{"prompt":"...", "connection":{...}}'
       Used by invoke-ai.ps1 for standardized script delegation.

.PARAMETER Task
    The task description to send to the local model.

.PARAMETER MaxTokens
    Maximum tokens for the response (default: 2048).

.PARAMETER SystemPrompt
    Optional system prompt override.

.PARAMETER InputJson
    JSON string following the WOF script delegation contract.
    When provided, overrides Task, MaxTokens, SystemPrompt, and connection settings.
    Expected format: {"prompt":"...", "systemPrompt":"...", "model":"...", "maxTokens":N,
                      "connection":{"endpoint":"...", "apiKey":"...", ...}}

.EXAMPLE
    .\delegate-to-local-worker.ps1 -Task "Find all files containing 'ILogger'"

.EXAMPLE
    .\delegate-to-local-worker.ps1 -Task "Format this code snippet" -MaxTokens 1024

.EXAMPLE
    .\delegate-to-local-worker.ps1 -InputJson '{"prompt":"Hello","maxTokens":256}'
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$Task,

    [Parameter(Mandatory = $false)]
    [int]$MaxTokens = 2048,

    [Parameter(Mandatory = $false)]
    [string]$SystemPrompt = "You are a helpful coding assistant. Keep responses concise and focused.",

    [Parameter(Mandatory = $false)]
    [string]$InputJson
)

$ErrorActionPreference = "Stop"

# =============================================================================
# INPUT JSON CONTRACT (generic script delegation)
# =============================================================================
# When -InputJson is provided, parse it and override parameters.
# This enables invoke-ai.ps1 to call this script with standardized input.

if ($InputJson) {
    try {
        $input = $InputJson | ConvertFrom-Json
        $Task = $input.prompt
        if ($input.systemPrompt) { $SystemPrompt = $input.systemPrompt }
        if ($input.maxTokens -and $input.maxTokens -gt 0) { $MaxTokens = $input.maxTokens }
    }
    catch {
        return (@{
            Success = $false
            Content = $null
            Error = "Failed to parse InputJson: $_"
        } | ConvertTo-Json -Depth 5)
    }
}

# Validate that Task is provided (required for both modes)
if (-not $Task) {
    return (@{
        Success = $false
        Content = $null
        Error = "No task specified. Provide -Task or -InputJson with a 'prompt' field."
    } | ConvertTo-Json -Depth 5)
}

# =============================================================================
# CONNECTION CONFIGURATION
# =============================================================================
# If InputJson provided connection details, use them. Otherwise use defaults/env.

$inputConnection = $null
if ($InputJson) {
    try {
        $parsedInput = $InputJson | ConvertFrom-Json
        $inputConnection = $parsedInput.connection
    } catch { }
}

# Configuration
$baseEndpoint = if ($inputConnection -and $inputConnection.endpoint) {
    $inputConnection.endpoint.TrimEnd('/')
} elseif ($env:LOCAL_WORKER_ENDPOINT) {
    $env:LOCAL_WORKER_ENDPOINT
} else {
    "http://127.0.0.1:1234"
}
$endpoint = "$baseEndpoint/v1/chat/completions"
$model = if ($InputJson) {
    $parsedForModel = $InputJson | ConvertFrom-Json
    if ($parsedForModel.model) { $parsedForModel.model } else { "deepseek-coder-v2-lite-instruct" }
} else {
    "deepseek-coder-v2-lite-instruct"
}
$timeout = 60  # seconds

function Test-LocalModelAvailable {
    try {
        $response = Invoke-WebRequest -Uri "$baseEndpoint/v1/models" -Method GET -TimeoutSec 5 -ErrorAction SilentlyContinue
        return $response.StatusCode -eq 200
    }
    catch {
        return $false
    }
}

function Invoke-LocalWorker {
    param(
        [string]$TaskDescription,
        [int]$Tokens,
        [string]$System
    )

    $body = @{
        model = $model
        max_tokens = $Tokens
        messages = @(
            @{
                role = "system"
                content = $System
            },
            @{
                role = "user"
                content = $TaskDescription
            }
        )
    } | ConvertTo-Json -Depth 10

    $headers = @{
        "Content-Type" = "application/json"
    }

    try {
        $response = Invoke-RestMethod -Uri $endpoint -Method POST -Body $body -Headers $headers -TimeoutSec $timeout
        return @{
            Success = $true
            Content = $response.choices[0].message.content
            Model = $model
            Provider = "local_worker"
            TokensUsed = $response.usage.total_tokens
        }
    }
    catch {
        return @{
            Success = $false
            Error = $_.Exception.Message
            Fallback = "WorkerHeavy"
        }
    }
}

# Main execution
Write-Host "Worker-Lite: Checking local model availability..." -ForegroundColor Cyan

if (-not (Test-LocalModelAvailable)) {
    Write-Host "Worker-Lite: Local model unavailable. Falling back to Worker-Heavy." -ForegroundColor Yellow
    return @{
        Success = $false
        Available = $false
        Fallback = "WorkerHeavy"
        Message = "Local model is not running at $endpoint"
    } | ConvertTo-Json
}

Write-Host "Worker-Lite: Local model available. Processing task..." -ForegroundColor Green

$result = Invoke-LocalWorker -TaskDescription $Task -Tokens $MaxTokens -System $SystemPrompt

if ($result.Success) {
    Write-Host "Worker-Lite: Task completed successfully." -ForegroundColor Green
}
else {
    Write-Host "Worker-Lite: Task failed. Error: $($result.Error)" -ForegroundColor Red
}

return $result | ConvertTo-Json -Depth 5
