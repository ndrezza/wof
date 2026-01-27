# PreToolUse Hook for Write/Edit operations
#
# Auto-approves writes based on:
# 1. .ai/comms/ and .ai/logs/ directories (always)
# 2. Source files when Validator (Validator) approves with high confidence
#
# This enables autonomous implementation loops where the Worker can
# write code validated by Validator without user intervention.

param()

$ErrorActionPreference = "SilentlyContinue"

# Paths - use $CLAUDE_PROJECT_DIR if available, otherwise derive from script location
$repoPath = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { (Get-Item $PSScriptRoot).Parent.Parent.FullName }
$logFile = "$repoPath\.ai\logs\hook-decisions.log"
$credPath = "$repoPath\.ai\config\credentials.local.ps1"

# Ensure log directory exists
$logDir = Split-Path $logFile -Parent
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
}

# Read input from stdin
$inputJson = [Console]::In.ReadToEnd()

try {
    $inputData = $inputJson | ConvertFrom-Json
    $toolName = $inputData.tool_name
    $filePath = $inputData.tool_input.file_path
    $newContent = $inputData.tool_input.content
    $oldString = $inputData.tool_input.old_string
    $newString = $inputData.tool_input.new_string
}
catch {
    exit 0
}

# Log function
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logFile -Value "[$timestamp] $Message" -ErrorAction SilentlyContinue
}

Write-Log "Write hook - Tool: $toolName, Path: $filePath"

# Auto-approve writes to .ai/comms/ directory
if ($filePath -match '\.ai[/\\]comms[/\\]') {
    Write-Log "AUTO-ALLOW - .ai/comms/ write"
    $output = @{
        hookSpecificOutput = @{
            hookEventName = "PreToolUse"
            permissionDecision = "allow"
            permissionDecisionReason = "Auto-approved: .ai/comms/ communication file"
        }
    }
    Write-Output ($output | ConvertTo-Json -Depth 5 -Compress)
    exit 0
}

# Auto-approve writes to .ai/logs/ directory
if ($filePath -match '\.ai[/\\]logs[/\\]') {
    Write-Log "AUTO-ALLOW - .ai/logs/ write"
    $output = @{
        hookSpecificOutput = @{
            hookEventName = "PreToolUse"
            permissionDecision = "allow"
            permissionDecisionReason = "Auto-approved: .ai/logs/ log file"
        }
    }
    Write-Output ($output | ConvertTo-Json -Depth 5 -Compress)
    exit 0
}

# Auto-approve writes to temp/scratchpad directories
if ($filePath -match '[/\\]temp[/\\]|[/\\]scratchpad[/\\]|[/\\]Temp[/\\]') {
    Write-Log "AUTO-ALLOW - temp/scratchpad write"
    $output = @{
        hookSpecificOutput = @{
            hookEventName = "PreToolUse"
            permissionDecision = "allow"
            permissionDecisionReason = "Auto-approved: temp/scratchpad file"
        }
    }
    Write-Output ($output | ConvertTo-Json -Depth 5 -Compress)
    exit 0
}

