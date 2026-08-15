#!/usr/bin/env bash
# Mock-driven smoke tests for cursor/statusline.sh
set -u

SCRIPT="$(cd "$(dirname "$0")" && pwd)/statusline.sh"
PASS=0
FAIL=0
STUB_DIR=""
CACHE_ROOT=""
REPO=""

cleanup() {
  [ -n "$STUB_DIR" ] && rm -rf "$STUB_DIR"
  [ -n "$CACHE_ROOT" ] && rm -rf "$CACHE_ROOT"
  [ -n "$REPO" ] && rm -rf "$REPO"
}
trap cleanup EXIT

STUB_DIR=$(mktemp -d)
printf '#!/bin/sh\nexit 1\n' > "$STUB_DIR/gh"
chmod +x "$STUB_DIR/gh"
export PATH="$STUB_DIR:$PATH"

CACHE_ROOT=$(mktemp -d)
export CURSOR_STATUSLINE_CACHE="$CACHE_ROOT"

strip() { perl -pe 's/\e\[[0-9;]*m//g; s/\e\]8;;[^\a]*\a//g'; }

make_repo() {
  local d
  d=$(mktemp -d)
  git -C "$d" init -q
  git -C "$d" checkout -q -b feat/foo
  git -C "$d" remote add origin git@github.com:acme/demo.git
  git -C "$d" -c user.email=t@t -c user.name=t commit --allow-empty -q -m init
  printf '%s' "$d"
}

# run NAME CWD JSON -- WANT... ! NOWANT... RAW RAW...
run() {
  local name="$1" cwd="$2" json="$3"
  shift 3
  [ "$1" = "--" ] && shift
  local want=() forbid=() raw=() mode="want"
  for t in "$@"; do
    case "$t" in
      '!') mode="forbid" ;;
      RAW) mode="raw" ;;
      *)
        case "$mode" in
          want) want+=("$t") ;;
          forbid) forbid+=("$t") ;;
          raw) raw+=("$t") ;;
        esac
        ;;
    esac
  done

  local out rc vis miss="" bad=""
  out=$(cd "$cwd" && printf '%s' "$json" | bash "$SCRIPT" 2>/dev/null)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "✗ $name — exit code $rc (expected 0)"
    FAIL=$((FAIL + 1))
    return
  fi
  vis=$(printf '%s' "$out" | strip)

  local s
  for s in "${want[@]:-}"; do
    [ -z "$s" ] && continue
    case "$vis" in *"$s"*) ;; *) miss+=" [$s]" ;; esac
  done
  for s in "${forbid[@]:-}"; do
    [ -z "$s" ] && continue
    case "$vis" in *"$s"*) bad+=" [$s]" ;; esac
  done
  for s in "${raw[@]:-}"; do
    [ -z "$s" ] && continue
    case "$out" in *"$s"*) ;; *) miss+=" raw[$s]" ;; esac
  done
  case "$out" in
    *$'\xee\x82\xb0'*) bad+=" [powerline]" ;;
    *▀*) bad+=" [gauge]" ;;
  esac

  if [ -n "$miss" ] || [ -n "$bad" ]; then
    echo "✗ $name —${miss:+ missing:$miss}${bad:+ forbidden:$bad}"
    FAIL=$((FAIL + 1))
  else
    echo "✓ $name"
    PASS=$((PASS + 1))
  fi
}

REPO=$(make_repo)
printf 'changed\n' > "$REPO/tracked.txt"
git -C "$REPO" add tracked.txt
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q -m add
printf 'changed\nmore\n' > "$REPO/tracked.txt"
printf 'new\n' > "$REPO/untracked.txt"

TMP="${TMPDIR:-/tmp}"

run "full" "$REPO" '{
  "model":{"display_name":"Composer 2.5","param_summary":"(Thinking)"},
  "version":"2026.08.15",
  "workspace":{"current_dir":"'"$REPO"'"},
  "context_window":{"remaining_percentage":66.2,"used_percentage":33.8,"total_input_tokens":15234,"context_window_size":200000}
}' -- "2026.08.15" "Composer 2.5" "Thinking" "acme/demo" "feat/foo" "ctx 15,234  33%" "+1" "?1" ! "max" "autorun" "compact" "#123" "ctx 66%" "▀" \
  RAW $']8;;https://github.com/acme/demo\a' $']8;;https://github.com/acme/demo/tree/feat/foo\a'

run "used-percentage" "$REPO" '{
  "model":{"display_name":"Opus"},
  "version":"1.0.0",
  "workspace":{"current_dir":"'"$REPO"'"},
  "context_window":{"used_percentage":40}
}' -- "ctx 40%" ! "ctx 60%"

run "tokens-from-window" "$REPO" '{
  "model":{"display_name":"Opus"},
  "version":"1.0.0",
  "workspace":{"current_dir":"'"$REPO"'"},
  "context_window":{"used_percentage":25,"context_window_size":200000}
}' -- "ctx 50,000  25%"

run "max-autorun-style" "$REPO" '{
  "model":{"display_name":"Opus","max_mode":true},
  "version":"1.0.0",
  "autorun":true,
  "output_style":{"name":"compact"},
  "workspace":{"current_dir":"'"$REPO"'"}
}' -- "max" "autorun" "compact" ! "Thinking"

run "worktree" "$REPO" '{
  "model":{"display_name":"Opus"},
  "version":"1.0.0",
  "workspace":{"current_dir":"'"$REPO"'"},
  "worktree":{"name":"feat-foo"}
}' -- "feat-foo" ! "feat/foo"

run "not-git" "$TMP" '{
  "model":{"display_name":"Opus"},
  "version":"1.0.0",
  "workspace":{"current_dir":"/x/myproj"}
}' -- "myproj" "1.0.0" ! "feat/foo" "acme/demo"

run "issue-not-shown" "$REPO" '{
  "model":{"display_name":"Opus"},
  "version":"1.0.0",
  "workspace":{"current_dir":"'"$REPO"'"}
}' -- "feat/foo" ! "#123"

printf '%s' '{"number":42,"url":"https://github.com/acme/demo/pull/42","isDraft":false,"reviewDecision":"APPROVED"}' \
  > "$CACHE_ROOT/acme__demo__pr__feat-foo"

run "pr-from-cache" "$REPO" '{
  "model":{"display_name":"Opus"},
  "version":"1.0.0",
  "workspace":{"current_dir":"'"$REPO"'"}
}' -- "#42" RAW $']8;;https://github.com/acme/demo/pull/42\a'

run "minimal" "$TMP" '{}' --

wait 2>/dev/null || true

echo "─────────────────────────────"
echo "PASS=$PASS  FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
