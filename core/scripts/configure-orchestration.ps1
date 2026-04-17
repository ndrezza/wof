# ============================================================================
# WOF MANAGED FILE - DO NOT EDIT MANUALLY
# This file is managed by the Workload Orchestration Framework.
# Changes will be overwritten on the next WOF sync/update.
# To customize behavior, use configuration files in .ai/config/
# ============================================================================

<#
.SYNOPSIS
    Interactive configuration wizard for WOF orchestration patterns.

.DESCRIPTION
    Allows users to configure:
    - Parallel execution settings (agent count, isolation, complexity threshold)
    - Task queue settings (retries, dependency tracking)
    - Agent spawning limits (max agents, cooldown, timeout, rotation)
    - Quality gates (validator/critic thresholds, auto-approve T1)
    - Routing & specialization (domain routing, specialist preferences)
    - Observability (logging, state tracking)

.PARAMETER JsonOutput
    Return configuration as JSON instead of interactive display.

.PARAMETER ShowOnly
    Display current configuration without modification.

.EXAMPLE
    .\configure-orchestration.ps1

.EXAMPLE
    .\configure-orchestration.ps1 -ShowOnly

.EXAMPLE
    .\configure-orchestration.ps1 -JsonOutput
#>

param(
    [switch]$JsonOutput,
    [switch]$ShowOnly
)

$ErrorActionPreference = "SilentlyContinue"

# ============================================================================
# Output Helpers
# ============================================================================

