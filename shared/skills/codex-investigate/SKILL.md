---
name: codex-investigate
description: |
  コードベースの調査・プランニング・設計検討をCodex CLI（GPT-5.4）に委譲するスキル。
  read-onlyモードでリポジトリを探索し、調査結果をClaudeが咀嚼・圧縮して提示する。
  「調査して」「調べて」「リサーチして」「プランニングして」「計画を立てて」
  「実装計画を作って」「原因を調べて」「根本原因を特定して」「影響範囲を調べて」
  「アーキテクチャを調査して」「設計を検討して」「どう実装されているか調べて」
  「コードベースの〜を調べて」「〜の仕組みを調査して」といった調査・計画系の
  リクエストで必ずこのスキルを使うこと。Issue番号やURL付きの調査依頼にも対応する。
  codex:codex-rescueとの違い: rescueはClaudeが行き詰まった時のリアクティブな
  ツールだが、このスキルはユーザーの調査・計画リクエストに最初からCodexを使う
  プロアクティブな委譲スキル。
argument-hint: "[調査テーマ 例: 認証モジュールの構造を調査して / Issue #123の原因を調べて]"
allowed-tools:
  - Bash(codex:*)
  - Bash(gh:*)
  - Bash(git:*)
  - Bash(cat:*)
  - Bash(ls:*)
  - Bash(mktemp:*)
  - Read(*)
  - Glob(*)
  - Grep(*)
---

# Codex調査委譲

## ユーザー入力

```text
$ARGUMENTS
```

作業を開始する前に、ユーザーからの入力を理解する。

## 目的

コードベースの調査・プランニングタスクをCodex CLI（GPT-5.4）に委譲し、その結果をClaude自身が咀嚼・圧縮・検証して、次のアクションに繋げる。

Codexは「調査エンジン」、Claudeは「判断と実行のオーケストレーター」として機能する。Codexの出力を鵜呑みにせず、情報の取捨選択と正確性の検証を主体的に行う。

---

## Phase 1: 入力分析とコンテキスト収集

### 1-1. 調査タイプの分類

`$ARGUMENTS` から調査タイプを判定する:

| タイプ | キーワード例 | 説明 |
|--------|------------|------|
| **codebase** | 「構造を調査」「どう実装されているか」「仕組みを調べて」 | コードベースの探索・理解 |
| **planning** | 「実装計画」「設計を検討」「プランニング」「計画を立てて」 | アーキテクチャ設計・実装計画 |
| **diagnosis** | 「原因を調べて」「なぜ〜が起きるか」「根本原因」 | バグの根本原因分析 |
| **impact** | 「影響範囲」「変更した場合」「依存関係」 | 変更の影響範囲調査 |

複数のタイプに該当する場合は、もっとも支配的なものを選ぶ。

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

### 1-3. 最小限のプロジェクトコンテキスト

以下を収集してCodexに渡すコンテキストとする:

1. **プロジェクト構造**: `ls` でトップレベルのディレクトリ構成を確認
2. **開発ガイドライン**: CLAUDE.md や .cursorrules が存在すれば読み込む（関連箇所のみ）
3. **最近の活動**: `git log --oneline -10` で直近の変更傾向を把握

収集は簡潔に。Codexが自分でコードベースを探索できるので、ここでは方向付けに必要な最小限の情報だけでよい。

---

## Phase 2: Codex向けプロンプト構成

調査タイプに応じたXMLテンプレートでプロンプトを構成する。GPT-5.4はXMLタグベースの構造化プロンプトで高い推論品質を発揮する。

### 共通構造

すべてのプロンプトに含める共通部分:

```xml
<context>
Working directory: {cwd}
Project structure: {ls output}
Guidelines: {CLAUDE.md excerpt if relevant}
Recent activity: {git log excerpt}
{Issue/PR details if available}
</context>
```

### タイプ別テンプレート

#### codebase（コードベース探索）

```xml
<task>
Investigate {topic} in this repository.
Explore the codebase structure, trace through relevant code paths, and document findings.
</task>

<structured_output_contract>
Return:
1. Key findings with file paths and line references
2. Architecture: how relevant components connect
3. Patterns: coding conventions and design decisions observed
4. Open questions: areas needing further investigation
</structured_output_contract>

<research_mode>
Separate observed facts, reasoned inferences, and open questions.
Prefer breadth first, then go deeper where evidence changes the picture.
</research_mode>

<grounding_rules>
Ground every claim in repository context or tool outputs.
If a point is an inference, label it clearly.
</grounding_rules>

<missing_context_gating>
Do not guess missing repository facts.
If required context is absent, retrieve it with tools or state exactly what remains unknown.
</missing_context_gating>
```

