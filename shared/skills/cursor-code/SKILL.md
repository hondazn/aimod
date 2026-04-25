---
name: cursor-code
description: |
  コーディング・実装タスクをCursor Agent CLI（composer-2-fast）に委譲するスキル。
  ファイル作成、コード編集、バグ修正、リファクタリングなどの書き込み操作をCursorが実行し、
  結果をClaudeが検証・サマリーして提示する。
  「実装して」「コーディングして」「書いて」「作って」「追加して」「修正して」「直して」
  「リファクタして」「変更して」「更新して」「コードを書いて」「機能を追加」「バグを修正」
  といったコーディング・実装系のリクエストで必ずこのスキルを使うこと。
  Cursorを明示的に指定するリクエスト（「Cursorで」「Cursorに任せて」）にも当然対応する。
  codex-investigateとの違い: codex-investigateはread-only調査の委譲だが、
  このスキルはwrite操作（実装・コーディング）の委譲。調査や計画はcodex-investigate、
  実装はこのスキルという棲み分け。
argument-hint: "[実装タスク 例: 認証ミドルウェアを追加して / src/auth.tsをリファクタして]"
allowed-tools:
  - Bash(agent:*)
  - Bash(git:*)
  - Bash(gh:*)
  - Bash(ls:*)
  - Bash(mktemp:*)
  - Bash(rm:*)
  - Read(*)
  - Glob(*)
  - Grep(*)
---

# Cursorコーディング委譲

## ユーザー入力

```text
$ARGUMENTS
```

作業を開始する前に、ユーザーからの入力を理解する。

## 目的

コーディング・実装タスクをCursor Agent CLI（composer-2-fast）に委譲し、その結果をClaude自身が検証・サマリーして提示する。

Cursorは「実装エンジン」、Claudeは「品質保証とオーケストレーター」として機能する。Claudeは自分でファイルを書かない。コンテキスト収集、プロンプト構成、結果検証に専念する。

---

## Phase 1: 入力分析とコンテキスト収集

### 1-1. タスク内容の理解

`$ARGUMENTS` から以下を把握する:

- **何を実装するか**: 新機能、修正、リファクタリング、変更
- **対象ファイル/モジュール**: 言及されているパス、関数名、クラス名
- **制約や要件**: テストの有無、特定のライブラリ使用、パフォーマンス要件

### 1-2. Issue/PR参照の抽出

`$ARGUMENTS` にIssue番号（`#123`、`123`）やURLが含まれる場合:

```bash
gh issue view <番号> --json title,body,labels,state
```

PR番号の場合:

```bash
gh pr view <番号> --json title,body,headRefName,baseRefName,state
```

取得した情報はPhase 2のプロンプトに `<context>` として含める。

### 1-3. プロジェクトコンテキスト

以下を収集してCursorに渡すコンテキストとする:

1. **プロジェクト構造**: `ls` でトップレベルのディレクトリ構成を確認
2. **開発ガイドライン**: CLAUDE.md、.cursorrules、README.md が存在すれば読み込む（関連箇所のみ）
3. **最近の活動**: `git log --oneline -10` で直近の変更傾向を把握
4. **関連コード**: タスクが特定のファイルに言及している場合、その内容を読んでパターンを確認

収集は簡潔に。Cursorもコードベースを探索できるので、方向付けに必要な最小限の情報でよい。

---

## Phase 2: Cursorプロンプト構成

Cursorに渡すプロンプトを構成する。プロンプトはXMLタグで構造化し、タスクの意図とスコープを明確にする。

### プロンプトテンプレート

```xml
<context>
Working directory: {cwd}
Project structure: {ls output}
Guidelines: {CLAUDE.md / .cursorrules excerpt if relevant}
Recent activity: {git log excerpt}
{Issue/PR details if available}
{Related code excerpts if applicable}
</context>

<task>
{ユーザーの要求を明確な指示として再構成}
</task>

<action_safety>
Keep changes tightly scoped to the stated task.
Do not modify unrelated files or refactor surrounding code.
If the project has existing patterns and conventions, follow them.
If tests exist for the changed code, update them. If a test framework is set up, add tests for new functionality.
</action_safety>

<completeness_contract>
Implement the task fully. Do not leave TODO comments or placeholder implementations.
After implementing, verify the code is coherent: check for broken imports, type errors, and missing dependencies.
</completeness_contract>
```

### プロンプトの組み立て

