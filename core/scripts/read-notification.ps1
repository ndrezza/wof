# ============================================================================
# WOF MANAGED FILE - DO NOT EDIT MANUALLY
# This file is managed by the Workload Orchestration Framework.
# Changes will be overwritten on the next WOF sync/update.
# To customize behavior, use configuration files in .ai/config/
# ============================================================================

<#
.SYNOPSIS
    Reads new messages from the target user in the Teams chat.

.DESCRIPTION
    Polls the 1:1 Teams chat for messages from the target user (normal user)
    that were sent after the last read timestamp. Returns new messages as
    structured output for the AI to process.

    Uses the persistent MSAL disk cache for silent authentication.

.PARAMETER ConfigPath
    Path to notifications.json. Defaults to .ai/config/notifications.json.

.PARAMETER Since
    Only return messages after this ISO 8601 timestamp.
    If not provided, uses the last read timestamp from state, or returns
    messages from the last hour.

.PARAMETER MarkAsRead
    If set, updates the last read timestamp after retrieving messages.
    Defaults to true.

.PARAMETER MaxMessages
    Maximum number of messages to return. Defaults to 10.

.EXAMPLE
    .\read-notification.ps1

.EXAMPLE
    .\read-notification.ps1 -Since "2026-02-25T20:00:00Z" -MaxMessages 5

.EXAMPLE
    .\read-notification.ps1 -MarkAsRead:$false
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $false)]
    [string]$Since,

    [Parameter(Mandatory = $false)]
    [bool]$MarkAsRead = $true,

    [Parameter(Mandatory = $false)]
    [int]$MaxMessages = 10
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

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
}

$logFile = Join-Path $logDir "notifications.log"
$stateFile = Join-Path $logDir "notification-read-state.json"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logFile -Value "[$timestamp] [read-notification] $Message" -ErrorAction SilentlyContinue
}

$graphScopes = @("Chat.ReadWrite", "Mail.Send", "User.Read", "User.ReadBasic.All", "offline_access")

# ============================================================================
# STEP 1: Load Configuration
# ============================================================================
if (-not (Test-Path $ConfigPath)) {
    Write-Log "ERROR: Config not found: $ConfigPath"
    Write-Error "Notification config not found. Run graph-auth.ps1 first."
    exit 1
}

try {
    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
} catch {
    Write-Log "ERROR: Failed to parse config: $_"
    Write-Error "Failed to parse notifications.json: $_"
    exit 1
}

$graphClientId = if ($config.clientId) { $config.clientId } else { "14d82eec-204b-4c2f-b7e8-296a70dab67e" }

# ============================================================================
# STEP 2: Validate Prerequisites
# ============================================================================
if (-not $config.tenantId) {
    Write-Log "ERROR: tenantId not configured"
    Write-Error "tenantId not set. Run graph-auth.ps1 first."
    exit 1
}

if (-not $config.teams.chatId) {
    Write-Log "ERROR: No Teams chatId configured"
    Write-Error "No Teams chat configured. Run graph-auth.ps1 first."
    exit 1
}

if (-not $config.targetUser.userId) {
    Write-Log "ERROR: No target user ID configured"
    Write-Error "Target user ID not resolved. Run graph-auth.ps1 first."
    exit 1
}

# ============================================================================
# STEP 3: Resolve 'Since' Timestamp
# ============================================================================
if (-not $Since) {
    # Try loading from state file
    if (Test-Path $stateFile) {
        try {
            $state = Get-Content $stateFile -Raw | ConvertFrom-Json
            $Since = $state.lastReadTimestamp
            Write-Log "Using last read timestamp from state: $Since"
        } catch {
            Write-Log "WARNING: Failed to read state file: $_"
        }
    }

    # Default to last hour if no state
    if (-not $Since) {
        $Since = [DateTimeOffset]::UtcNow.AddHours(-1).ToString("o")
        Write-Log "No previous state, defaulting to last hour: $Since"
    }
}

# ============================================================================
# STEP 4: Acquire Token Silently (from persistent file cache)
# ============================================================================
Write-Log "Acquiring token silently..."

