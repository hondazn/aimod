#!/usr/bin/env bash
# Contracts for evidence-discipline/scripts/decision-log.mjs
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$ROOT/shared/skills/evidence-discipline/scripts/decision-log.mjs"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

file="$TMP_ROOT/decisions.tsv"

# 1行目はヘッダ、2行目以降がデータ
node "$LOG" "$file" "探索" "TSV にする" "列が要る規模" "docs/x.md:12" "採用" >/dev/null
node "$LOG" "$file" "実装" "ログを分ける" "PR ごとに読む" "commit abc123" "採用" >/dev/null

[ "$(head -1 "$file")" = "$(printf 'ts\tphase\tdecision\twhy\tevidence\tresult')" ] \
  || fail "ヘッダが正しくない: $(head -1 "$file")"
[ "$(wc -l < "$file" | tr -d ' ')" = "3" ] || fail "行数が 3 でない（ヘッダ重複の疑い）"

# 全行が6列
while IFS= read -r line; do
  cols="$(awk -F'\t' '{print NF}' <<<"$line")"
  [ "$cols" = "6" ] || fail "列数が 6 でない ($cols): $line"
done < "$file"

# セル内のタブ・改行は潰し、数式注入の先頭文字は無害化する
node "$LOG" "$file" $'探索\t2' "決定" $'理由\n改行' $'=SUM(A1)' "ok" >/dev/null
last="$(tail -1 "$file")"
[ "$(awk -F'\t' '{print NF}' <<<"$last")" = "6" ] || fail "サニタイズ後に列が壊れた: $last"
grep -q "'=SUM(A1)" <<<"$last" || fail "数式注入の防御が無い: $last"

# 引数不足は usage エラー（exit 2）
set +e
node "$LOG" "$file" "探索" >/dev/null 2>&1
code=$?
set -e
[ "$code" = "2" ] || fail "引数不足の終了コードが 2 でない: $code"

printf 'decision-log-test: OK\n'
