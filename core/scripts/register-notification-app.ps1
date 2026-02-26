# ============================================================================
# WOF MANAGED FILE - DO NOT EDIT MANUALLY
# This file is managed by the Workload Orchestration Framework.
# Changes will be overwritten on the next WOF sync/update.
# To customize behavior, use configuration files in .ai/config/
# ============================================================================

<#
.SYNOPSIS
    Registers a custom Azure AD app for WOF notifications.

.DESCRIPTION
    Creates an app registration ("WOF Notifications") in Entra ID with the
    minimum delegated permissions needed for Teams chat and email sending.

    The script:
    1. Authenticates an admin user via device code flow
    2. Creates the app registration with public client (device code) enabled
    3. Adds delegated permissions: Chat.ReadWrite, Mail.Send, User.Read, offline_access
    4. Grants tenant-wide admin consent
    5. Optionally updates notifications.json with the new client ID

    Requires an account with Application Administrator or Global Administrator role.

.PARAMETER TenantId
    Azure AD tenant ID. If not provided, reads from notifications.json.

.PARAMETER ConfigPath
    Path to notifications.json. Defaults to .ai/config/notifications.json.

.PARAMETER AppName
    Display name for the app registration. Defaults to "WOF Notifications".

.EXAMPLE
    .\register-notification-app.ps1

.EXAMPLE
    .\register-notification-app.ps1 -TenantId "0d3aa8f9-..." -AppName "WOF Notifications (Dev)"
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $false)]
    [string]$AppName = "WOF Notifications"
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

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
}

$logFile = Join-Path $logDir "notifications.log"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logFile -Value "[$timestamp] [register-app] $Message" -ErrorAction SilentlyContinue
}

function Write-Step { param([string]$Message) Write-Host "[*] $Message" -ForegroundColor Cyan }
function Write-Success { param([string]$Message) Write-Host "[+] $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "[!] $Message" -ForegroundColor Yellow }
function Write-Err { param([string]$Message) Write-Host "[-] $Message" -ForegroundColor Red }

Write-Host ""
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "           WOF NOTIFICATION SYSTEM - APP REGISTRATION                          " -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# STEP 1: Resolve Tenant ID
# ============================================================================
Write-Step "Resolving tenant ID..."

if (-not $TenantId) {
    if (Test-Path $ConfigPath) {
        try {
            $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
            $TenantId = $config.tenantId
        } catch { }
    }
}

if (-not $TenantId) {
    Write-Err "Tenant ID is required. Provide -TenantId or set it in notifications.json."
    exit 1
}

Write-Host "  Tenant ID: $TenantId" -ForegroundColor Gray
Write-Log "Tenant ID: $TenantId"

# ============================================================================
# STEP 2: Check/Install MSAL.PS
# ============================================================================
Write-Step "Checking MSAL.PS module..."

if (-not (Get-Module -ListAvailable -Name MSAL.PS)) {
    Write-Warn "MSAL.PS module is not installed."
    Write-Host "  This module is required for authentication." -ForegroundColor Gray
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
# STEP 3: Authenticate Admin User
# ============================================================================
Write-Step "Authenticating admin user..."
Write-Host ""
Write-Host "  You must sign in with an account that has Application Administrator" -ForegroundColor Yellow
Write-Host "  or Global Administrator role in this tenant." -ForegroundColor Yellow
Write-Host ""

# Use the well-known Azure CLI client ID for bootstrapping.
# This is pre-consented for admin operations in most tenants.
$bootstrapClientId = "04b07795-8ddb-461a-bbee-02f9e1bf7b46"
$adminScopes = @("https://graph.microsoft.com/Application.ReadWrite.All", "https://graph.microsoft.com/DelegatedPermissionGrant.ReadWrite.All")

Write-Log "Starting admin device code flow"

try {
    $adminToken = Get-MsalToken `
        -ClientId $bootstrapClientId `
        -TenantId $TenantId `
        -Scopes $adminScopes `
        -DeviceCode

    if (-not $adminToken -or -not $adminToken.AccessToken) {
        throw "No access token received"
    }

    Write-Success "Admin authenticated."
    Write-Log "Admin authenticated. Token expires: $($adminToken.ExpiresOn)"
} catch {
    Write-Err "Admin authentication failed: $_"
    Write-Log "ERROR: Admin auth failed: $_"
    exit 1
}

$authHeader = @{
    "Authorization" = "Bearer $($adminToken.AccessToken)"
    "Content-Type"  = "application/json"
}

# ============================================================================
# STEP 4: Check for Existing App
# ============================================================================
Write-Step "Checking for existing '$AppName' app registration..."

try {
    $filter = [System.Uri]::EscapeDataString("displayName eq '$AppName'")
    $existingApps = Invoke-RestMethod `
        -Uri "https://graph.microsoft.com/v1.0/applications?`$filter=$filter" `
        -Headers $authHeader `
        -Method GET

    if ($existingApps.value.Count -gt 0) {
        $existingApp = $existingApps.value[0]
        Write-Warn "App '$AppName' already exists."
        Write-Host "  App ID (Client ID): $($existingApp.appId)" -ForegroundColor Gray
        Write-Host "  Object ID:          $($existingApp.id)" -ForegroundColor Gray
        Write-Host ""
        $overwrite = Read-Host "  Overwrite with fresh registration? [y/N]"
        if (-not $overwrite -or $overwrite.ToLower() -ne "y") {
            Write-Host ""
            Write-Host "  Keeping existing app. Client ID: $($existingApp.appId)" -ForegroundColor Green
            $clientId = $existingApp.appId

            # Skip to consent and config update
            $skipCreation = $true
            $appObjectId = $existingApp.id
        } else {
            Write-Step "Deleting existing app..."
            Invoke-RestMethod `
                -Uri "https://graph.microsoft.com/v1.0/applications/$($existingApp.id)" `
                -Headers $authHeader `
                -Method DELETE | Out-Null
            Write-Success "Existing app deleted."
            Write-Log "Deleted existing app: $($existingApp.id)"
            $skipCreation = $false
        }
    } else {
        $skipCreation = $false
    }
} catch {
    Write-Warn "Could not check for existing apps: $_"
    Write-Log "WARNING: Existing app check failed: $_"
    $skipCreation = $false
}

