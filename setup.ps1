<#
.SYNOPSIS
    Sets up the Workload Orchestration Framework (WOF) in a target project.

.DESCRIPTION
    This script copies the framework files to a target project directory,
    processes templates with user-provided values, and configures the
    necessary hooks and MCP servers.

    WOI (Workload Orchestration Instance) files are always gitignored at the
    individual file level, allowing user-created files in .ai/ to be tracked.

.PARAMETER TargetPath
    The root path of the target project where the framework will be installed.

.PARAMETER SolutionName
    The name of the solution (used in templates).

.PARAMETER GitDefaultBranch
    The default git branch name (default: "main").

.PARAMETER BuildCommand
    The build command for the project (default: "dotnet build").

.PARAMETER WorkItemPrefix
    The prefix for work item references (default: "#").

.PARAMETER SkipTemplates
    Skip processing templates (copy core files only).

.PARAMETER Force
    Overwrite existing files without prompting.

.PARAMETER Cleanup
    Remove the WOF source directory after successful installation.
    Safe for temp directories; prompts for confirmation otherwise.

.EXAMPLE
    .\setup.ps1 -TargetPath "C:\code\MyProject" -SolutionName "MyProject"

.EXAMPLE
    .\setup.ps1 -TargetPath "C:\code\MyProject" -SolutionName "MyProject" -GitDefaultBranch "master" -BuildCommand "npm run build"

.EXAMPLE
    .\setup.ps1 -TargetPath "C:\code\MyProject" -Cleanup
    # Installs WOF and removes the source directory afterward
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$TargetPath,

    [Parameter(Mandatory=$false)]
    [string]$SolutionName = "",

    [Parameter(Mandatory=$false)]
    [string]$GitDefaultBranch = "main",

    [Parameter(Mandatory=$false)]
    [string]$BuildCommand = "dotnet build",

    [Parameter(Mandatory=$false)]
    [string]$WorkItemPrefix = "#",

    [Parameter(Mandatory=$false)]
    [string]$AdoOrganization = "",

    [Parameter(Mandatory=$false)]
    [string]$AdoProject = "",

    [Parameter(Mandatory=$false)]
    [switch]$SkipTemplates,

    [Parameter(Mandatory=$false)]
    [switch]$Force,

    [Parameter(Mandatory=$false)]
    [ValidateSet("v2", "legacy")]
    [string]$ConfigFormat = "v2",

    [Parameter(Mandatory=$false)]
    [switch]$Cleanup
)

$ErrorActionPreference = "Stop"

$scriptRoot = $PSScriptRoot
$coreDir = Join-Path $scriptRoot "core"
$templatesDir = Join-Path $scriptRoot "templates"

