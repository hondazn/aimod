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

# True when dest is a symlink aimod created, i.e. one resolving inside ROOT.
# readlink -f still resolves a path whose final component is missing, so this
# also classifies links left stale by a skill/rule deleted from shared/.
is_ours() {
  local dest="$1" target
  [[ -L "$dest" ]] || return 1
  target="$(readlink -f "$dest" || true)"
  [[ "$target" == "$ROOT" || "$target" == "$ROOT"/* ]]
}

# Drop a link we created whose source is gone. Claude / Cursor get one symlink
# for the whole skills dir and follow deletions on their own; only the per-entry
# targets (Codex skills, Cursor rules) can strand a dangling link.
prune_stale_link() {
  local dest="$1"
  if [[ -e "$dest" ]] || ! is_ours "$dest"; then
    return 0
  fi
  rm -f "$dest"
  log "prune stale $dest"
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
    if [[ "$(readlink "$dest")" == "$src" ]]; then
      return 0
    fi
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

# Link a rules directory without ever destroying rules we did not create. Only
# ~/.claude/rules is loaded natively by its tool; ~/.codex/rules is an aimod
# convention that Codex reads on demand, since Codex has AGENTS.md alone with
# no rule imports. Both may already hold entries from outside aimod, so anything
# not ours is left exactly as it is.
link_rule_path() {
  local src="$1" dest="$2"
  if [[ -L "$dest" ]]; then
    if [[ "$(readlink "$dest")" == "$src" ]]; then
      return 0
    fi
    # Mirrors undeploy.sh's unlink_if_ours: only touch links that resolve into ROOT,
    # so links managed by another dotfiles tool keep pointing where they do.
    if ! is_ours "$dest"; then
      log "SKIP $dest (symlink managed outside aimod -> $(readlink -f "$dest"))"
      return 1
    fi
    ln -sfn "$src" "$dest"
    log "link $dest -> $src"
    return 0
  fi
  if [[ -e "$dest" ]]; then
    log "SKIP $dest (existing file not managed by aimod) — move it into shared/, then re-run"
    return 1
  fi
  ln -sfn "$src" "$dest"
  log "link $dest -> $src"
}

log "deploying from $ROOT"

# Shared instructions
link "$ROOT/shared/instructions.md" "$HOME/.claude/CLAUDE.md"
link "$ROOT/shared/instructions.md" "$HOME/.codex/AGENTS.md"
# Cursor reaches this by walking up from the workspace for AGENTS.md, and ~ is an
# ancestor of every repo. Measured behaviourally (an instruction placed here changes
# cursor-agent's output; ~/.cursor/AGENTS.md and ~/.cursor/rules do not, and neither
# Claude Code nor Codex pick it up, so nothing is loaded twice). Guarded rather than
# replaced: a hand-written ~/AGENTS.md is the user's, not ours.
link_rule_path "$ROOT/shared/instructions.md" "$HOME/AGENTS.md" || true

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
# A skill removed from shared/skills leaves its Codex link dangling; .system and
# anything not ours fail is_ours and stay put.
for entry in "$HOME/.codex/skills"/*; do
  prune_stale_link "$entry"
done

# Rules — only ~/.claude/rules is loaded automatically. Codex reads them on demand
# via the task-rules table in AGENTS.md.
link_rule_path "$ROOT/shared/rules" "$HOME/.claude/rules" || true
link_rule_path "$ROOT/shared/rules" "$HOME/.codex/rules" || true

# Cursor: ~/.cursor/rules is not auto-loaded either. It is the storage the agent opens
# on demand via the task-rules table in AGENTS.md. Linked per file rather than as a
# whole directory: taking the directory would deliver nothing the moment the user
# keeps a file of their own there, because link_rule_path refuses to replace it.
if is_ours "$HOME/.cursor/rules"; then
  rm -f "$HOME/.cursor/rules"
  log "migrate: drop whole-dir link $HOME/.cursor/rules"
fi
mkdir -p "$HOME/.cursor/rules"
for rule in "$ROOT/shared/rules"/*.md; do
  link_rule_path "$rule" "$HOME/.cursor/rules/$(basename "$rule")" || true
done
# instructions.md used to be linked here as AGENTS.md; it lives at ~/AGENTS.md now.
if is_ours "$HOME/.cursor/rules/AGENTS.md"; then
  rm -f "$HOME/.cursor/rules/AGENTS.md"
  log "migrate: drop $HOME/.cursor/rules/AGENTS.md (now ~/AGENTS.md)"
fi
# A rule removed from shared/rules leaves its per-file link dangling.
for entry in "$HOME/.cursor/rules"/*.md; do
  prune_stale_link "$entry"
done

# Claude-only files
link "$ROOT/claude/settings.json" "$HOME/.claude/settings.json"
link "$ROOT/claude/statusline.sh" "$HOME/.claude/statusline.sh"

# Cursor-only files (cli-config.json is intentionally not managed)
link "$ROOT/cursor/statusline.sh" "$HOME/.cursor/statusline.sh"

# Codex accepts built-in footer item IDs only, so this cannot share Claude's
# command-based statusline implementation.
"$ROOT/scripts/manage-codex-statusline.sh" \
  apply "$HOME/.codex/config.toml" "$ROOT/codex/statusline.toml"
log "configure $HOME/.codex/config.toml tui.status_line"

log "done"
