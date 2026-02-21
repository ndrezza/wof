# ============================================================================
# WOF MANAGED FILE - DO NOT EDIT MANUALLY
# This file is managed by the Workload Orchestration Framework.
# Changes will be overwritten on the next WOF sync/update.
# To customize behavior, use configuration files in .ai/config/
# ============================================================================

<#
.SYNOPSIS
    Sends a notification from the d-user to the target user via Teams or email.

.DESCRIPTION
    Uses Microsoft Graph API to send notifications through Teams chat or email.
    Authentication is handled by MSAL.PS with cached tokens from graph-auth.ps1.

    Supports trigger-based filtering so notifications can be selectively enabled
    or disabled in notifications.json.

.PARAMETER Message
    The notification message text (required).

.PARAMETER Subject
    Email subject line. Only used for email channel. Defaults to "WOF Notification".

.PARAMETER Channel
    Delivery channel: "teams", "email", or "auto" (default).
    "auto" uses the primary channel from config, falls back if it fails.

.PARAMETER Type
    Notification type for trigger filtering: "needsInput", "blocked", "completed", "progress".
    If the type is disabled in notifications.json, the notification is silently skipped.

.PARAMETER ConfigPath
    Path to notifications.json. Defaults to .ai/config/notifications.json.

.EXAMPLE
    .\send-notification.ps1 -Message "Build completed successfully."

.EXAMPLE
    .\send-notification.ps1 -Message "Need approval for PR #42" -Type needsInput

.EXAMPLE
    .\send-notification.ps1 -Message "Deployment blocked by failing tests" -Type blocked -Channel teams

.EXAMPLE
    .\send-notification.ps1 -Message "Weekly report attached" -Subject "WOF Weekly Report" -Channel email
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Message,

    [Parameter(Mandatory = $false)]
    [string]$Subject = "WOF Notification",

    [Parameter(Mandatory = $false)]
    [ValidateSet("teams", "email", "auto")]
    [string]$Channel = "auto",

    [Parameter(Mandatory = $false)]
    [ValidateSet("needsInput", "blocked", "completed", "progress", "")]
    [string]$Type = "",

    [Parameter(Mandatory = $false)]
    [string]$ConfigPath
)

$ErrorActionPreference = "SilentlyContinue"

# ============================================================================
# PATHS & INITIALIZATION
# ============================================================================
$aiDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$configDir = Join-Path $aiDir "config"
$logDir = Join-Path $aiDir "logs"

if (-not $ConfigPath) {
    $ConfigPath = Join-Path $configDir "notifications.json"
}

# Ensure log directory exists
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
}

$logFile = Join-Path $logDir "notifications.log"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logFile -Value "[$timestamp] [send-notification] $Message" -ErrorAction SilentlyContinue
}

# Microsoft Graph PowerShell SDK well-known client ID
$graphClientId = "14d82eec-204b-4c2f-b7e8-296a70dab67e"
$graphScopes = @("Chat.ReadWrite", "Mail.Send", "User.Read", "offline_access")

# ============================================================================
# STEP 1: Load Configuration
# ============================================================================
if (-not (Test-Path $ConfigPath)) {
    Write-Log "ERROR: Config not found: $ConfigPath"
    Write-Warning "Notification config not found. Run graph-auth.ps1 first."
    exit 1
}

try {
    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
} catch {
    Write-Log "ERROR: Failed to parse config: $_"
    Write-Warning "Failed to parse notifications.json: $_"
    exit 1
}

# ============================================================================
# STEP 2: Check Trigger Filter
# ============================================================================
if ($Type -and $config.triggers.PSObject.Properties[$Type]) {
    $triggerEnabled = $config.triggers.$Type
    if (-not $triggerEnabled) {
        Write-Log "Skipped: trigger '$Type' is disabled"
        exit 0
    }
}

# ============================================================================
# STEP 3: Validate Configuration
# ============================================================================
if (-not $config.tenantId) {
    Write-Log "ERROR: tenantId not configured"
    Write-Warning "tenantId not set in notifications.json. Run graph-auth.ps1 first."
    exit 1
}

# Resolve channel
$primaryChannel = $Channel
if ($Channel -eq "auto") {
    $primaryChannel = if ($config.channels.primary) { $config.channels.primary } else { "teams" }
}

$fallbackChannel = if ($config.channels.fallback) { $config.channels.fallback } else { "email" }

# ============================================================================
# STEP 4: Acquire Token Silently
# ============================================================================
Write-Log "Acquiring token silently..."

