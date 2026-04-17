<#
.SYNOPSIS
    Install wof-cowork into Claude Desktop on Windows.

.DESCRIPTION
    Builds core/mcp/wof-cowork and merges an entry into Claude Desktop's
    claude_desktop_config.json. Idempotent — safe to re-run.
    See docs/cowork-bootstrap.md for the full guide.

.PARAMETER ProjectDir
    Absolute path to the repo the headless subprocess operates against.
    Defaults to the WOF clone itself.

.PARAMETER ServerName
    Key under mcpServers in the Claude Desktop config.
    Defaults to "wof-cowork".

.PARAMETER DryRun
    Print the planned config change without writing.
#>
[CmdletBinding()]
param(
    [string]$ProjectDir = "",
    [string]$ServerName = "wof-cowork",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# --- locate WOF root from script path ---
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$wofRoot = (Resolve-Path (Join-Path $scriptDir "..\..")).Path
$mcpPkg = Join-Path $wofRoot "core\mcp\wof-cowork"
$merger = Join-Path $wofRoot "core\scripts\cowork-config-merge.mjs"

# --- verify node >= 20 ---
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeCmd) {
    Write-Error "'node' not found on PATH. Install Node.js 20 or later."
    exit 2
}
$nodeMajor = [int](& node -p "process.versions.node.split('.')[0]")
if ($nodeMajor -lt 20) {
    Write-Error "Node.js $nodeMajor.x found, but >= 20 required."
    exit 2
}

# --- build the MCP server ---
Write-Host "[setup-cowork] Building wof-cowork MCP server ..."
Push-Location $mcpPkg
try {
    & npm install
    if ($LASTEXITCODE -ne 0) { throw "npm install failed" }
    & npm run build
    if ($LASTEXITCODE -ne 0) { throw "npm run build failed" }
} finally {
    Pop-Location
}

# --- collect project-dir ---
if ([string]::IsNullOrWhiteSpace($ProjectDir)) {
    $answer = Read-Host "Project dir for headless subprocess [default: $wofRoot]"
    if ([string]::IsNullOrWhiteSpace($answer)) {
        $ProjectDir = $wofRoot
    } else {
        $ProjectDir = $answer
    }
}
if (-not (Test-Path $ProjectDir -PathType Container)) {
    Write-Error "project dir does not exist: $ProjectDir"
    exit 2
}
$ProjectDir = (Resolve-Path $ProjectDir).Path

# --- Claude Desktop requires forward slashes in JSON "args" on Windows ---
function ConvertTo-ForwardSlash([string]$p) {
    return $p -replace '\\', '/'
}

$configPath = Join-Path $env:APPDATA "Claude\claude_desktop_config.json"
$serverPath = ConvertTo-ForwardSlash (Join-Path $mcpPkg "build\index.js")
$dataDir    = ConvertTo-ForwardSlash $mcpPkg
$projectFwd = ConvertTo-ForwardSlash $ProjectDir

Write-Host "[setup-cowork] Config:      $configPath"
Write-Host "[setup-cowork] Server name: $ServerName"
Write-Host "[setup-cowork] Server path: $serverPath"
Write-Host "[setup-cowork] Project dir: $projectFwd"
Write-Host "[setup-cowork] Data dir:    $dataDir"

# --- invoke merger ---
$mergerArgs = @(
    $merger,
    "--config", $configPath,
    "--server-name", $ServerName,
    "--server-path", $serverPath,
    "--project-dir", $projectFwd,
    "--data-dir", $dataDir
)
if ($DryRun) { $mergerArgs += "--dry-run" }

& node @mergerArgs
$mergeExit = $LASTEXITCODE
if ($mergeExit -ne 0) { exit $mergeExit }

if (-not $DryRun) {
    Write-Host ""
    Write-Host "[setup-cowork] Done."
    Write-Host "Next:"
    Write-Host "  1. Fully quit Claude Desktop (tray icon -> Quit) and relaunch."
    Write-Host "  2. In chat, ask: `"list your available MCP tools`" — confirm"
    Write-Host "     `"$ServerName`" tools are present."
    Write-Host "  3. Submit a smoke-test task and check get_log."
}
