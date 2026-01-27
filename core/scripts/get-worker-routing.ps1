<#
.SYNOPSIS
    Determines which worker should handle a task based on routing rules.

.DESCRIPTION
    Analyzes task descriptions and context to route to the appropriate worker:
    - Worker-Lite (Local DeepSeek): T1 lightweight tasks
    - Worker-Heavy (Azure Opus): T2+ complex tasks
    
    Based on routing-rules.md specifications.

.PARAMETER Task
    The task description to analyze.

.PARAMETER ContextTokens
    Estimated context size in tokens (default: 0 = auto-estimate).

.PARAMETER FileCount
    Number of files the task will need to read (default: 0).

.PARAMETER ForceHeavy
    Force routing to Worker-Heavy regardless of analysis.

.PARAMETER ForceLite
    Force routing to Worker-Lite (will still check availability).

.EXAMPLE
    .\.ai\scripts\get-worker-routing.ps1 -Task "Find all files containing ILogger"
    # Returns: WorkerLite

.EXAMPLE
    .\.ai\scripts\get-worker-routing.ps1 -Task "Implement the JobScheduler service"
    # Returns: WorkerHeavy

.OUTPUTS
    PSCustomObject with Worker, Tier, Reason, and Confidence properties.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Task,

    [Parameter(Mandatory = $false)]
    [int]$ContextTokens = 0,

    [Parameter(Mandatory = $false)]
    [int]$FileCount = 0,

    [Parameter(Mandatory = $false)]
    [switch]$ForceHeavy,

    [Parameter(Mandatory = $false)]
    [switch]$ForceLite,

    [Parameter(Mandatory = $false)]
    [switch]$JsonOutput
)

$ErrorActionPreference = "SilentlyContinue"

# =============================================================================
# ROUTING KEYWORDS (from routing-rules.md)
# =============================================================================

# T1 Keywords -> Worker-Lite
$LiteKeywords = @(
    "search", "find", "glob", "grep", "list", "format", "lint",
    "navigate", "locate", "show", "what", "where", "count",
    "which", "how many", "exists", "contains", "pattern"
)

# T2+ Keywords -> Worker-Heavy
$HeavyKeywords = @(
    "implement", "create", "write", "fix", "test", "refactor",
    "architect", "design", "debug", "optimize", "security",
    "analyze", "review", "generate", "build", "add", "update",
    "modify", "change", "extend", "integrate"
)

# Always Heavy (override all other rules)
$AlwaysHeavyKeywords = @(
    "deploy", "production", "critical", "security vulnerability",
    "comprehensive", "thorough", "entire codebase",
    "unit test", "integration test", "write test", "add test"
)

# Task type indicators
$CodeGenerationIndicators = @(
    "implement", "create", "write", "generate", "add new",
    "build", "develop", "construct"
)

$SearchIndicators = @(
    "find", "search", "grep", "glob", "locate", "where is",
    "which file", "list all", "show me"
)

$TestingIndicators = @(
    "test", "unit test", "integration test", "write test",
    "add test", "test case"
)

$RefactoringIndicators = @(
    "refactor", "restructure", "reorganize", "clean up",
    "extract", "rename across", "move to"
)

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

function Test-WorkerLiteAvailable {
    $baseEndpoint = if ($env:LOCAL_WORKER_ENDPOINT) { $env:LOCAL_WORKER_ENDPOINT } else { "http://127.0.0.1:1234" }
    try {
        $response = Invoke-WebRequest -Uri "$baseEndpoint/v1/models" -Method GET -TimeoutSec 3 -ErrorAction SilentlyContinue
        return $response.StatusCode -eq 200
    }
    catch {
        return $false
    }
}

function Get-KeywordScore {
    param(
        [string]$Text,
        [string[]]$Keywords
    )

    $score = 0
    $foundKeywords = @()
    $lowerText = $Text.ToLower()

    foreach ($keyword in $Keywords) {
        if ($lowerText -match [regex]::Escape($keyword.ToLower())) {
            $score++
            $foundKeywords += $keyword
        }
    }

    return @{
        Score = $score
        Matches = $foundKeywords
    }
}

