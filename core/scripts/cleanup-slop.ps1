# ============================================================================
# WOF MANAGED FILE - DO NOT EDIT MANUALLY
# This file is managed by the Workload Orchestration Framework.
# Changes will be overwritten on the next WOF sync/update.
# To customize behavior, use configuration files in .ai/config/
# ============================================================================

# Cleanup Slop Script
#
# Scans for common AI-generated artifacts in tracked files:
# - Debug logging statements (console.log, print, Write-Host)
# - AI-generated TODO comments (vague placeholders)
# - Inline lint/type suppressions (eslint-disable, noqa, type: ignore)
#
# Usage:
#   & '.\cleanup-slop.ps1' -DryRun                    # Preview findings
#   & '.\cleanup-slop.ps1' -Categories "debug-logs"    # Clean only debug logs
#   & '.\cleanup-slop.ps1' -JsonOutput                 # Machine-readable output

param(
    [string]$Path = ".",
    [switch]$DryRun,
    [string[]]$Categories = @("debug-logs", "todos", "suppressions"),
    [switch]$JsonOutput
)

$ErrorActionPreference = "Stop"

# Handle comma-separated categories passed as a single string (e.g., from bash)
$Categories = $Categories | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }

# --- Pattern definitions ---

$patterns = @{
    "debug-logs" = @(
        @{ regex = 'console\.(log|debug|warn|info)\s*\(';  ext = @('.js','.ts','.jsx','.tsx','.mjs','.cjs'); desc = "console.log/debug/warn/info" }
        @{ regex = '^\s*print\s*\(';                         ext = @('.py');                                    desc = "print() statement" }
        @{ regex = 'Write-Host\s';                           ext = @('.ps1');                                   desc = "Write-Host statement" }
        @{ regex = 'Write-Debug\s';                          ext = @('.ps1');                                   desc = "Write-Debug statement" }
    )
    "todos" = @(
        @{ regex = '(//|#)\s*TODO\s*:?\s*(implement|add\s+(error\s+)?handling|fix\s+(this\s+)?later|placeholder|stub|hack|temporary|remove\s+this)'; ext = @('.js','.ts','.jsx','.tsx','.py','.ps1','.cs','.java','.go','.rb','.rs'); desc = "AI-generated TODO" }
    )
    "suppressions" = @(
        @{ regex = 'eslint-disable';     ext = @('.js','.ts','.jsx','.tsx','.mjs','.cjs'); desc = "eslint-disable" }
        @{ regex = '#\s*noqa';           ext = @('.py');                                    desc = "noqa suppression" }
        @{ regex = '#\s*type:\s*ignore'; ext = @('.py');                                    desc = "type: ignore" }
        @{ regex = 'noinspection';       ext = @('.java','.kt');                            desc = "noinspection" }
        @{ regex = '@suppress';          ext = @('.java','.kt');                            desc = "@suppress" }
    )
}

# --- Get tracked files ---

Push-Location $Path
try {
    $trackedFiles = git ls-files 2>$null
    if (-not $trackedFiles) {
        if ($JsonOutput) {
            @{ findings = @(); summary = @{ total = 0; by_type = @{} }; error = "No git-tracked files found" } | ConvertTo-Json -Depth 5
        } else {
            Write-Output "No git-tracked files found in '$Path'."
        }
        return
    }
} finally {
    Pop-Location
}

# --- Scan ---

$findings = @()

foreach ($category in $Categories) {
    if (-not $patterns.ContainsKey($category)) {
        Write-Warning "Unknown category: $category (valid: debug-logs, todos, suppressions)"
        continue
    }

    foreach ($patternDef in $patterns[$category]) {
        $regex = $patternDef.regex
        $validExts = $patternDef.ext
        $desc = $patternDef.desc

        foreach ($relFile in $trackedFiles) {
            $ext = [System.IO.Path]::GetExtension($relFile)
            if ($validExts -and $ext -notin $validExts) { continue }

            $fullPath = Join-Path $Path $relFile
            if (-not (Test-Path $fullPath)) { continue }

            $lineNum = 0
            foreach ($line in (Get-Content $fullPath -ErrorAction SilentlyContinue)) {
                $lineNum++
                if ($line -match $regex) {
                    $findings += [PSCustomObject]@{
                        file     = $relFile
                        line     = $lineNum
                        type     = $category
                        pattern  = $desc
                        text     = $line.Trim()
                    }
                }
            }
        }
    }
}

# --- Summarize ---

$byType = @{}
foreach ($f in $findings) {
    if (-not $byType.ContainsKey($f.type)) { $byType[$f.type] = 0 }
    $byType[$f.type]++
}

$summary = [PSCustomObject]@{
    total   = $findings.Count
    by_type = $byType
}

# --- Output ---

if ($JsonOutput) {
    [PSCustomObject]@{
        dry_run  = [bool]$DryRun
        findings = $findings
        summary  = $summary
    } | ConvertTo-Json -Depth 5
    return
}

if ($findings.Count -eq 0) {
    Write-Output "No slop found. Codebase is clean."
    return
}

# Human-readable output
Write-Output "=== Slop Scan Results ==="
Write-Output "Found $($findings.Count) item(s) across $($byType.Count) category(ies):"
Write-Output ""

foreach ($cat in $byType.Keys) {
    Write-Output "  [$cat] $($byType[$cat]) finding(s)"
}
Write-Output ""

foreach ($f in $findings) {
    Write-Output "  $($f.file):$($f.line) [$($f.type)] $($f.pattern)"
    Write-Output "    $($f.text)"
    Write-Output ""
}

if ($DryRun) {
    Write-Output "--- DRY RUN: No files were modified ---"
    return
}

# --- Clean (non-dry-run) ---

$cleaned = 0
$fileGroups = $findings | Group-Object -Property file

foreach ($group in $fileGroups) {
    $filePath = Join-Path $Path $group.Name
    $lines = Get-Content $filePath
    $linesToRemove = $group.Group | ForEach-Object { $_.line }

    $newLines = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if (($i + 1) -notin $linesToRemove) {
            $newLines += $lines[$i]
        } else {
            $cleaned++
        }
    }

    Set-Content -Path $filePath -Value $newLines -Encoding UTF8
}

Write-Output "--- Cleaned $cleaned line(s) from $($fileGroups.Count) file(s) ---"
