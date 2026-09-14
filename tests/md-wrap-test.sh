#!/usr/bin/env bash
# Contracts for scripts/check-md-wrap.sh: 折り返しを検出し、構造行・コード例は通す。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ROOT/scripts/check-md-wrap.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# リポジトリ本体は常に通る
"$CHECK" >/dev/null || fail "リポジトリ本体が検査に落ちた"

make_md() {
  printf '%s' "$2" > "$TMP_ROOT/$1.md"
}

expect_ng() {
  local file="$TMP_ROOT/$1.md" out
  if out="$("$CHECK" "$file" 2>&1)"; then
    fail "検査が通ってしまった（期待: 折り返し検出）: $1"
  fi
  grep -q '折り返されている' <<<"$out" || fail "期待したメッセージが出ない: $out"
}

expect_ok() {
  "$CHECK" "$TMP_ROOT/$1.md" >/dev/null || fail "通すべきファイルが落ちた: $1"
}

# 1段落1物理行なら通る
make_md one-line '# 見出し

これは1段落1行の本文である。長くても折り返さない。

- 箇条書きも1行で書く
- 次も1行
'
expect_ok one-line

# 段落の折り返しは落ちる
make_md wrapped-para 'これは段落の途中で
折り返している本文である。
'
expect_ng wrapped-para

# リスト項目の継続行は落ちる
make_md wrapped-item '- 項目の本文が長いとき
  継続行に逃げてはいけない。
'
expect_ng wrapped-item

# 入れ子のリスト項目は新しい行のまま通る
make_md nested-item '- 親の項目
  - 子の項目
  - 子の項目2
'
expect_ok nested-item

# 表は各行が独立しているので通る
make_md table '| 列A | 列B |
|---|---|
| 値1 | 値2 |
| 値3 | 値4 |
'
expect_ok table

# フェンス付きコードブロックの中は通る
make_md fenced '```bash
curl -sS -X POST http://localhost:3000/login \
  -H "Content-Type: application/json" \
  -d "{}"
```
'
expect_ok fenced

# フェンスの中に現れるフェンス行（info string 付き）で状態がずれない
# create-pr/SKILL.md で実際に起きた誤検出の回帰テスト
make_md nested-fence '```markdown
- 例
```bash
curl -sS http://localhost/ \
  -d "{}"
```
```
'
expect_ok nested-fence

# インデント付きコードブロックは通る
make_md indented-code '説明:

    curl -sS http://localhost/ \
      -d "{}"
'
expect_ok indented-code

# frontmatter の後の折り返しは落ちる
make_md after-frontmatter '---
name: x
---

この段落は
折り返している。
'
expect_ng after-frontmatter

printf 'md-wrap-test: OK\n'
