<#
.SYNOPSIS
    Delegates tasks to the local Worker-Lite model.

.DESCRIPTION
    Sends requests to the local model (endpoint from LOCAL_WORKER_ENDPOINT env var).
    Used for T1 lightweight tasks: file search, simple formatting, code navigation.
    Falls back gracefully if local model is unavailable.

.PARAMETER Task
    The task description to send to the local model.

.PARAMETER MaxTokens
    Maximum tokens for the response (default: 2048).

.PARAMETER SystemPrompt
    Optional system prompt override.

.EXAMPLE
    .\delegate-to-local-worker.ps1 -Task "Find all files containing 'ILogger'"

.EXAMPLE
    .\delegate-to-local-worker.ps1 -Task "Format this code snippet" -MaxTokens 1024
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Task,

    [Parameter(Mandatory = $false)]
    [int]$MaxTokens = 2048,

    [Parameter(Mandatory = $false)]
    [string]$SystemPrompt = "You are a helpful coding assistant. Keep responses concise and focused."
)

$ErrorActionPreference = "Stop"

# Configuration
$baseEndpoint = if ($env:LOCAL_WORKER_ENDPOINT) { $env:LOCAL_WORKER_ENDPOINT } else { "http://127.0.0.1:1234" }
$endpoint = "$baseEndpoint/v1/chat/completions"
$model = "deepseek-coder-v2-lite-instruct"
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