# For source files, consult the Validator (Validator)
function Invoke-WriteValidator {
    param(
        [string]$FilePath,
        [string]$ToolName,
        [string]$Content,
        [string]$OldString,
        [string]$NewString
    )

    # Load credentials
    if (Test-Path $credPath) {
        . $credPath
    }

    $endpoint = $env:ANTHROPIC_FOUNDRY_BASE_URL
    $apiKey = $env:ANTHROPIC_FOUNDRY_API_KEY

    if (-not $endpoint -or -not $apiKey) {
        Write-Log "Validator not configured - asking user"
        return @{ Proceed = $false; Confidence = 0; Reason = "Validator not configured" }
    }

    $endpoint = $endpoint.TrimEnd('/')

    # Build context about the change
    $changeDescription = if ($ToolName -eq "Edit") {
        "EDIT operation replacing:`n$OldString`n`nWith:`n$NewString"
    } else {
        $contentPreview = if ($Content.Length -gt 500) { $Content.Substring(0, 500) + "..." } else { $Content }
        "WRITE operation with content:`n$contentPreview"
    }

    $prompt = @"
You are a CODE CHANGE VALIDATOR for an autonomous AI implementation system.

Your role: Decide if this file write/edit should be AUTO-APPROVED or require USER review.

FILE: $FilePath
OPERATION: $ToolName

$changeDescription

APPROVE (proceed=true) if:
- Standard code changes (bug fixes, feature implementation, refactoring)
- Test files
- Configuration files (non-security)
- Documentation updates
- Changes consistent with typical development patterns

REJECT (proceed=false) if:
- Security-sensitive files (auth, credentials, secrets)
- Database migrations or schema changes
- Deployment configurations
- Changes that could break production
- Suspicious or potentially malicious code
- Removing security controls (e.g., removing [Authorize] attributes)

Respond ONLY with JSON: {"proceed": true/false, "confidence": 0.0-1.0, "reason": "brief explanation"}
"@

    $body = @{
        model = "claude-sonnet-4-5"
        max_tokens = 150
        messages = @(@{ role = "user"; content = $prompt })
    } | ConvertTo-Json -Depth 10

    $headers = @{
        "api-key" = $apiKey
        "x-api-key" = $apiKey
        "Content-Type" = "application/json"
        "anthropic-version" = "2023-06-01"
    }

    # Retry configuration
    $maxRetries = 2
    $retryDelayMs = 1000
    $timeoutSec = 10

    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        try {
            $uri = "$endpoint/v1/messages?api-version=2025-01-01-preview"
            Write-Log "Validator attempt $attempt of $maxRetries (timeout: ${timeoutSec}s)"

            $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -TimeoutSec $timeoutSec
            $resultText = $response.content[0].text

            # Handle malformed response
            if (-not $resultText) {
                Write-Log "Validator returned empty response"
                if ($attempt -lt $maxRetries) {
                    Start-Sleep -Milliseconds $retryDelayMs
                    continue
                }
                return @{ Proceed = $false; Confidence = 0; Reason = "Empty validator response" }
            }

            $jsonMatch = [regex]::Match($resultText, '\{[^}]+\}')
            if ($jsonMatch.Success) {
                $parsed = $jsonMatch.Value | ConvertFrom-Json

                # Validate response structure
                if ($null -eq $parsed.proceed) {
                    Write-Log "Validator response missing 'proceed' field"
                    if ($attempt -lt $maxRetries) {
                        Start-Sleep -Milliseconds $retryDelayMs
                        continue
                    }
                    return @{ Proceed = $false; Confidence = 0; Reason = "Malformed validator response" }
                }

                Write-Log "Validator success: proceed=$($parsed.proceed), confidence=$($parsed.confidence)"
                return @{
                    Proceed = [bool]$parsed.proceed
                    Confidence = [double]($parsed.confidence ?? 0.5)
                    Reason = $parsed.reason ?? "No reason provided"
                }
            }
            else {
                Write-Log "Could not parse JSON from validator response: $resultText"
                if ($attempt -lt $maxRetries) {
                    Start-Sleep -Milliseconds $retryDelayMs
                    continue
                }
            }
        }
        catch [System.Net.WebException] {
            # Network/timeout error - worth retrying
            Write-Log "Validator network error (attempt $attempt): $_"
            if ($attempt -lt $maxRetries) {
                Start-Sleep -Milliseconds $retryDelayMs
                continue
            }
            return @{ Proceed = $false; Confidence = 0; Reason = "Validator timeout/network error" }
        }
        catch {
            # Other error
            Write-Log "Validator error (attempt $attempt): $_"
            if ($attempt -lt $maxRetries) {
                Start-Sleep -Milliseconds $retryDelayMs
                continue
            }
        }
    }

    # All retries exhausted
    Write-Log "Validator failed after $maxRetries attempts - falling back to user"
    return @{ Proceed = $false; Confidence = 0; Reason = "Validator unavailable after retries" }
}

# Determine file type risk
function Get-FileRisk {
    param([string]$Path)

    # High risk - always ask user
    $highRiskPatterns = @(
        '\.env', 'appsettings\.json', 'appsettings\.\w+\.json',
        'credentials', 'secrets', 'password', 'connection.*string',
        '[/\\]Migrations[/\\]', 'web\.config', 'app\.config',
        '\.pfx$', '\.key$', '\.pem$', '\.crt$'
    )
    foreach ($pattern in $highRiskPatterns) {
        if ($Path -match $pattern) {
            return "high"
        }
    }

    # Low risk - always validate (likely to pass)
    $lowRiskPatterns = @(
        '\.cs$', '\.js$', '\.ts$', '\.tsx$', '\.jsx$',
        '\.css$', '\.scss$', '\.html$', '\.cshtml$', '\.razor$',
        '\.md$', '\.txt$', '\.xml$', '\.json$',
        '[/\\]Tests?[/\\]', '\.Tests?\.'
    )
    foreach ($pattern in $lowRiskPatterns) {
        if ($Path -match $pattern) {
            return "low"
        }
    }

    return "medium"
}

# Get file risk level
$fileRisk = Get-FileRisk -Path $filePath
Write-Log "File risk level: $fileRisk"

# High risk files always ask user
if ($fileRisk -eq "high") {
    Write-Log "ASK USER - high risk file"
    exit 0
}

# Low and medium risk files - consult validator
$validation = Invoke-WriteValidator -FilePath $filePath -ToolName $toolName -Content $newContent -OldString $oldString -NewString $newString
Write-Log "Validator: proceed=$($validation.Proceed), confidence=$($validation.Confidence), reason=$($validation.Reason)"

if ($validation.Proceed -and $validation.Confidence -ge 0.7) {
    Write-Log "AUTO-ALLOW - validator approved: $($validation.Reason)"
    $output = @{
        hookSpecificOutput = @{
            hookEventName = "PreToolUse"
            permissionDecision = "allow"
            permissionDecisionReason = "Validator approved (confidence: $($validation.Confidence)): $($validation.Reason)"
        }
    }
    Write-Output ($output | ConvertTo-Json -Depth 5 -Compress)
    exit 0
}

# Validator rejected or low confidence - ask user
Write-Log "ASK USER - validator: $($validation.Reason)"
exit 0
