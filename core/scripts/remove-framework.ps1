<#
.SYNOPSIS
    Removes the Workload Orchestration Framework (WOF) from the current project.

.DESCRIPTION
    This script removes WOF from a project using the installation manifest to
    precisely identify and remove only WOF-installed files. User-created files
    and configuration files are preserved by default.

    Components removed:
    - Framework scripts (.ai/scripts/*.ps1)
    - WOF metadata files (.framework-version, .mode, .installed-files.json)
    - .claude/settings.json and .claude/skills/wof/ (WOF IDE integration)
    - CLAUDE.md in the project root
    - WOF-related entries from .gitignore (optional)

    Components PRESERVED by default:
    - config/credentials.local.ps1 (API keys, connection strings)
    - config/providers.yaml, models.yaml, ai-rules.md (customized settings)
    - memory/current-sprint.md, architecture.md, conventions.md (project context)
    - User-created files not in the manifest

.PARAMETER DryRun
    Shows what would be removed without making changes.

.PARAMETER Force
    Skips confirmation prompt.

.PARAMETER KeepGitIgnore
    Preserves .gitignore entries (doesn't clean up WOF patterns).

.PARAMETER IncludeConfig
    Also removes config and memory files that are normally preserved.
    Use this to completely clean up, but note that credentials will be lost.

.PARAMETER RemoveAll
    Removes entire .ai/ and .claude/ directories including ALL files.
    Use with extreme caution - this ignores the manifest completely.

.EXAMPLE
    .\remove-framework.ps1
    # Removes WOF scripts, preserves config and memory files

.EXAMPLE
    .\remove-framework.ps1 -DryRun
    # Preview what would be removed

.EXAMPLE
    .\remove-framework.ps1 -IncludeConfig
    # Also remove config files (credentials, providers, etc.)

.EXAMPLE
    .\remove-framework.ps1 -RemoveAll -Force
    # Nuclear option: remove everything, no confirmation

.NOTES
    The manifest file (.ai/.installed-files.json) tracks all WOF-installed files.
    Config and memory files are preserved by default because they contain:
    - API keys and connection strings (credentials.local.ps1)
    - Project-specific customizations (architecture.md, conventions.md)
    - Active work tracking (current-sprint.md)
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Force,
    [switch]$KeepGitIgnore,
    [switch]$IncludeConfig,
    [switch]$RemoveAll
)

$ErrorActionPreference = "Stop"

# Determine project root (go up from .ai/scripts to project root)
$ScriptDir = $PSScriptRoot
$AiDir = Split-Path $ScriptDir -Parent
$ProjectRoot = Split-Path $AiDir -Parent

# Validate we're in the right location
if (-not (Test-Path (Join-Path $AiDir ".framework-version")) -and -not (Test-Path (Join-Path $AiDir "config"))) {
    Write-Host "[-] ERROR: This script must be run from within a project's .ai/scripts directory" -ForegroundColor Red
    Write-Host "    Expected path: <project>/.ai/scripts/remove-framework.ps1" -ForegroundColor Gray
    exit 1
}

# Read current version
$VersionFile = Join-Path $AiDir ".framework-version"
$CurrentVersion = if (Test-Path $VersionFile) { (Get-Content $VersionFile).Trim() } else { "unknown" }

# Read installation manifest
$ManifestFile = Join-Path $AiDir ".installed-files.json"
$Manifest = $null
$ManifestFiles = @()

if (Test-Path $ManifestFile) {
    try {
        $Manifest = Get-Content $ManifestFile -Raw | ConvertFrom-Json
        $ManifestFiles = @($Manifest.files)
    }
    catch {
        Write-Host "[!] Warning: Could not parse manifest file. Will use directory-based removal." -ForegroundColor Yellow
        $RemoveAll = $true
    }
}
else {
    Write-Host "[!] Warning: No manifest file found. Will use directory-based removal." -ForegroundColor Yellow
    $RemoveAll = $true
}

# Display header
Write-Host ""
Write-Host "================================================================================" -ForegroundColor Red
Write-Host "          WORKLOAD ORCHESTRATION FRAMEWORK (WOF) REMOVAL                       " -ForegroundColor Red
Write-Host "================================================================================" -ForegroundColor Red
Write-Host ""
Write-Host "  Project:         $ProjectRoot" -ForegroundColor Gray
Write-Host "  Version:         $CurrentVersion" -ForegroundColor Gray
Write-Host "  Removal Mode:    $(if ($RemoveAll) { 'FULL (all files)' } else { 'MANIFEST (WOF files only)' })" -ForegroundColor $(if ($RemoveAll) { "Yellow" } else { "Gray" })

if ($DryRun) {
    Write-Host "  Preview:         DRY RUN" -ForegroundColor Yellow
}
Write-Host ""

# Collect files to remove
$FilesToRemove = @()
$UserFilesPreserved = @()

if ($RemoveAll) {
    # Remove entire directories
    Write-Host "[*] Mode: FULL REMOVAL (directories)" -ForegroundColor Yellow
    Write-Host ""

    if (Test-Path $AiDir) {
        $aiFileCount = (Get-ChildItem $AiDir -Recurse -File -ErrorAction SilentlyContinue).Count
        $FilesToRemove += @{ Path = $AiDir; Type = "Directory"; Description = ".ai/ directory ($aiFileCount files)" }
    }

    $ClaudeDir = Join-Path $ProjectRoot ".claude"
    if (Test-Path $ClaudeDir) {
        $claudeFileCount = (Get-ChildItem $ClaudeDir -Recurse -File -ErrorAction SilentlyContinue).Count
        $FilesToRemove += @{ Path = $ClaudeDir; Type = "Directory"; Description = ".claude/ directory ($claudeFileCount files)" }
    }

    $ClaudeMd = Join-Path $ProjectRoot "CLAUDE.md"
    if (Test-Path $ClaudeMd) {
        $FilesToRemove += @{ Path = $ClaudeMd; Type = "File"; Description = "CLAUDE.md" }
    }
}
else {
    # Manifest-based removal
    Write-Host "[*] Mode: MANIFEST-BASED REMOVAL (preserves user files)" -ForegroundColor Cyan
    Write-Host ""

    # Files to preserve by default (contain user data, secrets, or customizations)
    # These match the always_preserve and template_only patterns in sync-manifest.json
    # Can be overridden with -IncludeConfig flag
    $PreservePatterns = @(
        "config/credentials.local.ps1",   # API keys, connection strings - NEVER delete
        "memory/current-sprint.md",       # Active work tracking
        "memory/local-dev-setup.md",      # Local environment notes
        "memory/architecture.md",         # Project-specific architecture
        "memory/conventions.md",          # Project-specific conventions
        "config/providers.yaml",          # Customized provider settings
        "config/models.yaml",             # Customized model tiers
        "config/ai-rules.md"              # Customized AI behavior rules
    )

    if ($IncludeConfig) {
        Write-Host "[!] -IncludeConfig specified: Config and memory files will also be removed" -ForegroundColor Yellow
        Write-Host ""
        $PreservePatterns = @()  # Clear preservation list
    }

    # 1. Files from manifest (relative to .ai/), excluding preserved files
    foreach ($relPath in $ManifestFiles) {
        # Check if this file should be preserved
        $shouldPreserve = $false
        foreach ($pattern in $PreservePatterns) {
            if ($relPath -eq $pattern -or $relPath -eq $pattern.Replace('/', '\')) {
                $shouldPreserve = $true
                $UserFilesPreserved += $relPath
                break
            }
        }

        if (-not $shouldPreserve) {
            $fullPath = Join-Path $AiDir $relPath
            if (Test-Path $fullPath) {
                $FilesToRemove += @{ Path = $fullPath; Type = "File"; Description = ".ai/$relPath" }
            }
        }
    }

    # 2. WOF metadata files in .ai/
    $metadataFiles = @(".framework-version", ".installed-files.json")
    foreach ($metaFile in $metadataFiles) {
        $fullPath = Join-Path $AiDir $metaFile
        if (Test-Path $fullPath) {
            $FilesToRemove += @{ Path = $fullPath; Type = "File"; Description = ".ai/$metaFile (metadata)" }
        }
    }

    # 3. .claude/settings.json
    $ClaudeSettings = Join-Path $ProjectRoot ".claude\settings.json"
    if (Test-Path $ClaudeSettings) {
        $FilesToRemove += @{ Path = $ClaudeSettings; Type = "File"; Description = ".claude/settings.json" }
    }

    # 4. .claude/skills/wof/ directory
    $WofSkillDir = Join-Path $ProjectRoot ".claude\skills\wof"
    if (Test-Path $WofSkillDir) {
        $FilesToRemove += @{ Path = $WofSkillDir; Type = "Directory"; Description = ".claude/skills/wof/" }
    }

    # 5. CLAUDE.md - Remove WOI section only (NEVER delete the entire file)
    #    If no WOI section markers exist, the file wasn't created by WOI, so leave it alone
    $ClaudeMd = Join-Path $ProjectRoot "CLAUDE.md"
    $WoiSectionFound = $false
    if (Test-Path $ClaudeMd) {
        $claudeContent = Get-Content $ClaudeMd -Raw
        if ($claudeContent -match "<!-- WOI-SECTION-START") {
            $WoiSectionFound = $true
            # Don't add to FilesToRemove - we'll handle this separately
            Write-Host "    [WOI]   CLAUDE.md WOI section will be removed (file preserved)" -ForegroundColor Yellow
        } else {
            # No WOI section markers = file wasn't created by WOI, leave it alone
            Write-Host "    [SKIP]  CLAUDE.md has no WOI section markers (not WOI-managed)" -ForegroundColor Gray
        }
    }

    # Find user files that will be preserved
    if (Test-Path $AiDir) {
        $allAiFiles = Get-ChildItem $AiDir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
            $_.FullName.Substring($AiDir.Length + 1).Replace('\', '/')
        }

        $wofFiles = $ManifestFiles + $metadataFiles
        foreach ($file in $allAiFiles) {
            $isWofFile = $false
            foreach ($wofFile in $wofFiles) {
                if ($file -eq $wofFile -or $file -eq $wofFile.Replace('/', '\')) {
                    $isWofFile = $true
                    break
                }
            }
            if (-not $isWofFile) {
                $UserFilesPreserved += $file
            }
        }
    }

    # Check for user files in .claude/ (other skills, custom settings)
    $ClaudeDir = Join-Path $ProjectRoot ".claude"
    if (Test-Path $ClaudeDir) {
        $allClaudeFiles = Get-ChildItem $ClaudeDir -Recurse -File -ErrorAction SilentlyContinue
        foreach ($file in $allClaudeFiles) {
            $relPath = $file.FullName.Substring($ClaudeDir.Length + 1)
            # Check if it's a WOF file
            $isWofFile = ($relPath -eq "settings.json") -or ($relPath -like "skills\wof\*") -or ($relPath -like "skills/wof/*")
            if (-not $isWofFile) {
                $UserFilesPreserved += ".claude\$relPath"
            }
        }
    }
}

# Display files to remove
Write-Host "[*] WOF components to remove:" -ForegroundColor Cyan

$fileCount = ($FilesToRemove | Where-Object { $_.Type -eq "File" }).Count
$dirCount = ($FilesToRemove | Where-Object { $_.Type -eq "Directory" }).Count

if ($fileCount -gt 0 -or $dirCount -gt 0) {
    Write-Host ""

    # Group by directory for cleaner output
    if (-not $RemoveAll -and $fileCount -gt 10) {
        # Summarize by folder
        $byFolder = $FilesToRemove | Where-Object { $_.Type -eq "File" } | Group-Object { Split-Path $_.Description -Parent }
        foreach ($group in $byFolder) {
            Write-Host "    [FILES] $($group.Name)/ ($($group.Count) files)" -ForegroundColor Yellow
        }
        $FilesToRemove | Where-Object { $_.Type -eq "Directory" } | ForEach-Object {
            Write-Host "    [DIR]   $($_.Description)" -ForegroundColor Yellow
        }
    }
    else {
        foreach ($item in $FilesToRemove) {
            $icon = if ($item.Type -eq "Directory") { "[DIR] " } else { "[FILE]" }
            Write-Host "    $icon $($item.Description)" -ForegroundColor Yellow
        }
    }
}
else {
    Write-Host "    (none found)" -ForegroundColor Gray
}

# Display user files that will be preserved
if ($UserFilesPreserved.Count -gt 0) {
    Write-Host ""
    Write-Host "[*] User files to PRESERVE:" -ForegroundColor Green
    Write-Host ""
    foreach ($file in $UserFilesPreserved) {
        Write-Host "    [KEEP]  $file" -ForegroundColor Green
    }
}

# Check .gitignore for WOI sections
$GitIgnorePath = Join-Path $ProjectRoot ".gitignore"
$HasWoiFrameworkSection = $false
$HasLegacyWoiSection = $false

if ((Test-Path $GitIgnorePath) -and -not $KeepGitIgnore) {
    $gitIgnoreContent = Get-Content $GitIgnorePath -Raw

    # Check for new dual-section format
    if ($gitIgnoreContent -match "# <!-- WOI-FRAMEWORK-START") {
        $HasWoiFrameworkSection = $true
        Write-Host ""
        Write-Host "[*] .gitignore WOI-FRAMEWORK section to remove:" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "    [GITIGNORE] WOI-FRAMEWORK section (framework files)" -ForegroundColor Yellow
        Write-Host "    [PRESERVE]  WOI-USERDATA section (credentials, memory - kept)" -ForegroundColor Green
    }
    # Check for legacy single-section format
    elseif ($gitIgnoreContent -match "# <!-- WOI-SECTION-START") {
        $HasLegacyWoiSection = $true
        Write-Host ""
        Write-Host "[*] .gitignore WOI section to remove (legacy format):" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "    [GITIGNORE] WOI section (managed by WOF)" -ForegroundColor Yellow
        Write-Host "    [WARNING]   User data entries will also be removed (legacy format)" -ForegroundColor Yellow
    }
}

Write-Host ""

if ($FilesToRemove.Count -eq 0) {
    Write-Host "[!] No WOF components found to remove." -ForegroundColor Yellow
    exit 0
}

# Confirmation prompt
if (-not $DryRun -and -not $Force) {
    Write-Host "================================================================================" -ForegroundColor Red
    Write-Host "  WARNING: This will remove WOF from this project.                             " -ForegroundColor Red
    if ($UserFilesPreserved.Count -gt 0) {
        Write-Host "  User files ($($UserFilesPreserved.Count)) will be preserved.                                      " -ForegroundColor Green
    }
    Write-Host "================================================================================" -ForegroundColor Red
    Write-Host ""

    $confirmation = Read-Host "Type 'REMOVE' to confirm"
    if ($confirmation -ne "REMOVE") {
        Write-Host ""
        Write-Host "[!] Removal cancelled." -ForegroundColor Yellow
        exit 0
    }
    Write-Host ""
}

if ($DryRun) {
    Write-Host "[DRY RUN] Would remove the above components. No changes made." -ForegroundColor Yellow
    if ($UserFilesPreserved.Count -gt 0) {
        Write-Host "[DRY RUN] $($UserFilesPreserved.Count) user file(s) would be preserved." -ForegroundColor Green
    }
    Write-Host ""
    exit 0
}

# Perform removal
Write-Host "[1/4] Removing WOF files..." -ForegroundColor Cyan

$removedCount = 0
$failedCount = 0

foreach ($item in $FilesToRemove) {
    try {
        if (Test-Path $item.Path) {
            Remove-Item $item.Path -Recurse -Force
            $removedCount++
        }
    }
    catch {
        Write-Host "       FAILED: $($item.Description) - $_" -ForegroundColor Red
        $failedCount++
    }
}

Write-Host "       Removed $removedCount items" -ForegroundColor Green

# Remove WOI section from CLAUDE.md if present
if ($WoiSectionFound -and (Test-Path $ClaudeMd)) {
    Write-Host "[1.5/4] Removing WOI section from CLAUDE.md..." -ForegroundColor Cyan
    try {
        $claudeContent = Get-Content $ClaudeMd -Raw
        $startMarker = "<!-- WOI-SECTION-START"
        $endMarker = "<!-- WOI-SECTION-END -->"
        $pattern = "(?s)\r?\n?$([regex]::Escape($startMarker)).*?$([regex]::Escape($endMarker))\r?\n?"

        $newContent = $claudeContent -replace $pattern, "`n"
        # Clean up multiple consecutive newlines
        $newContent = $newContent -replace "(\r?\n){3,}", "`n`n"
        $newContent = $newContent.Trim() + "`n"

        Set-Content -Path $ClaudeMd -Value $newContent -NoNewline
        Write-Host "       WOI section removed from CLAUDE.md" -ForegroundColor Green
    }
    catch {
        Write-Host "       FAILED to remove WOI section: $_" -ForegroundColor Red
        $failedCount++
    }
}

# Clean up empty directories
Write-Host "[2/4] Cleaning empty directories..." -ForegroundColor Cyan

$emptyDirsRemoved = 0

# Function to recursively remove empty directories
function Remove-EmptyDirectories {
    param([string]$Path)

    if (-not (Test-Path $Path)) { return }

    Get-ChildItem $Path -Directory -Recurse | Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
        if ((Get-ChildItem $_.FullName -Force).Count -eq 0) {
            Remove-Item $_.FullName -Force
            $script:emptyDirsRemoved++
        }
    }

    # Check if root dir is now empty
    if ((Test-Path $Path) -and (Get-ChildItem $Path -Force).Count -eq 0) {
        Remove-Item $Path -Force
        $script:emptyDirsRemoved++
    }
}

if (Test-Path $AiDir) {
    Remove-EmptyDirectories -Path $AiDir
}

$ClaudeDir = Join-Path $ProjectRoot ".claude"
if (Test-Path $ClaudeDir) {
    Remove-EmptyDirectories -Path $ClaudeDir
}

if ($emptyDirsRemoved -gt 0) {
    Write-Host "       Removed $emptyDirsRemoved empty directories" -ForegroundColor Green
}
else {
    Write-Host "       No empty directories to remove" -ForegroundColor Gray
}

# Clean up .gitignore (remove WOI-FRAMEWORK section, preserve WOI-USERDATA)
Write-Host "[3/4] Cleaning .gitignore..." -ForegroundColor Cyan

if (($HasWoiFrameworkSection -or $HasLegacyWoiSection) -and (Test-Path $GitIgnorePath)) {
    try {
        $gitIgnoreContent = Get-Content $GitIgnorePath -Raw

        if ($HasWoiFrameworkSection) {
            # New format: Remove only FRAMEWORK section, keep USERDATA section
            $pattern = "(?s)\r?\n?# <!-- WOI-FRAMEWORK-START.*?# <!-- WOI-FRAMEWORK-END -->\r?\n?"
            $newContent = $gitIgnoreContent -replace $pattern, "`n"
            Write-Host "       Removed WOI-FRAMEWORK section" -ForegroundColor Green
            Write-Host "       Preserved WOI-USERDATA section (credentials stay gitignored)" -ForegroundColor Green
        }
        else {
            # Legacy format: Remove entire WOI section (no userdata preservation)
            $pattern = "(?s)\r?\n?# <!-- WOI-SECTION-START.*?# <!-- WOI-SECTION-END -->\r?\n?"
            $newContent = $gitIgnoreContent -replace $pattern, "`n"
            Write-Host "       Removed legacy WOI section from .gitignore" -ForegroundColor Green
            Write-Host "       Warning: User data files may now be untracked (legacy format)" -ForegroundColor Yellow
        }

        # Clean up multiple consecutive newlines
        $newContent = $newContent -replace "(\r?\n){3,}", "`n`n"
        $newContent = $newContent.Trim()

        if ($newContent) {
            $newContent += "`n"
        }

        Set-Content $GitIgnorePath -Value $newContent -NoNewline
    }
    catch {
        Write-Host "       Warning: Could not clean .gitignore - $_" -ForegroundColor Yellow
    }
}
else {
    Write-Host "       No changes needed" -ForegroundColor Gray
}

# Verify removal
Write-Host "[4/4] Verifying removal..." -ForegroundColor Cyan

$remainingWof = @()
if (Test-Path (Join-Path $AiDir ".framework-version")) { $remainingWof += ".ai/.framework-version" }
# Only warn about CLAUDE.md if it still contains WOI section markers (failed to remove them)
$claudeMdPath = Join-Path $ProjectRoot "CLAUDE.md"
if ((Test-Path $claudeMdPath) -and ((Get-Content $claudeMdPath -Raw) -match "<!-- WOI-SECTION-START")) {
    $remainingWof += "CLAUDE.md (WOI section)"
}
if (Test-Path (Join-Path $ProjectRoot ".claude\skills\wof")) { $remainingWof += ".claude/skills/wof/" }

if ($remainingWof.Count -eq 0) {
    Write-Host "       WOF successfully removed" -ForegroundColor Green
}
else {
    Write-Host "       Warning: Some WOF items remain: $($remainingWof -join ', ')" -ForegroundColor Yellow
}

# Final summary
Write-Host ""
if ($failedCount -eq 0) {
    Write-Host "================================================================================" -ForegroundColor Green
    Write-Host "                           REMOVAL COMPLETE                                    " -ForegroundColor Green
    Write-Host "================================================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  WOF v$CurrentVersion has been removed from this project." -ForegroundColor Green

    if ($UserFilesPreserved.Count -gt 0) {
        Write-Host "  $($UserFilesPreserved.Count) user file(s) were preserved in .ai/" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "  To reinstall WOF later, run setup.ps1 from the WOF repository:" -ForegroundColor DarkGray
    Write-Host "    .\setup.ps1 -TargetPath `"$ProjectRoot`"" -ForegroundColor DarkGray
}
else {
    Write-Host "================================================================================" -ForegroundColor Yellow
    Write-Host "                        REMOVAL PARTIALLY COMPLETE                             " -ForegroundColor Yellow
    Write-Host "================================================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Removed: $removedCount items" -ForegroundColor Green
    Write-Host "  Failed:  $failedCount items" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Please manually remove any remaining items." -ForegroundColor Yellow
}

Write-Host ""
