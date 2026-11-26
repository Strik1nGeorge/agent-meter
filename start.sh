#!/bin/sh
# Starts the local service in the background, unless it is already running, and opens the dashboard.
# The macOS / Linux counterpart of start.ps1; --no-browser skips the browser (the Mac widget uses it).
# Set PORT for another port and NODE to pick the Node.js binary.
set -eu
root=$(cd "$(dirname "$0")" && pwd)
cd "$root"
port=${PORT:-4318}
url="http://127.0.0.1:$port"

# Apps started from Finder get a minimal PATH, so look where Node.js installers usually put it.
node_bin=${NODE:-}
[ -n "$node_bin" ] || node_bin=$(command -v node 2>/dev/null || true)
if [ -z "$node_bin" ]; then
  for candidate in /opt/homebrew/bin/node /usr/local/bin/node /opt/local/bin/node "$HOME/.volta/bin/node" $(ls -d "$HOME"/.nvm/versions/node/*/bin/node 2>/dev/null | sort -V | tail -n 1); do
    if [ -x "$candidate" ]; then node_bin=$candidate; break; fi
  done
fi
if [ -z "$node_bin" ]; then
  # Then ask an interactive login shell, which reads the profile files where version managers such as fnm,
  # asdf and mise put Node.js on the PATH. It runs in the background, given five seconds, so a profile that
  # waits for input can't hold up startup.
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

healthy() { curl -fsS --max-time 2 "$url/api/health" 2>/dev/null | grep -q '"ok":true'; }

if ! healthy; then
  mkdir -p .data
  PORT=$port nohup "$node_bin" "$root/server.mjs" >.data/server.log 2>.data/server-error.log &
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
  echo "Agent Meter: $url"
else
  echo "Startup failed. Check .data/server-error.log." >&2
  exit 1
fi
