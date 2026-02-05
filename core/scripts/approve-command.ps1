# ============================================================================
# WOF MANAGED FILE - DO NOT EDIT MANUALLY
# This file is managed by the Workload Orchestration Framework.
# Changes will be overwritten on the next WOF sync/update.
# To customize behavior, use configuration files in .ai/config/
# ============================================================================

# PreToolUse Hook Script for Claude Code
#
# This script is called BEFORE any Bash command is executed.
# It receives JSON via stdin and returns a decision via stdout.
#
# Exit codes:
#   0 + JSON with permissionDecision -> Control the permission
#   0 (no output) -> Let normal permission flow proceed
#   2 + stderr message -> Block with error shown to Claude
#
# Risk levels:
#   LOW -> Auto-allow
#   MEDIUM -> Consult Validator validator
#   HIGH -> Let user decide (normal flow)

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
    $command = $inputData.tool_input.command
    $toolName = $inputData.tool_name
}
catch {
    # If we can't parse input, let normal flow proceed
    exit 0
}

# Log function
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logFile -Value "[$timestamp] $Message" -ErrorAction SilentlyContinue
}

Write-Log "Hook invoked - Tool: $toolName, Command: $command"

# Only process Bash commands
if ($toolName -ne "Bash") {
    Write-Log "Not a Bash command, skipping"
    exit 0
}

# Risk classification
function Get-RiskLevel {
    param([string]$Cmd)

    # Always allow - trivial commands
    if ($Cmd -match "^(echo|pwd|whoami|date)") {
        return "always_allow"
    }

    # Always block - dangerous patterns
    $blocked = @("rm -rf /", "rm -rf ~", ":(){ :|:& };:", "> /dev/sda")
    foreach ($b in $blocked) {
        if ($Cmd -eq $b) {
            return "blocked"
        }
    }

    # Low risk - read-only and standard dev commands
    $lowPatterns = @(
        "^dotnet build", "^dotnet test", "^dotnet restore", "^dotnet clean",
        "^git status", "^git diff", "^git log", "^git branch", "^git show",
        "^ls", "^dir", "^cat ", "^head ", "^tail ", "^grep ", "^rg ", "^find ",
        "^npm list", "^npm outdated", "^npm audit$",
        "^pwd", "^which ", "^where ", "^type ", "^mkdir", "^echo "
    )
    foreach ($pattern in $lowPatterns) {
        if ($Cmd -match $pattern) {
            return "low"
        }
    }

    # High risk - destructive or remote operations
    $highPatterns = @(
        "git push", "git reset --hard", "git rebase", "--force",
        "^rm -rf", "^rm -r ", "^rmdir /s",
        "^sudo ", "DROP ", "DELETE FROM", "TRUNCATE"
    )
    foreach ($pattern in $highPatterns) {
        if ($Cmd -match $pattern) {
            return "high"
        }
    }

    # Medium risk - everything else
    return "medium"
}

# Consult Validator validator
function Invoke-Validator {
    param([string]$Command)

    # Load credentials
    if (Test-Path $credPath) {
        . $credPath
    }

    $endpoint = $env:ANTHROPIC_FOUNDRY_BASE_URL
    $apiKey = $env:ANTHROPIC_FOUNDRY_API_KEY

    if (-not $endpoint -or -not $apiKey) {
        Write-Log "Validator not configured"
        return @{ Proceed = $false; Confidence = 0 }
    }

    $endpoint = $endpoint.TrimEnd('/')

    $prompt = @"
Should this command be auto-approved in a development environment?
Command: $Command

Respond ONLY with JSON: {"proceed": true/false, "confidence": 0.0-1.0}
proceed=true for standard dev commands, false for anything risky.
"@

    $body = @{
        model = "claude-sonnet-4-5"
        max_tokens = 100
        messages = @(@{ role = "user"; content = $prompt })
    } | ConvertTo-Json -Depth 10

    $headers = @{
        "api-key" = $apiKey
        "x-api-key" = $apiKey
        "Content-Type" = "application/json"
        "anthropic-version" = "2023-06-01"
    }

    try {
        $uri = "$endpoint/v1/messages?api-version=2025-01-01-preview"
        $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -TimeoutSec 10
        $resultText = $response.content[0].text

        $jsonMatch = [regex]::Match($resultText, '\{[^}]+\}')
        if ($jsonMatch.Success) {
            $parsed = $jsonMatch.Value | ConvertFrom-Json
            return @{
                Proceed = $parsed.proceed
                Confidence = $parsed.confidence
            }
        }
    }
    catch {
        Write-Log "Validator error: $_"
    }

    return @{ Proceed = $false; Confidence = 0 }
}

# Determine risk level
$riskLevel = Get-RiskLevel -Cmd $command
Write-Log "Risk level: $riskLevel"

# Make decision based on risk
switch ($riskLevel) {
    "blocked" {
        Write-Log "BLOCKED - dangerous command"
        Write-Error "Command blocked by security policy: $command"
        exit 2
    }
    "always_allow" {
        Write-Log "AUTO-ALLOW - trivial command"
        $output = @{
            hookSpecificOutput = @{
                hookEventName = "PreToolUse"
                permissionDecision = "allow"
                permissionDecisionReason = "Trivial command auto-approved"
            }
        }
        Write-Output ($output | ConvertTo-Json -Depth 5 -Compress)
        exit 0
    }
    "low" {
        Write-Log "AUTO-ALLOW - low risk"
        $output = @{
            hookSpecificOutput = @{
                hookEventName = "PreToolUse"
                permissionDecision = "allow"
                permissionDecisionReason = "Low-risk command auto-approved"
            }
        }
        Write-Output ($output | ConvertTo-Json -Depth 5 -Compress)
        exit 0
    }
    "medium" {
        # Consult validator
        $validation = Invoke-Validator -Command $command
        Write-Log "Validator: proceed=$($validation.Proceed), confidence=$($validation.Confidence)"

        if ($validation.Proceed -and $validation.Confidence -gt 0.7) {
            Write-Log "AUTO-ALLOW - validator approved"
            $output = @{
                hookSpecificOutput = @{
                    hookEventName = "PreToolUse"
                    permissionDecision = "allow"
                    permissionDecisionReason = "Validator approved (confidence: $($validation.Confidence))"
                }
            }
            Write-Output ($output | ConvertTo-Json -Depth 5 -Compress)
            exit 0
        }
        else {
            Write-Log "ASK USER - validator not confident"
            # Let normal permission flow proceed
            exit 0
        }
    }
    "high" {
        Write-Log "ASK USER - high risk"
        # Let normal permission flow proceed (user will see dialog)
        exit 0
    }
    default {
        Write-Log "ASK USER - unknown risk"
        exit 0
    }
}
