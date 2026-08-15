#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TRANSFORM="$ROOT/scripts/opencode-agent-transform.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

OUT_DIR="$TMP_ROOT/agents"

assert() {
  if ! "$@"; then
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
  fi
}

# frontmatter only (first --- to the closing ---)
fm() { awk '/^---$/ { if (++seen == 2) exit; next } seen >= 1 { print }' "$1"; }
# body only (after the closing ---)
body() { awk '/^---$/ { seen++; next } seen >= 2 { print }' "$1"; }

"$TRANSFORM" "$OUT_DIR"

src_count="$(find "$ROOT/shared/agents" -name '*.md' | wc -l)"
out_count="$(find "$OUT_DIR" -name '*.md' | wc -l)"
assert test "$src_count" == "$out_count"

for src in "$ROOT"/shared/agents/*.md; do
  name="$(basename "$src")"
  out="$OUT_DIR/$name"

  # mode: subagent injected as the first frontmatter key (opencode defaults to "all")
  assert test "$(sed -n '2p' "$out")" == 'mode: subagent'

  # colors are quoted hex or opencode theme names; Claude Code color names would
  # fail config load, and an unquoted #hex is a YAML comment (parses as null)
  color="$(fm "$out" | sed -n 's/^color: "\(.*\)"$/\1/p')"
  if [[ -n "$color" && ! "$color" =~ ^(\#[0-9a-fA-F]{6}|primary|secondary|accent|success|warning|error|info)$ ]]; then
    printf 'FAIL: invalid color %s in %s\n' "$color" "$out" >&2
    exit 1
  fi

  # name, remaining frontmatter, and body are preserved verbatim
  fm_src="$(fm "$src" | grep -v '^color:')"
  fm_out="$(fm "$out" | grep -v '^color:' | grep -v '^mode: subagent$')"
  assert test "$fm_src" == "$fm_out"
  assert test "$(body "$src")" == "$(body "$out")"
done

deploy_home="$TMP_ROOT/deploy-home"
mkdir -p "$deploy_home"
HOME="$deploy_home" "$ROOT/scripts/deploy.sh" >/dev/null
assert test -L "$deploy_home/.config/opencode/AGENTS.md"
assert test -L "$deploy_home/.config/opencode/agents"
assert test "$(readlink "$deploy_home/.config/opencode/agents")" == "$ROOT/.opencode-agents"
assert test -f "$deploy_home/.config/opencode/agents/meta-reviewer.md"
assert test -f "$deploy_home/.config/opencode/agents/fatal-reviewer.md"

before="$(sha256sum "$ROOT"/.opencode-agents/* | sort)"
HOME="$deploy_home" "$ROOT/scripts/deploy.sh" >/dev/null
after="$(sha256sum "$ROOT"/.opencode-agents/* | sort)"
assert test "$before" == "$after"

HOME="$deploy_home" "$ROOT/scripts/undeploy.sh" >/dev/null
assert test ! -e "$deploy_home/.config/opencode/agents"
assert test ! -e "$deploy_home/.config/opencode/AGENTS.md"

# guarded: a pre-existing user AGENTS.md is never replaced
custom="$TMP_ROOT/custom"
mkdir -p "$custom/.config/opencode"
printf 'mine\n' > "$custom/.config/opencode/AGENTS.md"
HOME="$custom" "$ROOT/scripts/deploy.sh" >/dev/null
assert test "$(cat "$custom/.config/opencode/AGENTS.md")" == 'mine'

printf 'ok\n'