$tokenResult = $null
try {
    # Ensure MSAL.PS is loaded
    if (-not (Get-Module -Name MSAL.PS)) {
        Import-Module MSAL.PS -ErrorAction Stop
    }

    $tokenResult = Get-MsalToken `
        -ClientId $graphClientId `
        -TenantId $config.tenantId `
        -Scopes $graphScopes `
        -Silent

    if (-not $tokenResult -or -not $tokenResult.AccessToken) {
        throw "No access token returned from silent auth"
    }

    Write-Log "Token acquired (expires: $($tokenResult.ExpiresOn))"
} catch {
    Write-Log "WARNING: Silent token acquisition failed: $_"

    # If primary was teams and we have a fallback, try fallback
    if ($primaryChannel -eq "teams" -and $fallbackChannel -eq "email") {
        Write-Log "Token refresh failed. Attempting fallback channel: email"
        $primaryChannel = "email"
    } else {
        Write-Warning "Authentication expired. Run graph-auth.ps1 to re-authenticate."
        exit 1
    }

    # Retry token acquisition for fallback
    try {
        $tokenResult = Get-MsalToken `
            -ClientId $graphClientId `
            -TenantId $config.tenantId `
            -Scopes $graphScopes `
            -Silent

        if (-not $tokenResult -or -not $tokenResult.AccessToken) {
            Write-Log "ERROR: Token acquisition failed for fallback too"
            Write-Warning "Authentication expired. Run graph-auth.ps1 to re-authenticate."
            exit 1
        }
    } catch {
        Write-Log "ERROR: Token acquisition failed completely: $_"
        Write-Warning "Authentication expired. Run graph-auth.ps1 to re-authenticate."
        exit 1
    }
}

$authHeader = @{
    "Authorization" = "Bearer $($tokenResult.AccessToken)"
    "Content-Type"  = "application/json"
}

# ============================================================================
# STEP 5: Send Notification
# ============================================================================

function Send-TeamsMessage {
    param([string]$Text)

    if (-not $config.teams.chatId) {
        Write-Log "ERROR: No Teams chatId configured"
        return $false
    }

    try {
        # Format message with type badge if applicable
        $htmlContent = $Text
        if ($Type) {
            $badgeColor = switch ($Type) {
                "needsInput" { "#FF8C00" }  # Orange
                "blocked"    { "#DC143C" }  # Red
                "completed"  { "#228B22" }  # Green
                "progress"   { "#4169E1" }  # Blue
                default      { "#808080" }  # Gray
            }
            $badgeLabel = switch ($Type) {
                "needsInput" { "INPUT NEEDED" }
                "blocked"    { "BLOCKED" }
                "completed"  { "COMPLETED" }
                "progress"   { "PROGRESS" }
                default      { $Type.ToUpper() }
            }
            $htmlContent = "<span style='background-color:$badgeColor;color:white;padding:2px 6px;border-radius:3px;font-size:11px;font-weight:bold'>$badgeLabel</span><br/>$Text"
        }

        $body = @{
            body = @{
                contentType = "html"
                content     = $htmlContent
            }
        } | ConvertTo-Json -Depth 5

        Invoke-RestMethod `
            -Uri "https://graph.microsoft.com/v1.0/chats/$($config.teams.chatId)/messages" `
            -Headers $authHeader `
            -Method POST `
            -Body $body | Out-Null

        Write-Log "Sent via Teams: $Text"
        return $true
    } catch {
        Write-Log "ERROR: Teams send failed: $_"
        return $false
    }
}

function Send-Email {
    param([string]$Text, [string]$EmailSubject)

    if (-not $config.targetUser.upn) {
        Write-Log "ERROR: No target user UPN configured"
        return $false
    }

    try {
        # Format email body
        $emailHtml = "<p>$Text</p><hr/><p style='font-size:11px;color:#888'>Sent by WOF Notification System from $($config.dUser.upn)</p>"

        $body = @{
            message = @{
                subject      = $EmailSubject
                body         = @{
                    contentType = "HTML"
                    content     = $emailHtml
                }
                toRecipients = @(
                    @{
                        emailAddress = @{
                            address = $config.targetUser.upn
                        }
                    }
                )
            }
            saveToSentItems = $false
        } | ConvertTo-Json -Depth 10

        Invoke-RestMethod `
            -Uri "https://graph.microsoft.com/v1.0/me/sendMail" `
            -Headers $authHeader `
            -Method POST `
            -Body $body | Out-Null

        Write-Log "Sent via email to $($config.targetUser.upn): $EmailSubject"
        return $true
    } catch {
        Write-Log "ERROR: Email send failed: $_"
        return $false
    }
}

# Attempt primary channel
$sent = $false

if ($primaryChannel -eq "teams") {
    $sent = Send-TeamsMessage -Text $Message
    if (-not $sent -and $fallbackChannel -eq "email") {
        Write-Log "Teams failed, falling back to email"
        $sent = Send-Email -Text $Message -EmailSubject $Subject
    }
} elseif ($primaryChannel -eq "email") {
    $sent = Send-Email -Text $Message -EmailSubject $Subject
    if (-not $sent -and $fallbackChannel -eq "teams") {
        Write-Log "Email failed, falling back to Teams"
        $sent = Send-TeamsMessage -Text $Message
    }
}

if ($sent) {
    Write-Log "Notification delivered successfully"
} else {
    Write-Log "ERROR: Notification delivery failed on all channels"
    Write-Warning "Failed to send notification. Check $logFile for details."
    exit 1
}