# Color helpers
function Write-Step { param([string]$Message) Write-Host "[*] $Message" -ForegroundColor Cyan }
function Write-Success { param([string]$Message) Write-Host "[+] $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "[!] $Message" -ForegroundColor Yellow }
function Write-Error { param([string]$Message) Write-Host "[-] $Message" -ForegroundColor Red }

# Validation
if (-not (Test-Path $TargetPath)) {
    Write-Error "Target path does not exist: $TargetPath"
    exit 1
}

if (-not $SolutionName) {
    $SolutionName = Split-Path $TargetPath -Leaf
    Write-Warn "No solution name provided, using directory name: $SolutionName"
}

Write-Host ""
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "           WORKLOAD ORCHESTRATION FRAMEWORK (WOF) SETUP                       " -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Target:        $TargetPath"
Write-Host "  Solution:      $SolutionName"
Write-Host "  Git Branch:    $GitDefaultBranch"
Write-Host "  Build Command: $BuildCommand"
if ($AdoOrganization -and $AdoProject) {
    Write-Host "  ADO Org:       $AdoOrganization"
    Write-Host "  ADO Project:   $AdoProject"
}
Write-Host "  Config Format: $ConfigFormat"
Write-Host ""

# Read version from source (needed for placeholders)
$versionFile = Join-Path $scriptRoot "VERSION"
$frameworkVersion = if (Test-Path $versionFile) { (Get-Content $versionFile).Trim() } else { "unknown" }

# Detect OS and shell environment
$isWindows = $env:OS -eq "Windows_NT" -or $PSVersionTable.Platform -eq "Win32NT" -or (-not $PSVersionTable.Platform)
$isUnix = $PSVersionTable.Platform -eq "Unix"
$isMacOS = $PSVersionTable.OS -match "Darwin"

if ($isWindows) {
    $woiOS = "Windows"
    $woiShell = "PowerShell"
} elseif ($isMacOS) {
    $woiOS = "macOS"
    $woiShell = "Bash/Zsh"
} else {
    $woiOS = "Linux"
    $woiShell = "Bash"
}

# ADO enabled flag
$adoEnabled = $AdoOrganization -and $AdoProject

# Placeholder values
$placeholders = @{
    "{{SOLUTION_NAME}}" = $SolutionName
    "{{GIT_DEFAULT_BRANCH}}" = $GitDefaultBranch
    "{{BUILD_COMMAND}}" = $BuildCommand
    "{{WORK_ITEM_PREFIX}}" = $WorkItemPrefix
    "{{CURRENT_DATE}}" = (Get-Date -Format "yyyy-MM-dd")
    "{{ADO_ORGANIZATION}}" = $AdoOrganization
    "{{ADO_PROJECT}}" = $AdoProject
    "{{WOI_VERSION}}" = $frameworkVersion
    "{{WOI_OS}}" = $woiOS
    "{{WOI_SHELL}}" = $woiShell
    "{{WOI_ADO_PROJECT}}" = $AdoProject
    "{{WOI_ADO_ORG}}" = $AdoOrganization
}

# Conditional flags for template processing
$conditionalFlags = @{
    "WOI_IS_WINDOWS" = $isWindows
    "WOI_IS_UNIX" = $isUnix -or $isMacOS
    "WOI_ADO_ENABLED" = $adoEnabled
}

function Process-ConditionalBlocks {
    param(
        [string]$Content,
        [hashtable]$Flags
    )

    # Process {{#if FLAG}}...{{/if}} blocks
    foreach ($flag in $Flags.Keys) {
        $ifPattern = "(?s)\{\{#if $flag\}\}(.*?)\{\{/if\}\}"
        if ($Flags[$flag]) {
            # Flag is true - keep the content, remove the markers
            $Content = [regex]::Replace($Content, $ifPattern, '$1')
        } else {
            # Flag is false - remove the entire block
            $Content = [regex]::Replace($Content, $ifPattern, '')
        }
    }

    # Process {{#unless FLAG}}...{{/unless}} blocks
    foreach ($flag in $Flags.Keys) {
        $unlessPattern = "(?s)\{\{#unless $flag\}\}(.*?)\{\{/unless\}\}"
        if (-not $Flags[$flag]) {
            # Flag is false - keep the content, remove the markers
            $Content = [regex]::Replace($Content, $unlessPattern, '$1')
        } else {
            # Flag is true - remove the entire block
            $Content = [regex]::Replace($Content, $unlessPattern, '')
        }
    }

    # Clean up any remaining empty lines from removed blocks
    $Content = $Content -replace "(\r?\n){3,}", "`n`n"

    return $Content
}

function Replace-Placeholders {
    param(
        [string]$Content,
        [hashtable]$Values
    )

    foreach ($key in $Values.Keys) {
        $Content = $Content -replace [regex]::Escape($key), $Values[$key]
    }

    return $Content
}

function Copy-WithPlaceholders {
    param(
        [string]$SourceFile,
        [string]$DestFile,
        [hashtable]$Values,
        [hashtable]$Flags = @{}
    )

    $content = Get-Content $SourceFile -Raw

    # Process conditional blocks first (if flags provided)
    if ($Flags.Count -gt 0) {
        $content = Process-ConditionalBlocks -Content $content -Flags $Flags
    }

    # Then replace placeholders
    $processed = Replace-Placeholders -Content $content -Values $Values

    $destDir = Split-Path $DestFile -Parent
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    Set-Content -Path $DestFile -Value $processed -NoNewline
}

# Step 1: Create directory structure
Write-Step "Creating .ai directory structure..."
$aiDir = Join-Path $TargetPath ".ai"
$dirs = @(
    (Join-Path $aiDir "scripts"),
    (Join-Path $aiDir "config"),
    (Join-Path $aiDir "memory"),
    (Join-Path $aiDir "agents"),
    (Join-Path $aiDir "workflows"),
    (Join-Path $aiDir "philosophy"),
    (Join-Path $aiDir "state"),
    (Join-Path $aiDir "logs")
)

foreach ($dir in $dirs) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "    Created: $dir" -ForegroundColor Gray
    }
}

# Step 2: Copy core scripts
Write-Step "Copying core scripts..."
$scriptsSource = Join-Path $coreDir "scripts"
$scriptsTarget = Join-Path $aiDir "scripts"

if (Test-Path $scriptsSource) {
    Get-ChildItem $scriptsSource -Filter "*.ps1" | ForEach-Object {
        $destFile = Join-Path $scriptsTarget $_.Name
        if ((Test-Path $destFile) -and -not $Force) {
            Write-Warn "    Skipping (exists): $($_.Name)"
        } else {
            Copy-Item $_.FullName $destFile -Force
            Write-Host "    Copied: $($_.Name)" -ForegroundColor Gray
        }
    }
}

