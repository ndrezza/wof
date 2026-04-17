#!/usr/bin/env bash
# Install wof-cowork into Claude Desktop on macOS/Linux.
#
# Usage:
#   setup-cowork.sh [--project-dir <abs-path>] [--server-name <name>] [--dry-run]
#
# Idempotent: safe to re-run. See docs/cowork-bootstrap.md.

set -euo pipefail

# --- locate WOF root from script path ---
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
wof_root="$(cd "$script_dir/../.." && pwd)"

mcp_pkg="$wof_root/core/mcp/wof-cowork"
merger="$wof_root/core/scripts/cowork-config-merge.mjs"

# --- parse args ---
project_dir=""
server_name="wof-cowork"
dry_run=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir) project_dir="${2:-}"; shift 2 ;;
    --server-name) server_name="${2:-}"; shift 2 ;;
    --dry-run) dry_run="--dry-run"; shift ;;
    -h|--help)
      sed -n '2,10p' "$0"
      exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# --- verify node >= 20 ---
if ! command -v node >/dev/null 2>&1; then
  echo "error: 'node' not found on PATH. Install Node.js 20 or later." >&2
  exit 2
fi
node_major="$(node -p 'process.versions.node.split(".")[0]')"
if (( node_major < 20 )); then
  echo "error: Node.js ${node_major}.x found, but >= 20 required." >&2
  exit 2
fi

# --- build the MCP server ---
echo "[setup-cowork] Building wof-cowork MCP server ..."
(
  cd "$mcp_pkg"
  npm install
  npm run build
)

# --- collect project-dir ---
if [[ -z "$project_dir" ]]; then
  read -r -p "Project dir for headless subprocess [default: $wof_root]: " project_dir
  project_dir="${project_dir:-$wof_root}"
fi
if [[ ! -d "$project_dir" ]]; then
  echo "error: project dir does not exist: $project_dir" >&2
  exit 2
fi
project_dir="$(cd "$project_dir" && pwd)"

# --- compute claude desktop config path ---
case "$(uname -s)" in
  Darwin) config_path="$HOME/Library/Application Support/Claude/claude_desktop_config.json" ;;
  Linux)  config_path="$HOME/.config/Claude/claude_desktop_config.json" ;;
  *) echo "error: unsupported OS $(uname -s). Use setup-cowork.ps1 on Windows." >&2; exit 2 ;;
esac

server_path="$mcp_pkg/build/index.js"
data_dir="$mcp_pkg"

echo "[setup-cowork] Config: $config_path"
echo "[setup-cowork] Server name: $server_name"
echo "[setup-cowork] Server path: $server_path"
echo "[setup-cowork] Project dir: $project_dir"
echo "[setup-cowork] Data dir:    $data_dir"

# --- invoke merger ---
node "$merger" \
  --config "$config_path" \
  --server-name "$server_name" \
  --server-path "$server_path" \
  --project-dir "$project_dir" \
  --data-dir "$data_dir" \
  ${dry_run:+$dry_run}

if [[ -z "$dry_run" ]]; then
  cat <<EOF

[setup-cowork] Done.
Next:
  1. Fully quit Claude Desktop (not just close the window) and relaunch.
  2. In chat, ask: "list your available MCP tools" — confirm
     "${server_name}" tools are present.
  3. Submit a smoke-test task and check get_log.
EOF
fi
