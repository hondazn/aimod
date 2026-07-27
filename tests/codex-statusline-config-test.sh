#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANAGER="$ROOT/scripts/manage-codex-statusline.sh"
STATUSLINE="$ROOT/codex/statusline.toml"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

EXPECTED='status_line = ["codex-version", "model-with-reasoning", "project-name", "git-branch", "branch-changes", "pull-request-number", "context-used", "used-tokens", "five-hour-limit", "weekly-limit"]'

assert_line() {
  local expected="$1" file="$2"
  grep -Fqx "$expected" "$file"
}

assert_count() {
  local expected="$1" count="$2" file="$3"
  [[ "$(grep -Fxc "$expected" "$file" || true)" == "$count" ]]
}

existing="$TMP_ROOT/existing.toml"
printf '%s\n' \
  'model = "test-model"' \
  '' \
  '[tui]' \
  'status_line = ["model"]' \
  'session_picker_view = "comfortable"' \
  '' \
  '[features]' \
  'goals = true' > "$existing"

"$MANAGER" apply "$existing" "$STATUSLINE"
assert_line "$EXPECTED" "$existing"
assert_count "$EXPECTED" 1 "$existing"
assert_line 'session_picker_view = "comfortable"' "$existing"
assert_line '[features]' "$existing"

before="$(sha256sum "$existing")"
"$MANAGER" apply "$existing" "$STATUSLINE"
after="$(sha256sum "$existing")"
[[ "$before" == "$after" ]]

without_tui="$TMP_ROOT/without-tui.toml"
printf '%s\n' 'model = "test-model"' > "$without_tui"
"$MANAGER" apply "$without_tui" "$STATUSLINE"
assert_line '[tui]' "$without_tui"
assert_line "$EXPECTED" "$without_tui"

missing="$TMP_ROOT/missing.toml"
"$MANAGER" apply "$missing" "$STATUSLINE"
assert_line '[tui]' "$missing"
assert_line "$EXPECTED" "$missing"

multiline="$TMP_ROOT/multiline.toml"
printf '%s\n' \
  '[tui]' \
  'status_line = [' \
  '  "model",' \
  '  "git-branch",' \
  ']' \
  'animations = false' > "$multiline"
"$MANAGER" apply "$multiline" "$STATUSLINE"
assert_line "$EXPECTED" "$multiline"
assert_count '  "model",' 0 "$multiline"
assert_line 'animations = false' "$multiline"

"$MANAGER" remove "$existing" "$STATUSLINE"
assert_count "$EXPECTED" 0 "$existing"
assert_line 'session_picker_view = "comfortable"' "$existing"

scoped="$TMP_ROOT/scoped.toml"
printf '%s\n' \
  '[other]' \
  "$EXPECTED" \
  '[tui]' \
  "$EXPECTED" > "$scoped"
"$MANAGER" remove "$scoped" "$STATUSLINE"
assert_count "$EXPECTED" 1 "$scoped"

customized="$TMP_ROOT/customized.toml"
printf '%s\n' '[tui]' 'status_line = ["model", "git-branch"]' > "$customized"
"$MANAGER" remove "$customized" "$STATUSLINE"
assert_line 'status_line = ["model", "git-branch"]' "$customized"

deploy_home="$TMP_ROOT/deploy-home"
mkdir -p "$deploy_home/.codex"
printf '%s\n' '[tui]' 'animations = false' > "$deploy_home/.codex/config.toml"
HOME="$deploy_home" "$ROOT/scripts/deploy.sh" >/dev/null
assert_line "$EXPECTED" "$deploy_home/.codex/config.toml"
assert_line 'animations = false' "$deploy_home/.codex/config.toml"
HOME="$deploy_home" "$ROOT/scripts/undeploy.sh" >/dev/null
assert_count "$EXPECTED" 0 "$deploy_home/.codex/config.toml"
assert_line 'animations = false' "$deploy_home/.codex/config.toml"

printf 'ok\n'