# Step 2b: Process script templates
Write-Step "Processing script templates..."
$scriptTemplatesSource = Join-Path $templatesDir "scripts"
if (Test-Path $scriptTemplatesSource) {
    Get-ChildItem $scriptTemplatesSource -Filter "*.template" | ForEach-Object {
        $destName = $_.Name -replace '\.template$', ''
        $destFile = Join-Path $scriptsTarget $destName
        if ((Test-Path $destFile) -and -not $Force) {
            Write-Warn "    Skipping (exists): $destName"
        } else {
            Copy-WithPlaceholders -SourceFile $_.FullName -DestFile $destFile -Values $placeholders
            Write-Host "    Created: $destName" -ForegroundColor Gray
        }
    }
}

# Step 3: Copy core config
Write-Step "Copying core config..."
$configSource = Join-Path $coreDir "config"
$configTarget = Join-Path $aiDir "config"

if (Test-Path $configSource) {
    Get-ChildItem $configSource -File | ForEach-Object {
        $destFile = Join-Path $configTarget $_.Name
        if ((Test-Path $destFile) -and -not $Force) {
            Write-Warn "    Skipping (exists): $($_.Name)"
        } else {
            Copy-Item $_.FullName $destFile -Force
            Write-Host "    Copied: $($_.Name)" -ForegroundColor Gray
        }
    }
}

# Step 4: Copy core agents
Write-Step "Copying agent definitions..."
$agentsSource = Join-Path $coreDir "agents"
$agentsTarget = Join-Path $aiDir "agents"

if (Test-Path $agentsSource) {
    Get-ChildItem $agentsSource -Filter "*.md" | ForEach-Object {
        $destFile = Join-Path $agentsTarget $_.Name
        if ((Test-Path $destFile) -and -not $Force) {
            Write-Warn "    Skipping (exists): $($_.Name)"
        } else {
            Copy-Item $_.FullName $destFile -Force
            Write-Host "    Copied: $($_.Name)" -ForegroundColor Gray
        }
    }
}

# Step 4b: Copy core philosophy
Write-Step "Copying philosophy documents..."
$philosophySource = Join-Path $coreDir "philosophy"
$philosophyTarget = Join-Path $aiDir "philosophy"

if (Test-Path $philosophySource) {
    Get-ChildItem $philosophySource -Filter "*.md" | ForEach-Object {
        $destFile = Join-Path $philosophyTarget $_.Name
        if ((Test-Path $destFile) -and -not $Force) {
            Write-Warn "    Skipping (exists): $($_.Name)"
        } else {
            Copy-Item $_.FullName $destFile -Force
            Write-Host "    Copied: $($_.Name)" -ForegroundColor Gray
        }
    }
}

# Step 4c: Copy core workflows
Write-Step "Copying workflow definitions..."
$workflowsSource = Join-Path $coreDir "workflows"
$workflowsTarget = Join-Path $aiDir "workflows"

if (Test-Path $workflowsSource) {
    Get-ChildItem $workflowsSource -Filter "*.md" | ForEach-Object {
        $destFile = Join-Path $workflowsTarget $_.Name
        if ((Test-Path $destFile) -and -not $Force) {
            Write-Warn "    Skipping (exists): $($_.Name)"
        } else {
            Copy-Item $_.FullName $destFile -Force
            Write-Host "    Copied: $($_.Name)" -ForegroundColor Gray
        }
    }
}

