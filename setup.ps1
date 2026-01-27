<#
.SYNOPSIS
    Sets up the Workload Orchestration Framework (WOF) in a target project.

.DESCRIPTION
    This script copies the framework files to a target project directory,
    processes templates with user-provided values, and configures the
    necessary hooks and MCP servers.

.PARAMETER TargetPath
    The root path of the target project where the framework will be installed.

.PARAMETER SolutionName
    The name of the solution (used in templates).

.PARAMETER Mode
    Installation mode:
    - "SourceControlled" (default): Framework is committed to git, shared with team.
      Only credentials and logs are gitignored.
    - "LocalOnly": Entire framework is gitignored. Personal use only, invisible to team.

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

.EXAMPLE
    .\setup.ps1 -TargetPath "C:\code\MyProject" -SolutionName "MyProject"

.EXAMPLE
    .\setup.ps1 -TargetPath "C:\code\MyProject" -SolutionName "MyProject" -Mode LocalOnly

.EXAMPLE
    .\setup.ps1 -TargetPath "C:\code\MyProject" -SolutionName "MyProject" -GitDefaultBranch "master" -BuildCommand "npm run build"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$TargetPath,

    [Parameter(Mandatory=$false)]
    [string]$SolutionName = "",

    [Parameter(Mandatory=$false)]
    [ValidateSet("SourceControlled", "LocalOnly")]
    [string]$Mode = "SourceControlled",

    [Parameter(Mandatory=$false)]
    [string]$GitDefaultBranch = "main",

    [Parameter(Mandatory=$false)]
    [string]$BuildCommand = "dotnet build",

    [Parameter(Mandatory=$false)]
    [string]$WorkItemPrefix = "#",

    [Parameter(Mandatory=$false)]
    [switch]$SkipTemplates,

    [Parameter(Mandatory=$false)]
    [switch]$Force
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
Write-Host "  Mode:          $Mode" -ForegroundColor $(if ($Mode -eq "LocalOnly") { "Yellow" } else { "White" })
Write-Host "  Git Branch:    $GitDefaultBranch"
Write-Host "  Build Command: $BuildCommand"
Write-Host ""

if ($Mode -eq "LocalOnly") {
    Write-Warn "LOCAL ONLY MODE: Framework will be gitignored and not shared with team"
    Write-Host ""
}

# Placeholder values
$placeholders = @{
    "{{SOLUTION_NAME}}" = $SolutionName
    "{{GIT_DEFAULT_BRANCH}}" = $GitDefaultBranch
    "{{BUILD_COMMAND}}" = $BuildCommand
    "{{WORK_ITEM_PREFIX}}" = $WorkItemPrefix
    "{{CURRENT_DATE}}" = (Get-Date -Format "yyyy-MM-dd")
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
        [hashtable]$Values
    )

    $content = Get-Content $SourceFile -Raw
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

