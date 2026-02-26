# ============================================================================
# WOF MANAGED FILE - DO NOT EDIT MANUALLY
# This file is managed by the Workload Orchestration Framework.
# Changes will be overwritten on the next WOF sync/update.
# To customize behavior, use configuration files in .ai/config/
# ============================================================================

<#
.SYNOPSIS
    Authenticates the d-user with Microsoft Graph for WOF notifications.

.DESCRIPTION
    Performs one-time interactive device code flow authentication using MSAL.PS.
    Uses the custom app registration clientId from notifications.json, or falls
    back to the Microsoft Graph PowerShell SDK's well-known client ID.
    Tokens are persisted to a file-based cache for silent auth across sessions.

    After authentication:
    - Resolves the target user's Graph ID
    - Creates or finds a 1:1 Teams chat with the target user
    - Caches chatId and userId in notifications.json
    - Sends a test message to verify connectivity

.PARAMETER ConfigPath
    Path to notifications.json. Defaults to .ai/config/notifications.json
    relative to the project root.

.EXAMPLE
    .\graph-auth.ps1

.EXAMPLE
    .\graph-auth.ps1 -ConfigPath "C:\code\myproject\.ai\config\notifications.json"
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath
)

$ErrorActionPreference = "Stop"

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
    Add-Content -Path $logFile -Value "[$timestamp] [graph-auth] $Message" -ErrorAction SilentlyContinue
}