#### planning（プランニング）

```xml
<task>
Design an implementation plan for {topic} in this repository.
Analyze existing patterns and architecture, then propose a concrete plan.
</task>

<structured_output_contract>
Return:
1. Current state: relevant existing code and patterns
2. Proposed approach: specific files to create/modify, with rationale
3. Implementation order: dependency-aware sequence of steps
4. Risks and tradeoffs: what could go wrong, alternatives considered
5. Open questions: decisions that need human input
</structured_output_contract>

<research_mode>
Separate observed facts, reasoned inferences, and open questions.
Prefer breadth first, then go deeper where evidence changes the recommendation.
</research_mode>

<grounding_rules>
Ground every recommendation in the repository's existing patterns.
Do not propose approaches that contradict established conventions without flagging it.
</grounding_rules>

<completeness_contract>
Trace through the full implementation path before finalizing.
Check for missed dependencies, edge cases, and integration points.
</completeness_contract>
```

#### diagnosis（根本原因分析）

```xml
<task>
Diagnose why {problem description} is occurring in this repository.
Use repository context and tools to identify the most likely root cause.
</task>

<compact_output_contract>
Return a compact diagnosis with:
1. Most likely root cause with evidence
2. Contributing factors (if any)
3. Smallest safe next step to fix or verify
</compact_output_contract>

<default_follow_through_policy>
Keep going until you have enough evidence to identify the root cause confidently.
Only stop when a missing detail changes correctness materially.
</default_follow_through_policy>

<verification_loop>
Before finalizing, verify that the proposed root cause matches all observed evidence.
Check for second-order failures and edge cases.
</verification_loop>

<missing_context_gating>
Do not guess missing repository facts.
If required context is absent, state exactly what remains unknown.
</missing_context_gating>
```

#### impact（影響分析）

```xml
<task>
Analyze the impact of {proposed change} in this repository.
Trace dependencies, identify affected components, and assess risk.
</task>

<structured_output_contract>
Return:
1. Directly affected files and functions
2. Indirectly affected components (via dependencies, imports, interfaces)
3. Test coverage: which tests exercise the affected paths
4. Risk assessment: likelihood and severity of breakage
5. Recommended verification steps
</structured_output_contract>

<completeness_contract>
Trace through import chains, interface implementations, and call sites.
Do not stop at the first layer of dependencies.
</completeness_contract>

<grounding_rules>
Ground every impact claim in actual code references.
Distinguish between confirmed dependencies and potential ones.
</grounding_rules>
```

### プロンプトの組み立て

1. `<context>` ブロックを構成
2. 調査タイプに応じたテンプレートの `{topic}` / `{problem description}` / `{proposed change}` をユーザーの入力で埋める
3. テンプレートと `<context>` を結合してプロンプトを完成させる
4. プロンプトが長い場合（Issue本文が大きい等）はtmpfileに書き出す:
   ```bash
   PROMPT_FILE=$(mktemp /tmp/codex-prompt-XXXXXX.md)
   cat > "$PROMPT_FILE" << 'PROMPT_EOF'
   {composed prompt}
   PROMPT_EOF
   ```

---

## Phase 3: Codex実行

### 3-1. 前提条件チェック

Codex CLIが利用可能か確認する:

```bash
codex --version
```

- コマンドが見つからない場合: 「Codex CLIがインストールされていません。`npm install -g @openai/codex` でインストールしてください。」と案内し、スキルを終了する
- バージョンが取得できた場合: 続行

### 3-2. 実行

**stdin 閉じ + ファイル出力 + ハードタイムアウト + 無音検知** の四点セットで起動する。これ以外の起動形は禁止。

