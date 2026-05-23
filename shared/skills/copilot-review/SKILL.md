---
name: copilot-review
description: |
  GitHub Copilot CLIにコードレビューを委譲し、結果を統合表示するスキル。
  pr-reviewスキルとは異なるAIモデルの視点でセカンドオピニオンを提供する。
  「Copilotにレビューさせて」「Copilotレビュー」「セカンドオピニオンがほしい」
  「別のAIにも見てもらって」「copilot review」「copilotに見せて」
  のようなリクエストで使用する。コードレビューやPRレビューの文脈で
  別の視点が欲しい場合にも積極的に提案すること。
argument-hint: "[対象: diff / staged / PR番号 / branch..branch] [--model モデル名]"
allowed-tools:
  - Bash(copilot:*)
  - Bash(git:*)
  - Bash(gh:*)
  - Bash(wc:*)
  - Read(*)
  - Glob(*)
  - Grep(*)
---

# Copilot Review — セカンドオピニオン

GitHub Copilot CLI を使って、Claude とは異なるAIの視点でコードレビューを行う。
Copilot CLI の非対話モード (`-p ... -s`) で実行し、結果を受け取って整形・表示する。

## ユーザー入力

```text
$ARGUMENTS
```

---

## Phase 1: 前提条件と入力解析

### 1-1. Copilot CLI の存在確認

!`which copilot 2>/dev/null || echo "NOT_FOUND"`

`NOT_FOUND` の場合は以下を案内して停止:
> Copilot CLI がインストールされていません。`npm install -g @github/copilot` でインストールしてください。

### 1-2. レビュースコープの決定

`$ARGUMENTS` を解析して、以下のスコープのいずれかを決定する:

| 入力パターン | スコープ | diff コマンド |
|---|---|---|
| `diff` | 未ステージの変更 | `git diff` |
| `staged` | ステージ済みの変更 | `git diff --staged` |
| `#123` / `123` / PR URL | PR の差分 | `gh pr diff <番号>` |
| `main..feature` | ブランチ間差分 | `git diff main..feature` |
| (指定なし) | 自動検出（下記参照） | — |

**自動検出ロジック（引数なしの場合）:**

1. `git diff --staged` が空でなければ → `staged`
2. `git diff` が空でなければ → `diff`
3. `gh pr view --json number --jq '.number'` が成功すれば → PR モード
4. いずれも該当しなければ → 「レビュー対象の変更がありません」と報告して停止

### 1-3. モデルの決定

`$ARGUMENTS` に `--model <名前>` が含まれていればそのモデルを使用する。
指定がなければ `gpt-5.4` をデフォルトとする。

利用可能なモデル例: `gpt-5.4`, `gpt-5.3-codex`, `gpt-5.4-mini` のいずれかを使う

### 1-4. 現在の状態

!`git status --short`

---

## Phase 2: 差分取得とサイズ判定

### 2-1. 差分の取得

Phase 1-2 で決定した diff コマンドを実行し、差分を取得する。

### 2-2. サイズ計測

差分の行数とファイル数を計測する:

```bash
printf '%s' "$DIFF" | wc -l        # 行数（空文字列で0を返す）
printf '%s' "$DIFF" | grep -c '^diff --git'  # ファイル数
```

### 2-3. Copilot への差分渡し方の決定

| 条件 | 戦略 |
|------|------|
| 差分 200行以下 | プロンプトに diff を直接埋め込む |
| 差分 200行超 | Copilot 自身に diff コマンドを実行させる |

大規模（30ファイル超 or 2000行超）の場合:
- ビジネスロジック > テスト > 設定ファイル > 自動生成ファイルの優先順でフィルタリング
- フィルタリングした旨をユーザーに報告する

---

## Phase 3: Copilot CLI 呼び出し

### 3-1. コマンド構成