function Write-Step { param([string]$Message) Write-Host "[*] $Message" -ForegroundColor Cyan }
function Write-Success { param([string]$Message) Write-Host "[+] $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "[!] $Message" -ForegroundColor Yellow }
function Write-Err { param([string]$Message) Write-Host "[-] $Message" -ForegroundColor Red }

# ============================================================================
# CONFIGURATION
# ============================================================================

$graphScopes = @("Chat.ReadWrite", "Mail.Send", "User.Read", "User.ReadBasic.All", "offline_access")

Write-Host ""
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "           WOF NOTIFICATION SYSTEM - GRAPH AUTHENTICATION                      " -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# STEP 1: Validate notifications.json
# ============================================================================
Write-Step "Loading notification configuration..."

if (-not (Test-Path $ConfigPath)) {
    Write-Err "Notification config not found: $ConfigPath"
    Write-Host "  Run setup.ps1 or create the file from the template first." -ForegroundColor Gray
    exit 1
}

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

# Validate required fields
$missingFields = @()
if (-not $config.dUser.upn) { $missingFields += "dUser.upn" }
if (-not $config.targetUser.upn) { $missingFields += "targetUser.upn" }
if (-not $config.tenantId) { $missingFields += "tenantId" }

if ($missingFields.Count -gt 0) {
    Write-Err "Missing required fields in notifications.json:"
    foreach ($field in $missingFields) {
        Write-Host "    - $field" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "  Edit $ConfigPath and fill in the required fields before running auth." -ForegroundColor Gray
    exit 1
}

# Use custom app registration from config if available, otherwise fall back
# to the Microsoft Graph PowerShell SDK well-known client ID.
$graphClientId = if ($config.clientId) { $config.clientId } else { "14d82eec-204b-4c2f-b7e8-296a70dab67e" }

Write-Host "  D-User:       $($config.dUser.upn)" -ForegroundColor Gray
Write-Host "  Target User:  $($config.targetUser.upn)" -ForegroundColor Gray
Write-Host "  Tenant ID:    $($config.tenantId)" -ForegroundColor Gray
Write-Host "  Client ID:    $graphClientId" -ForegroundColor Gray

# ============================================================================
# STEP 2: Check/Install MSAL.PS
# ============================================================================
Write-Step "Checking MSAL.PS module..."

if (-not (Get-Module -ListAvailable -Name MSAL.PS)) {
    Write-Warn "MSAL.PS module is not installed."
    Write-Host "  This module is required for device code authentication." -ForegroundColor Gray
    Write-Host ""
    $installChoice = Read-Host "  Install MSAL.PS from PSGallery? [Y/n]"
    if ($installChoice -and $installChoice.ToLower() -eq "n") {
        Write-Err "MSAL.PS is required. Install it manually: Install-Module MSAL.PS -Scope CurrentUser"
        exit 1
    }
    Write-Step "Installing MSAL.PS..."
    Install-Module MSAL.PS -Scope CurrentUser -Force -AcceptLicense
    Write-Success "MSAL.PS installed."
} else {
    Write-Success "MSAL.PS is available."
}

Import-Module MSAL.PS -ErrorAction Stop

# ============================================================================
# STEP 3: Device Code Authentication (with persistent file cache)
# ============================================================================
Write-Step "Setting up persistent token cache..."

$msalApp = New-MsalClientApplication -ClientId $graphClientId -TenantId $config.tenantId
$tokenCachePath = Join-Path $configDir "msal-token-cache.bin"

# Register file-based cache persistence (works on both PS5 and PS7)
# Uses env var to pass cache path into callbacks (scriptblocks can't close over variables)
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

Write-Success "Persistent token cache enabled ($tokenCachePath)"
Write-Log "MSAL app created with file cache at $tokenCachePath"

# Try silent first (cached token from previous session)
$tokenResult = $null
try {
    $tokenResult = Get-MsalToken `
        -PublicClientApplication $msalApp `
        -Scopes $graphScopes `
        -Silent

    if ($tokenResult -and $tokenResult.AccessToken) {
        Write-Success "Authenticated from cached token (no login required)."
        Write-Log "Silent auth successful. Token expires: $($tokenResult.ExpiresOn)"
    }
} catch {
    Write-Log "No cached token available, will use device code flow."
}

# Fall back to device code if silent failed
if (-not $tokenResult -or -not $tokenResult.AccessToken) {
    Write-Step "Starting device code authentication..."
    Write-Host ""
    Write-Host "  You will be prompted to sign in as the d-user ($($config.dUser.upn))." -ForegroundColor Yellow
    Write-Host "  A browser window will open - sign in with the d-user account." -ForegroundColor Yellow
    Write-Host ""

    Write-Log "Starting device code flow for tenant $($config.tenantId)"

    try {
        # Use MSAL.NET API directly instead of Get-MsalToken -DeviceCode.
        # The MSAL.PS wrapper has a known "Sequence contains no elements" error
        # when combined with custom cache serialization callbacks.
        $deviceCodeCallback = [System.Func[Microsoft.Identity.Client.DeviceCodeResult, System.Threading.Tasks.Task]]{
            param([Microsoft.Identity.Client.DeviceCodeResult]$dcr)
            Write-Host ""
            Write-Host "  $($dcr.Message)" -ForegroundColor Yellow
            Write-Host ""
            return [System.Threading.Tasks.Task]::CompletedTask
        }

        $authResult = $msalApp.AcquireTokenWithDeviceCode($graphScopes, $deviceCodeCallback).ExecuteAsync().GetAwaiter().GetResult()

        if (-not $authResult -or -not $authResult.AccessToken) {
            Write-Err "Authentication failed - no access token received."
            Write-Log "ERROR: No access token received from device code flow"
            exit 1
        }

        # Wrap in a PSObject with the same properties MSAL.PS would return
        $tokenResult = [PSCustomObject]@{
            AccessToken = $authResult.AccessToken
            ExpiresOn   = $authResult.ExpiresOn
            Account     = $authResult.Account
            Scopes      = $authResult.Scopes
        }

        Write-Success "Authenticated successfully. Token cached to disk."
        Write-Log "Authentication successful. Token expires: $($tokenResult.ExpiresOn)"
    } catch {
        Write-Err "Authentication failed: $_"
        Write-Log "ERROR: Authentication failed: $_"
        exit 1
    }
}

$authHeader = @{
    "Authorization" = "Bearer $($tokenResult.AccessToken)"
    "Content-Type"  = "application/json"
}

# ============================================================================
# STEP 4: Resolve Target User ID
# ============================================================================
Write-Step "Resolving target user..."

try {
    $userResponse = Invoke-RestMethod `
        -Uri "https://graph.microsoft.com/v1.0/users/$($config.targetUser.upn)" `
        -Headers $authHeader `
        -Method GET

    $targetUserId = $userResponse.id
    $targetDisplayName = $userResponse.displayName

    Write-Success "Resolved: $targetDisplayName ($targetUserId)"
    Write-Log "Resolved target user: $targetDisplayName ($targetUserId)"

    # Update config with resolved user info
    $config.targetUser.userId = $targetUserId
    if ($targetDisplayName) {
        $config.targetUser.displayName = $targetDisplayName
    }
} catch {
    Write-Err "Failed to resolve target user '$($config.targetUser.upn)': $_"
    Write-Log "ERROR: Failed to resolve target user: $_"
    exit 1
}

# ============================================================================
# STEP 5: Create or Find 1:1 Chat
# ============================================================================
Write-Step "Setting up Teams chat with target user..."

try {
    # Get the authenticated user's ID (the d-user)
    $meResponse = Invoke-RestMethod `
        -Uri "https://graph.microsoft.com/v1.0/me" `
        -Headers $authHeader `
        -Method GET

    $dUserId = $meResponse.id
    Write-Log "D-user ID: $dUserId"

    # Update d-user display name if available
    if ($meResponse.displayName) {
        $config.dUser.displayName = $meResponse.displayName
    }

    # Create or get existing 1:1 chat
    # Build members with explicit bracket notation to preserve @ keys in JSON
    $member1 = [ordered]@{}
    $member1['@odata.type'] = '#microsoft.graph.aadUserConversationMember'
    $member1['roles'] = @('owner')
    $member1['user@odata.bind'] = "https://graph.microsoft.com/v1.0/users('$dUserId')"

    $member2 = [ordered]@{}
    $member2['@odata.type'] = '#microsoft.graph.aadUserConversationMember'
    $member2['roles'] = @('owner')
    $member2['user@odata.bind'] = "https://graph.microsoft.com/v1.0/users('$targetUserId')"

    $chatPayload = [ordered]@{
        chatType = 'oneOnOne'
        members  = @($member1, $member2)
    }
    $chatBody = [System.Text.Encoding]::UTF8.GetBytes(($chatPayload | ConvertTo-Json -Depth 10))

    $chatResponse = Invoke-RestMethod `
        -Uri "https://graph.microsoft.com/v1.0/chats" `
        -Headers $authHeader `
        -Method POST `
        -Body $chatBody

    $chatId = $chatResponse.id
    Write-Success "Teams chat ready: $chatId"
    Write-Log "Chat ID: $chatId"

    # Cache chat ID in config
    $config.teams.chatId = $chatId
} catch {
    Write-Err "Failed to set up Teams chat: $_"
    Write-Log "ERROR: Failed to set up Teams chat: $_"
    Write-Warn "You can still use email notifications. Teams chat setup can be retried later."
}

# ============================================================================
# STEP 6: Save Updated Config
# ============================================================================
Write-Step "Saving configuration..."

$configJson = $config | ConvertTo-Json -Depth 10
Set-Content -Path $ConfigPath -Value $configJson -Encoding UTF8
Write-Success "Configuration saved to $ConfigPath"
Write-Log "Configuration saved"

# ============================================================================
# STEP 7: Send Test Message
# ============================================================================
Write-Step "Sending test message..."

if ($config.teams.chatId) {
    try {
        $testMessageBody = @{
            body = @{
                contentType = "html"
                content     = "<b>WOF Notification System</b><br/>Connected successfully. Notifications from <em>$($config.dUser.upn)</em> will appear here."
            }
        } | ConvertTo-Json -Depth 5
        $testMessageBytes = [System.Text.Encoding]::UTF8.GetBytes($testMessageBody)

        Invoke-RestMethod `
            -Uri "https://graph.microsoft.com/v1.0/chats/$($config.teams.chatId)/messages" `
            -Headers $authHeader `
            -Method POST `
            -Body $testMessageBytes | Out-Null

        Write-Success "Test message sent via Teams!"
        Write-Log "Test message sent via Teams"
    } catch {
        Write-Warn "Failed to send Teams test message: $_"
        Write-Log "WARNING: Failed to send Teams test message: $_"
    }
}

# ============================================================================
# DONE
# ============================================================================
Write-Host ""
Write-Host "================================================================================" -ForegroundColor Green
Write-Host "                        AUTHENTICATION COMPLETE                                " -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  D-User:       $($config.dUser.upn) ($($config.dUser.displayName))" -ForegroundColor Gray
Write-Host "  Target User:  $($config.targetUser.upn) ($($config.targetUser.displayName))" -ForegroundColor Gray
if ($config.teams.chatId) {
    Write-Host "  Teams Chat:   Ready" -ForegroundColor Green
} else {
    Write-Host "  Teams Chat:   Not configured (email only)" -ForegroundColor Yellow
}
Write-Host ""
Write-Host "  Token is cached by MSAL.PS and will auto-refresh silently." -ForegroundColor Gray
Write-Host "  Run this script again if authentication expires." -ForegroundColor Gray
Write-Host ""