function Estimate-TaskComplexity {
    param([string]$TaskDescription)
    
    $complexity = @{
        Score = 0
        Factors = @()
    }
    
    # Length-based complexity
    $wordCount = ($TaskDescription -split '\s+').Count
    if ($wordCount -gt 50) {
        $complexity.Score += 2
        $complexity.Factors += "Long description ($wordCount words)"
    }
    elseif ($wordCount -gt 20) {
        $complexity.Score += 1
        $complexity.Factors += "Medium description ($wordCount words)"
    }
    
    # Multi-step indicators
    if ($TaskDescription -match "and then|after that|first.*then|step|multiple|several") {
        $complexity.Score += 2
        $complexity.Factors += "Multi-step task"
    }
    
    # Cross-file indicators
    if ($TaskDescription -match "across|all files|multiple files|throughout|everywhere") {
        $complexity.Score += 2
        $complexity.Factors += "Cross-file operation"
    }
    
    # Quality indicators
    if ($TaskDescription -match "production|secure|robust|proper|best practice") {
        $complexity.Score += 1
        $complexity.Factors += "Quality requirements"
    }
    
    return $complexity
}

function Get-TaskType {
    param([string]$TaskDescription)
    
    $lowerTask = $TaskDescription.ToLower()
    
    # Check indicators in priority order
    if ((Get-KeywordScore -Text $lowerTask -Keywords $TestingIndicators).Score -gt 0) {
        return "Testing"
    }
    if ((Get-KeywordScore -Text $lowerTask -Keywords $RefactoringIndicators).Score -gt 0) {
        return "Refactoring"
    }
    if ((Get-KeywordScore -Text $lowerTask -Keywords $CodeGenerationIndicators).Score -gt 0) {
        return "CodeGeneration"
    }
    if ((Get-KeywordScore -Text $lowerTask -Keywords $SearchIndicators).Score -gt 0) {
        return "Search"
    }
    
    return "General"
}

# =============================================================================
# MAIN ROUTING LOGIC
# =============================================================================

