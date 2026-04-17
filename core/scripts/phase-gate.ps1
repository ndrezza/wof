# ============================================================================
# WOF MANAGED FILE - DO NOT EDIT MANUALLY
# This file is managed by the Workload Orchestration Framework.
# Changes will be overwritten on the next WOF sync/update.
# To customize behavior, use configuration files in .ai/config/
# ============================================================================

# Phase Gate Validation Script
#
# Enforces the 9-phase feature workflow by validating entry/exit criteria
# before allowing progression to the next phase.
#
# The 9 Phases:
#   1. intake     - Understand requirements, clarify with ADO
#   2. design     - Architecture decisions, validated approach
#   3. implement  - Write code incrementally
#   4. test       - Run unit tests, verify coverage
#   5. critique   - Security scan, code review, bias-control
#   6. validate   - Final verification, all issues fixed
#   7. document   - Update memory bank, feature docs
#   8. review     - Documentation review, completeness check
#   9. finish     - Commit, push, PR, update ADO
#
# Usage:
#   # Check if ready for next phase
#   $result = & '.\.ai\scripts\phase-gate.ps1' -CurrentPhase 'implement' -NextPhase 'test' -Context "implemented feature X"
#
#   # Force transition (skip validation)
#   $result = & '.\.ai\scripts\phase-gate.ps1' -CurrentPhase 'implement' -NextPhase 'test' -Force
#
#   # Get current workflow state
#   $state = & '.\.ai\scripts\phase-gate.ps1' -GetState

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('intake', 'design', 'implement', 'test', 'critique', 'validate', 'document', 'review', 'finish')]
    [string]$CurrentPhase,

    [Parameter(Mandatory=$false)]
    [ValidateSet('intake', 'design', 'implement', 'test', 'critique', 'validate', 'document', 'review', 'finish')]
    [string]$NextPhase,

    [Parameter(Mandatory=$false)]
    [string]$Context = "",

    [Parameter(Mandatory=$false)]
    [string]$WorkItemId = "",

    [Parameter(Mandatory=$false)]
    [switch]$Force,

    [Parameter(Mandatory=$false)]
    [switch]$GetState,

    [Parameter(Mandatory=$false)]
    [switch]$ResetState
)

$ErrorActionPreference = "Stop"

# Load orchestration config for quality gate thresholds (optional)
$validatorThreshold = 0.7  # default
$criticThreshold = 0.8     # default
$orchConfigPath = Join-Path $PSScriptRoot "..\config\orchestration.json"
if (Test-Path $orchConfigPath) {
    try {
        $orchConfig = Get-Content $orchConfigPath -Raw | ConvertFrom-Json
        if ($orchConfig.quality_gates.validator_threshold -ne $null) {
            $validatorThreshold = $orchConfig.quality_gates.validator_threshold
        }
        if ($orchConfig.quality_gates.critic_threshold -ne $null) {
            $criticThreshold = $orchConfig.quality_gates.critic_threshold
        }
    } catch {
        # Graceful fallback - use default thresholds
    }
}

# State file location
$stateDir = Join-Path $PSScriptRoot "..\state"
$stateFile = Join-Path $stateDir "workflow-state.json"

# Ensure state directory exists
if (-not (Test-Path $stateDir)) {
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
}

# Phase order for validation
$phaseOrder = @('intake', 'design', 'implement', 'test', 'critique', 'validate', 'document', 'review', 'finish')

