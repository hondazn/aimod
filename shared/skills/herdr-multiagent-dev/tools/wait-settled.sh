#!/usr/bin/env bash
# Debounced settled-wait for an agent running in a herdr pane.
#
# `herdr agent wait` returns early on the short state flickers a working agent
# produces, so completion is confirmed as "idle seen, still idle N seconds
# later". blocked gets the same debounce -- herdr's blocked detection has false
# positives.
#
# usage: wait-settled.sh <agent-name> [timeout-seconds] [debounce-seconds]
# exits 0 SETTLED / 2 TIMEBOX_EXCEEDED / 3 AGENT_GONE / 4 BLOCKED
set -uo pipefail
name="$1"; limit="${2:-7200}"; debounce="${3:-10}"
start=$(date +%s)
status_of() {
  herdr agent get "$name" 2>/dev/null | python3 -c "
import json, sys
try:
    print(json.load(sys.stdin)['result']['agent']['agent_status'])
except Exception:
    print('gone')
"
}
while :; do
  now=$(date +%s); elapsed=$((now - start))
  if [ "$elapsed" -ge "$limit" ]; then echo "TIMEBOX_EXCEEDED after ${elapsed}s"; exit 2; fi
  case "$(status_of)" in
    idle|done)
      sleep "$debounce"
      s=$(status_of)
      if [ "$s" = "idle" ] || [ "$s" = "done" ]; then echo "SETTLED:$s after ${elapsed}s"; exit 0; fi
      ;;
    gone) echo "AGENT_GONE after ${elapsed}s"; exit 3 ;;
    blocked)
      sleep 8
      if [ "$(status_of)" = "blocked" ]; then echo "BLOCKED after ${elapsed}s"; exit 4; fi
      ;;
  esac
  sleep 20
done
