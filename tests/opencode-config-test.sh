#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

HOME_DIR="$TMP_ROOT/home"
mkdir -p "$HOME_DIR/.config/opencode/plugins"

assert() {
  if ! "$@"; then
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
  fi
}

# A pre-existing real opencode.json is replaced: aimod owns this path like
# ~/.claude/settings.json, and skipping would leave first deploys a no-op.
printf 'user config\n' > "$HOME_DIR/.config/opencode/opencode.json"

# A plugin dropped by hand outside the repo must survive deploy.
printf '// mine\n' > "$HOME_DIR/.config/opencode/plugins/mine.js"

# A stale aimod plugin link (source deleted from the repo) is pruned on deploy.
ln -s "$ROOT/opencode/plugins/removed-plugin.js" \
  "$HOME_DIR/.config/opencode/plugins/stale.js"

HOME="$HOME_DIR" "$ROOT/scripts/deploy.sh" >/dev/null

config="$HOME_DIR/.config/opencode/opencode.json"
assert test "$(readlink "$config")" == "$ROOT/opencode/opencode.json"
assert cmp -s "$config" "$ROOT/opencode/opencode.json"

plugin="$HOME_DIR/.config/opencode/plugins/herdr-agent-state.js"
assert test "$(readlink "$plugin")" == "$ROOT/opencode/plugins/herdr-agent-state.js"

assert test "$(cat "$HOME_DIR/.config/opencode/plugins/mine.js")" == '// mine'
assert test ! -e "$HOME_DIR/.config/opencode/plugins/stale.js"

# Idempotent: a second run leaves the same links.
before="$(readlink "$config")"
HOME="$HOME_DIR" "$ROOT/scripts/deploy.sh" >/dev/null
assert test "$(readlink "$config")" == "$before"

# Undeploy drops our links but never touches the user's own plugin.
HOME="$HOME_DIR" "$ROOT/scripts/undeploy.sh" >/dev/null
assert test ! -e "$config"
assert test ! -e "$plugin"
assert test "$(cat "$HOME_DIR/.config/opencode/plugins/mine.js")" == '// mine'

printf 'ok\n'
