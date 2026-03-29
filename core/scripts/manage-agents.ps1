# ============================================================================
# WOF MANAGED FILE - DO NOT EDIT MANUALLY
# This file is managed by the Workload Orchestration Framework.
# Changes will be overwritten on the next WOF sync/update.
# To customize behavior, use configuration files in .ai/config/
# ============================================================================

<#
.SYNOPSIS
    Manages the WOF agent library - install, remove, and browse agents.

.DESCRIPTION
    Provides a CLI for managing agents in a WOI (Workload Orchestration Instance):
    - List installed agents
    - Add agents from the catalog
    - Remove installed agents
    - Auto-detect recommended agents based on project tech stack
    - Browse the full agent catalog

    Agent catalog is bundled at .ai/agents-catalog.json during setup.
    Installed agents are tracked in .ai/config/agents-selection.json.
    Agent files are deployed to .claude/agents/<name>.md.

.PARAMETER Action
    The action to perform: list, add, remove, detect, catalog.

.PARAMETER AgentName
    The agent name for add/remove actions.

.PARAMETER Category
    Filter by category for the catalog action.

.PARAMETER JsonOutput
    Output JSON instead of formatted text.

.EXAMPLE
    .\.ai\scripts\manage-agents.ps1 -Action list

.EXAMPLE
    .\.ai\scripts\manage-agents.ps1 -Action add -AgentName "csharp-developer"

.EXAMPLE
    .\.ai\scripts\manage-agents.ps1 -Action remove -AgentName "csharp-developer"

.EXAMPLE
    .\.ai\scripts\manage-agents.ps1 -Action detect

.EXAMPLE
    .\.ai\scripts\manage-agents.ps1 -Action catalog -Category "Language Specialists"

.EXAMPLE
    .\.ai\scripts\manage-agents.ps1 -Action detect -JsonOutput
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("list", "add", "remove", "detect", "catalog")]
    [string]$Action,

    [Parameter(Mandatory = $false)]
    [string]$AgentName,

    [Parameter(Mandatory = $false)]
    [string]$Category,

    [Parameter(Mandatory = $false)]
    [switch]$JsonOutput
)

$ErrorActionPreference = "SilentlyContinue"

# ============================================================================
# PATHS & INITIALIZATION
# ============================================================================
$aiDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$configDir = Join-Path $aiDir "config"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$catalogPath = Join-Path $aiDir "agents-catalog.json"
$selectionPath = Join-Path $configDir "agents-selection.json"
$agentsLibraryDir = Join-Path $aiDir "agents-library"
$claudeAgentsDir = Join-Path $projectRoot ".claude" "agents"

# ============================================================================
# OUTPUT HELPERS
# ============================================================================

function Write-Header {
    param([string]$Title)
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Success {
    param([string]$Message)
    Write-Host "[+] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[!] $Message" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Message)
    Write-Host "[-] $Message" -ForegroundColor Red
}

function Write-Info {
    param([string]$Message)
    Write-Host "    $Message" -ForegroundColor Gray
}

# ============================================================================
# DATA HELPERS
# ============================================================================

function Load-Catalog {
    if (-not (Test-Path $catalogPath)) {
        Write-Err "Agent catalog not found at: $catalogPath"
        Write-Info "Run 'wof update' to sync the agent catalog from the framework."
        return $null
    }
    try {
        $raw = Get-Content $catalogPath -Raw -ErrorAction Stop
        $catalog = $raw | ConvertFrom-Json -ErrorAction Stop
        return $catalog
    }
    catch {
        Write-Err "Failed to parse agent catalog: $_"
        return $null
    }
}

function Load-Selection {
    if (-not (Test-Path $selectionPath)) {
        # Return empty selection structure
        return @{
            version   = "1.0.0"
            installed = @()
        }
    }
    try {
        $raw = Get-Content $selectionPath -Raw -ErrorAction Stop
        $selection = $raw | ConvertFrom-Json -ErrorAction Stop
        return $selection
    }
    catch {
        Write-Warn "Failed to parse agents-selection.json, starting fresh."
        return @{
            version   = "1.0.0"
            installed = @()
        }
    }
}

function Save-Selection {
    param($Selection)

    # Ensure config directory exists
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    # Build a clean object for serialization
    $output = @{
        version   = "1.0.0"
        installed = @($Selection.installed)
    }

    $json = $output | ConvertTo-Json -Depth 5
    Set-Content -Path $selectionPath -Value $json -Encoding UTF8
}

