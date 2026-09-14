#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

HOME_DIR="$TMP_ROOT/home"
mkdir -p "$HOME_DIR/.agents/skills"

assert() {
  if ! "$@"; then
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
  fi
}

# A skill installed by another client (e.g. the skills CLI) must survive deploy.
mkdir -p "$HOME_DIR/.agents/skills/mine"
printf 'mine\n' > "$HOME_DIR/.agents/skills/mine/SKILL.md"

# A foreign skill whose name collides with a shared skill is skipped, not clobbered.
mkdir -p "$HOME_DIR/.agents/skills/comprehension-test"
printf 'user copy\n' > "$HOME_DIR/.agents/skills/comprehension-test/SKILL.md"

# A stale aimod link (source deleted from the repo) is pruned on deploy.
ln -s "$ROOT/shared/skills/removed-skill" "$HOME_DIR/.agents/skills/stale"

HOME="$HOME_DIR" "$ROOT/scripts/deploy.sh" >/dev/null

dest="$HOME_DIR/.agents/skills"
assert test "$(readlink "$dest/book-to-skill")" == "$ROOT/shared/skills/book-to-skill"
assert test "$(readlink "$dest/code-perfection")" == "$ROOT/shared/skills/code-perfection"
assert test "$(cat "$dest/mine/SKILL.md")" == 'mine'
assert test "$(cat "$dest/comprehension-test/SKILL.md")" == 'user copy'
assert test ! -e "$dest/stale"

# Idempotent: a second run leaves the same links.
before="$(readlink "$dest/book-to-skill")"
HOME="$HOME_DIR" "$ROOT/scripts/deploy.sh" >/dev/null
assert test "$(readlink "$dest/book-to-skill")" == "$before"

# Undeploy removes our links but never the other clients' skills.
HOME="$HOME_DIR" "$ROOT/scripts/undeploy.sh" >/dev/null
assert test ! -e "$dest/book-to-skill"
assert test ! -e "$dest/code-perfection"
assert test "$(cat "$dest/mine/SKILL.md")" == 'mine'
assert test "$(cat "$dest/comprehension-test/SKILL.md")" == 'user copy'

printf 'ok\n'