1. テンプレートの各プレースホルダーをPhase 1で収集した情報で埋める
2. `<task>` にはユーザーの入力を明確な実装指示に言い換える（曖昧さがあれば具体化する）
3. プロンプトが長い場合はtmpfileに書き出す:
   ```bash
   PROMPT_FILE=$(mktemp /tmp/cursor-prompt-XXXXXX.md)
   ```
   ファイルにプロンプト全文を書き出す

---

## Phase 3: Cursor実行

### 3-1. 前提条件チェック

Cursor Agent CLIが利用可能か確認する:

```bash
agent --version
```

- コマンドが見つからない場合: 「Cursor Agent CLIがインストールされていません。Cursorデスクトップアプリの Settings > General > CLI から `agent` コマンドを有効化してください。」と案内して終了
- バージョンが取得できた場合: 続行

### 3-2. Git状態スナップショット

実行前の状態を記録して、後で変更検出に使う:

```bash
git rev-parse HEAD
git status --porcelain
```

未コミットの変更がある場合は「未コミットの変更があります。Cursorの変更と混ざる可能性があります。」と警告する。ただしブロックはしない。

### 3-3. 実行

```bash
agent -p --trust --force --model composer-2-fast --output-format json "<composed prompt>"
```

プロンプトをtmpfileに書き出した場合:

```bash
agent -p --trust --force --model composer-2-fast --output-format json "$(cat "$PROMPT_FILE")"
rm -f "$PROMPT_FILE"
```

実行時の注意:
- `--trust` は headless 実行でワークスペース信頼を自動承認するために必須
- `--force` はファイル書き込みやシェルコマンドの自動承認に必須
- `--output-format json` で `is_error` フィールドによるエラー検出が可能
- タイムアウト: 300秒（5分）を設定する。実装タスクは時間がかかることがある

### 3-4. エラーハンドリング

| エラー | 対応 |
|--------|------|
| コマンド未検出 | インストール案内を表示して終了 |
| 認証エラー | 「`agent login` を実行してください。」と案内して終了 |
| タイムアウト | 「Cursorの実行がタイムアウトしました（5分）。タスクが大きすぎる可能性があります。」と報告して終了 |
| JSON出力の `is_error: true` | エラー内容を報告して終了 |
| JSONパース失敗 | 生の出力をテキストとして扱い、Phase 4に進む |

**重要**: Cursorが失敗した場合、Claude自身での実装にフォールバックしない。ユーザーがCursor委譲を選択しているため、失敗時はその旨を報告し、ユーザーの判断を仰ぐ。

---

## Phase 4: 結果検証・サマリー

### 4-1. 変更の検出

Phase 3-2のスナップショットと比較して、Cursorが行った変更を特定する:

```bash
git status --porcelain
git diff --stat
```

新規ファイル、変更されたファイル、削除されたファイルをそれぞれリストアップする。

### 4-2. 変更内容の検証

変更されたファイルを読み、以下を確認する:

- **構文の妥当性**: 明らかな構文エラーや不完全なコードがないか
- **実装の完全性**: TODO、FIXME、プレースホルダーが残っていないか
- **スコープの適切性**: タスクに無関係なファイルが変更されていないか
- **パターンの一貫性**: プロジェクトの既存パターンと著しく異なるスタイルでないか

### 4-3. lint/test/formatの実行

プロジェクトにlint、テスト、フォーマットのツールがセットアップされている場合（package.json, Makefile, pyproject.toml 等で検出）、実行して結果を報告する。ツールの有無が不明な場合は省略してよい。

### 4-4. サマリーの提示

以下の形式で結果を報告する:

1. **変更概要**: 作成/変更/削除されたファイル一覧と各ファイルの変更内容の要約
2. **Cursorの所感**: Cursorの出力テキストから有用な情報を抽出（実装判断の理由等）
3. **検証結果**: lint/testの結果、問題があれば具体的に指摘
4. **実行メトリクス**: JSON出力から `duration_ms` とトークン使用量を報告

### 4-5. 問題がある場合

検証で問題が見つかった場合:

- 問題の内容を具体的に報告する
- 自分で修正はしない（Write/Editツールを持っていない）
- 「再度Cursorに修正を依頼しますか？」とユーザーに確認する
- ユーザーが望めば、修正内容を明確にしたプロンプトで再度Phase 2から実行する

## 注意事項

- このスキルはClaude自身によるファイル書き込みを一切行わない。Write/Editツールは意図的にallowed-toolsから除外されている
- `--force` フラグによりCursorはすべてのツール実行を自動承認する。これはヘッドレス実行に必須だが、意図しないファイル変更のリスクがある。Phase 4の検証でそれを補う
- 調査・計画タスクはこのスキルの対象外。それらは `codex-investigate` に委譲する
