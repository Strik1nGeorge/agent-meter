#!/bin/sh
# Starts the local service in the background, unless it is already running, and opens the dashboard.
# The macOS / Linux counterpart of start.ps1; --no-browser skips the browser (the Mac widget uses it).
# Set PORT for another port and NODE to pick the Node.js binary.
set -eu
root=$(cd "$(dirname "$0")" && pwd)
cd "$root"
port=${PORT:-4318}
url="http://127.0.0.1:$port"
backend=${AGENT_METER_BACKEND:-auto}
rust_bin="$root/rust/bin/agent-meter"
[ -x "$rust_bin" ] || rust_bin="$root/rust/target/release/agent-meter"
case "$backend" in
  auto) if [ -x "$rust_bin" ]; then backend=rust; else backend=node; fi ;;
  rust|node) ;;
  *) echo "AGENT_METER_BACKEND must be auto, rust, or node." >&2; exit 1 ;;
esac

if [ "$backend" = rust ]; then
  if [ ! -x "$rust_bin" ]; then echo 'Build Rust with cargo build --release --manifest-path rust/Cargo.toml.' >&2; exit 1; fi
  service=$rust_bin
  argument=serve
else
  # Finder gives apps a minimal PATH. Keep the existing Node discovery for the fallback backend.
  node_bin=${NODE:-}
  [ -n "$node_bin" ] || node_bin=$(command -v node 2>/dev/null || true)
  if [ -z "$node_bin" ]; then
    for candidate in /opt/homebrew/bin/node /usr/local/bin/node /opt/local/bin/node "$HOME/.volta/bin/node" $(ls -d "$HOME"/.nvm/versions/node/*/bin/node 2>/dev/null | sort -V | tail -n 1); do
      if [ -x "$candidate" ]; then node_bin=$candidate; break; fi
    done
  fi
  if [ -z "$node_bin" ]; then
    found=$(mktemp "${TMPDIR:-/tmp}/agent-meter.XXXXXX")
    "${SHELL:-/bin/zsh}" -ilc 'command -v node' >"$found" 2>/dev/null </dev/null &
    shell_pid=$!
    waited=0
    while kill -0 "$shell_pid" 2>/dev/null && [ "$waited" -lt 50 ]; do sleep 0.1; waited=$((waited + 1)); done
    kill "$shell_pid" 2>/dev/null || true
    candidate=$(tail -n 1 "$found")
    rm -f "$found"
    if [ -x "$candidate" ]; then node_bin=$candidate; fi
  fi
  if [ -z "$node_bin" ]; then echo "Node.js 22 or newer is required." >&2; exit 1; fi
  service=$node_bin
  argument="$root/server.mjs"
fi

read_health() { curl -fsS --max-time 2 "$url/api/health" 2>/dev/null; }
matches_backend() {
  case "$1" in *'"ok":true'*) ;; *) return 1 ;; esac
  case "$1" in *'"backend":"rust"'*) [ "$backend" = rust ] ;; *) [ "$backend" = node ] ;; esac
}
healthy() { matches_backend "$(read_health || true)"; }

if ! healthy; then
  case "$(read_health || true)" in
    *'"ok":true'*) echo "A different Agent Meter backend is using port $port. Set PORT to run alongside it." >&2; exit 1 ;;
  esac
  mkdir -p .data
  PORT=$port nohup "$service" "$argument" >.data/server.log 2>.data/server-error.log &
  echo $! >.data/server.pid
  tries=0
  while [ "$tries" -lt 30 ] && ! healthy; do sleep 0.3; tries=$((tries + 1)); done
fi

if healthy; then
  if [ "${1:-}" != "--no-browser" ]; then
    if command -v open >/dev/null 2>&1; then open "$url"
    elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$url" >/dev/null 2>&1 &
    fi
  fi
  echo "Agent Meter ($backend): $url"
else
  echo "Startup failed. Check .data/server-error.log." >&2
  exit 1
fi