```bash
LOG=$(mktemp /tmp/codex-out-XXXXXX.log)
codex exec --sandbox read-only "$(cat "$PROMPT_FILE")" \
  < /dev/null \
  > "$LOG" 2>&1 \
  & CODEX_PID=$!

# 上限 15 分（複雑タスクなら 1800 秒まで）の hard timeout +
# 5 分間ファイル mtime が更新されなければ無音と判定して kill
HARD_TIMEOUT=900
SILENCE_LIMIT=300
START=$(date +%s)
while kill -0 $CODEX_PID 2>/dev/null; do
  NOW=$(date +%s)
  if [ $((NOW - START)) -gt $HARD_TIMEOUT ]; then
    echo "[codex-investigate] hard timeout ${HARD_TIMEOUT}s exceeded, killing $CODEX_PID" >&2
    kill $CODEX_PID 2>/dev/null
    break
  fi
  MTIME=$(stat -c %Y "$LOG" 2>/dev/null || echo 0)
  if [ $((NOW - MTIME)) -gt $SILENCE_LIMIT ] && [ $((NOW - START)) -gt $SILENCE_LIMIT ]; then
    echo "[codex-investigate] silent for ${SILENCE_LIMIT}s, killing $CODEX_PID" >&2
    kill $CODEX_PID 2>/dev/null
    break
  fi
  sleep 30
done
wait $CODEX_PID 2>/dev/null
EXIT=$?
tail -300 "$LOG"
rm -f "$LOG" "$PROMPT_FILE"
```

ガード理由:
- `< /dev/null` — codex は起動時に追加 stdin を読みに行く。pipe / heredoc 経由で起動すると親 shell の stdin が閉じない限り永久に "Reading additional input from stdin..." で hang する。明示的に閉じる
- `> "$LOG" 2>&1` ファイル出力 — `| tail` パイプは codex の EOF を待つので、生死判定とトレースが噛み合わない。ファイルなら別シェルから自由に追える
- hard timeout — 上限を切らないと codex が応答性を失った時に検知できない
- silence detection — codex が動いていれば必ずトークンを stream し、ログ mtime が更新される。5 分以上更新が無ければ stuck 確定

実行時の注意:
- `--sandbox read-only` は必須。調査タスクではファイル変更を許可しない
- 認証エラーが出た場合: 「Codex CLIの認証が必要です。`codex login` を実行してください。」と案内
- 上記スクリプトを発行する Bash ツール呼び出し自体には `timeout` パラメータ（HARD_TIMEOUT より長め、例: 1800000ms = 30 分）を別途設定する。スクリプト内の `HARD_TIMEOUT` が先に効くべき設計

### 3-3. エラーハンドリング

| エラー | 対応 |
|--------|------|
| コマンド未検出 | インストール案内を表示して終了 |
| 認証エラー | `codex login` を案内して終了 |
| タイムアウト | 部分的な出力があればそれを使用。なければClaude自身で調査にフォールバック |
| sandbox エラー | bubblewrap未対応環境の可能性を報告 |
| その他のエラー | エラー内容を報告し、Claude自身での調査にフォールバック |

フォールバック時は、Phase 2で構成したプロンプトの内容をClaudeの調査指針として再利用する。

---

## Phase 4: 結果の咀嚼・圧縮・判断

Codexの出力をそのまま提示してはならない。Claudeが主体的に情報処理を行い、関係者の認知負荷を最小化する。

### 4-1. 情報の圧縮と取捨選択

- Codexの出力から**重要な発見だけを抽出**する。冗長な説明、自明な情報、文脈から推測可能な情報は省く
- ファイルパスや行番号など**具体的な根拠は残す**（再現性・検証可能性のため）
- 発見事項を重要度順に並べ替える

### 4-2. 適否の自律的判断

Codexの主張を鵜呑みにしない。以下の検証を行う:

- **ファイルパスの実在確認**: Codexが言及したファイルが実際に存在するか、Glob/Readで確認する
- **コード引用の正確性**: 重要な主張の根拠となるコードを実際に読んで照合する
- **論理の妥当性**: 推論の飛躍や矛盾がないか批判的に評価する
- 矛盾や誤りを発見した場合は自分で修正し、修正した旨を明記する
- 不確実な情報には「（未検証）」「（推測）」と付記する

### 4-3. 次のアクションへの接続

調査結果に基づいて次のステップを自律的に判断し、行動に移す:

| 調査タイプ | 結果 | 次のアクション |
|-----------|------|---------------|
| codebase | 構造が理解できた | 発見に基づいて実装方針を提案 |
| planning | 計画が立った | 計画を提示し、ユーザー承認後に実装着手 |
| diagnosis | 原因が特定できた | 修正の実装に移行 |
| diagnosis | 原因が不明確 | 追加調査を実行（Codex再委譲 or Claude自身） |
| impact | 影響範囲が判明 | テスト計画・修正順序を提案 |

ユーザーが明示的に「調査のみ」「調べるだけでいい」と求めた場合は、結果提示で止める。