$tokenResult = $null
try {
    if (-not (Get-Module -Name MSAL.PS)) {
        Import-Module MSAL.PS -ErrorAction Stop
    }

    $msalApp = New-MsalClientApplication -ClientId $graphClientId -TenantId $config.tenantId
    $tokenCachePath = Join-Path $configDir "msal-token-cache.bin"

    $msalApp.UserTokenCache.SetBeforeAccess([Microsoft.Identity.Client.TokenCacheCallback]{
        param([Microsoft.Identity.Client.TokenCacheNotificationArgs]$a)
        $fullPath = [System.Environment]::GetEnvironmentVariable("WOF_MSAL_CACHE_PATH")
        if ($fullPath -and [System.IO.File]::Exists($fullPath)) {
            $a.TokenCache.DeserializeMsalV3([System.IO.File]::ReadAllBytes($fullPath))
        }
    })
    $msalApp.UserTokenCache.SetAfterAccess([Microsoft.Identity.Client.TokenCacheCallback]{
        param([Microsoft.Identity.Client.TokenCacheNotificationArgs]$a)
        if ($a.HasStateChanged) {
            $fullPath = [System.Environment]::GetEnvironmentVariable("WOF_MSAL_CACHE_PATH")
            if ($fullPath) {
                [System.IO.File]::WriteAllBytes($fullPath, $a.TokenCache.SerializeMsalV3())
            }
        }
    })
    [System.Environment]::SetEnvironmentVariable("WOF_MSAL_CACHE_PATH", $tokenCachePath)

    $tokenResult = Get-MsalToken `
        -PublicClientApplication $msalApp `
        -Scopes $graphScopes `
        -Silent

    if (-not $tokenResult -or -not $tokenResult.AccessToken) {
        throw "No access token returned from silent auth"
    }

    Write-Log "Token acquired (expires: $($tokenResult.ExpiresOn))"
} catch {
    Write-Log "ERROR: Silent token acquisition failed: $_"
    Write-Error "Authentication expired. Run graph-auth.ps1 to re-authenticate."
    exit 1
}

$authHeader = @{
    "Authorization" = "Bearer $($tokenResult.AccessToken)"
    "Content-Type"  = "application/json"
}

# ============================================================================
# STEP 5: Fetch Messages from Teams Chat
# ============================================================================
Write-Log "Fetching messages from chat $($config.teams.chatId) since $Since"

try {
    $chatId = $config.teams.chatId
    $targetUserId = $config.targetUser.userId
    $top = $MaxMessages + 10  # Fetch extra to account for filtering

    $messagesResponse = Invoke-RestMethod `
        -Uri "https://graph.microsoft.com/v1.0/chats/$chatId/messages?`$top=$top&`$orderby=createdDateTime desc" `
        -Headers $authHeader `
        -Method GET

    if (-not $messagesResponse -or -not $messagesResponse.value) {
        Write-Log "No messages returned from API"
        Write-Output "[]"
        exit 0
    }

    Write-Log "Fetched $($messagesResponse.value.Count) total messages"
} catch {
    Write-Log "ERROR: Failed to fetch messages: $_"
    Write-Error "Failed to fetch Teams messages: $_"
    exit 1
}

# ============================================================================
# STEP 6: Filter Messages from Target User
# ============================================================================
$sinceDate = [DateTimeOffset]::Parse($Since)
$newMessages = @()

foreach ($msg in $messagesResponse.value) {
    # Skip system/event messages
    if ($msg.messageType -ne "message") { continue }

    # Skip messages from the d-user (only want messages FROM the target user)
    if (-not $msg.from -or -not $msg.from.user) { continue }
    if ($msg.from.user.id -ne $targetUserId) { continue }

    # Filter by timestamp
    $msgDate = [DateTimeOffset]::Parse($msg.createdDateTime)
    if ($msgDate -le $sinceDate) { continue }

    # Extract plain text content
    $content = $msg.body.content
    if ($msg.body.contentType -eq "html") {
        # Strip HTML tags for plain text output
        $content = $content -replace '<[^>]+>', '' -replace '&nbsp;', ' ' -replace '&amp;', '&' -replace '&lt;', '<' -replace '&gt;', '>'
        $content = $content.Trim()
    }

    $newMessages += @{
        id        = $msg.id
        timestamp = $msg.createdDateTime
        from      = $msg.from.user.displayName
        content   = $content
        rawHtml   = if ($msg.body.contentType -eq "html") { $msg.body.content } else { $null }
    }

    if ($newMessages.Count -ge $MaxMessages) { break }
}

# Sort oldest first for natural reading order
$newMessages = $newMessages | Sort-Object { [DateTimeOffset]::Parse($_.timestamp) }

Write-Log "Found $($newMessages.Count) new messages from target user"

# ============================================================================
# STEP 7: Update Read State
# ============================================================================
if ($MarkAsRead -and $newMessages.Count -gt 0) {
    $latestTimestamp = ($newMessages | Select-Object -Last 1).timestamp
    try {
        $stateObj = @{
            lastReadTimestamp = $latestTimestamp
            lastChecked       = [DateTimeOffset]::UtcNow.ToString("o")
        }
        $stateObj | ConvertTo-Json | Set-Content -Path $stateFile -Encoding UTF8
        Write-Log "Read state updated: lastReadTimestamp=$latestTimestamp"
    } catch {
        Write-Log "WARNING: Failed to update read state: $_"
    }
}

# ============================================================================
# STEP 8: Output Results
# ============================================================================
$newMessages | ConvertTo-Json -Depth 5 -Compress