function Find-AgentInCatalog {
    param(
        $Catalog,
        [string]$Name
    )

    $lowerName = $Name.ToLower()

    foreach ($cat in $Catalog.categories) {
        foreach ($agent in $cat.agents) {
            if ($agent.name.ToLower() -eq $lowerName) {
                return @{
                    Agent       = $agent
                    Category    = $cat.name
                    CategoryDir = $cat.dir
                }
            }
        }
    }
    return $null
}

function Get-FuzzySuggestions {
    param(
        $Catalog,
        [string]$Name
    )

    $lowerName = $Name.ToLower()
    $suggestions = @()

    foreach ($cat in $Catalog.categories) {
        foreach ($agent in $cat.agents) {
            $agentLower = $agent.name.ToLower()
            # Check if the search term is contained in the agent name or vice versa
            if ($agentLower -like "*$lowerName*" -or $lowerName -like "*$agentLower*") {
                $suggestions += $agent.name
            }
            # Check for partial word match
            elseif ($lowerName.Length -ge 3) {
                $nameParts = $agentLower -split '-'
                foreach ($part in $nameParts) {
                    if ($part -like "*$lowerName*" -or $lowerName -like "*$part*") {
                        $suggestions += $agent.name
                        break
                    }
                }
            }
        }
    }

    return $suggestions | Select-Object -Unique
}

function Is-AgentInstalled {
    param(
        $Selection,
        [string]$Name
    )

    $lowerName = $Name.ToLower()
    foreach ($inst in $Selection.installed) {
        if ($inst.name.ToLower() -eq $lowerName) {
            return $true
        }
    }
    return $false
}

# ============================================================================
# ACTION: LIST
# ============================================================================

function Invoke-List {
    $selection = Load-Selection

    $installed = @($selection.installed)

    if ($JsonOutput) {
        return $installed | ConvertTo-Json -Depth 5
    }

    Write-Header "Installed Agents"

    if ($installed.Count -eq 0) {
        Write-Info "No agents installed."
        Write-Host ""
        Write-Info "Use '-Action catalog' to browse available agents."
        Write-Info "Use '-Action detect' to auto-detect recommended agents."
        Write-Host ""
        return
    }

    Write-Host "  Found $($installed.Count) installed agent(s):" -ForegroundColor White
    Write-Host ""

    foreach ($agent in $installed) {
        $name = $agent.name
        $category = $agent.category
        $model = if ($agent.model) { $agent.model } else { "default" }
        $installedAt = if ($agent.installedAt) { $agent.installedAt } else { "unknown" }

        Write-Host "  * " -NoNewline -ForegroundColor Green
        Write-Host "$name" -NoNewline -ForegroundColor White
        Write-Host "  [$category]" -NoNewline -ForegroundColor DarkGray
        Write-Host "  model: $model" -ForegroundColor Gray
    }

    Write-Host ""
}

# ============================================================================
# ACTION: ADD
# ============================================================================

function Invoke-Add {
    if (-not $AgentName) {
        Write-Err "Agent name is required for the 'add' action."
        Write-Info "Usage: manage-agents.ps1 -Action add -AgentName <name>"
        return
    }

    # Load catalog
    $catalog = Load-Catalog
    if (-not $catalog) { return }

    # Load current selection
    $selection = Load-Selection

    # Check if already installed
    if (Is-AgentInstalled -Selection $selection -Name $AgentName) {
        Write-Warn "Agent '$AgentName' is already installed."
        return
    }

    # Find agent in catalog
    $found = Find-AgentInCatalog -Catalog $catalog -Name $AgentName
    if (-not $found) {
        Write-Err "Agent '$AgentName' not found in the catalog."

        $suggestions = Get-FuzzySuggestions -Catalog $catalog -Name $AgentName
        if ($suggestions.Count -gt 0) {
            Write-Host ""
            Write-Host "  Did you mean:" -ForegroundColor Yellow
            foreach ($s in $suggestions) {
                Write-Host "    - $s" -ForegroundColor White
            }
        }
        else {
            Write-Info "Use '-Action catalog' to browse available agents."
        }
        Write-Host ""
        return
    }

    $agent = $found.Agent
    $categoryName = $found.Category
    $categoryDir = $found.CategoryDir

    # Locate the agent source file in the bundled library
    $sourceFile = Join-Path $agentsLibraryDir $categoryDir "$($agent.name).md"

    if (-not (Test-Path $sourceFile)) {
        Write-Err "Agent source file not found: $sourceFile"
        Write-Info "The agents library may not be fully synced. Run 'wof update' to refresh."
        return
    }

    # Ensure target directory exists
    if (-not (Test-Path $claudeAgentsDir)) {
        New-Item -ItemType Directory -Path $claudeAgentsDir -Force | Out-Null
    }

    # Copy agent file to .claude/agents/
    $targetFile = Join-Path $claudeAgentsDir "$($agent.name).md"
    Copy-Item -Path $sourceFile -Destination $targetFile -Force

    if (-not (Test-Path $targetFile)) {
        Write-Err "Failed to copy agent file to: $targetFile"
        return
    }

    # Update selection
    $model = if ($agent.model) { $agent.model } else { "sonnet" }
    $newEntry = @{
        name        = $agent.name
        category    = $categoryName
        categoryDir = $categoryDir
        model       = $model
        installedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }

    $installedList = [System.Collections.ArrayList]@()
    foreach ($existing in $selection.installed) {
        $installedList.Add($existing) | Out-Null
    }
    $installedList.Add($newEntry) | Out-Null
    $selection.installed = $installedList.ToArray()

    Save-Selection -Selection $selection

    if ($JsonOutput) {
        return $newEntry | ConvertTo-Json -Depth 5
    }

    Write-Success "Agent '$($agent.name)' installed successfully."
    Write-Info "Category: $categoryName"
    Write-Info "Model:    $model"
    Write-Info "File:     $targetFile"
    Write-Host ""
}