# Step 5: Process templates
if (-not $SkipTemplates) {
    Write-Step "Processing templates..."

    # CLAUDE.md - Create base if needed, then inject/update WOI-SECTION
    $claudeBaseTemplate = Join-Path $templatesDir "CLAUDE.md.base.template"
    $claudeTarget = Join-Path $TargetPath "CLAUDE.md"
    $woiSectionTemplate = Join-Path $templatesDir "WOI-SECTION.md"

    # Step 1: Create base CLAUDE.md if it doesn't exist
    if (-not (Test-Path $claudeTarget)) {
        if (Test-Path $claudeBaseTemplate) {
            Copy-WithPlaceholders -SourceFile $claudeBaseTemplate -DestFile $claudeTarget -Values $placeholders
            Write-Host "    Created: CLAUDE.md (base)" -ForegroundColor Gray
        } else {
            Write-Warn "    CLAUDE.md base template not found"
        }
    }

    # Step 2: Inject/update WOI-SECTION
    if ((Test-Path $claudeTarget) -and (Test-Path $woiSectionTemplate)) {
        $claudeContent = Get-Content $claudeTarget -Raw
        $woiSection = Get-Content $woiSectionTemplate -Raw
        # Process conditional blocks first, then placeholders
        $woiSection = Process-ConditionalBlocks -Content $woiSection -Flags $conditionalFlags
        $woiSection = Replace-Placeholders -Content $woiSection -Values $placeholders

        $startMarker = "<!-- WOI-SECTION-START"
        $endMarker = "<!-- WOI-SECTION-END -->"

        if ($claudeContent -match [regex]::Escape($startMarker)) {
            # Update existing WOI section
            $pattern = "(?s)$([regex]::Escape($startMarker)).*?$([regex]::Escape($endMarker))"
            $newContent = $claudeContent -replace $pattern, $woiSection.Trim()
            Set-Content -Path $claudeTarget -Value $newContent -NoNewline
            Write-Host "    Updated: CLAUDE.md (WOI section)" -ForegroundColor Gray
        } else {
            # Inject new WOI section after first heading or at the end
            if ($claudeContent -match "(?m)^#[^#].*$") {
                $firstHeadingMatch = [regex]::Match($claudeContent, "(?m)^#[^#].*$")
                $insertPos = $firstHeadingMatch.Index + $firstHeadingMatch.Length
                $newContent = $claudeContent.Insert($insertPos, "`n`n" + $woiSection.Trim() + "`n")
            } else {
                # No heading found, add at end
                $newContent = $claudeContent.TrimEnd() + "`n`n" + $woiSection.Trim() + "`n"
            }
            Set-Content -Path $claudeTarget -Value $newContent -NoNewline
            Write-Host "    Injected: CLAUDE.md (WOI section)" -ForegroundColor Gray
        }
    }

    # .mcp.json (MCP server configuration for Claude Code)
    $mcpTemplate = Join-Path $templatesDir "mcp.json.template"
    $mcpTarget = Join-Path $TargetPath ".mcp.json"
    if ((Test-Path $mcpTemplate) -and $AdoOrganization) {
        if ((Test-Path $mcpTarget) -and -not $Force) {
            Write-Warn "    Skipping (exists): .mcp.json"
        } else {
            Copy-WithPlaceholders -SourceFile $mcpTemplate -DestFile $mcpTarget -Values $placeholders
            Write-Host "    Created: .mcp.json (Azure DevOps MCP)" -ForegroundColor Gray
        }
    }

    # .gitattributes (line ending normalization)
    $gitattributesTemplate = Join-Path $templatesDir ".gitattributes.template"
    $gitattributesTarget = Join-Path $TargetPath ".gitattributes"
    if (Test-Path $gitattributesTemplate) {
        if ((Test-Path $gitattributesTarget) -and -not $Force) {
            Write-Warn "    Skipping (exists): .gitattributes"
        } else {
            Copy-WithPlaceholders -SourceFile $gitattributesTemplate -DestFile $gitattributesTarget -Values $placeholders
            Write-Host "    Created: .gitattributes (LF normalization)" -ForegroundColor Gray
        }
    }

    # .claude/settings.json (source from dot-claude to avoid Claude Code detecting templates)
    $settingsTemplate = Join-Path $templatesDir "dot-claude\settings.json.template"
    $settingsTarget = Join-Path $TargetPath ".claude\settings.json"
    if (Test-Path $settingsTemplate) {
        if ((Test-Path $settingsTarget) -and -not $Force) {
            Write-Warn "    Skipping (exists): .claude/settings.json"
        } else {
            Copy-WithPlaceholders -SourceFile $settingsTemplate -DestFile $settingsTarget -Values $placeholders
            Write-Host "    Created: .claude/settings.json" -ForegroundColor Gray
        }
    }

    # .claude/skills (slash commands) - source from dot-claude to avoid Claude Code detecting templates
    $skillsSource = Join-Path $templatesDir "dot-claude\skills"
    $skillsTarget = Join-Path $TargetPath ".claude\skills"
    if (Test-Path $skillsSource) {
        Get-ChildItem $skillsSource -Directory | ForEach-Object {
            $skillName = $_.Name
            $skillFile = Join-Path $_.FullName "SKILL.md"
            $destDir = Join-Path $skillsTarget $skillName
            $destFile = Join-Path $destDir "SKILL.md"

            if (Test-Path $skillFile) {
                if ((Test-Path $destFile) -and -not $Force) {
                    Write-Warn "    Skipping (exists): .claude/skills/$skillName/SKILL.md"
                } else {
                    if (-not (Test-Path $destDir)) {
                        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                    }
                    Copy-WithPlaceholders -SourceFile $skillFile -DestFile $destFile -Values $placeholders
                    Write-Host "    Created: .claude/skills/$skillName/SKILL.md" -ForegroundColor Gray
                }
            }
        }
    }

    # .claude/agents (Claude Code subagents) - source from dot-claude
    $agentsClaudeSource = Join-Path $templatesDir "dot-claude\agents"
    $agentsClaudeTarget = Join-Path $TargetPath ".claude\agents"
    if (Test-Path $agentsClaudeSource) {
        Get-ChildItem $agentsClaudeSource -Filter "*.md" | ForEach-Object {
            $agentName = $_.BaseName
            $destFile = Join-Path $agentsClaudeTarget $_.Name

            if ((Test-Path $destFile) -and -not $Force) {
                Write-Warn "    Skipping (exists): .claude/agents/$($_.Name)"
            } else {
                if (-not (Test-Path $agentsClaudeTarget)) {
                    New-Item -ItemType Directory -Path $agentsClaudeTarget -Force | Out-Null
                }
                Copy-WithPlaceholders -SourceFile $_.FullName -DestFile $destFile -Values $placeholders
                Write-Host "    Created: .claude/agents/$($_.Name)" -ForegroundColor Gray
            }
        }
    }

    # Memory templates
    $memoryTemplates = @(
        "memory\architecture.md.template",
        "memory\conventions.md.template",
        "memory\current-sprint.md.template"
    )

    foreach ($template in $memoryTemplates) {
        $source = Join-Path $templatesDir $template
        $destName = $template -replace '\\', '\' -replace '\.template$', ''
        $dest = Join-Path $aiDir $destName

        if (Test-Path $source) {
            if ((Test-Path $dest) -and -not $Force) {
                Write-Warn "    Skipping (exists): $destName"
            } else {
                Copy-WithPlaceholders -SourceFile $source -DestFile $dest -Values $placeholders
                Write-Host "    Created: $destName" -ForegroundColor Gray
            }
        }
    }

    # Config templates - depends on ConfigFormat
    if ($ConfigFormat -eq "v2") {
        # v2 format: JSON-based configuration
        $configTemplates = @(
            "config\connections.json.template",
            "config\roles.json.template",
            "config\credentials.local.json.template",
            "config\ado.json.template",
            "config\finish.json.template",
            "config\models.yaml.template",
            "config\ai-rules.md.template"
        )
        Write-Host "    Using v2 config format (JSON-based)" -ForegroundColor Cyan
    } else {
        # Legacy format: YAML/PS1 configuration
        $configTemplates = @(
            "config\providers.yaml.template",
            "config\models.yaml.template",
            "config\credentials.local.ps1.template",
            "config\ado.json.template",
            "config\ai-rules.md.template"
        )
        Write-Host "    Using legacy config format (YAML/PS1)" -ForegroundColor Yellow
    }

    # Files that should NEVER be overwritten (contain user secrets/customizations)
    $neverOverwrite = @(
        "config/credentials.local.json",
        "config/credentials.local.ps1",
        "config/connections.json",
        "config/roles.json",
        "config/ado.json"
    )

    foreach ($template in $configTemplates) {
        $source = Join-Path $templatesDir $template
        $destName = $template -replace '\\', '\' -replace '\.template$', ''
        $dest = Join-Path $aiDir $destName
        $destRelative = $destName -replace '\\', '/'

        if (Test-Path $source) {
            $fileExists = Test-Path $dest
            $isProtected = $neverOverwrite -contains $destRelative

            if ($fileExists -and $isProtected) {
                # NEVER overwrite protected files, even with -Force
                Write-Host "    Preserved: $destName (user data)" -ForegroundColor Green
            } elseif ($fileExists -and -not $Force) {
                Write-Warn "    Skipping (exists): $destName"
            } else {
                Copy-WithPlaceholders -SourceFile $source -DestFile $dest -Values $placeholders
                Write-Host "    Created: $destName" -ForegroundColor Gray
            }
        }
    }
}