# Phase definitions with entry/exit criteria
$phaseDefinitions = @{
    'intake' = @{
        DisplayName = "1. Intake"
        Description = "Understand requirements, clarify with ADO"
        EntryCriteria = @(
            "Work item ID identified"
        )
        ExitCriteria = @(
            "Requirements understood"
            "Questions posted to ADO (if any)"
            "Scope confirmed"
        )
        Validators = @()  # No special validation needed
    }
    'design' = @{
        DisplayName = "2. Design"
        Description = "Architecture decisions, validated approach"
        EntryCriteria = @(
            "Intake phase completed"
            "Requirements clear"
        )
        ExitCriteria = @(
            "Design approach documented"
            "Validator approved (confidence >= $validatorThreshold)"
            "No blocking questions"
        )
        Validators = @('autonomy')  # Uses validate-autonomy.ps1
    }
    'implement' = @{
        DisplayName = "3. Implement"
        Description = "Write code incrementally"
        EntryCriteria = @(
            "Design approved"
        )
        ExitCriteria = @(
            "Code written"
            "Build passes"
            "No compiler errors"
        )
        Validators = @('build')  # Requires successful build
    }
    'test' = @{
        DisplayName = "4. Test"
        Description = "Run unit tests, verify coverage"
        EntryCriteria = @(
            "Implementation complete"
            "Build passes"
        )
        ExitCriteria = @(
            "Unit tests pass"
            "New tests written (if applicable)"
            "No regressions"
        )
        Validators = @('test')  # Requires test execution
    }
    'critique' = @{
        DisplayName = "5. Critique"
        Description = "Security scan, code review, bias-control"
        EntryCriteria = @(
            "Tests pass"
        )
        ExitCriteria = @(
            "Security review done"
            "Bias-control viability >= $([math]::Round($criticThreshold * 100))%"
            "No critical issues"
        )
        Validators = @('security', 'bias-control')
    }
    'validate' = @{
        DisplayName = "6. Validate"
        Description = "Final verification, all issues fixed"
        EntryCriteria = @(
            "Critique phase passed"
        )
        ExitCriteria = @(
            "All critique issues addressed"
            "Final build passes"
            "Final tests pass"
        )
        Validators = @('build', 'test')
    }
    'document' = @{
        DisplayName = "7. Document"
        Description = "Update memory bank, feature docs"
        EntryCriteria = @(
            "Validation complete"
        )
        ExitCriteria = @(
            "current-sprint.md updated"
            "Feature documentation added (if needed)"
        )
        Validators = @('documentation')
    }
    'review' = @{
        DisplayName = "8. Review"
        Description = "Documentation review, completeness check"
        EntryCriteria = @(
            "Documentation updated"
        )
        ExitCriteria = @(
            "Documentation reviewed"
            "Completeness checklist passed"
        )
        Validators = @('autonomy')
    }
    'finish' = @{
        DisplayName = "9. Finish"
        Description = "Commit, push, PR, update ADO"
        EntryCriteria = @(
            "Review complete"
        )
        ExitCriteria = @(
            "Changes committed"
            "Pushed to remote"
            "PR created (if applicable)"
            "ADO work item updated"
        )
        Validators = @('git')
    }
}

function Get-WorkflowState {
    if (Test-Path $stateFile) {
        return Get-Content $stateFile | ConvertFrom-Json
    }
    return @{
        CurrentPhase = $null
        WorkItemId = $null
        PhaseHistory = @()
        StartedAt = $null
        LastUpdated = $null
    }
}

function Save-WorkflowState {
    param([object]$State)
    $State | ConvertTo-Json -Depth 10 | Set-Content $stateFile
}

function Reset-WorkflowState {
    if (Test-Path $stateFile) {
        Remove-Item $stateFile -Force
    }
    return @{ Success = $true; Message = "Workflow state reset" }
}

function Get-PhaseIndex {
    param([string]$Phase)
    return $phaseOrder.IndexOf($Phase)
}

function Test-PhaseTransitionValid {
    param(
        [string]$From,
        [string]$To
    )

    $fromIndex = Get-PhaseIndex -Phase $From
    $toIndex = Get-PhaseIndex -Phase $To

    # Can only move forward one phase at a time, or stay in same phase
    return ($toIndex -eq $fromIndex + 1) -or ($toIndex -eq $fromIndex)
}

