#!/bin/sh
# Stops the service that start.sh started, and nothing else. The macOS / Linux counterpart of stop.ps1.
set -eu
root=$(cd "$(dirname "$0")" && pwd)
pid_file="$root/.data/server.pid"
if [ ! -f "$pid_file" ]; then echo "No server started by the launcher was found."; exit 0; fi
pid=$(cat "$pid_file")
command=$(ps -p "$pid" -o command= 2>/dev/null || true)
case "$command" in
  *"$root/server.mjs")
    pkill -P "$pid" -f 'app-server' 2>/dev/null || true
    kill "$pid"
    echo "Agent Meter stopped."
    ;;
  "$root/rust/target/release/agent-meter serve"|"$root/rust/bin/agent-meter serve")
    kill "$pid"
    echo "Agent Meter stopped."
    ;;
  *) echo "No matching Agent Meter process; other processes were left alone." ;;
esac
rm -f "$pid_file"
