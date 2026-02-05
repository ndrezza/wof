# ============================================================================
# WOF MANAGED FILE - DO NOT EDIT MANUALLY
# This file is managed by the Workload Orchestration Framework.
# Changes will be overwritten on the next WOF sync/update.
# To customize behavior, use configuration files in .ai/config/
# ============================================================================

<#
.SYNOPSIS
    Updates the Workload Orchestration Framework (WOF) to the latest version.

.DESCRIPTION
    This script pulls the latest framework version from the central Workload-Orchestration
    repository and applies updates while respecting customization boundaries.
    
    It is designed to be run from within a target project that has the framework installed.
    The script clones the source repository, runs the official sync, and cleans up.

.PARAMETER DryRun
    Shows what would be updated without making changes.

.PARAMETER Force
    Ignores customization markers and forces update of all eligible files.

.PARAMETER Branch
    Specifies which branch to sync from. Defaults to 'main'.

.PARAMETER Tag
    Specifies a version tag to sync from (e.g., 'v1.1.0'). Overrides Branch if specified.

.PARAMETER RepoUrl
    Override the default repository URL. Useful for forks or internal mirrors.

.EXAMPLE
    .\update-framework.ps1
    
.EXAMPLE
    .\update-framework.ps1 -DryRun

.EXAMPLE
    .\update-framework.ps1 -Tag v1.2.0

.EXAMPLE
    .\update-framework.ps1 -Force -Branch develop

.NOTES
    Default Repository: https://github.com/ndrezza/wof.git
    
    Sync behavior is controlled by sync-manifest.json in the source repository:
    - overwrite: Framework core files always updated (scripts, routing rules)
    - skip_if_customized: Files with '# CUSTOMIZED' marker are preserved
    - always_preserve: Local-only files never touched (credentials, current-sprint, etc.)
    
    To mark a file as customized (prevents overwrite on future updates):
      Add '# CUSTOMIZED' comment near the top of the file
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Force,
    [string]$Branch = "main",
    [string]$Tag,
    [string]$RepoUrl = "https://github.com/ndrezza/wof.git"
)

$ErrorActionPreference = "Stop"

# Determine project root (go up from .ai/scripts to project root)
$ScriptDir = $PSScriptRoot
$AiDir = Split-Path $ScriptDir -Parent
$ProjectRoot = Split-Path $AiDir -Parent

# Validate we're in the right location
if (-not (Test-Path (Join-Path $AiDir ".mode")) -and -not (Test-Path (Join-Path $AiDir "config"))) {
    Write-Host "[-] ERROR: This script must be run from within a project's .ai/scripts directory" -ForegroundColor Red
    Write-Host "    Expected path: <project>/.ai/scripts/update-framework.ps1" -ForegroundColor Gray
    exit 1
}

# Create temp directory for clone
$TempDir = Join-Path ([System.IO.Path]::GetTempPath()) "workload-orchestration-update-$(Get-Random)"

# Read current version
$VersionFile = Join-Path $AiDir ".framework-version"
$CurrentVersion = if (Test-Path $VersionFile) { (Get-Content $VersionFile).Trim() } else { "unknown" }

# Display header
Write-Host ""
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "          WORKLOAD ORCHESTRATION FRAMEWORK (WOF) UPDATE                       " -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Project:         $ProjectRoot" -ForegroundColor Gray
Write-Host "  Current Version: $CurrentVersion" -ForegroundColor $(if ($CurrentVersion -eq "unknown") { "Yellow" } else { "Gray" })
Write-Host "  Repository:      $RepoUrl" -ForegroundColor Gray

# Determine ref to clone
$CloneRef = if ($Tag) { $Tag } else { $Branch }
Write-Host "  Target Ref:      $CloneRef" -ForegroundColor Gray

if ($DryRun) {
    Write-Host "  Mode:            DRY RUN" -ForegroundColor Yellow
}
Write-Host ""

# Step 1: Clone the repository
Write-Host "[1/4] Fetching latest framework from repository..." -ForegroundColor Cyan

if (Test-Path $TempDir) {
    Remove-Item $TempDir -Recurse -Force
}

# Clone with specific ref (redirect stderr to stdout to avoid PowerShell treating progress as errors)
$cloneRef = if ($Tag) { $Tag } else { $Branch }
$env:GIT_TERMINAL_PROMPT = "0"
git clone --depth 1 --branch $cloneRef --quiet $RepoUrl $TempDir 2>$null

if ($LASTEXITCODE -ne 0 -or -not (Test-Path $TempDir)) {
    Write-Host "       Failed to clone repository" -ForegroundColor Red
    Write-Host ""
    Write-Host "       Troubleshooting:" -ForegroundColor Yellow
    Write-Host "       - Check network connectivity" -ForegroundColor Gray
    Write-Host "       - Verify git credentials are configured" -ForegroundColor Gray
    Write-Host "       - Try: git ls-remote $RepoUrl" -ForegroundColor Gray
    exit 1
}
Write-Host "       Cloned successfully" -ForegroundColor Green