function Write-Header {
    param([string]$Title)
    Write-Host ""
    Write-Host "=== $Title ===" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Pass {
    param([string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  [!!] $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host "  [XX] $Message" -ForegroundColor Red
}

function Write-Info {
    param([string]$Message)
    Write-Host "  $Message" -ForegroundColor Gray
}

# ============================================================================
# Configuration Loading
# ============================================================================

$configDir = Join-Path $PSScriptRoot "..\config"
$orchestrationPath = Join-Path $configDir "orchestration.json"

function Get-OrchestrationConfig {
    if (Test-Path $orchestrationPath) {
        try {
            return Get-Content $orchestrationPath -Raw | ConvertFrom-Json
        } catch {
            Write-Warn "Could not parse orchestration.json, using defaults"
            return Get-DefaultConfig
        }
    }
    return Get-DefaultConfig
}

function Get-DefaultConfig {
    return @{
        version = "1.0.0"
        description = "Orchestration pattern configuration. Controls parallel execution, task queue, agent spawning, quality gates, and role specializations."
        patterns = @{
            parallel_execution = @{
                enabled = $false
                max_parallel_agents = 3
                isolation_method = "worktree"
                min_task_complexity_for_parallel = "T2"
                plan_approval_required = $true
                merge_strategy = "orchestrator_review"
            }
            task_queue = @{
                enabled = $false
                state_directory = ".ai/state/queue"
                max_queue_depth = 20
                retry_on_failure = $true
                max_retries = 2
                dependency_tracking = $true
            }
            worktree_isolation = @{
                enabled = $false
                base_directory = ".claude/worktrees"
                cleanup_on_completion = $true
                max_concurrent_worktrees = 3
            }
        }
        agent_spawning = @{
            max_total_agents = 5
            max_workers = 3
            max_validators = 1
            max_critics = 1
            cooldown_between_spawns_seconds = 5
            agent_session_timeout_minutes = 30
            rotation_after_consecutive_runs = 5
        }
        quality_gates = @{
            validator_threshold = 0.7
            critic_threshold = 0.8
            require_validation_for_parallel = $true
            require_critic_before_merge = $true
            auto_approve_t1_tasks = $false
        }
        routing_enhancements = @{
            speculative_execution = $true
            domain_routing_enabled = $false
            prefer_specialist_agents = $false
            parallel_threshold_minutes = 30
        }
        role_specializations = @{
            enabled = $false
            specializations = @{
                worker = @("researcher", "implementer", "test-generator")
                validator = @("security-reviewer")
                critic = @("devils-advocate")
            }
        }
        observability = @{
            enabled = $true
            log_agent_activity = $true
            log_task_transitions = $true
            state_file = ".ai/state/orchestration-state.json"
            activity_log = ".ai/state/orchestration-activity.log"
            max_log_entries = 500
        }
    }
}

function Save-OrchestrationConfig {
    param([object]$Config)

    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    $Config | ConvertTo-Json -Depth 5 | Set-Content $orchestrationPath -Encoding UTF8
    Write-Pass "Orchestration configuration saved to orchestration.json"
}

# ============================================================================
# Display Helpers
# ============================================================================

function Get-OnOff {
    param([bool]$Value)
    if ($Value) { return "ON" } else { return "OFF" }
}

function Get-OnOffColor {
    param([bool]$Value)
    if ($Value) { return "Green" } else { return "DarkGray" }
}

function Show-CurrentStatus {
    param([object]$Config)

    $parallelEnabled = $Config.patterns.parallel_execution.enabled
    $queueEnabled = $Config.patterns.task_queue.enabled
    $worktreeEnabled = $Config.patterns.worktree_isolation.enabled
    $specEnabled = $Config.role_specializations.enabled
    $observEnabled = $Config.observability.enabled

    Write-Host "  Current Status:" -ForegroundColor Cyan
    Write-Host "    Parallel Execution:  " -NoNewline
    Write-Host "$(Get-OnOff $parallelEnabled)" -ForegroundColor $(Get-OnOffColor $parallelEnabled)
    Write-Host "    Task Queue:          " -NoNewline
    Write-Host "$(Get-OnOff $queueEnabled)" -ForegroundColor $(Get-OnOffColor $queueEnabled)
    Write-Host "    Worktree Isolation:  " -NoNewline
    Write-Host "$(Get-OnOff $worktreeEnabled)" -ForegroundColor $(Get-OnOffColor $worktreeEnabled)
    Write-Host "    Role Specializations:" -NoNewline
    Write-Host " $(Get-OnOff $specEnabled)" -ForegroundColor $(Get-OnOffColor $specEnabled)
    Write-Host "    Observability:       " -NoNewline
    Write-Host "$(Get-OnOff $observEnabled)" -ForegroundColor $(Get-OnOffColor $observEnabled)
    Write-Host ""
}

function Show-FullConfig {
    param([object]$Config)

    Write-Header "Orchestration Pattern Configuration"
    Show-CurrentStatus -Config $Config

    Write-Host "  Parallel Execution:" -ForegroundColor White
    Write-Host "    Max parallel agents:     $($Config.patterns.parallel_execution.max_parallel_agents)"
    Write-Host "    Isolation method:        $($Config.patterns.parallel_execution.isolation_method)"
    Write-Host "    Min complexity:          $($Config.patterns.parallel_execution.min_task_complexity_for_parallel)"
    Write-Host "    Plan approval required:  $(Get-OnOff $Config.patterns.parallel_execution.plan_approval_required)"
    Write-Host "    Merge strategy:          $($Config.patterns.parallel_execution.merge_strategy)"
    Write-Host ""

    Write-Host "  Task Queue:" -ForegroundColor White
    Write-Host "    State directory:         $($Config.patterns.task_queue.state_directory)"
    Write-Host "    Max queue depth:         $($Config.patterns.task_queue.max_queue_depth)"
    Write-Host "    Retry on failure:        $(Get-OnOff $Config.patterns.task_queue.retry_on_failure)"
    Write-Host "    Max retries:             $($Config.patterns.task_queue.max_retries)"
    Write-Host "    Dependency tracking:     $(Get-OnOff $Config.patterns.task_queue.dependency_tracking)"
    Write-Host ""

    Write-Host "  Agent Spawning:" -ForegroundColor White
    Write-Host "    Max total agents:        $($Config.agent_spawning.max_total_agents)"
    Write-Host "    Max workers:             $($Config.agent_spawning.max_workers)"
    Write-Host "    Max validators:          $($Config.agent_spawning.max_validators)"
    Write-Host "    Max critics:             $($Config.agent_spawning.max_critics)"
    Write-Host "    Cooldown (seconds):      $($Config.agent_spawning.cooldown_between_spawns_seconds)"
    Write-Host "    Session timeout (min):   $($Config.agent_spawning.agent_session_timeout_minutes)"
    Write-Host "    Rotation after runs:     $($Config.agent_spawning.rotation_after_consecutive_runs)"
    Write-Host ""

    Write-Host "  Quality Gates:" -ForegroundColor White
    Write-Host "    Validator threshold:     $($Config.quality_gates.validator_threshold)"
    Write-Host "    Critic threshold:        $($Config.quality_gates.critic_threshold)"
    Write-Host "    Validate for parallel:   $(Get-OnOff $Config.quality_gates.require_validation_for_parallel)"
    Write-Host "    Critic before merge:     $(Get-OnOff $Config.quality_gates.require_critic_before_merge)"
    Write-Host "    Auto-approve T1:         $(Get-OnOff $Config.quality_gates.auto_approve_t1_tasks)"
    Write-Host ""

    Write-Host "  Routing Enhancements:" -ForegroundColor White
    Write-Host "    Speculative execution:   $(Get-OnOff $Config.routing_enhancements.speculative_execution)"
    Write-Host "    Domain routing:          $(Get-OnOff $Config.routing_enhancements.domain_routing_enabled)"
    Write-Host "    Prefer specialists:      $(Get-OnOff $Config.routing_enhancements.prefer_specialist_agents)"
    Write-Host "    Parallel threshold (min):$($Config.routing_enhancements.parallel_threshold_minutes)"
    Write-Host ""

    Write-Host "  Role Specializations:" -ForegroundColor White
    if ($Config.role_specializations.specializations) {
        $specs = $Config.role_specializations.specializations
        if ($specs.worker) { Write-Host "    Worker:    $($specs.worker -join ', ')" }
        if ($specs.validator) { Write-Host "    Validator: $($specs.validator -join ', ')" }
        if ($specs.critic) { Write-Host "    Critic:    $($specs.critic -join ', ')" }
    }
    Write-Host ""

    Write-Host "  Observability:" -ForegroundColor White
    Write-Host "    Log agent activity:      $(Get-OnOff $Config.observability.log_agent_activity)"
    Write-Host "    Log task transitions:    $(Get-OnOff $Config.observability.log_task_transitions)"
    Write-Host "    State file:              $($Config.observability.state_file)"
    Write-Host "    Activity log:            $($Config.observability.activity_log)"
    Write-Host "    Max log entries:         $($Config.observability.max_log_entries)"
    Write-Host ""
}

# ============================================================================
# Submenu Functions
# ============================================================================

function Show-ParallelMenu {
    param([object]$Config)

    while ($true) {
        Write-Header "Parallel Execution Configuration"

        $pe = $Config.patterns.parallel_execution
        Write-Host "  Current: $(Get-OnOff $pe.enabled)" -ForegroundColor $(Get-OnOffColor $pe.enabled)
        Write-Host "    Max parallel agents: $($pe.max_parallel_agents)"
        Write-Host "    Isolation method:    $($pe.isolation_method)"
        Write-Host "    Min complexity:      $($pe.min_task_complexity_for_parallel)"
        Write-Host "    Plan approval:       $(Get-OnOff $pe.plan_approval_required)"
        Write-Host "    Merge strategy:      $($pe.merge_strategy)"
        Write-Host ""
        Write-Host "  [1] Toggle enabled (currently $(Get-OnOff $pe.enabled))"
        Write-Host "  [2] Set max parallel agents (currently $($pe.max_parallel_agents))"
        Write-Host "  [3] Set min complexity (currently $($pe.min_task_complexity_for_parallel))"
        Write-Host "  [4] Toggle plan approval (currently $(Get-OnOff $pe.plan_approval_required))"
        Write-Host "  [B] Back"
        Write-Host ""
        Write-Host "Choice: " -NoNewline
        $choice = Read-Host

        switch ($choice.ToUpper()) {
            "1" {
                $Config.patterns.parallel_execution.enabled = -not $pe.enabled
                Write-Pass "Parallel execution: $(Get-OnOff $Config.patterns.parallel_execution.enabled)"
            }
            "2" {
                Write-Host "  Max parallel agents (1-5): " -NoNewline
                $val = Read-Host
                $num = [int]$val
                if ($num -ge 1 -and $num -le 5) {
                    $Config.patterns.parallel_execution.max_parallel_agents = $num
                    Write-Pass "Max parallel agents set to $num"
                } else {
                    Write-Warn "Invalid value. Must be 1-5."
                }
            }
            "3" {
                Write-Host "  Min complexity for parallel [T1/T2/T3]: " -NoNewline
                $val = Read-Host
                if ($val -in @("T1", "T2", "T3")) {
                    $Config.patterns.parallel_execution.min_task_complexity_for_parallel = $val
                    Write-Pass "Min complexity set to $val"
                } else {
                    Write-Warn "Invalid value. Must be T1, T2, or T3."
                }
            }
            "4" {
                $Config.patterns.parallel_execution.plan_approval_required = -not $pe.plan_approval_required
                Write-Pass "Plan approval: $(Get-OnOff $Config.patterns.parallel_execution.plan_approval_required)"
            }
            "B" { return $Config }
        }
    }
}

function Show-QueueMenu {
    param([object]$Config)

    while ($true) {
        Write-Header "Task Queue Configuration"

        $tq = $Config.patterns.task_queue
        Write-Host "  Current: $(Get-OnOff $tq.enabled)" -ForegroundColor $(Get-OnOffColor $tq.enabled)
        Write-Host "    Max queue depth:     $($tq.max_queue_depth)"
        Write-Host "    Retry on failure:    $(Get-OnOff $tq.retry_on_failure)"
        Write-Host "    Max retries:         $($tq.max_retries)"
        Write-Host "    Dependency tracking: $(Get-OnOff $tq.dependency_tracking)"
        Write-Host ""
        Write-Host "  [1] Toggle enabled (currently $(Get-OnOff $tq.enabled))"
        Write-Host "  [2] Set max queue depth (currently $($tq.max_queue_depth))"
        Write-Host "  [3] Toggle retry on failure (currently $(Get-OnOff $tq.retry_on_failure))"
        Write-Host "  [4] Set max retries (currently $($tq.max_retries))"
        Write-Host "  [5] Toggle dependency tracking (currently $(Get-OnOff $tq.dependency_tracking))"
        Write-Host "  [B] Back"
        Write-Host ""
        Write-Host "Choice: " -NoNewline
        $choice = Read-Host

        switch ($choice.ToUpper()) {
            "1" {
                $Config.patterns.task_queue.enabled = -not $tq.enabled
                Write-Pass "Task queue: $(Get-OnOff $Config.patterns.task_queue.enabled)"
            }
            "2" {
                Write-Host "  Max queue depth (5-50): " -NoNewline
                $val = Read-Host
                $num = [int]$val
                if ($num -ge 5 -and $num -le 50) {
                    $Config.patterns.task_queue.max_queue_depth = $num
                    Write-Pass "Max queue depth set to $num"
                } else {
                    Write-Warn "Invalid value. Must be 5-50."
                }
            }
            "3" {
                $Config.patterns.task_queue.retry_on_failure = -not $tq.retry_on_failure
                Write-Pass "Retry on failure: $(Get-OnOff $Config.patterns.task_queue.retry_on_failure)"
            }
            "4" {
                Write-Host "  Max retries (0-5): " -NoNewline
                $val = Read-Host
                $num = [int]$val
                if ($num -ge 0 -and $num -le 5) {
                    $Config.patterns.task_queue.max_retries = $num
                    Write-Pass "Max retries set to $num"
                } else {
                    Write-Warn "Invalid value. Must be 0-5."
                }
            }
            "5" {
                $Config.patterns.task_queue.dependency_tracking = -not $tq.dependency_tracking
                Write-Pass "Dependency tracking: $(Get-OnOff $Config.patterns.task_queue.dependency_tracking)"
            }
            "B" { return $Config }
        }
    }
}

function Show-SpawningMenu {
    param([object]$Config)

    while ($true) {
        Write-Header "Agent Spawning Limits"

        $as = $Config.agent_spawning
        Write-Host "  Max total agents:      $($as.max_total_agents)"
        Write-Host "  Max workers:           $($as.max_workers)"
        Write-Host "  Max validators:        $($as.max_validators)"
        Write-Host "  Max critics:           $($as.max_critics)"
        Write-Host "  Cooldown (seconds):    $($as.cooldown_between_spawns_seconds)"
        Write-Host "  Session timeout (min): $($as.agent_session_timeout_minutes)"
        Write-Host "  Rotation after runs:   $($as.rotation_after_consecutive_runs)"
        Write-Host ""
        Write-Host "  [1] Set max total agents (currently $($as.max_total_agents))"
        Write-Host "  [2] Set max workers (currently $($as.max_workers))"
        Write-Host "  [3] Set cooldown seconds (currently $($as.cooldown_between_spawns_seconds))"
        Write-Host "  [4] Set session timeout minutes (currently $($as.agent_session_timeout_minutes))"
        Write-Host "  [5] Set rotation threshold (currently $($as.rotation_after_consecutive_runs))"
        Write-Host "  [B] Back"
        Write-Host ""
        Write-Host "Choice: " -NoNewline
        $choice = Read-Host

        switch ($choice.ToUpper()) {
            "1" {
                Write-Host "  Max total agents (2-10): " -NoNewline
                $val = Read-Host
                $num = [int]$val
                if ($num -ge 2 -and $num -le 10) {
                    $Config.agent_spawning.max_total_agents = $num
                    Write-Pass "Max total agents set to $num"
                } else {
                    Write-Warn "Invalid value. Must be 2-10."
                }
            }
            "2" {
                Write-Host "  Max workers (1-5): " -NoNewline
                $val = Read-Host
                $num = [int]$val
                if ($num -ge 1 -and $num -le 5) {
                    $Config.agent_spawning.max_workers = $num
                    Write-Pass "Max workers set to $num"
                } else {
                    Write-Warn "Invalid value. Must be 1-5."
                }
            }
            "3" {
                Write-Host "  Cooldown between spawns in seconds (0-30): " -NoNewline
                $val = Read-Host
                $num = [int]$val
                if ($num -ge 0 -and $num -le 30) {
                    $Config.agent_spawning.cooldown_between_spawns_seconds = $num
                    Write-Pass "Cooldown set to $num seconds"
                } else {
                    Write-Warn "Invalid value. Must be 0-30."
                }
            }
            "4" {
                Write-Host "  Session timeout in minutes (10-120): " -NoNewline
                $val = Read-Host
                $num = [int]$val
                if ($num -ge 10 -and $num -le 120) {
                    $Config.agent_spawning.agent_session_timeout_minutes = $num
                    Write-Pass "Session timeout set to $num minutes"
                } else {
                    Write-Warn "Invalid value. Must be 10-120."
                }
            }
            "5" {
                Write-Host "  Rotate agent after consecutive runs (1-20): " -NoNewline
                $val = Read-Host
                $num = [int]$val
                if ($num -ge 1 -and $num -le 20) {
                    $Config.agent_spawning.rotation_after_consecutive_runs = $num
                    Write-Pass "Rotation threshold set to $num runs"
                } else {
                    Write-Warn "Invalid value. Must be 1-20."
                }
            }
            "B" { return $Config }
        }
    }
}

function Show-QualityGatesMenu {
    param([object]$Config)

    while ($true) {
        Write-Header "Quality Gates Configuration"

        $qg = $Config.quality_gates
        Write-Host "  Validator threshold:     $($qg.validator_threshold)"
        Write-Host "  Critic threshold:        $($qg.critic_threshold)"
        Write-Host "  Validate for parallel:   $(Get-OnOff $qg.require_validation_for_parallel)"
        Write-Host "  Critic before merge:     $(Get-OnOff $qg.require_critic_before_merge)"
        Write-Host "  Auto-approve T1:         $(Get-OnOff $qg.auto_approve_t1_tasks)"
        Write-Host ""
        Write-Host "  [1] Set validator threshold (currently $($qg.validator_threshold))"
        Write-Host "  [2] Set critic threshold (currently $($qg.critic_threshold))"
        Write-Host "  [3] Toggle validate for parallel (currently $(Get-OnOff $qg.require_validation_for_parallel))"
        Write-Host "  [4] Toggle critic before merge (currently $(Get-OnOff $qg.require_critic_before_merge))"
        Write-Host "  [5] Toggle auto-approve T1 tasks (currently $(Get-OnOff $qg.auto_approve_t1_tasks))"
        Write-Host "  [B] Back"
        Write-Host ""
        Write-Host "Choice: " -NoNewline
        $choice = Read-Host

        switch ($choice.ToUpper()) {
            "1" {
                Write-Host "  Validator threshold (0.0-1.0): " -NoNewline
                $val = Read-Host
                $num = [double]$val
                if ($num -ge 0.0 -and $num -le 1.0) {
                    $Config.quality_gates.validator_threshold = $num
                    Write-Pass "Validator threshold set to $num"
                } else {
                    Write-Warn "Invalid value. Must be 0.0-1.0."
                }
            }
            "2" {
                Write-Host "  Critic threshold (0.0-1.0): " -NoNewline
                $val = Read-Host
                $num = [double]$val
                if ($num -ge 0.0 -and $num -le 1.0) {
                    $Config.quality_gates.critic_threshold = $num
                    Write-Pass "Critic threshold set to $num"
                } else {
                    Write-Warn "Invalid value. Must be 0.0-1.0."
                }
            }
            "3" {
                $Config.quality_gates.require_validation_for_parallel = -not $qg.require_validation_for_parallel
                Write-Pass "Validate for parallel: $(Get-OnOff $Config.quality_gates.require_validation_for_parallel)"
            }
            "4" {
                $Config.quality_gates.require_critic_before_merge = -not $qg.require_critic_before_merge
                Write-Pass "Critic before merge: $(Get-OnOff $Config.quality_gates.require_critic_before_merge)"
            }
            "5" {
                $Config.quality_gates.auto_approve_t1_tasks = -not $qg.auto_approve_t1_tasks
                Write-Pass "Auto-approve T1: $(Get-OnOff $Config.quality_gates.auto_approve_t1_tasks)"
            }
            "B" { return $Config }
        }
    }
}

function Show-RoutingMenu {
    param([object]$Config)

    while ($true) {
        Write-Header "Routing & Specialization Configuration"

        $re = $Config.routing_enhancements
        $rs = $Config.role_specializations
        Write-Host "  Speculative execution:     $(Get-OnOff $re.speculative_execution)"
        Write-Host "  Domain routing:            $(Get-OnOff $re.domain_routing_enabled)"
        Write-Host "  Prefer specialists:        $(Get-OnOff $re.prefer_specialist_agents)"
        Write-Host "  Parallel threshold (min):  $($re.parallel_threshold_minutes)"
        Write-Host "  Role specializations:      $(Get-OnOff $rs.enabled)"
        Write-Host ""
        Write-Host "  [1] Toggle speculative execution (currently $(Get-OnOff $re.speculative_execution))"
        Write-Host "  [2] Toggle domain routing (currently $(Get-OnOff $re.domain_routing_enabled))"
        Write-Host "  [3] Toggle prefer specialists (currently $(Get-OnOff $re.prefer_specialist_agents))"
        Write-Host "  [4] Set parallel threshold minutes (currently $($re.parallel_threshold_minutes))"
        Write-Host "  [5] Toggle role specializations (currently $(Get-OnOff $rs.enabled))"
        Write-Host "  [B] Back"
        Write-Host ""
        Write-Host "Choice: " -NoNewline
        $choice = Read-Host

        switch ($choice.ToUpper()) {
            "1" {
                $Config.routing_enhancements.speculative_execution = -not $re.speculative_execution
                Write-Pass "Speculative execution: $(Get-OnOff $Config.routing_enhancements.speculative_execution)"
            }
            "2" {
                $Config.routing_enhancements.domain_routing_enabled = -not $re.domain_routing_enabled
                Write-Pass "Domain routing: $(Get-OnOff $Config.routing_enhancements.domain_routing_enabled)"
            }
            "3" {
                $Config.routing_enhancements.prefer_specialist_agents = -not $re.prefer_specialist_agents
                Write-Pass "Prefer specialists: $(Get-OnOff $Config.routing_enhancements.prefer_specialist_agents)"
            }
            "4" {
                Write-Host "  Parallel threshold in minutes (10-120): " -NoNewline
                $val = Read-Host
                $num = [int]$val
                if ($num -ge 10 -and $num -le 120) {
                    $Config.routing_enhancements.parallel_threshold_minutes = $num
                    Write-Pass "Parallel threshold set to $num minutes"
                } else {
                    Write-Warn "Invalid value. Must be 10-120."
                }
            }
            "5" {
                $Config.role_specializations.enabled = -not $rs.enabled
                Write-Pass "Role specializations: $(Get-OnOff $Config.role_specializations.enabled)"
            }
            "B" { return $Config }
        }
    }
}

function Show-ObservabilityMenu {
    param([object]$Config)

    while ($true) {
        Write-Header "Observability Configuration"

        $ob = $Config.observability
        Write-Host "  Enabled:               $(Get-OnOff $ob.enabled)"
        Write-Host "  Log agent activity:    $(Get-OnOff $ob.log_agent_activity)"
        Write-Host "  Log task transitions:  $(Get-OnOff $ob.log_task_transitions)"
        Write-Host "  Max log entries:       $($ob.max_log_entries)"
        Write-Host ""
        Write-Host "  [1] Toggle enabled (currently $(Get-OnOff $ob.enabled))"
        Write-Host "  [2] Toggle log agent activity (currently $(Get-OnOff $ob.log_agent_activity))"
        Write-Host "  [3] Toggle log task transitions (currently $(Get-OnOff $ob.log_task_transitions))"
        Write-Host "  [4] Set max log entries (currently $($ob.max_log_entries))"
        Write-Host "  [B] Back"
        Write-Host ""
        Write-Host "Choice: " -NoNewline
        $choice = Read-Host

        switch ($choice.ToUpper()) {
            "1" {
                $Config.observability.enabled = -not $ob.enabled
                Write-Pass "Observability: $(Get-OnOff $Config.observability.enabled)"
            }
            "2" {
                $Config.observability.log_agent_activity = -not $ob.log_agent_activity
                Write-Pass "Log agent activity: $(Get-OnOff $Config.observability.log_agent_activity)"
            }
            "3" {
                $Config.observability.log_task_transitions = -not $ob.log_task_transitions
                Write-Pass "Log task transitions: $(Get-OnOff $Config.observability.log_task_transitions)"
            }
            "4" {
                Write-Host "  Max log entries (100-5000): " -NoNewline
                $val = Read-Host
                $num = [int]$val
                if ($num -ge 100 -and $num -le 5000) {
                    $Config.observability.max_log_entries = $num
                    Write-Pass "Max log entries set to $num"
                } else {
                    Write-Warn "Invalid value. Must be 100-5000."
                }
            }
            "B" { return $Config }
        }
    }
}

function Apply-RecommendedDefaults {
    param([object]$Config)

    $Config.patterns.parallel_execution.enabled = $true
    $Config.patterns.parallel_execution.max_parallel_agents = 3
    $Config.patterns.parallel_execution.plan_approval_required = $true

    $Config.patterns.task_queue.enabled = $true
    $Config.patterns.task_queue.retry_on_failure = $true
    $Config.patterns.task_queue.max_retries = 2

    $Config.patterns.worktree_isolation.enabled = $true
    $Config.patterns.worktree_isolation.cleanup_on_completion = $true

    $Config.observability.enabled = $true
    $Config.observability.log_agent_activity = $true
    $Config.observability.log_task_transitions = $true

    Write-Pass "Applied recommended defaults:"
    Write-Info "  Parallel execution: ON (3 agents, plan approval required)"
    Write-Info "  Task queue: ON (retry enabled, 2 max retries)"
    Write-Info "  Worktree isolation: ON (auto-cleanup)"
    Write-Info "  Observability: ON (full logging)"

    return $Config
}

function Reset-ToSequential {
    param([object]$Config)

    $Config.patterns.parallel_execution.enabled = $false
    $Config.patterns.task_queue.enabled = $false
    $Config.patterns.worktree_isolation.enabled = $false
    $Config.role_specializations.enabled = $false
    $Config.routing_enhancements.domain_routing_enabled = $false

    Write-Pass "Reset to sequential mode:"
    Write-Info "  All parallel patterns disabled"
    Write-Info "  Domain routing disabled"
    Write-Info "  Role specializations disabled"

    return $Config
}

# ============================================================================
# Main Menu
# ============================================================================

function Show-OrchestrationMainMenu {
    param([object]$Config)

    while ($true) {
        Write-Header "Orchestration Pattern Configuration"
        Show-CurrentStatus -Config $Config

        Write-Host "  [1] Parallel Execution"
        Write-Host "  [2] Task Queue"
        Write-Host "  [3] Agent Spawning Limits"
        Write-Host "  [4] Quality Gates"
        Write-Host "  [5] Routing & Specialization"
        Write-Host "  [6] Observability"
        Write-Host ""
        Write-Host "  [7] Apply Recommended Defaults" -ForegroundColor Green
        Write-Host "  [8] Reset to Sequential" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  [V] View Full Configuration"
        Write-Host "  [S] Save & Back"
        Write-Host "  [B] Back (discard changes)"
        Write-Host ""
        Write-Host "Choice: " -NoNewline
        $choice = Read-Host

        switch ($choice.ToUpper()) {
            "1" { $Config = Show-ParallelMenu -Config $Config }
            "2" { $Config = Show-QueueMenu -Config $Config }
            "3" { $Config = Show-SpawningMenu -Config $Config }
            "4" { $Config = Show-QualityGatesMenu -Config $Config }
            "5" { $Config = Show-RoutingMenu -Config $Config }
            "6" { $Config = Show-ObservabilityMenu -Config $Config }
            "7" {
                $Config = Apply-RecommendedDefaults -Config $Config
                Write-Host ""
                Write-Host "  Press Enter to continue..." -NoNewline
                Read-Host
            }
            "8" {
                $Config = Reset-ToSequential -Config $Config
                Write-Host ""
                Write-Host "  Press Enter to continue..." -NoNewline
                Read-Host
            }
            "V" {
                Show-FullConfig -Config $Config
                Write-Host "  Press Enter to continue..." -NoNewline
                Read-Host
            }
            "S" {
                Save-OrchestrationConfig -Config $Config
                return $Config
            }
            "B" { return $null }
        }
    }
}

# ============================================================================
# Entry Point
# ============================================================================

$config = Get-OrchestrationConfig

if ($JsonOutput) {
    $config | ConvertTo-Json -Depth 5
    return
}

if ($ShowOnly) {
    Show-FullConfig -Config $config
    return
}

$result = Show-OrchestrationMainMenu -Config $config
if ($null -ne $result) {
    # Config was saved via the menu
} else {
    Write-Info "Changes discarded."
}