function Get-WorkerRouting {
    param(
        [string]$TaskDescription,
        [int]$ContextSize,
        [int]$Files
    )
    
    $result = @{
        Worker = "WorkerHeavy"  # Default to Heavy
        Tier = "T2"
        Reason = @()
        Confidence = 0.5
        TaskType = ""
        Analysis = @{
            LiteKeywords = @()
            HeavyKeywords = @()
            AlwaysHeavyKeywords = @()
            Complexity = @{}
        }
    }
    
    # Step 1: Check for Always Heavy keywords (highest priority)
    $alwaysHeavy = Get-KeywordScore -Text $TaskDescription -Keywords $AlwaysHeavyKeywords
    if ($alwaysHeavy.Score -gt 0) {
        $result.Worker = "WorkerHeavy"
        $result.Tier = "T3"
        $matchedKeywords = [string]::Join(", ", $alwaysHeavy.Matches)
        $result.Reason += "Contains always-heavy keywords: $matchedKeywords"
        $result.Confidence = 0.95
        $result.Analysis.AlwaysHeavyKeywords = $alwaysHeavy.Matches
        return $result
    }
    
    # Step 2: Context size check
    if ($ContextSize -gt 16000) {
        $result.Worker = "WorkerHeavy"
        $result.Tier = "T2"
        $result.Reason += "Context size ($ContextSize tokens) exceeds Lite limit (16K)"
        $result.Confidence = 0.9
        return $result
    }
    
    # Step 3: File count check
    if ($Files -gt 5) {
        $result.Worker = "WorkerHeavy"
        $result.Tier = "T2"
        $result.Reason += "File count ($Files) exceeds Lite limit (5)"
        $result.Confidence = 0.85
        return $result
    }
    
    # Step 4: Analyze task type
    $taskType = Get-TaskType -TaskDescription $TaskDescription
    $result.TaskType = $taskType
    
    # Testing and Refactoring always go to Heavy
    if ($taskType -eq "Testing") {
        $result.Worker = "WorkerHeavy"
        $result.Tier = "T2"
        $result.Reason += "Testing tasks require Worker-Heavy"
        $result.Confidence = 0.9
        return $result
    }
    
    if ($taskType -eq "Refactoring") {
        $result.Worker = "WorkerHeavy"
        $result.Tier = "T3"
        $result.Reason += "Refactoring requires semantic understanding"
        $result.Confidence = 0.9
        return $result
    }
    
    # Step 5: Keyword analysis
    $liteScore = Get-KeywordScore -Text $TaskDescription -Keywords $LiteKeywords
    $heavyScore = Get-KeywordScore -Text $TaskDescription -Keywords $HeavyKeywords
    
    $result.Analysis.LiteKeywords = $liteScore.Matches
    $result.Analysis.HeavyKeywords = $heavyScore.Matches
    
    # Step 6: Complexity analysis
    $complexity = Estimate-TaskComplexity -TaskDescription $TaskDescription
    $result.Analysis.Complexity = $complexity
    
    # Step 7: Make routing decision
    $litePoints = $liteScore.Score * 2  # Weight lite keywords higher for simple tasks
    $heavyPoints = $heavyScore.Score * 2 + $complexity.Score
    
    if ($taskType -eq "Search" -and $liteScore.Score -gt 0) {
        # Search tasks with search keywords go to Lite
        $result.Worker = "WorkerLite"
        $result.Tier = "T1"
        $liteMatches = [string]::Join(", ", $liteScore.Matches)
        $result.Reason += "Search task with lite keywords: $liteMatches"
        $result.Confidence = 0.85
    }
    elseif ($litePoints -gt $heavyPoints -and $complexity.Score -lt 3) {
        # More lite keywords and low complexity
        $result.Worker = "WorkerLite"
        $result.Tier = "T1"
        $result.Reason += "Lite keywords ($litePoints pts) > Heavy keywords ($heavyPoints pts)"
        $result.Reason += "Low complexity (score: $($complexity.Score))"
        $result.Confidence = 0.7 + (0.1 * ($litePoints - $heavyPoints))
        $result.Confidence = [Math]::Min($result.Confidence, 0.9)
    }
    elseif ($heavyPoints -gt $litePoints) {
        # More heavy keywords
        $result.Worker = "WorkerHeavy"
        $result.Tier = if ($complexity.Score -ge 4) { "T3" } else { "T2" }
        $result.Reason += "Heavy keywords ($heavyPoints pts) > Lite keywords ($litePoints pts)"
        if ($complexity.Factors.Count -gt 0) {
            $complexFactors = [string]::Join(", ", $complexity.Factors)
            $result.Reason += "Complexity factors: $complexFactors"
        }
        $result.Confidence = 0.7 + (0.05 * ($heavyPoints - $litePoints))
        $result.Confidence = [Math]::Min($result.Confidence, 0.95)
    }
    elseif ($taskType -eq "CodeGeneration") {
        # Code generation defaults to Heavy unless very simple
        $result.Worker = "WorkerHeavy"
        $result.Tier = "T2"
        $result.Reason += "Code generation task defaults to Worker-Heavy"
        $result.Confidence = 0.75
    }
    else {
        # Tie or uncertain - use speculative execution (try Lite first)
        $result.Worker = "WorkerLite"
        $result.Tier = "T1"
        $result.Reason += "Uncertain routing - using speculative execution (try Lite first)"
        $result.Confidence = 0.5
    }
    
    return $result
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Handle force flags
if ($ForceHeavy) {
    $routing = @{
        Worker = "WorkerHeavy"
        Tier = "T3"
        Reason = @("Forced to Worker-Heavy by parameter")
        Confidence = 1.0
        TaskType = "Forced"
        LiteAvailable = $false
    }
}
elseif ($ForceLite) {
    $liteAvailable = Test-WorkerLiteAvailable
    if ($liteAvailable) {
        $routing = @{
            Worker = "WorkerLite"
            Tier = "T1"
            Reason = @("Forced to Worker-Lite by parameter")
            Confidence = 1.0
            TaskType = "Forced"
            LiteAvailable = $true
        }
    }
    else {
        $routing = @{
            Worker = "WorkerHeavy"
            Tier = "T2"
            Reason = @("Forced to Worker-Lite but unavailable - falling back to Heavy")
            Confidence = 1.0
            TaskType = "Forced"
            LiteAvailable = $false
        }
    }
}
else {
    # Normal routing analysis
    $routing = Get-WorkerRouting -TaskDescription $Task -ContextSize $ContextTokens -Files $FileCount
    
    # Check Worker-Lite availability if routed there
    if ($routing.Worker -eq "WorkerLite") {
        $liteAvailable = Test-WorkerLiteAvailable
        $routing.LiteAvailable = $liteAvailable
        
        if (-not $liteAvailable) {
            $routing.Worker = "WorkerHeavy"
            $routing.Tier = "T2"
            $routing.Reason += "Worker-Lite unavailable - falling back to Worker-Heavy"
            $routing.Confidence = 1.0
        }
    }
    else {
        $routing.LiteAvailable = $false  # Not checked since routing to Heavy
    }
}

# Output
if ($JsonOutput) {
    return $routing | ConvertTo-Json -Depth 5
}
else {
    # Human-readable output
    Write-Host ""
    Write-Host "Task Routing Analysis" -ForegroundColor Cyan
    Write-Host "=====================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Task: " -NoNewline -ForegroundColor Gray
    Write-Host $Task.Substring(0, [Math]::Min(80, $Task.Length)) -ForegroundColor White
    if ($Task.Length -gt 80) { Write-Host "..." -ForegroundColor Gray }
    Write-Host ""
    
    $workerColor = if ($routing.Worker -eq "WorkerLite") { "Green" } else { "Yellow" }
    Write-Host "Routing Decision:" -ForegroundColor Cyan
    Write-Host "  Worker: " -NoNewline
    Write-Host $routing.Worker -ForegroundColor $workerColor
    Write-Host "  Tier:   " -NoNewline
    Write-Host $routing.Tier -ForegroundColor $workerColor
    Write-Host "  Confidence: " -NoNewline
    Write-Host "$([Math]::Round($routing.Confidence * 100))%" -ForegroundColor $workerColor
    
    if ($routing.TaskType) {
        Write-Host "  Task Type: $($routing.TaskType)" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "Reasons:" -ForegroundColor Cyan
    foreach ($reason in $routing.Reason) {
        Write-Host "  * $reason" -ForegroundColor Gray
    }
    
    if ($routing.Analysis -and $routing.Analysis.LiteKeywords -and $routing.Analysis.LiteKeywords.Count -gt 0) {
        Write-Host ""
        Write-Host "Lite Keywords Found: " -NoNewline -ForegroundColor Gray
        $liteKw = @($routing.Analysis.LiteKeywords) | ForEach-Object { $_ }
        Write-Host ($liteKw -join ", ") -ForegroundColor Green
    }
    
    if ($routing.Analysis -and $routing.Analysis.HeavyKeywords -and $routing.Analysis.HeavyKeywords.Count -gt 0) {
        Write-Host "Heavy Keywords Found: " -NoNewline -ForegroundColor Gray
        $heavyKw = @($routing.Analysis.HeavyKeywords) | ForEach-Object { $_ }
        Write-Host ($heavyKw -join ", ") -ForegroundColor Yellow
    }
    
    Write-Host ""
    
    # Return the worker name for easy piping
    return $routing.Worker
}