# ============================================================================
# STEP 5: Create App Registration
# ============================================================================

# Microsoft Graph API well-known resource ID
$graphResourceId = "00000003-0000-0000-c000-000000000000"

# Delegated permission IDs for Microsoft Graph:
#   Chat.ReadWrite      = 9ff7295e-131b-4d94-90e1-69fde507ac11
#   Mail.Send           = e383f46e-2787-4529-855e-0e479a3ffbd0
#   User.Read           = e1fe6dd8-ba31-4d61-89e7-88639da4683d
#   User.ReadBasic.All  = b340eb25-3456-403f-be2f-af7a0d370277
#   offline_access      = 7427e0e9-2fba-42fe-b0c0-848c9e6a8182
$permissions = @(
    @{ id = "9ff7295e-131b-4d94-90e1-69fde507ac11"; type = "Scope" },  # Chat.ReadWrite
    @{ id = "e383f46e-2787-4529-855e-0e479a3ffbd0"; type = "Scope" },  # Mail.Send
    @{ id = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"; type = "Scope" },  # User.Read
    @{ id = "b340eb25-3456-403f-be2f-af7a0d370277"; type = "Scope" },  # User.ReadBasic.All
    @{ id = "7427e0e9-2fba-42fe-b0c0-848c9e6a8182"; type = "Scope" }   # offline_access
)

if (-not $skipCreation) {
    Write-Step "Creating app registration '$AppName'..."

    $appBody = @{
        displayName            = $AppName
        signInAudience         = "AzureADMyOrg"
        isFallbackPublicClient = $true
        publicClient           = @{
            redirectUris = @("https://login.microsoftonline.com/common/oauth2/nativeclient")
        }
        requiredResourceAccess = @(
            @{
                resourceAppId  = $graphResourceId
                resourceAccess = $permissions
            }
        )
        tags                   = @("WOF", "Notifications", "D-User")
    } | ConvertTo-Json -Depth 10

    try {
        $appResponse = Invoke-RestMethod `
            -Uri "https://graph.microsoft.com/v1.0/applications" `
            -Headers $authHeader `
            -Method POST `
            -Body $appBody

        $clientId = $appResponse.appId
        $appObjectId = $appResponse.id

        Write-Success "App registered."
        Write-Host "  App ID (Client ID): $clientId" -ForegroundColor Gray
        Write-Host "  Object ID:          $appObjectId" -ForegroundColor Gray
        Write-Log "App registered: $clientId (object: $appObjectId)"
    } catch {
        Write-Err "Failed to create app registration: $_"
        Write-Log "ERROR: App creation failed: $_"
        exit 1
    }
}

# ============================================================================
# STEP 6: Create Service Principal
# ============================================================================
Write-Step "Ensuring service principal exists..."

try {
    $filter = [System.Uri]::EscapeDataString("appId eq '$clientId'")
    $spResponse = Invoke-RestMethod `
        -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=$filter" `
        -Headers $authHeader `
        -Method GET

    if ($spResponse.value.Count -eq 0) {
        $spBody = @{ appId = $clientId } | ConvertTo-Json
        $sp = Invoke-RestMethod `
            -Uri "https://graph.microsoft.com/v1.0/servicePrincipals" `
            -Headers $authHeader `
            -Method POST `
            -Body $spBody
        $spId = $sp.id
        Write-Success "Service principal created: $spId"
        Write-Log "Service principal created: $spId"
    } else {
        $spId = $spResponse.value[0].id
        Write-Success "Service principal already exists: $spId"
        Write-Log "Service principal found: $spId"
    }
} catch {
    Write-Err "Failed to create service principal: $_"
    Write-Log "ERROR: Service principal creation failed: $_"
    exit 1
}

# ============================================================================
# STEP 7: Grant Admin Consent
# ============================================================================
Write-Step "Granting admin consent for delegated permissions..."

try {
    # Find the Microsoft Graph service principal in this tenant
    $graphFilter = [System.Uri]::EscapeDataString("appId eq '$graphResourceId'")
    $graphSp = Invoke-RestMethod `
        -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=$graphFilter" `
        -Headers $authHeader `
        -Method GET

    $graphSpId = $graphSp.value[0].id

    # Build the scope string
    $scopeString = "Chat.ReadWrite Mail.Send User.Read User.ReadBasic.All offline_access"

    # Check for existing consent grant
    $existingGrants = Invoke-RestMethod `
        -Uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants?`$filter=clientId eq '$spId' and resourceId eq '$graphSpId'" `
        -Headers $authHeader `
        -Method GET

    if ($existingGrants.value.Count -gt 0) {
        # Update existing grant
        $grantId = $existingGrants.value[0].id
        $grantBody = @{ scope = $scopeString } | ConvertTo-Json
        Invoke-RestMethod `
            -Uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants/$grantId" `
            -Headers $authHeader `
            -Method PATCH `
            -Body $grantBody | Out-Null
        Write-Success "Admin consent updated."
        Write-Log "Admin consent updated for grant: $grantId"
    } else {
        # Create new consent grant
        $grantBody = @{
            clientId    = $spId
            consentType = "AllPrincipals"
            resourceId  = $graphSpId
            scope       = $scopeString
        } | ConvertTo-Json

        Invoke-RestMethod `
            -Uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants" `
            -Headers $authHeader `
            -Method POST `
            -Body $grantBody | Out-Null
        Write-Success "Admin consent granted."
        Write-Log "Admin consent granted for: $scopeString"
    }
} catch {
    Write-Err "Failed to grant admin consent: $_"
    Write-Log "ERROR: Admin consent failed: $_"
    Write-Warn "You can grant consent manually in Entra admin center:"
    Write-Host "  Enterprise applications > $AppName > Permissions > Grant admin consent" -ForegroundColor Gray
}

