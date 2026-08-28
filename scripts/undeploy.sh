#!/usr/bin/env bash
# Remove aimod-managed symlinks from Claude Code / Cursor / Codex CLI home dirs.
# Only removes symlinks whose resolved target is inside this repository.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

log() { printf '%s\n' "$*"; }

unlink_if_ours() {
  local dest="$1"
  if [[ ! -L "$dest" ]]; then
    return 0
  fi
  local target
  target="$(readlink -f "$dest" || true)"
  if [[ "$target" != "$ROOT" && "$target" != "$ROOT"/* ]]; then
    # readlink -f refuses to resolve when an intermediate directory of the
    # target is gone; fall back to the raw link text (always absolute in aimod).
    target="$(readlink "$dest")"
  fi
  if [[ "$target" == "$ROOT" || "$target" == "$ROOT"/* ]]; then
    rm -f "$dest"
    log "removed $dest"
  else
    log "SKIP $dest (points outside aimod)"
  fi
}

log "undeploying aimod links from $ROOT"

unlink_if_ours "$HOME/.claude/CLAUDE.md"
unlink_if_ours "$HOME/.codex/AGENTS.md"
unlink_if_ours "$HOME/AGENTS.md"

unlink_if_ours "$HOME/.claude/agents"
unlink_if_ours "$HOME/.cursor/agents"

unlink_if_ours "$HOME/.claude/skills"
unlink_if_ours "$HOME/.cursor/skills"

unlink_if_ours "$HOME/.config/opencode/AGENTS.md"
unlink_if_ours "$HOME/.config/opencode/agents"

# Plugins are linked per file, so sweep the destination rather than deriving the
# list from opencode/plugins: that would miss links left behind by a plugin we
# have since deleted. Files the user keeps here are not symlinks into ROOT, so
# unlink_if_ours leaves them alone.
unlink_if_ours "$HOME/.config/opencode/opencode.json"
if [[ -d "$HOME/.config/opencode/plugins" ]]; then
  shopt -s nullglob
  for entry in "$HOME/.config/opencode/plugins"/*; do
    unlink_if_ours "$entry"
  done
fi

unlink_if_ours "$HOME/.claude/rules"
unlink_if_ours "$HOME/.codex/rules"
unlink_if_ours "$HOME/.cursor/rules"

# Cursor rules are linked per file, so sweep the destination rather than deriving the
# list from shared/rules: that would miss links left behind by a rule we have since
# deleted, and the legacy AGENTS.md that lived here before ~/AGENTS.md. Files the user
# keeps here are not symlinks into ROOT, so unlink_if_ours leaves them alone.
if [[ -d "$HOME/.cursor/rules" ]]; then
  shopt -s nullglob
  for entry in "$HOME/.cursor/rules"/*; do
    unlink_if_ours "$entry"
  done
  rmdir "$HOME/.cursor/rules" 2>/dev/null || true
fi

unlink_if_ours "$HOME/.claude/settings.json"
unlink_if_ours "$HOME/.claude/statusline.sh"
unlink_if_ours "$HOME/.cursor/statusline.sh"

"$ROOT/scripts/manage-codex-statusline.sh" \
  remove "$HOME/.codex/config.toml" "$ROOT/codex/statusline.toml"
log "undeploy managed tui.status_line from $HOME/.codex/config.toml if unchanged"

# Remove a legacy file-level skill dir if every file/symlink resolves into ROOT.
remove_legacy_skill_dir_if_ours() {
  local dest="$1" file target
  while IFS= read -r -d '' file; do
    if [[ -L "$file" ]]; then
      target="$(readlink -f "$file" || true)"
      if [[ "$target" != "$ROOT" && "$target" != "$ROOT"/* ]]; then
        log "SKIP $dest (not an aimod legacy tree)"
        return 0
      fi
    else
      log "SKIP $dest (not an aimod legacy tree)"
      return 0
    fi
  done < <(find "$dest" \( -type f -o -type l \) -print0 2>/dev/null)
  rm -rf "$dest"
  log "removed legacy skill dir $dest"
}

# Codex per-skill links (never touch .system)
if [[ -d "$HOME/.codex/skills" ]]; then
  shopt -s nullglob
  for entry in "$HOME/.codex/skills"/*; do
    name="$(basename "$entry")"
    [[ "$name" == ".system" ]] && continue
    if [[ -L "$entry" ]]; then
      unlink_if_ours "$entry"
    elif [[ -d "$entry" ]]; then
      remove_legacy_skill_dir_if_ours "$entry"
    fi
  done
fi

log "done"