# Step 6: Build list of WOI files to gitignore (will be finalized after manifest)
# We'll collect all installed files and add them to .gitignore with WOI section markers
$woiGitignoreFiles = @()

# Step 7: Generate installed files manifest
Write-Step "Generating installed files manifest..."
$installedFiles = @()

# Collect all installed files relative to .ai/
if (Test-Path $scriptsTarget) {
    Get-ChildItem $scriptsTarget -Filter "*.ps1" | ForEach-Object {
        $installedFiles += "scripts/$($_.Name)"
    }
}
if (Test-Path $configTarget) {
    Get-ChildItem $configTarget -File | ForEach-Object {
        $installedFiles += "config/$($_.Name)"
    }
}
if (Test-Path $agentsTarget) {
    Get-ChildItem $agentsTarget -Filter "*.md" | ForEach-Object {
        $installedFiles += "agents/$($_.Name)"
    }
}
$memoryTarget = Join-Path $aiDir "memory"
if (Test-Path $memoryTarget) {
    Get-ChildItem $memoryTarget -Filter "*.md" | ForEach-Object {
        $installedFiles += "memory/$($_.Name)"
    }
}

# Create manifest object (version already read at top of script)
$manifest = @{
    version = $frameworkVersion
    installedAt = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    files = $installedFiles | Sort-Object
}

