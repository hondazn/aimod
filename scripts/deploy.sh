#!/usr/bin/env bash
# Deploy aimod shared config into Claude Code / Cursor / Codex CLI home dirs.
# Idempotent: uses ln -sfn. No external deps beyond bash + coreutils.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

log() { printf '%s\n' "$*"; }

link() {
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [[ -L "$dest" ]]; then
    local current
    current="$(readlink "$dest")"
    if [[ "$current" == "$src" ]]; then
      return 0
    fi
  elif [[ -e "$dest" ]]; then
    log "replace non-symlink: $dest"
    rm -rf "$dest"
  fi
  ln -sfn "$src" "$dest"
  log "link $dest -> $src"
}

# True if every regular file under dest resolves inside ROOT (legacy file-level deploy).
is_aimod_file_tree() {
  local dest="$1" file target
  while IFS= read -r -d '' file; do
    if [[ -L "$file" ]]; then
      target="$(readlink -f "$file" || true)"
      if [[ "$target" != "$ROOT" && "$target" != "$ROOT"/* ]]; then
        return 1
      fi
    else
      return 1
    fi
  done < <(find "$dest" -type f -print0 2>/dev/null; find "$dest" -type l -print0 2>/dev/null)
  return 0
}

# Only replace a Codex skill path when it is safe (symlink, or prior aimod file-level deploy).
link_codex_skill() {
  local src="$1" dest="$2"
  if [[ -L "$dest" ]]; then
    ln -sfn "$src" "$dest"
    log "link $dest -> $src"
    return 0
  fi
  if [[ -d "$dest" ]]; then
    if is_aimod_file_tree "$dest"; then
      rm -rf "$dest"
      ln -sfn "$src" "$dest"
      log "link $dest -> $src (replaced file-level dir)"
      return 0
    fi
    log "SKIP $dest (exists and is not an aimod symlink tree)"
    return 0
  fi
  if [[ -e "$dest" ]]; then
    log "SKIP $dest (unexpected non-directory)"
    return 0
  fi
  ln -sfn "$src" "$dest"
  log "link $dest -> $src"
}

log "deploying from $ROOT"

# Shared instructions
link "$ROOT/shared/instructions.md" "$HOME/.claude/CLAUDE.md"
link "$ROOT/shared/instructions.md" "$HOME/.codex/AGENTS.md"
link "$ROOT/shared/instructions.md" "$HOME/.cursor/rules/AGENTS.md"

# Agents (Claude / Cursor only)
link "$ROOT/shared/agents" "$HOME/.claude/agents"
link "$ROOT/shared/agents" "$HOME/.cursor/agents"

# Skills — full directory for Claude / Cursor
link "$ROOT/shared/skills" "$HOME/.claude/skills"
link "$ROOT/shared/skills" "$HOME/.cursor/skills"

# Skills — per skill for Codex so ~/.codex/skills/.system can coexist
mkdir -p "$HOME/.codex/skills"
shopt -s nullglob
for skill in "$ROOT/shared/skills"/*; do
  [[ -d "$skill" ]] || continue
  link_codex_skill "$skill" "$HOME/.codex/skills/$(basename "$skill")"
done

# Claude-only files
link "$ROOT/claude/settings.json" "$HOME/.claude/settings.json"
link "$ROOT/claude/statusline.sh" "$HOME/.claude/statusline.sh"

log "done"