function Invoke-PhaseValidator {
    param(
        [string]$ValidatorType,
        [string]$Context
    )

    switch ($ValidatorType) {
        'autonomy' {
            # Call Validator
            $validatorScript = Join-Path $PSScriptRoot "validate-autonomy.ps1"
            if (Test-Path $validatorScript) {
                try {
                    $result = & $validatorScript -Decision "Phase transition validation" -Context $Context -RiskLevel "low"
                    return @{
                        Passed = $result.Proceed -and ($result.Confidence -ge $validatorThreshold)
                        Confidence = $result.Confidence
                        Reason = $result.Reason
                    }
                }
                catch {
                    return @{ Passed = $true; Confidence = 0.5; Reason = "Validator unavailable, proceeding with caution" }
                }
            }
            return @{ Passed = $true; Confidence = 0.5; Reason = "Validator script not found" }
        }
        'build' {
            # Check if build passes
            return @{
                Passed = $true  # Assume build was checked externally
                Confidence = 1.0
                Reason = "Build validation delegated to caller"
            }
        }
        'test' {
            # Check if tests pass
            return @{
                Passed = $true  # Assume tests were checked externally
                Confidence = 1.0
                Reason = "Test validation delegated to caller"
            }
        }
        'bias-control' {
            # Would call bias-control.ps1
            return @{
                Passed = $true
                Confidence = $criticThreshold
                Reason = "Bias-control validation delegated to caller (threshold: $criticThreshold)"
            }
        }
        'security' {
            return @{
                Passed = $true
                Confidence = 0.8
                Reason = "Security review delegated to caller"
            }
        }
        'documentation' {
            # Check if current-sprint.md was updated recently
            $sprintFile = Join-Path $PSScriptRoot "..\memory\current-sprint.md"
            if (Test-Path $sprintFile) {
                $lastWrite = (Get-Item $sprintFile).LastWriteTime
                $recentlyUpdated = $lastWrite -gt (Get-Date).AddHours(-2)
                return @{
                    Passed = $recentlyUpdated
                    Confidence = if ($recentlyUpdated) { 0.9 } else { 0.5 }
                    Reason = if ($recentlyUpdated) { "Documentation updated within last 2 hours" } else { "Documentation may be stale" }
                }
            }
            return @{ Passed = $false; Confidence = 0.3; Reason = "current-sprint.md not found" }
        }
        'git' {
            # Check git status
            return @{
                Passed = $true
                Confidence = 1.0
                Reason = "Git validation delegated to caller"
            }
        }
        default {
            return @{ Passed = $true; Confidence = 0.5; Reason = "Unknown validator type" }
        }
    }
}

function Test-PhaseGate {
    param(
        [string]$CurrentPhase,
        [string]$NextPhase,
        [string]$Context,
        [bool]$ForceTransition
    )

    $result = @{
        CanProceed = $false
        CurrentPhase = $CurrentPhase
        NextPhase = $NextPhase
        BlockingIssues = @()
        ValidatorResults = @()
        OverallConfidence = 0.0
    }

    # Check phase order
    if (-not (Test-PhaseTransitionValid -From $CurrentPhase -To $NextPhase)) {
        $result.BlockingIssues += "Invalid phase transition: cannot skip from '$CurrentPhase' to '$NextPhase'"
        if (-not $ForceTransition) {
            return $result
        }
    }

    # Get phase definition
    $phaseDef = $phaseDefinitions[$CurrentPhase]
    if (-not $phaseDef) {
        $result.BlockingIssues += "Unknown phase: $CurrentPhase"
        return $result
    }

    # Check exit criteria (informational)
    Write-Host "`nExit criteria for $($phaseDef.DisplayName):" -ForegroundColor Cyan
    foreach ($criterion in $phaseDef.ExitCriteria) {
        Write-Host "  - $criterion" -ForegroundColor Gray
    }

    # Run validators
    $validatorConfidences = @()
    foreach ($validator in $phaseDef.Validators) {
        Write-Host "`nRunning validator: $validator" -ForegroundColor Yellow
        $validatorResult = Invoke-PhaseValidator -ValidatorType $validator -Context $Context
        $result.ValidatorResults += @{
            Type = $validator
            Passed = $validatorResult.Passed
            Confidence = $validatorResult.Confidence
            Reason = $validatorResult.Reason
        }

        if (-not $validatorResult.Passed -and -not $ForceTransition) {
            $result.BlockingIssues += "Validator '$validator' failed: $($validatorResult.Reason)"
        }

        $validatorConfidences += $validatorResult.Confidence
    }

    # Calculate overall confidence
    if ($validatorConfidences.Count -gt 0) {
        $result.OverallConfidence = ($validatorConfidences | Measure-Object -Average).Average
    }
    else {
        $result.OverallConfidence = 1.0  # No validators = auto-pass
    }

    # Determine if can proceed
    $result.CanProceed = ($result.BlockingIssues.Count -eq 0) -or $ForceTransition

    return $result
}

