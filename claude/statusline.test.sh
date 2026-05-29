#!/usr/bin/env bash
# Mock-driven smoke tests for statusline.sh
# Asserts: (1) exit code 0 on every input, (2) expected visible markers present,
#          (3) certain markers ABSENT when their source field is missing.
# Not deployed by dotter (absent from .dotter/global.toml).
set -u

SCRIPT="$(cd "$(dirname "$0")" && pwd)/statusline.sh"
PASS=0; FAIL=0

# Strip ANSI SGR, OSC-8 hyperlinks and the Powerline glyph so we match visible text.
strip() { perl -pe 's/\e\[[0-9;]*m//g; s/\e\]8;;[^\a]*\a//g; s/\xee\x82\xb0//g'; }

# run NAME CWD JSON -- WANT... ! NOWANT...
#   tokens after `--` are required substrings; tokens after `!` are forbidden.
run() {
  local name="$1" cwd="$2" json="$3"; shift 3
  [ "$1" = "--" ] && shift
  local want=() forbid=() mode="want"
  for t in "$@"; do
    if [ "$t" = "!" ]; then mode="forbid"; continue; fi
    if [ "$mode" = "want" ]; then want+=("$t"); else forbid+=("$t"); fi
  done

  local out rc vis miss="" bad=""
  out=$( cd "$cwd" && printf '%s' "$json" | bash "$SCRIPT" 2>/dev/null ); rc=$?
  if [ "$rc" -ne 0 ]; then echo "✗ $name — exit code $rc (expected 0)"; FAIL=$((FAIL+1)); return; fi
  vis=$(printf '%s' "$out" | strip)

  local s
  for s in "${want[@]:-}";   do [ -z "$s" ] && continue; case "$vis" in *"$s"*) ;; *) miss+=" [$s]";; esac; done
  for s in "${forbid[@]:-}"; do [ -z "$s" ] && continue; case "$vis" in *"$s"*) bad+=" [$s]";; esac; done

  if [ -n "$miss" ] || [ -n "$bad" ]; then
    echo "✗ $name —${miss:+ missing:$miss}${bad:+ forbidden:$bad}"
    FAIL=$((FAIL+1))
  else
    echo "✓ $name"; PASS=$((PASS+1))
  fi
}

REPO="$(cd "$(dirname "$0")" && pwd)"   # a real git repo → exercises repo/branch paths
TMP="${TMPDIR:-/tmp}"                   # not a git repo → exercises fallback

# 1) full payload — everything present (token count from current_usage = 124,500)
run "full" "$REPO" '{
  "model":{"display_name":"Opus"},"version":"2.1.160",
  "effort":{"level":"high"},"thinking":{"enabled":true},"output_style":{"name":"explanatory"},
  "workspace":{"project_dir":"/x/aimod"},
  "pr":{"number":42,"review_state":"approved","url":"https://github.com/o/r/pull/42"},
  "context_window":{"used_percentage":62,"current_usage":{"input_tokens":50000,"cache_creation_input_tokens":30000,"cache_read_input_tokens":44500}},
  "cost":{"total_cost_usd":0.34,"total_duration_ms":480000,"total_lines_added":156,"total_lines_removed":23},
  "rate_limits":{"five_hour":{"used_percentage":23,"resets_at":9999999999},"seven_day":{"used_percentage":12,"resets_at":9999999999}}
}' -- "🤖 Opus" "💥2.1.160" "🎚 high" "💭" "🎨 explanatory" "🔀#42" "approved" "🧠" "124" "62%" "⏰" "📆" "💰" '$0.34' ! "🔋" "Σ" "ctx 62%"

# 2) no PR
run "no-pr" "$REPO" '{
  "model":{"display_name":"Opus"},"version":"2.1.160","workspace":{"project_dir":"/x/aimod"},
  "context_window":{"used_percentage":40},
  "rate_limits":{"five_hour":{"used_percentage":10,"resets_at":9999999999},"seven_day":{"used_percentage":5,"resets_at":9999999999}}
}' -- "🧠" "40%" "⏰" "📆" ! "🔀"

# 3) no rate_limits (free tier / before first response) → 5h+7d gauges omitted, ctx still renders
run "no-ratelimits" "$REPO" '{
  "model":{"display_name":"Sonnet"},"version":"2.1.160","workspace":{"project_dir":"/x/aimod"},
  "context_window":{"used_percentage":15}
}' -- "🤖 Sonnet" "🧠" "15%" ! "⏰" "📆" "🔋"

# 4) worktree session → ⌥ marker
run "worktree" "$REPO" '{
  "model":{"display_name":"Opus"},"version":"2.1.160","workspace":{"project_dir":"/x/aimod"},
  "worktree":{"name":"feat-foo"},"context_window":{"used_percentage":20}
}' -- "⌥ feat-foo" "🧠" "20%"

# 5) not a git repo → repo falls back to project_dir basename, no branch
run "not-git" "$TMP" '{
  "model":{"display_name":"Opus"},"version":"2.1.160","workspace":{"project_dir":"/x/myproj"},
  "context_window":{"used_percentage":30}
}' -- "🚀 myproj" "🧠" "30%" ! "⚡"

# 6) effort-less model + default output_style → mode markers absent
run "no-effort-default-style" "$REPO" '{
  "model":{"display_name":"Haiku"},"version":"2.1.160","workspace":{"project_dir":"/x/aimod"},
  "thinking":{"enabled":false},"output_style":{"name":"default"},
  "context_window":{"used_percentage":5}
}' -- "🤖 Haiku" "🧠" "5%" ! "🎚" "🎨" "💭"

# 7) empty / minimal payload → must not crash
run "minimal" "$TMP" '{}' --

echo "─────────────────────────────"
echo "PASS=$PASS  FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