# ============================================================================
# ACTION: REMOVE
# ============================================================================

function Invoke-Remove {
    if (-not $AgentName) {
        Write-Err "Agent name is required for the 'remove' action."
        Write-Info "Usage: manage-agents.ps1 -Action remove -AgentName <name>"
        return
    }

    # Load current selection
    $selection = Load-Selection

    # Check if the agent is installed
    if (-not (Is-AgentInstalled -Selection $selection -Name $AgentName)) {
        Write-Err "Agent '$AgentName' is not installed."
        Write-Info "Use '-Action list' to see installed agents."
        return
    }

    # Remove the agent file from .claude/agents/
    $targetFile = Join-Path $claudeAgentsDir "$AgentName.md"
    if (Test-Path $targetFile) {
        Remove-Item -Path $targetFile -Force
    }

    # Update selection - remove the agent entry
    $lowerName = $AgentName.ToLower()
    $remaining = @()
    foreach ($inst in $selection.installed) {
        if ($inst.name.ToLower() -ne $lowerName) {
            $remaining += $inst
        }
    }
    $selection.installed = $remaining

    Save-Selection -Selection $selection

    if ($JsonOutput) {
        return @{ removed = $AgentName; success = $true } | ConvertTo-Json -Depth 5
    }

    Write-Success "Agent '$AgentName' removed."
    if (Test-Path $targetFile) {
        Write-Warn "Note: Agent file could not be deleted from $targetFile"
    }
    else {
        Write-Info "Removed file: $targetFile"
    }
    Write-Host ""
}

# ============================================================================
# ACTION: DETECT
# ============================================================================

function Invoke-Detect {
    # Load catalog
    $catalog = Load-Catalog
    if (-not $catalog) { return }

    $selection = Load-Selection
    $suggestions = @()

    if (-not $JsonOutput) {
        Write-Header "Auto-Detecting Project Tech Stack"
        Write-Host "  Scanning project root: $projectRoot" -ForegroundColor Gray
        Write-Host ""
    }

    foreach ($cat in $catalog.categories) {
        foreach ($agent in $cat.agents) {
            if (-not $agent.detect -or -not $agent.detect.files) { continue }

            $matched = $false
            $matchedFiles = @()

            foreach ($markerFile in $agent.detect.files) {
                $fullPath = Join-Path $projectRoot $markerFile

                # Support glob patterns
                if ($markerFile -match '\*') {
                    $globResults = Get-ChildItem -Path $projectRoot -Filter $markerFile -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($globResults) {
                        $matched = $true
                        $matchedFiles += $markerFile
                    }
                }
                else {
                    if (Test-Path $fullPath) {
                        $matched = $true
                        $matchedFiles += $markerFile
                    }
                }
            }

            if ($matched) {
                $isInstalled = Is-AgentInstalled -Selection $selection -Name $agent.name
                $suggestions += @{
                    name        = $agent.name
                    category    = $cat.name
                    categoryDir = $cat.dir
                    description = if ($agent.description) { $agent.description } else { "" }
                    model       = if ($agent.model) { $agent.model } else { "sonnet" }
                    matchedFiles = $matchedFiles
                    installed   = $isInstalled
                }
            }
        }
    }

    if ($JsonOutput) {
        return $suggestions | ConvertTo-Json -Depth 5
    }

    if ($suggestions.Count -eq 0) {
        Write-Info "No agents matched your project's tech stack."
        Write-Info "Use '-Action catalog' to browse all available agents."
        Write-Host ""
        return
    }

    Write-Host "  Detected $($suggestions.Count) recommended agent(s):" -ForegroundColor White
    Write-Host ""

    foreach ($s in $suggestions) {
        $statusTag = if ($s.installed) { " [INSTALLED]" } else { "" }
        $statusColor = if ($s.installed) { "Green" } else { "Yellow" }

        Write-Host "  * " -NoNewline -ForegroundColor Cyan
        Write-Host "$($s.name)" -NoNewline -ForegroundColor White
        if ($statusTag) {
            Write-Host $statusTag -NoNewline -ForegroundColor $statusColor
        }
        Write-Host ""

        if ($s.description) {
            Write-Info "    $($s.description)"
        }
        $filesStr = $s.matchedFiles -join ", "
        Write-Host "      Detected via: $filesStr" -ForegroundColor DarkGray
        Write-Host ""
    }

    # Summary of uninstalled suggestions
    $uninstalled = @($suggestions | Where-Object { -not $_.installed })
    if ($uninstalled.Count -gt 0) {
        Write-Host "  To install a suggested agent:" -ForegroundColor Gray
        Write-Host "    manage-agents.ps1 -Action add -AgentName <name>" -ForegroundColor White
        Write-Host ""
    }
}

