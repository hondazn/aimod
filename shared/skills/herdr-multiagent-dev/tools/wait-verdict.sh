#!/usr/bin/env bash
# Wait for a headless role session (opencode run, codex exec) to finish.
#
# Waits for both signals, because either alone lies: the verdict line can appear
# while the agent is still writing, and a quiet log can just mean it is thinking.
# Do NOT wait on the process instead -- `pgrep -f` matches the waiting shell's
# own command line, and a shell's `[1]+ Done` reports the nohup wrapper, not the
# setsid child.
#
# usage: wait-verdict.sh <log> [timeout-seconds] [quiet-seconds]
set -uo pipefail
log="$1"; limit="${2:-3600}"; quiet="${3:-30}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
start=$(date +%s)
while :; do
  now=$(date +%s)
  if [ $((now - start)) -ge "$limit" ]; then echo "TIMEOUT after $((now - start))s"; exit 2; fi
  if [ -f "$log" ]; then
    v=$(python3 "$here/verdict.py" "$log" 2>/dev/null) || v=""
    if [ -n "$v" ] && [ "$v" != "判定不明" ]; then
      m=$(stat -c %Y "$log")
      if [ $((now - m)) -ge "$quiet" ]; then echo "VERDICT:$v"; exit 0; fi
    fi
  fi
  sleep 20
done