# Step 2: Read remote version
Write-Host "[2/4] Checking remote version..." -ForegroundColor Cyan
$RemoteVersionFile = Join-Path $TempDir "VERSION"
$RemoteVersion = if (Test-Path $RemoteVersionFile) { (Get-Content $RemoteVersionFile).Trim() } else { "unknown" }
Write-Host "       Remote Version: $RemoteVersion" -ForegroundColor Green

if ($CurrentVersion -eq $RemoteVersion -and -not $Force) {
    Write-Host ""
    Write-Host "       Already up to date! (v$CurrentVersion)" -ForegroundColor Green
    Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 0
}

# Check for breaking change (major version bump)
function Get-MajorVersion {
    param([string]$Version)
    if ($Version -eq "unknown" -or [string]::IsNullOrWhiteSpace($Version)) {
        return -1
    }
    # Handle versions with 'v' prefix
    $cleanVersion = $Version.TrimStart('v', 'V')
    $parts = $cleanVersion.Split('.')
    if ($parts.Length -ge 1) {
        $major = 0
        if ([int]::TryParse($parts[0], [ref]$major)) {
            return $major
        }
    }
    return -1
}

$CurrentMajor = Get-MajorVersion -Version $CurrentVersion
$RemoteMajor = Get-MajorVersion -Version $RemoteVersion

if ($CurrentMajor -ge 0 -and $RemoteMajor -ge 0 -and $RemoteMajor -gt $CurrentMajor) {
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Red
    Write-Host "                         BREAKING CHANGE DETECTED                              " -ForegroundColor Red
    Write-Host "================================================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "  The remote version ($RemoteVersion) has a MAJOR version bump from your" -ForegroundColor Yellow
    Write-Host "  current version ($CurrentVersion). This indicates breaking changes that" -ForegroundColor Yellow
    Write-Host "  cannot be safely applied via update." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  To upgrade to v$RemoteMajor.x.x:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1. Remove the current WOF installation:" -ForegroundColor White
    Write-Host "       /wof remove" -ForegroundColor Gray
    Write-Host "       - or -" -ForegroundColor DarkGray
    Write-Host "       .\.ai\scripts\remove.ps1" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  2. Restart your Claude Code / AI session" -ForegroundColor White
    Write-Host "       (This ensures a clean slate without cached WOI context)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  3. Run fresh setup from the new version:" -ForegroundColor White
    Write-Host "       irm https://raw.githubusercontent.com/ndrezza/wof/main/setup.ps1 | iex" -ForegroundColor Gray
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Red
    Write-Host ""
    Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 2
}

# Step 3: Verify sync.ps1 exists
Write-Host "[3/4] Verifying sync script..." -ForegroundColor Cyan
$SyncScript = Join-Path $TempDir "sync.ps1"
if (-not (Test-Path $SyncScript)) {
    Write-Host "       ERROR: sync.ps1 not found in repository" -ForegroundColor Red
    Write-Host "       The repository structure may have changed" -ForegroundColor Gray
    Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}
Write-Host "       Sync script found" -ForegroundColor Green

# Step 4: Run official sync
Write-Host "[4/4] Applying updates..." -ForegroundColor Cyan
Write-Host ""

# Build the command dynamically to avoid splatting issues
$syncCommand = "& `"$SyncScript`" -TargetPath `"$ProjectRoot`""
if ($DryRun) {
    $syncCommand += " -DryRun"
}
if ($Force) {
    $syncCommand += " -Force"
}

try {
    # Use Invoke-Expression to run the sync script with proper parameter handling
    Invoke-Expression $syncCommand
    $SyncExitCode = $LASTEXITCODE
}
catch {
    Write-Host "       Sync failed with error: $_" -ForegroundColor Red
    $SyncExitCode = 1
}
finally {
    # Cleanup
    Write-Host ""
    Write-Host "[*] Cleaning up temporary files..." -ForegroundColor Cyan
    Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
}

if ($SyncExitCode -ne 0) {
    Write-Host ""
    Write-Host "Update failed with exit code: $SyncExitCode" -ForegroundColor Red
    exit $SyncExitCode
}

# Final summary
Write-Host ""
Write-Host "================================================================================" -ForegroundColor Green
Write-Host "                              UPDATE COMPLETE                                  " -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Green
Write-Host ""

if (-not $DryRun) {
    Write-Host "  Updated: $CurrentVersion -> $RemoteVersion" -ForegroundColor Green
}

Write-Host ""
Write-Host "Tips:" -ForegroundColor DarkGray
Write-Host "  - To preserve a file from future updates, add '# CUSTOMIZED' at the top" -ForegroundColor DarkGray
Write-Host "  - Run with -DryRun to preview changes before applying" -ForegroundColor DarkGray
Write-Host "  - Use -Tag v1.x.x to update to a specific version" -ForegroundColor DarkGray
Write-Host ""