# ============================================================================
# ACTION: CATALOG
# ============================================================================

function Invoke-Catalog {
    # Load catalog
    $catalog = Load-Catalog
    if (-not $catalog) { return }

    $selection = Load-Selection

    # Filter by category if specified
    $categories = $catalog.categories
    if ($Category) {
        $lowerCategory = $Category.ToLower()
        $categories = @($categories | Where-Object { $_.name.ToLower() -like "*$lowerCategory*" })

        if ($categories.Count -eq 0) {
            Write-Err "No category matching '$Category' found."
            Write-Host ""
            Write-Host "  Available categories:" -ForegroundColor Gray
            foreach ($cat in $catalog.categories) {
                Write-Host "    - $($cat.name)" -ForegroundColor White
            }
            Write-Host ""
            return
        }
    }

    if ($JsonOutput) {
        $output = @()
        foreach ($cat in $categories) {
            foreach ($agent in $cat.agents) {
                $isInstalled = Is-AgentInstalled -Selection $selection -Name $agent.name
                $output += @{
                    name        = $agent.name
                    category    = $cat.name
                    categoryDir = $cat.dir
                    description = if ($agent.description) { $agent.description } else { "" }
                    model       = if ($agent.model) { $agent.model } else { "sonnet" }
                    installed   = $isInstalled
                }
            }
        }
        return $output | ConvertTo-Json -Depth 5
    }

    Write-Header "Agent Catalog"

    # Summary line
    $totalAgents = 0
    foreach ($cat in $categories) {
        $totalAgents += $cat.agents.Count
    }
    Write-Host "  $($categories.Count) categor$(if ($categories.Count -eq 1) { 'y' } else { 'ies' }), $totalAgents agent(s) total" -ForegroundColor Gray
    Write-Host ""

    foreach ($cat in $categories) {
        $agentCount = $cat.agents.Count
        Write-Host "  $($cat.name) ($agentCount)" -ForegroundColor Cyan
        Write-Host "  $('-' * ($cat.name.Length + 4))" -ForegroundColor DarkCyan

        foreach ($agent in $cat.agents) {
            $isInstalled = Is-AgentInstalled -Selection $selection -Name $agent.name
            $installedMark = if ($isInstalled) { " [INSTALLED]" } else { "" }
            $markColor = if ($isInstalled) { "Green" } else { "White" }

            Write-Host "    * " -NoNewline -ForegroundColor Gray
            Write-Host "$($agent.name)" -NoNewline -ForegroundColor $markColor
            if ($installedMark) {
                Write-Host $installedMark -NoNewline -ForegroundColor Green
            }
            Write-Host ""

            if ($agent.description) {
                Write-Host "      $($agent.description)" -ForegroundColor DarkGray
            }
        }
        Write-Host ""
    }

    Write-Host "  To install an agent:" -ForegroundColor Gray
    Write-Host "    manage-agents.ps1 -Action add -AgentName <name>" -ForegroundColor White
    Write-Host ""
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

switch ($Action) {
    "list"    { Invoke-List }
    "add"     { Invoke-Add }
    "remove"  { Invoke-Remove }
    "detect"  { Invoke-Detect }
    "catalog" { Invoke-Catalog }
}
