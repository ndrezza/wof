<#
.SYNOPSIS
    Syncs the Workload Orchestration Framework (WOF) in a target project with the latest version.

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
Write-Host "            WORKLOAD ORCHESTRATION FRAMEWORK (WOF) SYNC                       " -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Target:          $TargetPath"
Write-Host "  Current Version: $currentVersion"
Write-Host "  New Version:     $newVersion"
if ($DryRun) { Write-Host "  Mode:            DRY RUN" -ForegroundColor Yellow }
Write-Host ""

$coreDir = Join-Path $scriptRoot "core"
$aiDir = Join-Path $TargetPath ".ai"
$configDir = Join-Path $aiDir "config"

$updated = @()
$skipped = @()
$preserved = @()
$deprecated = @()
$newInstalledFiles = @()

# Check for v1 -> v2 config migration
$oldProvidersYaml = Join-Path $configDir "providers.yaml"
$oldCredentialsPs1 = Join-Path $configDir "credentials.local.ps1"
$newConnectionsJson = Join-Path $configDir "connections.json"
$newRolesJson = Join-Path $configDir "roles.json"

$hasOldConfig = (Test-Path $oldProvidersYaml) -or (Test-Path $oldCredentialsPs1)
$hasNewConfig = (Test-Path $newConnectionsJson) -and (Test-Path $newRolesJson)

if ($hasOldConfig -and -not $hasNewConfig) {
    Write-Step "Detected v1 configuration format - running migration..."
    $migrateScript = Join-Path $scriptRoot "core\scripts\migrate-config.ps1"
    if (Test-Path $migrateScript) {
        if ($DryRun) {
            Write-Info "Would run: migrate-config.ps1 -TargetPath '$TargetPath' -DryRun"
            & $migrateScript -TargetPath $TargetPath -DryRun
        } else {
            $migrationResult = & $migrateScript -TargetPath $TargetPath
            if ($migrationResult.Migrated) {
                Write-Success "Configuration migrated from v1 to v2 format"
                Write-Info "Connections: $($migrationResult.ConnectionsCount), Roles: $($migrationResult.RolesCount)"
            }
        }
    } else {
        Write-Warn "migrate-config.ps1 not found, skipping configuration migration"
    }
    Write-Host ""
}

# Load previous installed files manifest
$installedManifestFile = Join-Path $aiDir ".installed-files.json"
$previousFiles = @()
if (Test-Path $installedManifestFile) {
    try {
        $installedManifest = Get-Content $installedManifestFile -Raw | ConvertFrom-Json
        $previousFiles = @($installedManifest.files)
        Write-Host "  Previous Install: $($previousFiles.Count) files tracked"
    } catch {
        Write-Warn "Could not read installed files manifest, skipping orphan detection"
    }
} else {
    Write-Host "  Previous Install: No manifest found (first sync or legacy install)"
}

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

            # Track file for manifest (normalize path separators)
            $normalizedPath = $relativePath -replace '\\', '/'
            $newInstalledFiles += $normalizedPath

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

            # Track file for manifest (normalize path separators)
            $normalizedPath = $relativePath -replace '\\', '/'
            $newInstalledFiles += $normalizedPath

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

# Process skills (slash commands)
Write-Step "Processing skills (slash commands)..."
$templatesDir = Join-Path $scriptRoot "templates"
$skillsSource = Join-Path $templatesDir "dot-claude\skills"
$skillsTarget = Join-Path $TargetPath ".claude\skills"