# ============================================================================
# STEP 8: Update notifications.json
# ============================================================================
if (Test-Path $ConfigPath) {
    Write-Step "Updating notifications.json with new client ID..."

    try {
        $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

        # Add or update clientId field
        if ($config.PSObject.Properties["clientId"]) {
            $config.clientId = $clientId
        } else {
            $config | Add-Member -NotePropertyName "clientId" -NotePropertyValue $clientId
        }

        $configJson = $config | ConvertTo-Json -Depth 10
        Set-Content -Path $ConfigPath -Value $configJson -Encoding UTF8
        Write-Success "notifications.json updated with clientId: $clientId"
        Write-Log "Config updated with clientId: $clientId"
    } catch {
        Write-Warn "Could not update notifications.json: $_"
        Write-Host "  Add this manually to your notifications.json:" -ForegroundColor Gray
        Write-Host "    `"clientId`": `"$clientId`"" -ForegroundColor White
    }
} else {
    Write-Host ""
    Write-Host "  No notifications.json found at $ConfigPath" -ForegroundColor Gray
    Write-Host "  Add this to your notifications.json:" -ForegroundColor Gray
    Write-Host "    `"clientId`": `"$clientId`"" -ForegroundColor White
}

# ============================================================================
# DONE
# ============================================================================
Write-Host ""
Write-Host "================================================================================" -ForegroundColor Green
Write-Host "                     APP REGISTRATION COMPLETE                                 " -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  App Name:     $AppName" -ForegroundColor Gray
Write-Host "  Client ID:    $clientId" -ForegroundColor White
Write-Host "  Tenant ID:    $TenantId" -ForegroundColor Gray
Write-Host "  Permissions:  Chat.ReadWrite, Mail.Send, User.Read, User.ReadBasic.All, offline_access" -ForegroundColor Gray
Write-Host "  Public Client: Enabled (device code flow)" -ForegroundColor Gray
Write-Host ""
Write-Host "  Next step: Run graph-auth.ps1 to authenticate the d-user." -ForegroundColor Cyan
Write-Host ""