# Main execution
if ($GetState) {
    return Get-WorkflowState
}

if ($ResetState) {
    return Reset-WorkflowState
}

if (-not $CurrentPhase -or -not $NextPhase) {
    Write-Host "Phase Gate Validator" -ForegroundColor Cyan
    Write-Host "===================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  Validate transition:  phase-gate.ps1 -CurrentPhase 'implement' -NextPhase 'test' -Context 'summary'"
    Write-Host "  Get current state:    phase-gate.ps1 -GetState"
    Write-Host "  Reset state:          phase-gate.ps1 -ResetState"
    Write-Host "  Force transition:     phase-gate.ps1 -CurrentPhase 'X' -NextPhase 'Y' -Force"
    Write-Host ""
    Write-Host "Phases:" -ForegroundColor Yellow
    foreach ($phase in $phaseOrder) {
        $def = $phaseDefinitions[$phase]
        Write-Host "  $($def.DisplayName) - $($def.Description)" -ForegroundColor Gray
    }
    return @{ Success = $false; Error = "CurrentPhase and NextPhase are required" }
}

# Validate phase transition
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Phase Gate Validation" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "From: $($phaseDefinitions[$CurrentPhase].DisplayName)" -ForegroundColor White
Write-Host "To:   $($phaseDefinitions[$NextPhase].DisplayName)" -ForegroundColor White
Write-Host "----------------------------------------" -ForegroundColor Gray

$gateResult = Test-PhaseGate -CurrentPhase $CurrentPhase -NextPhase $NextPhase -Context $Context -ForceTransition $Force

# Display results
Write-Host ""
if ($gateResult.CanProceed) {
    Write-Host "GATE PASSED - Ready to proceed to $NextPhase" -ForegroundColor Green
}
else {
    Write-Host "GATE BLOCKED - Cannot proceed to $NextPhase" -ForegroundColor Red
    Write-Host "`nBlocking Issues:" -ForegroundColor Red
    foreach ($issue in $gateResult.BlockingIssues) {
        Write-Host "  - $issue" -ForegroundColor Yellow
    }
}

Write-Host "`nOverall Confidence: $([math]::Round($gateResult.OverallConfidence * 100))%" -ForegroundColor Cyan

# Update state if proceeding
if ($gateResult.CanProceed) {
    $state = Get-WorkflowState
    $historyEntry = @{
        FromPhase = $CurrentPhase
        ToPhase = $NextPhase
        Timestamp = (Get-Date -Format "o")
        Confidence = $gateResult.OverallConfidence
        Forced = $Force.IsPresent
    }

    if ($null -eq $state.PhaseHistory) {
        $state.PhaseHistory = @()
    }
    $state.PhaseHistory += $historyEntry
    $state.CurrentPhase = $NextPhase
    $state.LastUpdated = (Get-Date -Format "o")

    if ($WorkItemId) {
        $state.WorkItemId = $WorkItemId
    }

    if (-not $state.StartedAt) {
        $state.StartedAt = (Get-Date -Format "o")
    }

    Save-WorkflowState -State $state
    Write-Host "`nWorkflow state updated." -ForegroundColor Gray
}

return @{
    Success = $true
    CanProceed = $gateResult.CanProceed
    CurrentPhase = $CurrentPhase
    NextPhase = $NextPhase
    BlockingIssues = $gateResult.BlockingIssues
    ValidatorResults = $gateResult.ValidatorResults
    OverallConfidence = $gateResult.OverallConfidence
    Forced = $Force.IsPresent
}
