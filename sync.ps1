<#
.SYNOPSIS
    Syncs the Workload Orchestration Framework in a target project with the latest version.

.DESCRIPTION
    This script updates framework files in a target project based on the sync-manifest.json
    rules. It respects customization boundaries and only overwrites files marked for update.

.PARAMETER TargetPath
    The root path of the target project where the framework is installed.

.PARAMETER DryRun
    Show what would be updated without making changes.

.PARAMETER Force
    Ignore customization markers and force update all eligible files.

.EXAMPLE
    .\sync.ps1 -TargetPath "C:\code\MyProject"

.EXAMPLE
    .\sync.ps1 -TargetPath "C:\code\MyProject" -DryRun
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$TargetPath,

    [Parameter(Mandatory=$false)]
    [switch]$DryRun,

    [Parameter(Mandatory=$false)]
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$scriptRoot = $PSScriptRoot
$manifestFile = Join-Path $scriptRoot "sync-manifest.json"
$versionFile = Join-Path $scriptRoot "VERSION"

# Color helpers
function Write-Step { param([string]$Message) Write-Host "[*] $Message" -ForegroundColor Cyan }
function Write-Success { param([string]$Message) Write-Host "[+] $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "[!] $Message" -ForegroundColor Yellow }
function Write-Info { param([string]$Message) Write-Host "    $Message" -ForegroundColor Gray }

# Validation
if (-not (Test-Path $TargetPath)) {
    Write-Host "[-] Target path does not exist: $TargetPath" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $manifestFile)) {
    Write-Host "[-] sync-manifest.json not found" -ForegroundColor Red
    exit 1
}

# Load manifest and version
$manifest = Get-Content $manifestFile | ConvertFrom-Json
$newVersion = if (Test-Path $versionFile) { (Get-Content $versionFile).Trim() } else { "unknown" }

# Check current version in target
$targetVersionFile = Join-Path $TargetPath ".ai\.framework-version"
$currentVersion = if (Test-Path $targetVersionFile) { (Get-Content $targetVersionFile).Trim() } else { "not-installed" }

Write-Host ""
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "              WORKLOAD ORCHESTRATION FRAMEWORK SYNC                            " -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Target:          $TargetPath"
Write-Host "  Current Version: $currentVersion"
Write-Host "  New Version:     $newVersion"
if ($DryRun) { Write-Host "  Mode:            DRY RUN" -ForegroundColor Yellow }
Write-Host ""

$coreDir = Join-Path $scriptRoot "core"
$aiDir = Join-Path $TargetPath ".ai"

$updated = @()
$skipped = @()
$preserved = @()

function Test-PatternMatch {
    param(
        [string]$FilePath,
        [string[]]$Patterns
    )

    foreach ($pattern in $Patterns) {
        if ($FilePath -like $pattern) {
            return $true
        }
    }
    return $false
}

function Test-FileCustomized {
    param([string]$FilePath)

    if (-not (Test-Path $FilePath)) { return $false }

    $content = Get-Content $FilePath -Raw -ErrorAction SilentlyContinue
    if ($content -match "# CUSTOMIZED|// CUSTOMIZED|<!-- CUSTOMIZED -->") {
        return $true
    }
    return $false
}

# Process overwrite files (always update)
Write-Step "Processing files to overwrite..."
foreach ($pattern in $manifest.overwrite.patterns) {
    $sourcePath = Join-Path $coreDir ($pattern -replace '/', '\')
    $sourceDir = Split-Path $sourcePath -Parent

    if (Test-Path $sourceDir) {
        $files = Get-ChildItem $sourceDir -Filter (Split-Path $pattern -Leaf) -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            $relativePath = $file.FullName.Substring($coreDir.Length + 1)
            $targetFile = Join-Path $aiDir $relativePath

            if ($DryRun) {
                Write-Info "Would update: $relativePath"
                $updated += $relativePath
            } else {
                $targetDir = Split-Path $targetFile -Parent
                if (-not (Test-Path $targetDir)) {
                    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                }
                Copy-Item $file.FullName $targetFile -Force
                Write-Info "Updated: $relativePath"
                $updated += $relativePath
            }
        }
    }
}

# Process skip_if_customized files
Write-Step "Processing files to skip if customized..."
foreach ($pattern in $manifest.skip_if_customized.patterns) {
    $sourcePath = Join-Path $coreDir ($pattern -replace '/', '\')
    $sourceDir = Split-Path $sourcePath -Parent

    if (Test-Path $sourceDir) {
        $files = Get-ChildItem $sourceDir -Filter (Split-Path $pattern -Leaf) -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            $relativePath = $file.FullName.Substring($coreDir.Length + 1)
            $targetFile = Join-Path $aiDir $relativePath

            if ((Test-Path $targetFile) -and (Test-FileCustomized $targetFile) -and -not $Force) {
                Write-Info "Skipped (customized): $relativePath"
                $skipped += $relativePath
            } elseif ($DryRun) {
                Write-Info "Would update: $relativePath"
                $updated += $relativePath
            } else {
                $targetDir = Split-Path $targetFile -Parent
                if (-not (Test-Path $targetDir)) {
                    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                }
                Copy-Item $file.FullName $targetFile -Force
                Write-Info "Updated: $relativePath"
                $updated += $relativePath
            }
        }
    }
}

# List preserved files (never update)
Write-Step "Preserved files (never updated)..."
foreach ($pattern in $manifest.always_preserve.patterns) {
    Write-Info "Preserved: $pattern"
    $preserved += $pattern
}

# Update version marker
if (-not $DryRun) {
    $versionDir = Split-Path $targetVersionFile -Parent
    if (-not (Test-Path $versionDir)) {
        New-Item -ItemType Directory -Path $versionDir -Force | Out-Null
    }
    Set-Content -Path $targetVersionFile -Value $newVersion
}

# Summary
Write-Host ""
Write-Host "================================================================================" -ForegroundColor Green
Write-Host "                              SYNC COMPLETE                                    " -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Updated:   $($updated.Count) files"
Write-Host "  Skipped:   $($skipped.Count) files (customized)"
Write-Host "  Preserved: $($preserved.Count) patterns"
Write-Host ""

if ($DryRun) {
    Write-Warn "DRY RUN - No changes were made"
    Write-Host ""
}

if ($skipped.Count -gt 0) {
    Write-Host "Skipped files (add # CUSTOMIZED marker to preserve):" -ForegroundColor Yellow
    foreach ($file in $skipped) {
        Write-Host "  - $file" -ForegroundColor Gray
    }
    Write-Host ""
}

return @{
    Success = $true
    Updated = $updated
    Skipped = $skipped
    Preserved = $preserved
    FromVersion = $currentVersion
    ToVersion = $newVersion
}
