#!/usr/bin/env bash
# Contracts for scripts/check-skills.sh: 壊れたスキルを検出し、正しいスキルは通す。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ROOT/scripts/check-skills.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# リポジトリ本体は常に通る
"$CHECK" >/dev/null || fail "リポジトリの shared/skills が検査に落ちた"

# 1スキルだけを持つ検査用ディレクトリを作る
make_skill() {
  local dir="$1" name="$2" body="$3"
  mkdir -p "$dir/$name"
  printf '%s\n' "$body" > "$dir/$name/SKILL.md"
}

expect_ng() {
  local dir="$1" pattern="$2"
  local out
  if out="$("$CHECK" "$dir" 2>&1)"; then
    fail "検査が通ってしまった（期待: $pattern）"
  fi
  grep -q -- "$pattern" <<<"$out" || fail "期待したメッセージが出ない: $pattern / 実際: $out"
}

# Codex 用の呼び出しポリシー（スキル直下の agents/openai.yaml）
make_codex_policy() {
  local dir="$1" name="$2" body="$3"
  mkdir -p "$dir/$name/agents"
  printf '%s\n' "$body" > "$dir/$name/agents/openai.yaml"
}

# name がディレクトリ名と違う
d="$TMP_ROOT/name-mismatch"
make_skill "$d" other '---
name: wrong
description: 何か
---
本文
'
expect_ng "$d" "ディレクトリ名と違う"

# description が上限を超える
d="$TMP_ROOT/long-desc"
long="$(printf 'あ%.0s' $(seq 1 201))"
make_skill "$d" long-desc "---
name: long-desc
description: $long
---
本文
"
expect_ng "$d" "上限 200 字を超えている"

# 相対リンクが解決しない
d="$TMP_ROOT/broken-link"
make_skill "$d" broken-link '---
name: broken-link
description: 何か
---
[参照](references/missing.md)
'
expect_ng "$d" "相対リンクが解決しない"

# 相対リンクがスキルディレクトリの外を指す
d="$TMP_ROOT/escape-link"
make_skill "$d" escape-link '---
name: escape-link
description: 何か
---
[外](../outside.md)
'
expect_ng "$d" "スキルディレクトリの外を指す"

# description が無い
d="$TMP_ROOT/no-desc"
make_skill "$d" no-desc '---
name: no-desc
---
本文
'
expect_ng "$d" "description が無い"

# description が複数行
d="$TMP_ROOT/multiline-desc"
make_skill "$d" multiline-desc '---
name: multiline-desc
description: 1行目
  2行目
---
本文
'
expect_ng "$d" "description が複数行"

# インラインコード内のリンク例は参照切れとして数えない
d="$TMP_ROOT/example-link"
make_skill "$d" example-link '---
name: example-link
description: 何か
---
エビデンスの例: `![](./docs/assets/before-after.png)`
'
"$CHECK" "$d" >/dev/null || fail "インラインコード内のリンク例を参照切れと誤判定した"

# 実在する補助ファイルへのリンクは通る
d="$TMP_ROOT/valid"
make_skill "$d" valid '---
name: valid
description: 何か
---
[詳細](references/detail.md)
'
mkdir -p "$d/valid/references"
printf '詳細\n' > "$d/valid/references/detail.md"
"$CHECK" "$d" >/dev/null || fail "正しいスキルが検査に落ちた"

# 呼び出し制御の値は true / false だけ（fail-closed）
d="$TMP_ROOT/bad-invocation-value"
make_skill "$d" bad-invocation-value '---
name: bad-invocation-value
description: 何か
disable-model-invocation: True
---
本文
'
expect_ng "$d" '値 "True" が不正'

# camelCase のキーは使わない（DSH が拒否する）
d="$TMP_ROOT/camel-invocation"
make_skill "$d" camel-invocation '---
name: camel-invocation
description: 何か
disableModelInvocation: true
---
本文
'
expect_ng "$d" "camelCase の呼び出し制御キー"

# フラグだけでは足りない。Codex と opencode は無視するので description でも宣言する
d="$TMP_ROOT/silent-manual"
make_skill "$d" silent-manual '---
name: silent-manual
description: 何かのやつ
disable-model-invocation: true
---
本文
'
expect_ng "$d" "手動起動を宣言していない"

# モデルからもユーザーからも呼べない組み合わせは到達不能
d="$TMP_ROOT/unreachable"
make_skill "$d" unreachable '---
name: unreachable
description: /unreachable と打たれたときだけ使う
disable-model-invocation: true
user-invocable: false
---
本文
'
expect_ng "$d" "到達不能"

# 手動起動を description で宣言していれば通る（Codex 用の yaml も揃っている）
d="$TMP_ROOT/manual-ok"
make_skill "$d" manual-ok '---
name: manual-ok
description: /manual-ok と打たれたときだけ使う。モデルは自動選択してはならない。
disable-model-invocation: true
---
本文
'
make_codex_policy "$d" manual-ok 'policy:
  allow_implicit_invocation: false
'
"$CHECK" "$d" >/dev/null || fail "手動起動を宣言したスキルが検査に落ちた"

# Codex は frontmatter を無視するので、yaml が無いと Codex だけ自動選択に戻る
d="$TMP_ROOT/no-codex-policy"
make_skill "$d" no-codex-policy '---
name: no-codex-policy
description: /no-codex-policy と打たれたときだけ使う
disable-model-invocation: true
---
本文
'
expect_ng "$d" "agents/openai.yaml が無い"

# フラグと yaml が食い違う
d="$TMP_ROOT/policy-mismatch"
make_skill "$d" policy-mismatch '---
name: policy-mismatch
description: /policy-mismatch と打たれたときだけ使う
disable-model-invocation: true
---
本文
'
make_codex_policy "$d" policy-mismatch 'policy:
  allow_implicit_invocation: true
'
expect_ng "$d" "矛盾する"

# yaml だけあってフラグが無い（Codex だけ手動専用）
d="$TMP_ROOT/policy-orphan"
make_skill "$d" policy-orphan '---
name: policy-orphan
description: 何かのやつ
---
本文
'
make_codex_policy "$d" policy-orphan 'policy:
  allow_implicit_invocation: false
'
expect_ng "$d" "Codex だけ手動専用"

# yaml のキーは snake_case のみ
d="$TMP_ROOT/policy-camel"
make_skill "$d" policy-camel '---
name: policy-camel
description: /policy-camel と打たれたときだけ使う
disable-model-invocation: true
---
本文
'
make_codex_policy "$d" policy-camel 'policy:
  allowImplicitInvocation: false
'
expect_ng "$d" "camelCase"

# yaml の値は true / false のみ（fail-closed）
d="$TMP_ROOT/policy-bad-value"
make_skill "$d" policy-bad-value '---
name: policy-bad-value
description: 何かのやつ
---
本文
'
make_codex_policy "$d" policy-bad-value 'policy:
  allow_implicit_invocation: maybe
'
expect_ng "$d" "不正"

printf 'skills-lint-test: OK\n'