```bash
copilot -p "<REVIEW_PROMPT>" \
  -s \
  --model <MODEL> \
  --excluded-tools='write' \
  --allow-all-tools \
  --deny-tool='shell(rm:*)' \
  --deny-tool='shell(git push:*)' \
  --deny-tool='shell(git commit:*)' \
  --deny-tool='shell(git checkout:*)' \
  --deny-tool='shell(sed -i:*)' \
  --deny-tool='shell(mv:*)' \
  --no-custom-instructions
```

各フラグの意味:
- `-s`: テキスト出力のみ（UIなし）
- `--excluded-tools='write'`: Copilot の組み込みファイル書き込みツールを無効化。`--available-tools` は使わない（Copilot の `read_file` 等の組み込みツールまで無効化してしまうため）
- `--allow-all-tools`: 残りのツールを確認なしで自律実行
- `--deny-tool`: 破壊的なシェルコマンドを個別に禁止。deny は allow に常に優先する
- `--no-custom-instructions`: Copilot 側の AGENTS.md を無効化し、クリーンなコンテキストで実行

Bash ツールのタイムアウトには **300000ms（300秒）** を指定する。Copilot CLI 自体にはタイムアウトフラグがないため、Claude Code の Bash ツール側で制御する。

### 3-2. レビュープロンプトの構成

Copilot に渡すプロンプトは英語で構成する（コード解析の精度が高いため）。
以下のテンプレートを使い、スコープに応じて `{SCOPE}` と `{DIFF_INSTRUCTION}` を埋める。

```text
You are a code reviewer. Review the following changes and report findings.

## Scope
{SCOPE}

## Changes to review
{DIFF_INSTRUCTION}

## Output format
For each finding, use exactly this format:
- **L{line}** [{severity}] `{file}` -- {description}

If the finding spans multiple lines, use the starting line number.

Severity levels:
- must: Bug, crash, security vulnerability, data loss
- suggestion: Better alternative exists, meaningful improvement
- nit: Minor style or naming improvement
- good: Well-written code worth praising

## Review perspectives
1. Correctness: logic errors, boundary conditions, error handling, null safety
2. Security: injection, auth gaps, hardcoded secrets, input validation
3. Performance: N+1 queries, memory leaks, inefficient loops
4. Readability: unclear naming, dead code, unnecessary complexity

## Rules
- Only report real issues. Do not pad with trivial findings.
- If no issues found, output exactly: "No significant issues found."
- No preamble, no summary. Output only the findings list.
```

**`{SCOPE}` の埋め方:**
- diff → `"Unstaged changes in the working directory"`
- staged → `"Staged changes (git diff --staged)"`
- PR → `"Pull request #N: {title}"`
- branch → `"Changes between {branch1} and {branch2}"`

**`{DIFF_INSTRUCTION}` の埋め方:**
- 小規模diff（200行以下）→ diff 内容をそのまま埋め込み:
  ```
  Here is the diff:
  ```diff
  {diff内容}
  ```
  ```
- 大規模diff → Copilot に読み取りを指示:
  ```
  Run `{diffコマンド}` to see the changes. Review all modified files.
  ```

### 3-3. 実行

構成したコマンドを Bash で実行する。コマンドが長い場合はヒアドキュメントを使う:

```bash
copilot -p "$(cat <<'PROMPT'
{レビュープロンプト全文}
PROMPT
)" -s --model gpt-5.4 --excluded-tools='write' --allow-all-tools --deny-tool='shell(rm:*)' --deny-tool='shell(git push:*)' --deny-tool='shell(git commit:*)' --deny-tool='shell(git checkout:*)' --deny-tool='shell(sed -i:*)' --deny-tool='shell(mv:*)' --no-custom-instructions
```

### 3-4. エラーハンドリング

| 状況 | 検出方法 | 対応 |
|------|---------|------|
| 認証エラー | 出力に `auth` / `login` / `401` を含む | `copilot login` を案内 |
| タイムアウト | exit code / 出力なし | スコープ縮小を提案 |
| レート制限 | 出力に `rate limit` / `429` を含む | 待機後リトライを提案 |
| その他エラー | 非ゼロ exit code | エラー内容を表示 |

