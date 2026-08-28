#!/usr/bin/env bash
# Contracts for parent-led review + Lead judgment (Act on / Consider / Noted / Dismissed).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$ROOT/shared/skills/pr-review/SKILL.md"
CONSULT="$ROOT/shared/skills/consult-specialists/SKILL.md"
BADGES="$ROOT/shared/skills/pr-review/REVIEW-BADGES.md"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
has() { grep -q -- "$1" "$2"; }
lacks() { ! grep -q -- "$1" "$2"; }

has "常にこの2体をエージェントとして起動する" "$SKILL" && \
  fail "mandatory meta+fatal spawn is still in the skill"
has "ユーザーへ「固定: meta, fatal" "$SKILL" && \
  fail "startup report still assumes fixed meta+fatal"
lacks "親レビュー / 追加" "$SKILL" && \
  fail "startup report must say 親レビュー / 追加"

lacks "Act on" "$SKILL" && fail "Lead bucket Act on missing from pr-review"
lacks "Consider" "$SKILL" && fail "Lead bucket Consider missing from pr-review"
lacks "Noted" "$SKILL" && fail "Lead bucket Noted missing from pr-review"
lacks "Dismissed" "$SKILL" && fail "Lead bucket Dismissed missing from pr-review"

lacks "reviewer.: .lead." "$SKILL" && ! grep -q '"lead"' "$SKILL" && \
  fail "parent findings must use reviewer lead"

# Parent (lead) may assign fatal; specialists still may not keep it.
if ! grep -qE 'lead.*fatal|親.*fatal|fatal を付け' "$SKILL"; then
  fail "parent/lead is not allowed to assign fatal"
fi

if ! grep -qE '通常.*0|0体|起動しない' "$SKILL"; then
  fail "default of zero review subagents is not stated"
fi

has "0〜3 体" "$SKILL" && fail "specialist cap is still 0-3"

lacks "Act on" "$CONSULT" && fail "consult-specialists missing Act on"
lacks "Consider" "$CONSULT" && fail "consult-specialists missing Consider"
lacks "Noted" "$CONSULT" && fail "consult-specialists missing Noted"
lacks "Dismissed" "$CONSULT" && fail "consult-specialists missing Dismissed"

if ! grep -qE '判定|Act on' "$SKILL"; then
  fail "4-6 triage table has no Lead disposition"
fi

lacks '"lead"' "$BADGES" && ! grep -q '| `lead`' "$BADGES" && \
  fail "REVIEW-BADGES has no lead animation pool"

printf 'OK\n'
