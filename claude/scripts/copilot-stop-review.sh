#!/usr/bin/env bash
# copilot-stop-review.sh — Claude Code Stop hook
# Claudeが停止する直前に、Copilot CLIで直前のターンのコード変更をレビューする。
# BLOCK / ALLOW を判定し、BLOCKなら停止をブロックする。
#
# 環境変数:
#   COPILOT_STOP_REVIEW=1  : 有効化（デフォルト: 無効）
#   COPILOT_STOP_REVIEW_MODEL : 使用モデル（デフォルト: gpt-5.4）
#   COPILOT_STOP_REVIEW_TIMEOUT : タイムアウト秒数（デフォルト: 300）

set -euo pipefail

# --- 設定 ---
: "${COPILOT_STOP_REVIEW:=0}"
: "${COPILOT_STOP_REVIEW_MODEL:=gpt-5.4}"
: "${COPILOT_STOP_REVIEW_TIMEOUT:=300}"

# --- 無効なら即終了 ---
if [[ "$COPILOT_STOP_REVIEW" != "1" ]]; then
  exit 0
fi

# --- copilot CLI の存在確認 ---
if ! command -v copilot &>/dev/null; then
  echo "Copilot CLI が見つかりません。copilot stop-review をスキップします。" >&2
  exit 0
fi

# --- stdin からhook入力を読む ---
INPUT="$(cat)"

CWD="$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
LAST_MSG="$(echo "$INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null || true)"

if [[ -n "$CWD" ]]; then
  cd "$CWD"
fi

# --- 直前のターンでコード変更があったか簡易判定 ---
# last_assistant_messageが空、またはツール呼び出し（Edit/Write）の痕跡がなければスキップ
if [[ -z "$LAST_MSG" ]]; then
  exit 0
fi

# Edit/Write/Bash(sed/awk/tee)など、ファイル変更を示すキーワードがなければスキップ
# hookのlast_assistant_messageはtool_useも含むため、これで十分な精度が得られる
HAS_CHANGES=0
for keyword in "Edit" "Write" "NotebookEdit" "created file" "modified file" "wrote to"; do
  if echo "$LAST_MSG" | grep -qi "$keyword"; then
    HAS_CHANGES=1
    break
  fi
done

if [[ "$HAS_CHANGES" -eq 0 ]]; then
  exit 0
fi

# --- git diffで実際の変更を確認 ---
DIFF="$(git diff --stat HEAD 2>/dev/null || true)"
STAGED_DIFF="$(git diff --staged --stat 2>/dev/null || true)"

if [[ -z "$DIFF" && -z "$STAGED_DIFF" ]]; then
  # diffが空 = 実際のファイル変更なし
  exit 0
fi

# --- レビュープロンプト構成 ---
REVIEW_PROMPT="$(cat <<'PROMPT'
You are a code reviewer performing a stop-gate review.
Review ONLY the uncommitted changes in this repository right now.

## Instructions
1. Run `git diff` and `git diff --staged` to see the current changes.
2. Review the changes for:
   - Logic errors, boundary conditions, off-by-one errors
   - Security vulnerabilities (injection, auth gaps, hardcoded secrets)
   - Null/undefined safety issues
   - Missing error handling that could cause crashes
   - Race conditions or data corruption risks
3. Only flag issues that are genuinely blocking — bugs, crashes, security holes, data loss.
4. Do NOT flag style, naming, missing tests, or minor improvements.

## Output contract
Your FIRST line must be exactly one of:
- ALLOW: <short reason>
- BLOCK: <short reason>

If BLOCK, add a brief explanation of each blocking issue after the first line.
Do not put anything before the first ALLOW/BLOCK line.

Use ALLOW if there are no blocking issues.
Use BLOCK only if you found a bug, crash, security hole, or data loss risk that must be fixed before stopping.
PROMPT
)"

# --- Copilot CLI 実行 ---
COPILOT_OUTPUT=""
COPILOT_EXIT=0

COPILOT_OUTPUT="$(timeout "${COPILOT_STOP_REVIEW_TIMEOUT}" copilot \
  -p "$REVIEW_PROMPT" \
  -s \
  --model "$COPILOT_STOP_REVIEW_MODEL" \
  --excluded-tools='write' \
  --allow-all-tools \
  --deny-tool='shell(rm:*)' \
  --deny-tool='shell(git push:*)' \
  --deny-tool='shell(git commit:*)' \
  --deny-tool='shell(git checkout:*)' \
  --deny-tool='shell(git reset:*)' \
  --deny-tool='shell(sed -i:*)' \
  --deny-tool='shell(mv:*)' \
  --no-custom-instructions \
  2>/dev/null)" || COPILOT_EXIT=$?

# --- タイムアウト / エラー処理 ---
if [[ "$COPILOT_EXIT" -eq 124 ]]; then
  echo "Copilot stop-review がタイムアウトしました (${COPILOT_STOP_REVIEW_TIMEOUT}s)。スキップします。" >&2
  exit 0
fi

if [[ "$COPILOT_EXIT" -ne 0 ]]; then
  echo "Copilot stop-review がエラーで終了しました (exit=$COPILOT_EXIT)。スキップします。" >&2
  exit 0
fi

if [[ -z "$COPILOT_OUTPUT" ]]; then
  exit 0
fi

# --- 結果パース ---
FIRST_LINE="$(echo "$COPILOT_OUTPUT" | head -1 | sed 's/^[[:space:]]*//')"

if [[ "$FIRST_LINE" == ALLOW:* ]]; then
  echo "Copilot review: ${FIRST_LINE}" >&2
  exit 0
fi

if [[ "$FIRST_LINE" == BLOCK:* ]]; then
  REASON="$(echo "$COPILOT_OUTPUT" | sed 's/^BLOCK:[[:space:]]*//')"
  # JSON出力でClaude Codeに停止ブロックを伝える
  jq -n --arg reason "Copilot stop-review: $REASON" \
    '{"decision": "block", "reason": $reason}'
  exit 0
fi

# ALLOW/BLOCKどちらでもない場合はスキップ（安全側に倒す）
echo "Copilot stop-review: 想定外の出力。スキップします。" >&2
echo "$COPILOT_OUTPUT" >&2
exit 0