# Write manifest as JSON (PS 5.1 compatible)
$manifestPath = Join-Path $aiDir ".installed-files.json"
$manifestJson = $manifest | ConvertTo-Json -Depth 10
Set-Content -Path $manifestPath -Value $manifestJson -Encoding UTF8
Write-Host "    Created: .ai/.installed-files.json ($($installedFiles.Count) files tracked)" -ForegroundColor Gray

# Also write version file
$targetVersionFile = Join-Path $aiDir ".framework-version"
Set-Content -Path $targetVersionFile -Value $frameworkVersion
Write-Host "    Created: .ai/.framework-version ($frameworkVersion)" -ForegroundColor Gray

# Step 8: Configure .gitignore with WOI sections (framework + userdata)
Write-Step "Configuring .gitignore with WOI sections..."
$gitignoreFile = Join-Path $TargetPath ".gitignore"

# Define which files are "userdata" (preserved after WOF removal)
# These contain user customizations, secrets, or project-specific content
$userdataPatterns = @(
    # v2 config format (JSON)
    "config/credentials.local.json",  # API keys, connection strings - CRITICAL (v2)
    "config/connections.json",        # Customized AI connections (v2)
    "config/roles.json",              # Customized role mappings (v2)
    "config/ado.json",                # Azure DevOps PAT, org, project, filters (v2)
    "config/finish.json",             # Finish workflow configuration (v2)
    # Legacy config format (YAML/PS1)
    "config/credentials.local.ps1",   # API keys, connection strings - CRITICAL (legacy)
    "config/providers.yaml",          # Customized provider settings (legacy)
    # Shared config
    "config/models.yaml",             # Customized model tiers
    "config/ai-rules.md",             # Customized AI behavior rules
    # Memory
    "memory/architecture.md",         # Project-specific architecture
    "memory/conventions.md",          # Project-specific conventions
    "memory/current-sprint.md"        # Active work tracking
)

# Build framework files list (removed with WOF)
$frameworkFiles = @()

# .ai/ files from manifest, excluding userdata
foreach ($file in $installedFiles) {
    $isUserdata = $false
    foreach ($pattern in $userdataPatterns) {
        if ($file -eq $pattern) {
            $isUserdata = $true
            break
        }
    }
    if (-not $isUserdata) {
        $frameworkFiles += "/.ai/$file"
    }
}

# .ai/ metadata files (framework)
$frameworkFiles += "/.ai/.framework-version"
$frameworkFiles += "/.ai/.installed-files.json"

# .claude/ files (framework)
$claudeDir = Join-Path $TargetPath ".claude"
if (Test-Path $claudeDir) {
    $claudeSettings = Join-Path $claudeDir "settings.json"
    if (Test-Path $claudeSettings) {
        $frameworkFiles += "/.claude/settings.json"
    }
    $skillsDir = Join-Path $claudeDir "skills"
    if (Test-Path $skillsDir) {
        Get-ChildItem $skillsDir -Directory | ForEach-Object {
            $skillName = $_.Name
            $skillFile = Join-Path $_.FullName "SKILL.md"
            if (Test-Path $skillFile) {
                $frameworkFiles += "/.claude/skills/$skillName/SKILL.md"
            }
        }
    }
    $agentsDir = Join-Path $claudeDir "agents"
    if (Test-Path $agentsDir) {
        Get-ChildItem $agentsDir -Filter "*.md" | ForEach-Object {
            $frameworkFiles += "/.claude/agents/$($_.Name)"
        }
    }
}

# CLAUDE.md (framework - deleted on remove)
$frameworkFiles += "/CLAUDE.md"

# .mcp.json (MCP server config - framework)
$mcpJson = Join-Path $TargetPath ".mcp.json"
if (Test-Path $mcpJson) {
    $frameworkFiles += "/.mcp.json"
}

# .gitattributes (line ending normalization - framework)
$gitattributes = Join-Path $TargetPath ".gitattributes"
if (Test-Path $gitattributes) {
    $frameworkFiles += "/.gitattributes"
}

# Sort framework files
$frameworkFiles = $frameworkFiles | Sort-Object

# Build userdata files list (preserved after WOF removal)
$userdataFiles = @()
foreach ($pattern in $userdataPatterns) {
    $fullPath = Join-Path $aiDir $pattern
    if (Test-Path $fullPath) {
        $userdataFiles += "/.ai/$pattern"
    }
}