# Step 5: Process templates
if (-not $SkipTemplates) {
    Write-Step "Processing templates..."

    # CLAUDE.md
    $claudeTemplate = Join-Path $templatesDir "CLAUDE.md.template"
    $claudeTarget = Join-Path $TargetPath "CLAUDE.md"
    if (Test-Path $claudeTemplate) {
        if ((Test-Path $claudeTarget) -and -not $Force) {
            Write-Warn "    Skipping (exists): CLAUDE.md"
        } else {
            Copy-WithPlaceholders -SourceFile $claudeTemplate -DestFile $claudeTarget -Values $placeholders
            Write-Host "    Created: CLAUDE.md" -ForegroundColor Gray
        }
    }

    # .claude/settings.json
    $settingsTemplate = Join-Path $templatesDir ".claude\settings.json.template"
    $settingsTarget = Join-Path $TargetPath ".claude\settings.json"
    if (Test-Path $settingsTemplate) {
        if ((Test-Path $settingsTarget) -and -not $Force) {
            Write-Warn "    Skipping (exists): .claude/settings.json"
        } else {
            Copy-WithPlaceholders -SourceFile $settingsTemplate -DestFile $settingsTarget -Values $placeholders
            Write-Host "    Created: .claude/settings.json" -ForegroundColor Gray
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

    # Config templates
    $configTemplates = @(
        "config\providers.yaml.template",
        "config\models.yaml.template",
        "config\credentials.local.ps1.template",
        "config\ai-rules.md.template"
    )

    foreach ($template in $configTemplates) {
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
}

# Step 6: Create .gitignore entries based on mode
Write-Step "Configuring .gitignore for $Mode mode..."
$gitignoreFile = Join-Path $TargetPath ".gitignore"

# Define entries based on mode
if ($Mode -eq "LocalOnly") {
    # Local Only: Entire framework is gitignored
    $gitignoreEntries = @(
        "",
        "# Workload Orchestration Framework (WOF) - Local Only Mode",
        ".ai/",
        ".claude/",
        "CLAUDE.md"
    )
} else {
    # Source Controlled: Only sensitive files gitignored
    $gitignoreEntries = @(
        "",
        "# Workload Orchestration Framework (WOF) - Source Controlled Mode",
        ".ai/config/credentials.local.ps1",
        ".ai/state/",
        ".ai/logs/"
    )
}

if (Test-Path $gitignoreFile) {
    $gitignoreContent = Get-Content $gitignoreFile -Raw
    $added = $false

    # Ensure file ends with newline before adding entries
    if ($gitignoreContent -and -not $gitignoreContent.EndsWith("`n")) {
        Add-Content -Path $gitignoreFile -Value ""
    }

    foreach ($entry in $gitignoreEntries) {
        if ($entry -and ($gitignoreContent -notmatch [regex]::Escape($entry))) {
            Add-Content -Path $gitignoreFile -Value $entry
            if ($entry -notmatch "^#") {
                Write-Host "    Added to .gitignore: $entry" -ForegroundColor Gray
            }
            $added = $true
        }
    }

    if (-not $added) {
        Write-Host "    .gitignore already configured" -ForegroundColor Gray
    }
} else {
    $gitignoreContent = $gitignoreEntries -join "`n"
    Set-Content -Path $gitignoreFile -Value $gitignoreContent
    Write-Host "    Created .gitignore with AI entries" -ForegroundColor Gray
}

# Store mode in .ai directory for reference
$modeFile = Join-Path $aiDir ".mode"
Set-Content -Path $modeFile -Value $Mode
Write-Host "    Saved mode to .ai/.mode: $Mode" -ForegroundColor Gray

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

# Read version from source
$versionFile = Join-Path $scriptRoot "VERSION"
$frameworkVersion = if (Test-Path $versionFile) { (Get-Content $versionFile).Trim() } else { "unknown" }

# Create manifest object
$manifest = @{
    version = $frameworkVersion
    installedAt = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    mode = $Mode
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

# Step 8: Display next steps
Write-Host ""
Write-Host "================================================================================" -ForegroundColor Green
Write-Host "                              SETUP COMPLETE                                   " -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Green
Write-Host ""
Write-Success "Framework installed to: $TargetPath"
Write-Success "Mode: $Mode"
Write-Host ""

if ($Mode -eq "LocalOnly") {
    Write-Host "LOCAL ONLY MODE:" -ForegroundColor Yellow
    Write-Host "  - Framework files are gitignored (not visible to team)"
    Write-Host "  - No commits needed - just start using Claude Code"
    Write-Host "  - To switch to SourceControlled mode later:"
    Write-Host "    1. Remove .ai/, .claude/, CLAUDE.md from .gitignore"
    Write-Host "    2. Commit the framework files"
    Write-Host ""
}

Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  1. Configure credentials:" -ForegroundColor Cyan
Write-Host "     Edit: .ai/config/credentials.local.ps1"
Write-Host "     Add your Azure AI Foundry and OpenAI API keys"
Write-Host ""
Write-Host "  2. Set up MCP server:" -ForegroundColor Cyan
Write-Host "     claude mcp add --scope local secondary-claude -- claude mcp serve"
Write-Host ""
Write-Host "  3. (Optional) Start local Worker-Lite:" -ForegroundColor Cyan
Write-Host "     Start LM Studio with deepseek-coder-v2-lite on port 1234"
Write-Host ""
Write-Host "  4. Verify setup:" -ForegroundColor Cyan
Write-Host "     .\.ai\scripts\check-orchestration-health.ps1"
Write-Host ""
Write-Host "  5. (Optional) Add Azure DevOps integration:" -ForegroundColor Cyan
Write-Host "     Copy extensions/azure-devops/*.template to .ai/scripts/"
Write-Host "     Update placeholders with your ADO organization/project"
Write-Host ""

return @{
    Success = $true
    TargetPath = $TargetPath
    SolutionName = $SolutionName
    Mode = $Mode
}
