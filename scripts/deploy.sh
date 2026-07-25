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

# Link a rules path without ever destroying rules we did not create. All three
# rule locations are native to their tool and may already hold entries from
# outside aimod, so anything not ours is left exactly as it is. Used for both
# the whole-dir targets (~/.claude/rules, ~/.codex/rules) and the per-file ones
# (~/.cursor/rules/<name>.md), where a generic name like coding.md can collide
# with a rule the user already keeps there.
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
    log "SKIP $dest (existing non-aimod rules) — move into shared/rules, then re-run"
    return 1
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
# A skill removed from shared/skills leaves its Codex link dangling; .system and
# anything not ours fail is_ours and stay put.
for entry in "$HOME/.codex/skills"/*; do
  prune_stale_link "$entry"
done

# Rules — Claude loads ~/.claude/rules natively; Cursor / Codex read them on demand
link_rule_path "$ROOT/shared/rules" "$HOME/.claude/rules" || true
link_rule_path "$ROOT/shared/rules" "$HOME/.codex/rules" || true
# Cursor keeps AGENTS.md inside ~/.cursor/rules, so link rule files individually
mkdir -p "$HOME/.cursor/rules"
for rule in "$ROOT/shared/rules"/*.md; do
  link_rule_path "$rule" "$HOME/.cursor/rules/$(basename "$rule")" || true
done
# Same for a rule removed from shared/rules. AGENTS.md still resolves, so it is
# never a prune candidate.
for entry in "$HOME/.cursor/rules"/*.md; do
  prune_stale_link "$entry"
done

# Claude-only files
link "$ROOT/claude/settings.json" "$HOME/.claude/settings.json"
link "$ROOT/claude/statusline.sh" "$HOME/.claude/statusline.sh"

log "done"