---

## Phase 4: 結果パースと表示

### 4-1. 出力パース

Copilot の出力から findings を抽出する。期待するフォーマット:

```
- **L{line}** [{severity}] `{file}` -- {description}
```

正規表現でパースし、各 finding を構造化する。
パースできない行はスキップし、最後に生テキストとしてフォールバック表示する。

### 4-2. 「問題なし」の判定

パース結果の判定は以下の順序で行う（「findings が空」だけで判断してはならない）:

1. Copilot の出力に `No significant issues found.` が **明示的に含まれている** → 問題なし確定
2. 正規表現に一致する findings が **1件以上ある** → findings として処理（4-3へ）
3. 出力が空でなく、上記いずれにも該当しない → **パース失敗**（4-4 のフォールバックへ）
4. 出力が完全に空 → エラーとして処理（3-4 のエラーハンドリングへ）

問題なしの場合:

```
Copilot Review (gpt-5.4): 問題は検出されませんでした。
```

### 4-3. 結果テーブルの表示

findings がある場合、severity 順（must → suggestion → nit → good）にソートして表示する:

```text
## Copilot Review (gpt-5.4)

| # | ファイル:行 | 問題の内容 | 重要度 |
|---|-----------|-----------|--------|
| 1 | src/foo.rs:42 | nullチェックが漏れており、クラッシュの可能性 | must |
| 2 | src/bar.rs:15 | エラーメッセージが不明瞭 | suggestion |
```

ヘッダーにモデル名を必ず明記する。findings の description は日本語に翻訳して表示する。

### 4-4. パース失敗時のフォールバック

正規表現でのパースが全て失敗した場合、Copilot の生出力をコードブロックで表示する:

```text
## Copilot Review (gpt-5.4) — 生出力

構造化されたパースに失敗したため、Copilot の出力をそのまま表示します:

\`\`\`
{Copilot の生出力}
\`\`\`
```

---

## Phase 5: セカンドオピニオン比較（任意）

会話中に既存の `pr-review` スキルの結果がある場合のみ実行する。

同じPR/差分に対する Claude のレビュー結果と Copilot のレビュー結果を比較し、一致/相違のサマリーを表示する:

```text
## セカンドオピニオン比較

| # | ファイル:行 | Claude | Copilot (gpt-5.4) | 一致 |
|---|-----------|--------|-------------------|------|
| 1 | src/foo:42 | must: nullチェック漏れ | must: null参照の可能性 | Yes |
| 2 | src/bar:15 | — | suggestion: エラーメッセージ改善 | — |
| 3 | src/baz:8 | nit: 命名改善 | — | — |
```

両者が一致した指摘は信頼度が高い。片方のみの指摘は追加の検討材料として提示する。

---

## Phase 6: GitHub投稿（PRスコープ時のみ・任意）

PRスコープでレビューした場合、findings を GitHub レビューコメントとして投稿するか確認する。

**制約事項:** Copilot の出力フォーマットには行番号（`L{line}`）とファイル名のみが含まれ、diff の `side`（LEFT/RIGHT）や複数行範囲（`start_line`）の情報は含まれない。そのため GitHub インラインコメントは **変更後ファイルの単一行（`side: RIGHT`）** に限定される。削除行への正確なコメント配置が必要な場合は、`pr-review` スキルを使用すること。

投稿する場合:
1. Phase 4 の findings からインラインコメントJSONを構築（`side: "RIGHT"` 固定）
2. サマリー本文の冒頭に `**[Copilot Review via {model}]**` を付与してソースを明記
3. `gh api` で PR review を投稿する（`pr-review` Phase 6 と同じ形式）

投稿は明示的に依頼された場合のみ行う。デフォルトでは画面表示のみで完了する。