# Always include state and logs in userdata (even if not yet created)
$userdataFiles += "/.ai/state/"
$userdataFiles += "/.ai/logs/"

# Sort userdata files
$userdataFiles = $userdataFiles | Sort-Object

# Build FRAMEWORK section content
$frameworkSectionStart = "# <!-- WOI-FRAMEWORK-START - Managed by WOF, removed with framework -->"
$frameworkSectionEnd = "# <!-- WOI-FRAMEWORK-END -->"
$frameworkSectionContent = @($frameworkSectionStart, "# WOF Framework Files (deleted when WOF is removed)")
$frameworkSectionContent += $frameworkFiles
$frameworkSectionContent += $frameworkSectionEnd

# Build USERDATA section content
$userdataSectionStart = "# <!-- WOI-USERDATA-START - Managed by WOF, preserved after removal -->"
$userdataSectionEnd = "# <!-- WOI-USERDATA-END -->"
$userdataSectionContent = @($userdataSectionStart, "# WOI User Data (kept after WOF removal - contains secrets/customizations)")
$userdataSectionContent += $userdataFiles
$userdataSectionContent += $userdataSectionEnd

# Combine both sections
$woiFullContent = $frameworkSectionContent + @("") + $userdataSectionContent

# Helper function to update or add a section
function Update-GitignoreSection {
    param(
        [string]$Content,
        [string]$StartMarker,
        [string]$EndMarker,
        [string[]]$NewSection
    )

    $startPattern = [regex]::Escape($StartMarker) -replace "WOI-FRAMEWORK-START|WOI-USERDATA-START", "WOI-(FRAMEWORK|USERDATA)-START"
    if ($Content -match $StartMarker.Substring(0, 20)) {
        # Section exists, replace it
        $pattern = "(?s)$([regex]::Escape($StartMarker)).*?$([regex]::Escape($EndMarker))"
        $replacement = $NewSection -join "`n"
        return $Content -replace $pattern, $replacement
    }
    return $null  # Section doesn't exist
}

# Update or create .gitignore
if (Test-Path $gitignoreFile) {
    $gitignoreContent = Get-Content $gitignoreFile -Raw
    $updated = $false

    # Check for legacy single WOI section and remove it
    if ($gitignoreContent -match "# <!-- WOI-SECTION-START") {
        $pattern = "(?s)\r?\n?# <!-- WOI-SECTION-START.*?# <!-- WOI-SECTION-END -->\r?\n?"
        $gitignoreContent = $gitignoreContent -replace $pattern, "`n"
        $gitignoreContent = $gitignoreContent -replace "(\r?\n){3,}", "`n`n"
        Write-Host "    Removed legacy WOI section" -ForegroundColor Yellow
    }

    # Update or add FRAMEWORK section
    if ($gitignoreContent -match "# <!-- WOI-FRAMEWORK-START") {
        $pattern = "(?s)# <!-- WOI-FRAMEWORK-START.*?# <!-- WOI-FRAMEWORK-END -->"
        $replacement = $frameworkSectionContent -join "`n"
        $gitignoreContent = $gitignoreContent -replace $pattern, $replacement
        Write-Host "    Updated WOI-FRAMEWORK section" -ForegroundColor Gray
        $updated = $true
    }

    # Update or add USERDATA section
    if ($gitignoreContent -match "# <!-- WOI-USERDATA-START") {
        $pattern = "(?s)# <!-- WOI-USERDATA-START.*?# <!-- WOI-USERDATA-END -->"
        $replacement = $userdataSectionContent -join "`n"
        $gitignoreContent = $gitignoreContent -replace $pattern, $replacement
        Write-Host "    Updated WOI-USERDATA section" -ForegroundColor Gray
        $updated = $true
    }

    if ($updated) {
        Set-Content -Path $gitignoreFile -Value $gitignoreContent -NoNewline
    } else {
        # Append both sections
        if (-not $gitignoreContent.EndsWith("`n")) {
            Add-Content -Path $gitignoreFile -Value ""
        }
        Add-Content -Path $gitignoreFile -Value ""
        Add-Content -Path $gitignoreFile -Value ($woiFullContent -join "`n")
        Write-Host "    Added WOI-FRAMEWORK and WOI-USERDATA sections" -ForegroundColor Gray
    }
} else {
    # Create new .gitignore with both sections
    Set-Content -Path $gitignoreFile -Value ($woiFullContent -join "`n")
    Write-Host "    Created .gitignore with WOI sections" -ForegroundColor Gray
}

Write-Host "    Framework: $($frameworkFiles.Count) files | Userdata: $($userdataFiles.Count) files" -ForegroundColor Gray

