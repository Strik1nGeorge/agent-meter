#!/bin/sh
# Stops the service that start.sh started, and nothing else. The macOS / Linux counterpart of stop.ps1.
set -eu
root=$(cd "$(dirname "$0")" && pwd)
pid_file="$root/.data/server.pid"
if [ ! -f "$pid_file" ]; then echo "No server started by the launcher was found."; exit 0; fi
pid=$(cat "$pid_file")
if ps -p "$pid" -o command= 2>/dev/null | grep -qF "$root/server.mjs"; then
  # The Codex quota reader runs as a child of the service.
  pkill -P "$pid" -f 'app-server' 2>/dev/null || true
  kill "$pid"
  echo "Agent Meter stopped."
else
  echo "No matching Agent Meter process; other processes were left alone."
fi
rm -f "$pid_file"
