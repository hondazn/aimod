#!/usr/bin/env bash
# 1段落1物理行の規約を検査する（technical-writing「Markdown の整形」）。
# 段落・リスト項目の途中で折り返した行を見つける。表・見出し・フェンス・frontmatter は対象外。
#
#   ./scripts/check-md-wrap.sh [PATH...]   # 既定: shared/ README.md CLAUDE.md
#
# 除外は「凍結された記録」。docs/specs/ と shared/skills-archive/ は既定の対象に含めない
# （点検の範囲を狭める側に倒す。理由は technical-writing「点検の範囲」）。
#
# フェンスの開閉は CommonMark の規則（同じマーカー文字・同数以上・インデント3以下）で判定する。
# 単純なトグルでは、コード例の中に現れるフェンス行で状態がずれ、コードブロックを段落として
# 結合してしまう（create-pr/SKILL.md で実際に起きた）。
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ "$#" -gt 0 ]; then
  targets=("$@")
else
  targets=("$ROOT/shared/skills" "$ROOT/shared/instructions.md" "$ROOT/shared/agents" "$ROOT/README.md" "$ROOT/CLAUDE.md")
fi

problems=0

report() {
  local file="$1"
  local out
  out="$(awk '
    function indent_of(s,   i) {
      for (i = 0; i < length(s); i++) if (substr(s, i + 1, 1) != " ") return i
      return length(s)
    }
    function marker_run(s,   t, ch, n) {
      t = s; sub(/^[ \t]+/, "", t)
      ch = substr(t, 1, 1)
      if (ch != "`" && ch != "~") return 0
      n = 0
      while (substr(t, n + 1, 1) == ch) n++
      return n
    }
    function is_fence_open(s,   n) {
      if (indent_of(s) > 3) return 0
      return marker_run(s) >= 3
    }
    # can_absorb: 折り返しの受け手になれる行（段落・リスト項目・引用の続き）
    function can_absorb(s,   t) {
      if (s ~ /^[[:space:]]*$/) return 0
      if (s ~ /^#{1,6}[[:space:]]/) return 0
      if (s ~ /^[[:space:]]*\|/) return 0
      if (s ~ /^[[:space:]]*>([[:space:]]|$)/) return 0
      if (s ~ /^[[:space:]]*(-{3,}|\*{3,}|_{3,})[[:space:]]*$/) return 0
      if (indent_of(s) >= 4) return 0          # インデント付きコードブロック
      return 1
    }
    # can_continue: 前の行へ結合される側になれる行（新しいリスト項目は新しい行のまま）
    function can_continue(s) {
      if (!can_absorb(s)) return 0
      if (s ~ /^[[:space:]]*([-*+]|[0-9]+\.)[[:space:]]/) return 0
      return 1
    }
    FNR == 1 && $0 ~ /^---[[:space:]]*$/ { fm = 1; next }
    fm == 1 { if ($0 ~ /^---[[:space:]]*$/) fm = 0; next }
    fence {
      n = marker_run($0)
      if (indent_of($0) <= 3 && n >= fn) {
        t = $0; sub(/^[ \t]+/, "", t)
        if (substr(t, 1, 1) == fch && substr(t, n + 1) ~ /^[ \t]*$/) { fence = 0; prev = "" }
      }
      next
    }
    {
      if (is_fence_open($0)) {
        t = $0; sub(/^[ \t]+/, "", t)
        fch = substr(t, 1, 1)
        fn = marker_run($0)
        fence = 1
        prev = ""
        next
      }
      if ($0 ~ /^[[:space:]]*$/) { prev = ""; next }
      if (can_absorb(prev) && can_continue($0)) printf "%d: %s\n", FNR, $0
      prev = $0
    }
  ' "$file")"
  if [ -n "$out" ]; then
    while IFS= read -r line; do
      printf 'FAIL: %s:%s\n' "${file#"$ROOT"/}" "$line" >&2
      problems=$((problems + 1))
    done <<<"$out"
  fi
}

shopt -s nullglob
for t in "${targets[@]}"; do
  if [ -d "$t" ]; then
    # skills-archive は退避済みの凍結記録なので、ディレクトリ指定でも中へ入らない
    while IFS= read -r f; do
      report "$f"
    done < <(find "$t" -name '*.md' -type f -not -path '*/skills-archive/*' | sort)
  elif [ -f "$t" ]; then
    report "$t"
  else
    printf 'FAIL: 対象が無い: %s\n' "$t" >&2
    problems=$((problems + 1))
  fi
done

if [ "$problems" -gt 0 ]; then
  printf '\n%d 行が折り返されている。1段落1物理行に直す\n' "$problems" >&2
  exit 1
fi

printf 'OK: Markdown の折り返しは無い\n'