# Step 9: Display next steps
Write-Host ""
Write-Host "================================================================================" -ForegroundColor Green
Write-Host "                              SETUP COMPLETE                                   " -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Green
Write-Host ""
Write-Success "Framework installed to: $TargetPath"
Write-Host ""
Write-Host "  ** RESTART CLAUDE CODE to load new skills and commands (/wof) **" -ForegroundColor Yellow
Write-Host ""

Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  1. Configure credentials:" -ForegroundColor Cyan
if ($ConfigFormat -eq "v2") {
    Write-Host "     Edit: .ai/config/credentials.local.json"
    Write-Host "     Fill in AI1_ENDPOINT, AI1_API_KEY, AI2_*, AI3_*, AI4_* (for Worker-Lite)"
} else {
    Write-Host "     Edit: .ai/config/credentials.local.ps1"
    Write-Host "     Add your Azure AI Foundry and OpenAI API keys"
}
Write-Host ""
Write-Host "  2. Set up MCP servers (for multi-agent orchestration):" -ForegroundColor Cyan
Write-Host "     claude mcp add --scope local validator-claude -- claude mcp serve"
Write-Host "     claude mcp add --scope local critic-claude -- claude mcp serve"
Write-Host "     claude mcp add --scope local worker-claude-heavy -- claude mcp serve"
Write-Host ""
Write-Host "  3. (Optional) Configure Worker-Lite:" -ForegroundColor Cyan
Write-Host "     Use local models, vLLMs, network deployments, or cloud providers"
Write-Host ""
Write-Host "  4. Verify setup:" -ForegroundColor Cyan
Write-Host "     .\.ai\scripts\check-orchestration-health.ps1"
Write-Host ""
Write-Host "  Or run the interactive configuration wizard:" -ForegroundColor Cyan
Write-Host "     .\.ai\scripts\configure-wizard.ps1"
Write-Host ""
if ($AdoOrganization -and $AdoProject) {
    Write-Host "  5. Azure DevOps integration:" -ForegroundColor Cyan
    Write-Host "     ADO utilities installed to .ai/scripts/ado-utils.ps1"
    Write-Host "     Usage: . '.\.ai\scripts\ado-utils.ps1'"
    Write-Host "            Set-WorkItemActiveWithParent -WorkItemId 1234"
    Write-Host ""
} else {
    Write-Host "  5. (Optional) Add Azure DevOps integration:" -ForegroundColor Cyan
    Write-Host "     Re-run setup with -AdoOrganization and -AdoProject parameters"
    Write-Host ""
}

# Optional: Run configuration wizard
Write-Host "Would you like to configure AI connections now? [y/N]: " -NoNewline
$configureChoice = Read-Host
if ($configureChoice -and $configureChoice.ToLower() -eq "y") {
    $wizardScript = Join-Path $aiDir "scripts\configure-wizard.ps1"
    if (Test-Path $wizardScript) {
        & $wizardScript
    } else {
        Write-Warn "Configuration wizard not found at: $wizardScript"
    }
}

# Step 10: Cleanup source directory if requested
if ($Cleanup) {
    Write-Host ""
    Write-Step "Cleaning up WOF source directory..."

    # Don't delete if running from the target path (self-install scenario)
    $normalizedScriptRoot = (Resolve-Path $scriptRoot).Path.TrimEnd('\', '/')
    $normalizedTargetPath = (Resolve-Path $TargetPath).Path.TrimEnd('\', '/')

    if ($normalizedScriptRoot -eq $normalizedTargetPath) {
        Write-Warn "Skipping cleanup: source and target are the same directory (inception mode)"
    } elseif ($scriptRoot -match [regex]::Escape($env:TEMP) -or $scriptRoot -match "\\Temp\\" -or $scriptRoot -match "/tmp/") {
        # Running from temp directory - safe to clean up
        try {
            Remove-Item -Recurse -Force $scriptRoot -ErrorAction Stop
            Write-Success "Removed temporary WOF source: $scriptRoot"
        } catch {
            Write-Warn "Could not remove source directory: $_"
            Write-Host "    You can manually delete: $scriptRoot" -ForegroundColor Gray
        }
    } else {
        # Not in temp - ask for confirmation
        Write-Host "Source directory is not in a temp location: $scriptRoot" -ForegroundColor Yellow
        Write-Host "Delete this directory? [y/N]: " -NoNewline
        $confirmDelete = Read-Host
        if ($confirmDelete -and $confirmDelete.ToLower() -eq "y") {
            try {
                Remove-Item -Recurse -Force $scriptRoot -ErrorAction Stop
                Write-Success "Removed WOF source: $scriptRoot"
            } catch {
                Write-Warn "Could not remove source directory: $_"
            }
        } else {
            Write-Host "    Keeping source directory" -ForegroundColor Gray
        }
    }
}
