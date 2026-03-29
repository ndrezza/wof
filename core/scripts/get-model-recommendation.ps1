<#
.SYNOPSIS
    WOF Model Recommendation Engine — ranks models for WOF roles.

.DESCRIPTION
    Loads core/data/model-capabilities.json and provides weighted scoring
    to recommend optimal model-to-role mappings based on mode (autonomy,
    cost, quality, balanced).

    This is the entry point that configure-wizard.ps1 (#2998) will call.

.PARAMETER Role
    Rank models for a specific WOF role (primary, worker-heavy, worker-lite, validator, critic).

.PARAMETER Mode
    Weighting strategy: autonomy, cost, quality, balanced (default: balanced).

.PARAMETER Model
    Get full details for a single model by name.

.PARAMETER AvailableModels
    Constrain recommendations to only these model names.

.PARAMETER RecommendAll
    Recommend a model mapping for all 5 WOF roles at once.

.PARAMETER ListModels
    List all models with a summary table.

.PARAMETER Provider
    Filter by provider: anthropic, openai, ollama, all (default: all).

.PARAMETER JsonOutput
    Emit machine-readable JSON instead of formatted text.

.EXAMPLE
    .\get-model-recommendation.ps1 -ListModels
    .\get-model-recommendation.ps1 -Role primary -Mode autonomy
    .\get-model-recommendation.ps1 -RecommendAll -Mode cost -JsonOutput
    .\get-model-recommendation.ps1 -Model "claude-opus-4-6"
#>
[CmdletBinding(DefaultParameterSetName = 'List')]
param(
    [Parameter(ParameterSetName = 'Role')]
    [ValidateSet('primary', 'worker-heavy', 'worker-lite', 'validator', 'critic')]
    [string]$Role,

    [ValidateSet('autonomy', 'cost', 'quality', 'balanced')]
    [string]$Mode = 'balanced',

    [Parameter(ParameterSetName = 'Model')]
    [string]$Model,

    [string[]]$AvailableModels,

    [Parameter(ParameterSetName = 'RecommendAll')]
    [switch]$RecommendAll,

    [Parameter(ParameterSetName = 'List')]
    [switch]$ListModels,

    [ValidateSet('anthropic', 'openai', 'ollama', 'all')]
    [string]$Provider = 'all',

    [switch]$JsonOutput
)

# ── Locate data file ──────────────────────────────────────────────────
$dataFile = Join-Path $PSScriptRoot '..\data\model-capabilities.json'
if (-not (Test-Path $dataFile)) {
    Write-Error "Model capabilities file not found: $dataFile"
    exit 1
}

$data = Get-Content $dataFile -Raw | ConvertFrom-Json

# ── Helper: get filtered model list ───────────────────────────────────
function Get-FilteredModels {
    param($Data, $Provider, $AvailableModels)

    $models = @{}
    foreach ($prop in $Data.models.PSObject.Properties) {
        $m = $prop.Value
        # Provider filter
        if ($Provider -ne 'all' -and $m.provider -ne $Provider) { continue }
        # Available models filter
        if ($AvailableModels -and $AvailableModels.Count -gt 0 -and $prop.Name -notin $AvailableModels) { continue }
        $models[$prop.Name] = $m
    }
    return $models
}

# ── Helper: get dimension weights for a mode ──────────────────────────
function Get-ModeWeights {
    param([string]$Mode)

    switch ($Mode) {
        'autonomy' {
            return @{
                coding              = 1.0
                reasoning           = 2.0
                speed               = 1.0
                cost_efficiency     = 0.0
                instruction_following = 2.0
                context_handling    = 1.0
            }
        }
        'cost' {
            return @{
                coding              = 1.0
                reasoning           = 1.0
                speed               = 1.5
                cost_efficiency     = 3.0
                instruction_following = 1.0
                context_handling    = 1.0
            }
        }
        'quality' {
            return @{
                coding              = 2.0
                reasoning           = 2.0
                speed               = 1.0
                cost_efficiency     = 0.0
                instruction_following = 1.0
                context_handling    = 1.0
            }
        }
        default { # balanced
            return @{
                coding              = 1.5
                reasoning           = 1.5
                speed               = 1.0
                cost_efficiency     = 1.0
                instruction_following = 1.0
                context_handling    = 1.0
            }
        }
    }
}

# ── Helper: compute weighted score for a model + role ─────────────────
function Get-WeightedScore {
    param($ModelEntry, [string]$RoleName, [hashtable]$Weights)

    $scores = $ModelEntry.scores
    $weightedSum = 0.0
    $totalWeight = 0.0

    foreach ($dim in $Weights.Keys) {
        $w = $Weights[$dim]
        if ($w -le 0) { continue }
        $val = $scores.$dim
        if ($null -eq $val) { $val = 0 }
        $weightedSum += $val * $w
        $totalWeight += $w
    }

    $dimScore = if ($totalWeight -gt 0) { $weightedSum / $totalWeight } else { 0 }

    # Add role_fitness bonus (weighted 40% of final score)
    $roleFit = 0
    if ($ModelEntry.role_fitness -and $ModelEntry.role_fitness.$RoleName) {
        $roleFit = $ModelEntry.role_fitness.$RoleName
    }

    return [math]::Round($dimScore * 0.6 + $roleFit * 0.4, 2)
}

# ── Helper: format model summary line ─────────────────────────────────
function Format-ModelSummary {
    param($Name, $Entry)
    $type = if ($Entry.type -eq 'cloud') { 'cloud' } else { 'local' }
    $ctx = if ($Entry.context_window -ge 1000000) { '1M' }
           elseif ($Entry.context_window -ge 100000) { "$([math]::Floor($Entry.context_window / 1000))K" }
           else { "$([math]::Floor($Entry.context_window / 1024))K" }

    $provStr = $Entry.provider.PadRight(9)
    $typeStr = $type.PadRight(5)
    $nameStr = $Name.PadRight(25)
    $famStr  = $Entry.family.PadRight(10)

    return "$nameStr $provStr $typeStr $famStr ctx:$ctx  quality:$($Entry.quality_tier)"
}

# ══════════════════════════════════════════════════════════════════════
# ── COMMAND: -ListModels ──────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════════
if ($PSCmdlet.ParameterSetName -eq 'List' -or $ListModels) {
    $models = Get-FilteredModels -Data $data -Provider $Provider -AvailableModels $AvailableModels

    if ($JsonOutput) {
        $result = @()
        foreach ($name in ($models.Keys | Sort-Object)) {
            $m = $models[$name]
            $result += @{
                name           = $name
                provider       = $m.provider
                type           = $m.type
                family         = $m.family
                context_window = $m.context_window
                quality_tier   = $m.quality_tier
                speed_tier     = $m.speed_tier
                scores         = $m.scores
                role_fitness   = $m.role_fitness
            }
        }
        $result | ConvertTo-Json -Depth 5
        return
    }

    Write-Host ""
    Write-Host "WOF Model Capabilities v$($data.version) ($($models.Count) models)" -ForegroundColor Cyan
    Write-Host ("=" * 80)

    # Group by provider
    $grouped = $models.GetEnumerator() | Group-Object { $_.Value.provider } | Sort-Object Name
    foreach ($group in $grouped) {
        Write-Host ""
        Write-Host "  [$($group.Name.ToUpper())]" -ForegroundColor Yellow
        foreach ($entry in ($group.Group | Sort-Object Key)) {
            Write-Host "    $(Format-ModelSummary -Name $entry.Key -Entry $entry.Value)"
        }
    }
    Write-Host ""
    return
}

# ══════════════════════════════════════════════════════════════════════
# ── COMMAND: -Model <name> ────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════════
if ($PSCmdlet.ParameterSetName -eq 'Model') {
    $entry = $data.models.$Model
    if (-not $entry) {
        Write-Error "Model '$Model' not found in capabilities database."
        exit 1
    }

    if ($JsonOutput) {
        @{ name = $Model; details = $entry } | ConvertTo-Json -Depth 5
        return
    }

    Write-Host ""
    Write-Host "Model: $Model" -ForegroundColor Cyan
    Write-Host ("=" * 60)
    Write-Host "  Provider:       $($entry.provider)"
    Write-Host "  Type:           $($entry.type)"
    Write-Host "  Family:         $($entry.family)"
    Write-Host "  Parameters:     $($entry.parameters)"
    Write-Host "  Context:        $($entry.context_window)"
    Write-Host "  Max Output:     $($entry.max_output)"
    Write-Host "  Quality Tier:   $($entry.quality_tier)"
    Write-Host "  Speed Tier:     $($entry.speed_tier)"

    if ($entry.pricing) {
        Write-Host "  Pricing:        `$$($entry.pricing.input_per_mtok)/MTok in, `$$($entry.pricing.output_per_mtok)/MTok out"
    } else {
        Write-Host "  Pricing:        Free (local)"
    }

    if ($entry.ram_required_gb) {
        Write-Host "  RAM Required:   $($entry.ram_required_gb) GB"
    }

    Write-Host ""
    Write-Host "  Scores:" -ForegroundColor Yellow
    foreach ($dim in @('coding', 'reasoning', 'speed', 'cost_efficiency', 'instruction_following', 'context_handling')) {
        $val = $entry.scores.$dim
        $bar = '#' * $val + '-' * (10 - $val)
        Write-Host "    $($dim.PadRight(22)) [$bar] $val/10"
    }

    Write-Host ""
    Write-Host "  Role Fitness:" -ForegroundColor Yellow
    foreach ($r in @('primary', 'worker-heavy', 'worker-lite', 'validator', 'critic')) {
        $val = $entry.role_fitness.$r
        $bar = '#' * $val + '-' * (10 - $val)
        Write-Host "    $($r.PadRight(15)) [$bar] $val/10"
    }

    Write-Host ""
    Write-Host "  Strengths:  $($entry.strengths -join ', ')"
    Write-Host "  Weaknesses: $($entry.weaknesses -join ', ')"
    Write-Host "  Notes:      $($entry.notes)"
    Write-Host ""
    return
}

# ══════════════════════════════════════════════════════════════════════
# ── COMMAND: -Role <name> ─────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════════
if ($PSCmdlet.ParameterSetName -eq 'Role') {
    $models = Get-FilteredModels -Data $data -Provider $Provider -AvailableModels $AvailableModels
    $weights = Get-ModeWeights -Mode $Mode

    $ranked = @()
    foreach ($name in $models.Keys) {
        $m = $models[$name]
        $score = Get-WeightedScore -ModelEntry $m -RoleName $Role -Weights $weights
        $ranked += [PSCustomObject]@{
            Name     = $name
            Score    = $score
            Provider = $m.provider
            Type     = $m.type
            Fitness  = $m.role_fitness.$Role
        }
    }

    $ranked = $ranked | Sort-Object Score -Descending

    if ($JsonOutput) {
        $result = @{
            role    = $Role
            mode    = $Mode
            ranking = @()
        }
        foreach ($r in $ranked) {
            $result.ranking += @{
                model        = $r.Name
                score        = $r.Score
                role_fitness = $r.Fitness
                provider     = $r.Provider
                type         = $r.Type
            }
        }
        $result | ConvertTo-Json -Depth 5
        return
    }

    Write-Host ""
    Write-Host "Top models for [$Role] (mode: $Mode)" -ForegroundColor Cyan
    Write-Host ("=" * 70)
    Write-Host "  Rank  Model                      Score  Fitness  Provider   Type"
    Write-Host "  ----  -------------------------  -----  -------  ---------  -----"

    $rank = 1
    foreach ($r in $ranked) {
        $marker = if ($rank -le 3) { '*' } else { ' ' }
        $color = if ($rank -eq 1) { 'Green' } elseif ($rank -le 3) { 'Yellow' } else { 'White' }
        $line = "  $marker$($rank.ToString().PadLeft(3))  $($r.Name.PadRight(25))  $($r.Score.ToString('0.00').PadLeft(5))  $($r.Fitness.ToString().PadLeft(7))  $($r.Provider.PadRight(9))  $($r.Type)"
        Write-Host $line -ForegroundColor $color
        $rank++
    }
    Write-Host ""
    return
}

# ══════════════════════════════════════════════════════════════════════
# ── COMMAND: -RecommendAll ────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════════
if ($RecommendAll) {
    $models = Get-FilteredModels -Data $data -Provider $Provider -AvailableModels $AvailableModels
    $weights = Get-ModeWeights -Mode $Mode
    $roles = @('primary', 'worker-heavy', 'worker-lite', 'validator', 'critic')

    $assignments = @{}
    $assignedModels = @{}

    foreach ($roleName in $roles) {
        $ranked = @()
        foreach ($name in $models.Keys) {
            $m = $models[$name]
            $score = Get-WeightedScore -ModelEntry $m -RoleName $roleName -Weights $weights

            # Diversity bonus: validator and critic get a small bonus for different provider than worker-heavy
            if ($roleName -in @('validator', 'critic') -and $assignedModels['worker-heavy']) {
                $whProvider = $models[$assignedModels['worker-heavy']].provider
                if ($m.provider -ne $whProvider) {
                    $score += 0.5
                }
            }

            $ranked += [PSCustomObject]@{
                Name     = $name
                Score    = [math]::Round($score, 2)
                Provider = $m.provider
                Type     = $m.type
                Fitness  = $m.role_fitness.$roleName
            }
        }

        $ranked = $ranked | Sort-Object Score -Descending
        $best = $ranked[0]
        $assignments[$roleName] = @{
            model        = $best.Name
            score        = $best.Score
            role_fitness = $best.Fitness
            provider     = $best.Provider
            type         = $best.Type
        }
        $assignedModels[$roleName] = $best.Name
    }

    if ($JsonOutput) {
        $result = @{
            mode        = $Mode
            provider    = $Provider
            assignments = $assignments
        }
        $result | ConvertTo-Json -Depth 5
        return
    }

    Write-Host ""
    Write-Host "Recommended Model Mapping (mode: $Mode, provider: $Provider)" -ForegroundColor Cyan
    Write-Host ("=" * 70)
    Write-Host ""

    foreach ($roleName in $roles) {
        $a = $assignments[$roleName]
        Write-Host "  $($roleName.PadRight(15))" -ForegroundColor Yellow -NoNewline
        Write-Host " -> " -NoNewline
        Write-Host "$($a.model)" -ForegroundColor Green -NoNewline
        Write-Host "  (score: $($a.score), fitness: $($a.role_fitness), $($a.provider)/$($a.type))"
    }

    Write-Host ""
    return
}

# If no valid parameter set matched, show help
Write-Host "Usage: get-model-recommendation.ps1 [-ListModels] [-Role <name>] [-RecommendAll] [-Model <name>]"
Write-Host "       [-Mode <autonomy|cost|quality|balanced>] [-Provider <anthropic|openai|ollama|all>]"
Write-Host "       [-AvailableModels <name[]>] [-JsonOutput]"
Write-Host ""
Write-Host "Run 'Get-Help .\get-model-recommendation.ps1 -Full' for details."
