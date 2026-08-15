#!/usr/bin/env bash
# Generate opencode-compatible agent files from shared/agents into .opencode-agents/.
# opencode rejects Claude Code's color names (only #RRGGBB or theme colors) and
# defaults a missing `mode` to "all"; the transform injects mode: subagent and maps
# the color palette. The output dir becomes ~/.config/opencode/agents via symlink.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

SRC_DIR="$ROOT/shared/agents"
OUT_DIR="${1:-$ROOT/.opencode-agents}"

log() { printf '%s\n' "$*"; }

# Claude Code color names -> hex values (radix palette, keeps the hue per agent).
color_hex() {
  case "${1:-}" in
    red)     printf '%s' '#e5484d' ;;
    orange)  printf '%s' '#f76b15' ;;
    yellow)  printf '%s' '#ffb224' ;;
    green)   printf '%s' '#30a46c' ;;
    blue)    printf '%s' '#0091ff' ;;
    cyan)    printf '%s' '#00c2d7' ;;
    teal)    printf '%s' '#12a594' ;;
    purple)  printf '%s' '#8e4ec6' ;;
    magenta) printf '%s' '#d6409f' ;;
    pink)    printf '%s' '#de5d83' ;;
    brown)   printf '%s' '#ad7f58' ;;
    gray)    printf '%s' '#8d8d8d' ;;
    *)       return 1 ;;
  esac
}

# sed script mapping every palette name to its hex, for the color: line in frontmatter.
# The hex must be quoted: an unquoted `#12a594` is a YAML comment, so the value
# would parse as null and opencode rejects it.
color_sed() {
  local name sed_script=''
  for name in red orange yellow green blue cyan teal purple magenta pink brown gray; do
    sed_script+="s/^color: ${name}$/color: \"$(color_hex "$name")\"/;"
  done
  printf '%s' "$sed_script"
}

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

shopt -s nullglob
for src in "$SRC_DIR"/*.md; do
  if [[ "$(head -1 "$src")" != "---" ]]; then
    log "SKIP $src (no frontmatter)"
    continue
  fi
  {
    printf '%s\n' '---'
    printf '%s\n' 'mode: subagent'
    sed -n '2,$p' "$src"
  } | sed -E "$(color_sed)" > "$OUT_DIR/$(basename "$src")"
  log "generate $OUT_DIR/$(basename "$src")"
done