if (Test-Path $skillsSource) {
    Get-ChildItem $skillsSource -Directory | ForEach-Object {
        $skillName = $_.Name
        $skillFile = Join-Path $_.FullName "SKILL.md"
        $destFile = Join-Path $skillsTarget "$skillName\SKILL.md"
        $relativePath = ".claude/skills/$skillName/SKILL.md"

        # Track for manifest
        $newInstalledFiles += $relativePath

        if (Test-Path $skillFile) {
            if ((Test-Path $destFile) -and (Test-FileCustomized $destFile) -and -not $Force) {
                Write-Info "Skipped (customized): $relativePath"
                $skipped += $relativePath
            } elseif ($DryRun) {
                Write-Info "Would update: $relativePath"
                $updated += $relativePath
            } else {
                $destDir = Split-Path $destFile -Parent
                if (-not (Test-Path $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                }
                Copy-Item $skillFile $destFile -Force
                Write-Info "Updated: $relativePath"
                $updated += $relativePath
            }
        }
    }
} else {
    Write-Info "No skills found in framework"
}

# List preserved files (never update)
Write-Step "Preserved files (never updated)..."
foreach ($pattern in $manifest.always_preserve.patterns) {
    Write-Info "Preserved: $pattern"
    $preserved += $pattern
}

# Detect and handle orphaned files (in old manifest but not in new)
if ($previousFiles.Count -gt 0) {
    Write-Step "Checking for orphaned files..."

    # Build list of patterns to exclude from orphan detection
    # These are files created from templates or always preserved - they're expected to exist
    $excludePatterns = @()
    $excludePatterns += $manifest.always_preserve.patterns
    $excludePatterns += $manifest.template_only.patterns

    $orphanedFiles = $previousFiles | Where-Object {
        $file = $_
        $inNewManifest = $file -in $newInstalledFiles

        # Check if file matches any exclude pattern
        $isExcluded = $false
        foreach ($pattern in $excludePatterns) {
            # Convert pattern to work with our file paths
            $normalizedPattern = $pattern -replace '\.ai/', '' -replace '\*', '.*'
            if ($file -match "^$normalizedPattern$" -or ".ai/$file" -like $pattern) {
                $isExcluded = $true
                break
            }
        }

        (-not $inNewManifest) -and (-not $isExcluded)
    }

    if ($orphanedFiles.Count -gt 0) {
        $deprecatedDir = Join-Path $aiDir ".deprecated"

        foreach ($orphan in $orphanedFiles) {
            $orphanPath = Join-Path $aiDir ($orphan -replace '/', '\')

            if (Test-Path $orphanPath) {
                $isCustomized = Test-FileCustomized $orphanPath

                if ($isCustomized) {
                    Write-Warn "Orphaned (customized, preserved): $orphan"
                    # Keep customized orphans in place but warn
                } else {
                    if ($DryRun) {
                        Write-Info "Would deprecate: $orphan"
                    } else {
                        # Move to .deprecated folder
                        $deprecatedPath = Join-Path $deprecatedDir ($orphan -replace '/', '\')
                        $deprecatedParent = Split-Path $deprecatedPath -Parent

                        if (-not (Test-Path $deprecatedParent)) {
                            New-Item -ItemType Directory -Path $deprecatedParent -Force | Out-Null
                        }

                        Move-Item $orphanPath $deprecatedPath -Force
                        Write-Info "Deprecated: $orphan -> .deprecated/$orphan"
                    }
                    $deprecated += $orphan
                }
            }
        }

        if ($deprecated.Count -gt 0 -and -not $DryRun) {
            Write-Host ""
            Write-Warn "$($deprecated.Count) file(s) moved to .ai/.deprecated/"
            Write-Host "    Review and delete if no longer needed" -ForegroundColor Gray
        }
    } else {
        Write-Info "No orphaned files detected"
    }
}

# Update installed files manifest
Write-Step "Updating installed files manifest..."
$newManifest = @{
    version = $newVersion
    installedAt = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    syncedFrom = $currentVersion
    files = $newInstalledFiles | Sort-Object | Select-Object -Unique
}

if (-not $DryRun) {
    $manifestJson = $newManifest | ConvertTo-Json -Depth 10
    Set-Content -Path $installedManifestFile -Value $manifestJson -Encoding UTF8
    Write-Info "Updated: .installed-files.json ($($newInstalledFiles.Count) files)"
} else {
    Write-Info "Would update: .installed-files.json ($($newInstalledFiles.Count) files)"
}

# Update version marker
if (-not $DryRun) {
    $versionDir = Split-Path $targetVersionFile -Parent
    if (-not (Test-Path $versionDir)) {
        New-Item -ItemType Directory -Path $versionDir -Force | Out-Null
    }
    Set-Content -Path $targetVersionFile -Value $newVersion
}

# Inject/Update WOI section in CLAUDE.md
Write-Step "Processing WOI section in CLAUDE.md..."
$claudeMdPath = Join-Path $TargetPath "CLAUDE.md"
$woiSectionTemplate = Join-Path $scriptRoot "templates\WOI-SECTION.md"

if (Test-Path $claudeMdPath) {
    $claudeMdContent = Get-Content $claudeMdPath -Raw

    # Load WOI section template and replace placeholders
    if (Test-Path $woiSectionTemplate) {
        $woiSection = Get-Content $woiSectionTemplate -Raw
        $woiSection = $woiSection -replace '\{\{WOI_VERSION\}\}', $newVersion

        $startMarker = "<!-- WOI-SECTION-START"
        $endMarker = "<!-- WOI-SECTION-END -->"

        if ($claudeMdContent -match [regex]::Escape($startMarker)) {
            # Update existing WOI section
            $pattern = "(?s)$([regex]::Escape($startMarker)).*?$([regex]::Escape($endMarker))"
            if ($DryRun) {
                Write-Info "Would update WOI section in CLAUDE.md"
            } else {
                $newContent = $claudeMdContent -replace $pattern, $woiSection.Trim()
                Set-Content -Path $claudeMdPath -Value $newContent -NoNewline
                Write-Info "Updated WOI section in CLAUDE.md"
            }
        } else {
            # Inject new WOI section after first heading or at the top
            if ($DryRun) {
                Write-Info "Would inject WOI section into CLAUDE.md"
            } else {
                # Find position after first # heading line
                if ($claudeMdContent -match "(?m)^#[^#].*$") {
                    $firstHeadingMatch = [regex]::Match($claudeMdContent, "(?m)^#[^#].*$")
                    $insertPos = $firstHeadingMatch.Index + $firstHeadingMatch.Length
                    $newContent = $claudeMdContent.Insert($insertPos, "`n`n" + $woiSection.Trim() + "`n")
                } else {
                    # No heading found, add at beginning
                    $newContent = $woiSection.Trim() + "`n`n" + $claudeMdContent
                }
                Set-Content -Path $claudeMdPath -Value $newContent -NoNewline
                Write-Info "Injected WOI section into CLAUDE.md"
            }
        }
    } else {
        Write-Warn "WOI section template not found, skipping CLAUDE.md update"
    }
} else {
    Write-Info "CLAUDE.md not found, skipping WOI section injection"
}

# Sync WOI section in .gitignore
Write-Step "Syncing WOI section in .gitignore..."
$gitignoreFile = Join-Path $TargetPath ".gitignore"

# Build list of files to gitignore (individual files, not folders)
$woiGitignoreFiles = @()

# .ai/ files from manifest
foreach ($file in $newInstalledFiles) {
    # Files in manifest are relative to .ai/, convert to gitignore format
    if ($file -notmatch "^\.claude/") {
        $woiGitignoreFiles += "/.ai/$file"
    }
}

# .ai/ metadata files
$woiGitignoreFiles += "/.ai/.framework-version"
$woiGitignoreFiles += "/.ai/.installed-files.json"

# Always gitignore sensitive files and directories
$woiGitignoreFiles += "/.ai/state/"
$woiGitignoreFiles += "/.ai/logs/"

# Add v2 config files if they exist (credentials contain secrets)
if (Test-Path (Join-Path $configDir "credentials.local.json")) {
    $woiGitignoreFiles += "/.ai/config/credentials.local.json"
}
if (Test-Path (Join-Path $configDir "connections.json")) {
    $woiGitignoreFiles += "/.ai/config/connections.json"
}
if (Test-Path (Join-Path $configDir "roles.json")) {
    $woiGitignoreFiles += "/.ai/config/roles.json"
}

# .claude/ files
$claudeDir = Join-Path $TargetPath ".claude"
if (Test-Path $claudeDir) {
    $claudeSettings = Join-Path $claudeDir "settings.json"
    if (Test-Path $claudeSettings) {
        $woiGitignoreFiles += "/.claude/settings.json"
    }
    $wofSkillsDir = Join-Path $claudeDir "skills"
    if (Test-Path $wofSkillsDir) {
        Get-ChildItem $wofSkillsDir -Directory | ForEach-Object {
            $skillName = $_.Name
            $skillFile = Join-Path $_.FullName "SKILL.md"
            if (Test-Path $skillFile) {
                $woiGitignoreFiles += "/.claude/skills/$skillName/SKILL.md"
            }
        }
    }
}

# CLAUDE.md
$woiGitignoreFiles += "/CLAUDE.md"

# Sort the list
$woiGitignoreFiles = $woiGitignoreFiles | Sort-Object | Select-Object -Unique

# Build WOI section content
$woiSectionStart = "# <!-- WOI-SECTION-START - Managed by WOF, do not edit manually -->"
$woiSectionEnd = "# <!-- WOI-SECTION-END -->"
$woiSectionContent = @($woiSectionStart, "# Workload Orchestration Instance (WOI)")
$woiSectionContent += $woiGitignoreFiles
$woiSectionContent += $woiSectionEnd

# Check for legacy folder-based entries and migrate
$migratedLegacy = $false
if (Test-Path $gitignoreFile) {
    $gitignoreContent = Get-Content $gitignoreFile -Raw

    # Detect legacy folder-based entries
    $legacyPatterns = @("/.ai/`$", "/.claude/`$", "^/.ai/`$", "^/.claude/`$")
    $hasLegacyAi = $gitignoreContent -match "(?m)^/?\.ai/?`$"
    $hasLegacyClaude = $gitignoreContent -match "(?m)^/?\.claude/?`$"

    if ($hasLegacyAi -or $hasLegacyClaude) {
        Write-Warn "Detected legacy folder-based gitignore entries, migrating to file-level..."
        $migratedLegacy = $true

        if (-not $DryRun) {
            # Remove legacy entries
            $lines = Get-Content $gitignoreFile
            $newLines = @()
            foreach ($line in $lines) {
                $trimmed = $line.Trim()
                # Skip legacy WOF entries
                if ($trimmed -match "^/?\.ai/?`$" -or
                    $trimmed -match "^/?\.claude/?`$" -or
                    $trimmed -match "^/?CLAUDE\.md`$" -or
                    $trimmed -match "# Workload Orchestration Framework.*Mode") {
                    continue
                }
                $newLines += $line
            }

            # Clean up multiple consecutive blank lines
            $cleanedLines = @()
            $lastWasBlank = $false
            foreach ($line in $newLines) {
                $isBlank = [string]::IsNullOrWhiteSpace($line)
                if (-not ($isBlank -and $lastWasBlank)) {
                    $cleanedLines += $line
                }
                $lastWasBlank = $isBlank
            }

            $gitignoreContent = $cleanedLines -join "`n"
            Write-Info "Removed legacy folder-based entries"
        } else {
            Write-Info "Would remove legacy folder-based entries"
        }
    }

    # Check if WOI section already exists
    if ($gitignoreContent -match "# <!-- WOI-SECTION-START") {
        # Replace existing WOI section
        $pattern = "(?s)# <!-- WOI-SECTION-START.*?# <!-- WOI-SECTION-END -->"
        $newWoiSection = $woiSectionContent -join "`n"
        if ($DryRun) {
            Write-Info "Would update WOI section in .gitignore"
        } else {
            $gitignoreContent = $gitignoreContent -replace $pattern, $newWoiSection
            Set-Content -Path $gitignoreFile -Value $gitignoreContent -NoNewline
            Write-Info "Updated WOI section in .gitignore"
        }
    } else {
        # Append WOI section
        if ($DryRun) {
            Write-Info "Would add WOI section to .gitignore"
        } else {
            if (-not $gitignoreContent.EndsWith("`n")) {
                $gitignoreContent += "`n"
            }
            $gitignoreContent += "`n" + ($woiSectionContent -join "`n")
            Set-Content -Path $gitignoreFile -Value $gitignoreContent -NoNewline
            Write-Info "Added WOI section to .gitignore"
        }
    }
} else {
    # Create new .gitignore with WOI section
    if ($DryRun) {
        Write-Info "Would create .gitignore with WOI section"
    } else {
        Set-Content -Path $gitignoreFile -Value ($woiSectionContent -join "`n")
        Write-Info "Created .gitignore with WOI section"
    }
}

if ($migratedLegacy -and -not $DryRun) {
    Write-Host ""
    Write-Warn "MIGRATION: Converted from folder-based to file-level gitignore"
    Write-Host "    User-created files in .ai/ are now trackable in git" -ForegroundColor Gray
}

Write-Info "Gitignore covers $($woiGitignoreFiles.Count) WOI files"

# Summary
Write-Host ""
Write-Host "================================================================================" -ForegroundColor Green
Write-Host "                              SYNC COMPLETE                                    " -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Updated:    $($updated.Count) files"
Write-Host "  Skipped:    $($skipped.Count) files (customized)"
Write-Host "  Deprecated: $($deprecated.Count) files (orphaned)"
Write-Host "  Preserved:  $($preserved.Count) patterns"
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

if ($deprecated.Count -gt 0) {
    Write-Host "Deprecated files (moved to .ai/.deprecated/):" -ForegroundColor Yellow
    foreach ($file in $deprecated) {
        Write-Host "  - $file" -ForegroundColor Gray
    }
    Write-Host ""
}

return @{
    Success = $true
    Updated = $updated
    Skipped = $skipped
    Deprecated = $deprecated
    Preserved = $preserved
    FromVersion = $currentVersion
    ToVersion = $newVersion
}
