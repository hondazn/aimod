---
allowed-tools: Read(*) Write(*) Edit(*) Glob(*) Grep(*) Bash(gh:*) Bash(git:*) Bash(ls:*) AskUserQuestion Agent
argument-hint: '[PR番号 例: #123 または 123]'
description: |
    PRの未解決レビューコメントを取得し、Acceptor（受容者）/Challenger（挑戦者）の
    2視点で合議的に評価して最適な対応（修正 / 返信 / スキップ）を自律的に導くスキル。
    トリガー: 「レビュー対応して」「レビューコメントを修正して」「PR #NNのレビューを対応して」「PRレビューをトリアージして」「レビューを精査して」
name: resolve-review
---
# レビューコメント対応（合議型分類・修正・返信）

## ユーザー入力

```text
$ARGUMENTS
```

作業を開始する前に、ユーザーからの入力を**必ず**理解せよ。

## 目的

PRの未解決レビューコメントを取得し、**Acceptor（受容者）** と **Challenger（挑戦者）** の2視点で合議的に評価して、各コメントへの最適な対応を自律的に導く。

address-review（受容寄り）と triage-review（防御寄り）を高次元に融合した単一スキル。

---

## Phase 1: PR情報取得・前提検証

### 1-1. PR番号の抽出

`$ARGUMENTS` からPR番号を抽出する。以下の形式に対応:
- `#123`
- `123`
- `https://github.com/.../pull/123` 形式のURL
- 番号未指定の場合: `git branch --show-current` → `gh pr view --json number,url,title` で現在ブランチのPRを自動検出

### 1-2. PR情報の取得

```bash
gh pr view <番号> --json number,title,state,headRefName,baseRefName,url,body
```

### 1-3. 前提条件チェック

以下を順に確認し、問題があれば**停止**して報告する:

| チェック項目 | 条件 | 失敗時のアクション |
|-------------|------|-------------------|
| PRステータス | `state == OPEN` | MERGED/CLOSEDなら停止・報告 |
| ブランチ一致 | 現在のブランチ == `headRefName` | 不一致なら `AskUserQuestion` でチェックアウト確認 |
| ワーキングツリー | `git status --porcelain` が空 | 未コミット変更があれば先にコミット/stashを促す |

### 1-4. リモート同期

```bash
git pull --rebase
```

---

## Phase 2: コメント取得・前処理

### 2-1. GraphQL APIで未解決レビュースレッドを取得

REST APIでは `isResolved` / `isOutdated` フィールドが取得できないため、**GraphQL API**を使用する。

> 注意: `reviewThreads(first: 100)` は最大100件。101件以上のスレッドが存在する場合は `pageInfo { hasNextPage, endCursor }` と `after:` 引数でページネーションすること。

```bash
gh api graphql -f query='
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviewThreads(first: 100) {
        nodes {
          isResolved
          isOutdated
          path
          line
          startLine
          comments(first: 50) {
            nodes {
              id
              databaseId
              body
              author { login }
              createdAt
              pullRequestReview {
                state
              }
            }
          }
        }
      }
    }
  }
}' -f owner='{owner}' -f repo='{repo}' -F number=<PR番号>
```

`isResolved == false` かつ `isOutdated == false` のスレッドのみを対象とする。

### 2-2. トップレベルレビュー取得

本文付きのトップレベルレビューを別途取得する:

```bash
gh api repos/{owner}/{repo}/pulls/{number}/reviews --paginate \
  --jq '.[] | select(.body != "") | {id, body, user: .user.login, state}'
```

> トップレベルレビューへの返信は `issues/{number}/comments` APIを使用する（Phase 7参照）。

### 2-3. レビュワー属性判定

各レビュワーに以下の属性をメタデータとして付与する。この情報は Phase 3 の分類精度を上げるインプットとして使用する。

| 属性 | 判定基準 |
|------|---------|
| **AI Bot** | `copilot[bot]`, `devin-ai[bot]`, `[bot]`サフィックス |
| **AI代弁** | 人間アカウントだがAI的文体（過度な丁寧さ、箇条書き構造、一般的すぎる指摘） |
| **人間** | 上記に該当しない |

### 2-4. 対象コードの事前読み込み

各コメントの `path` と `line` から対象コードを `Read` で取得する（該当行の前後20行程度）。

### 2-5. コメントごとの構造化入力パケット構築

各コメントを以下の構造に整形する:

```text
## コメント #N
- スレッドID: <id>
- databaseId: <databaseId>
- レビュワー: <author> (<AI Bot | AI代弁 | 人間>)
- レビュー状態: <CHANGES_REQUESTED | COMMENTED | APPROVED>
- ファイル: <path>
- 行: <line>
- コメント本文: <body>
- 対象コード（該当行の前後20行）:
  ```
  <code snippet>
  ```
- GitHub suggestion の有無: <あり | なし>
```

- **0件の場合**: 未解決コメントがない旨を報告して**正常終了**する

---

## Phase 3: 合議分類

### 3-1. 事前スクリーニング（合議不要コメントの自動分類）

全コメントを3段階でフィルタリングし、合議が必要なコメントのみを Stage 3 に回す:

| Stage | 対象 | 自動分類 | 合議 |
|-------|------|---------|------|
| 1 | GitHub `suggestion` コードブロックを含む | **Mechanical Fix** | 不要 |
| 2 | `nit:` で始まる / 純粋な質問（疑問形のみ） | **Cosmetic** / **Clarification** | 不要 |
| 3 | 上記以外の全コメント | — | **必要** |

### 3-2. 合議の実行方式（動的閾値）

| 合議対象コメント数 | 方式 |
|---|---|
| **0件** | Phase 3 完了。Phase 4 へ進む |
| **1〜3件** | リード自身が両面評価（3-3 へ） |
| **4件以上** | Acceptor/Challenger サブエージェント並列起動（3-4 へ） |

### 3-3. リードによる両面評価（合議対象 3件以下の場合）

サブエージェントを起動せず、リード自身が以下の手順で各コメントを評価する:

各コメントについて:
1. **Acceptor視点**: このコメントに従って修正すべき理由を2-3点列挙する
2. **Challenger視点**: このコメントに従わない理由を2-3点列挙する
3. **対象コードを Read で確認**し、事実に基づいて判断する
4. Phase 4 の合成マトリクスに基づいて最終分類を決定する

結果を以下の形式で記録する:

```text
| # | thread_id | Acceptor視点 | Challenger視点 | verdict組 |
|---|-----------|-------------|--------------|----------|
```

→ Phase 4 へ進む

### 3-4. Acceptor/Challenger サブエージェント並列起動（合議対象 4件以上の場合）

2つのサブエージェントを**同一メッセージ内で並列に**起動する。

**事前準備: プロジェクトコンテキストの収集**

以下の情報を収集し、`$PROJECT_CONTEXT` として構造化する:

1. `CLAUDE.md` または `.claude/CLAUDE.md` が存在すれば、技術スタック・コマンド・ルールに関する記述を抽出
2. プロジェクトのルートにあるビルド設定ファイル（`Cargo.toml`, `package.json`, `pubspec.yaml` 等）から言語・フレームワークを推定
3. `.claude/rules/` 配下のルールファイルがあれば、アーキテクチャやコーディング規約に関する記述を抽出

これらを以下の形式で整形する:

```text
- 技術スタック: <言語> / <フレームワーク>
- アーキテクチャ: <検出できた場合のみ>
- CI: <CLAUDE.mdから検出したコマンド、または推定コマンド>
- コーディング規約: <検出できた場合のみ>
```

**手順**:

1. 以下の **付録 A（Acceptor）** / **付録 B（Challenger）** のプロンプトテンプレートを用いる（エージェント定義ファイルは使わない）
2. 以下の2つの `Agent` 呼び出しを**同一メッセージ内で並列に**実行する:

**Acceptor Agent**:
- description: `Acceptor: PR #<番号> レビューコメント受容的評価`
- prompt: 付録 A の本文。`$COMMENTS` を Phase 2-5 で構築した全コメント入力パケットに、`$PROJECT_CONTEXT` を収集済みのプロジェクトコンテキストに置換
  > 注: `Agent` ツールの `subagent_type` ではなく prompt 埋め込みを使用する理由は、`$COMMENTS` や `$PROJECT_CONTEXT` などのプレースホルダーを動的に置換する必要があるため。

**Challenger Agent**:
- description: `Challenger: PR #<番号> レビューコメント批判的評価`
- prompt: 付録 B の本文。`$COMMENTS` を全コメント入力パケットに、`$DESIGN_CONTEXT` をPR body + baseブランチとの diff 概要に、`$PROJECT_CONTEXT` を収集済みのプロジェクトコンテキストに置換

3. 両Agentの結果（JSON形式の評価結果）を取得する
4. Phase 4 へ進む

---

## Phase 4: 合成・最終分類

### 4-1. 合成マトリクス

Phase 3 の結果（リード自身の両面評価 or サブエージェントのJSON出力）を以下のマトリクスで合成する:

| Acceptor verdict | Challenger verdict | 条件 | 最終分類 |
|---|---|---|---|
| fix | fix | — | **Defect**（修正する） |
| fix | no_fix | Acceptor conf. > Challenger conf. | **Likely Fix**（修正推奨） |
| fix | no_fix | Challenger conf. > Acceptor conf. | **Likely Dismiss**（棄却推奨） |
| fix | no_fix | 同等 | **Contested**（要ユーザー判断） |
| no_fix | fix | Challenger conf. > Acceptor conf. | **Likely Fix**（修正推奨） |
| no_fix | fix | Acceptor conf. > Challenger conf. | **Likely Dismiss**（棄却推奨） |
| no_fix | fix | 同等 | **Contested**（要ユーザー判断） |
| no_fix | no_fix | — | **Dismiss**（返信のみ）→ 4-2 で細分化 |

> **confidence の比較規則**: `high` > `medium` > `low` の全順序。同レベルは「同等」として扱う。未設定値は `low` と同等。

### 4-2. Dismiss の細分化

Challenger の `rejection_basis` に基づいて返信方針を決定する:

| rejection_basis | 最終分類 | 返信方針 |
|---|---|---|
| design_intent | **Design Intent** | 設計意図を説明 |
| pattern_consistency | **Pattern Consistency** | 既存パターンとの一貫性を説明 |
| factual_error | **Incorrect** | 丁寧に誤りを指摘、根拠を示す |
| scope_mismatch | **Out of Scope** | 別Issue化を提案 |
| none | **Clarification** | 質問への回答 |

### 4-3. 結果表示

分類結果を3グループに分けて表示する:

```text
## 合議分類結果

### 合意（両者一致）
| # | ファイル:行 | 最終分類 | レビュワー (属性) | 概要 |
|---|-----------|---------|-----------------|------|
| 1 | src/foo:42 | Defect | reviewer1 (人間) | エラーハンドリング漏れ |
| 2 | src/baz:30 | Design Intent | copilot[bot] (AI Bot) | 命名は既存パターンに準拠 |

### 対立（ユーザー判断が必要）
| # | ファイル:行 | 分類 | Acceptorの見解 | Challengerの見解 |
|---|-----------|------|--------------|----------------|
| 3 | src/qux:8 | Contested | 「Option使用で型安全性が向上」(high) | 「既存パターンと一致、変更不要」(high) |
| 4 | src/abc:20 | Likely Fix | 「エッジケース対応が必要」(high) | 「発生確率が極低」(medium) |

### 自動分類（合議スキップ）
| # | ファイル:行 | 最終分類 | 理由 |
|---|-----------|---------|------|
| 5 | src/def:5 | Mechanical Fix | GitHub suggestion |
| 6 | src/ghi:12 | Cosmetic | nit: prefix |
| 7 | src/jkl:25 | Clarification | 質問形式 |
```

---

## Phase 5: 修正計画の提示・ユーザー承認（ゲート）

### 5-1. 修正計画の提示

Phase 4 の結果をもとに、各コメントに対する対応方針を一覧表示する:

```text
| # | 最終分類 | ファイル:行 | アクション | 修正/返信内容の概要 |
|---|---------|------------|-----------|-------------------|
```

### 5-2. ユーザー承認

`AskUserQuestion` で以下を確認する:

1. **Contested コメントの判断**: Acceptor/Challengerの論点を両方提示し、ユーザーが「修正する」「棄却する」を判断
2. **Likely Fix / Likely Dismiss の確認**: 推奨方針を受け入れるか
3. **コミット戦略**: 1コミットにまとめる（推奨）/ コメントごとに個別コミット
4. 修正方針に対する追加指示があれば受け付ける

ユーザーが分類を変更した場合はそれに従う。

**承認されるまで Phase 6 に進まないこと。**

---

## Phase 6: コード修正・CI検証・コミット・プッシュ

### 6-1. GitHub suggestion の適用

コメント本文に GitHub `suggestion` コードブロック（` ```suggestion `）が含まれるものは、提案内容をそのまま機械的に適用する。

### 6-2. 指摘ベースの修正

Defect / Likely Fix（承認済み）/ Contested（修正判断） / Cosmetic に分類されたコメントについて、指摘内容を理解してコード修正を行う。

### 6-3. 修正順序

同一ファイル内で複数の修正がある場合は、**行番号の大きい方から修正**する（行番号ズレ防止）。

### 6-4. CI検証

プロジェクトの標準的なフォーマット・lint・テストを実行する。

**コマンド検出の優先順位:**

1. **CLAUDE.md / .claude/CLAUDE.md**: 「コマンド」「Commands」セクションに format/lint/test コマンドの記載があればそれを使用
2. **プロジェクト構成ファイルから推定**:

| ファイル | format | lint | test |
|---------|--------|------|------|
| `Cargo.toml` | `cargo fmt --all` | `cargo clippy --workspace --all-targets -- -D warnings` | `cargo test --workspace --all-targets` |
| `package.json` | scripts内の `format` or `lint:fix` | scripts内の `lint` | scripts内の `test` |
| `pubspec.yaml` | `dart format .` | `dart analyze` | `flutter test` |
| `Makefile` | `make fmt`（存在すれば） | `make lint`（存在すれば） | `make test`（存在すれば） |
| `pyproject.toml` | `ruff format` | `ruff check` | `pytest` |
| `go.mod` | `gofmt -w .` | `golangci-lint run` | `go test ./...` |

3. **上記で検出できない場合**: format/lint/testの各ステップをスキップし、修正が構文的に正しいことのみ確認する

- 失敗した場合は修正して再実行する

### 6-5. コミット

Conventional Commits形式でコミットする:

```bash
git add <修正ファイル>
git commit -m "fix: レビュー指摘事項を修正

PR #<番号> のレビューコメントに対応:
- <修正内容1>
- <修正内容2>
..."
```

### 6-6. プッシュ

```bash
git push
```

---

## Phase 7: レビューコメントへの返信・完了報告

### 7-1. 各コメントへの返信

最終分類に応じた返信を投稿する。

**インラインコメントへの返信**:

`in_reply_to` には、GraphQL 取得結果のレビューコメントの `databaseId`（数値の pull request review comment id）を指定すること。

```bash
gh api repos/{owner}/{repo}/pulls/<PR番号>/comments/<databaseId>/replies \
  --method POST -f body='<返信内容>'
```

**トップレベルレビューへの返信**:

```bash
gh api repos/{owner}/{repo}/issues/<PR番号>/comments \
  -f body="<返信内容>"
```

### 7-2. 返信テンプレート（最終分類別）

| 最終分類 | 返信テンプレート |
|---------|--------------|
| Mechanical Fix | `suggestionsを適用しました。ありがとうございます。` |
| Cosmetic | `修正しました。\n- <修正内容>\n\n該当コミット: <SHA>` |
| Defect | `ご指摘の通りです。修正しました。\n- <修正内容>\n\n該当コミット: <SHA>` |
| Likely Fix（修正した場合） | `修正しました。\n- <修正内容>\n\n該当コミット: <SHA>` |
| Contested（修正した場合） | `修正しました。\n- <修正内容>\n\n該当コミット: <SHA>` |
| Design Intent | `意図的にこの実装としています。\n理由: <設計意図の説明>` |
| Pattern Consistency | `既存の<リファレンス>と一貫性を保つため、現状の実装としています。\n参考: <ファイルパス>` |
| Incorrect | `確認したところ、<正しい情報の説明>となっています。\n根拠: <コード参照 or 仕様参照>` |
| Out of Scope | `ご提案ありがとうございます。このPRのスコープ外となるため、別Issueとして検討します。` |
| Clarification | `<質問への具体的な回答>` |
| Likely Dismiss / Contested（棄却の場合） | `<棄却理由の説明>` |

### 7-3. 対応サマリー

最終的な対応結果をテーブル形式で表示する:

```text
| # | ファイル:行 | 最終分類 | アクション | 返信済み |
|---|-----------|---------|----------|---------|
| 1 | src/foo:42 | Defect | 修正 | Yes |
| 2 | src/bar:15 | Cosmetic | 修正 | Yes |
| 3 | src/baz:30 | Design Intent | 返信 | Yes |

PR説明文: 更新済み / スキップ（コード修正なし）
PR URL: <URL>
```

---

## Phase 8: PR説明文の更新

Phase 7 完了後に実行する。コード修正がなかった場合（返信のみ等）はスキップし、その旨を Phase 7-3 のサマリーに記載する。

### 8-1. 更新要否の判断

- Phase 6 でファイル修正・コミットがあった → **更新対象**として 8-2 へ進む
- 返信のみ → **スキップ**し、Phase 7-3 サマリーに「スキップ（コード修正なし）」と記載して終了

### 8-2. 情報収集

```bash
# 現在のPR本文を取得
gh pr view <PR番号> --json body --jq '.body'

# baseブランチとの最新diffを取得
gh pr diff <PR番号>

# コミット一覧を取得
gh pr view <PR番号> --json commits
```

### 8-3. PR説明文の再生成

現在のPR本文をベースに、最新のdiffとコミット履歴を踏まえて内容を更新する。

**セクション構造の検出:**

1. `.github/pull_request_template.md` が存在すれば、そのセクション見出し構造（`## セクション名`）を解析してテンプレートのセクション一覧を取得する
2. テンプレートが存在しない場合は、現在のPR本文の `## ` 見出し行からセクション構造を推定する

**更新対象の判定:**

検出したセクションを以下の基準で「更新対象」「維持対象」に分類する:

| 更新対象となるキーワード（セクション名に含む） | 更新方針 |
|---|---|
| 変更, changes, what changed | レビュー対応による修正を反映 |
| テスト, test | テストが追加・変更された場合に更新 |
| 影響, impact, scope | 修正による影響範囲の変化を反映 |
| レビュー, review | 対応済み指摘の反映 |
| 注意, 懸念, concern, caveat | 解消された懸念の削除、残存する懸念の更新 |

上記に該当しないセクション（概要、背景、目的、関連Issue等）は既存の記述をそのまま保持する。

**テンプレートもPR本文にもセクション構造がない場合**: PR本文全体をレビュー対応を踏まえて自然に更新する。

### 8-4. ユーザー確認ゲート

`AskUserQuestion` で更新後のPR説明文全体をプレビュー表示し、承認を得る。

- 修正指示があれば反映して再提示する
- **承認されるまで 8-5 に進まない**

### 8-5. PR説明文の更新

```bash
gh pr edit <PR番号> --body "$(cat <<'PRBODY'
<更新済みPR本文>
PRBODY
)"
```

### 8-6. 更新確認

更新が反映されたことを確認し、Phase 7-3 の最終サマリーに以下を含めて報告する:

```text
PR説明文: 更新済み（変更内容, テスト観点と影響範囲 等）
PR URL: <URL>
```

---

## 付録 A: Acceptor（受容者）プロンプト

PRレビューコメントを**好意的・受容的に**解釈する。レビュワーの指摘を「正当な改善要求」として捉え、修正すべき理由を積極的に探す。

### プロジェクトコンテキスト

$PROJECT_CONTEXT

### 評価原則

1. **善意の解釈**: レビュワーは改善を意図してコメントしている前提で読む
2. **品質向上の機会**: コード品質・正確性・保守性・可読性が向上するなら修正の価値がある
3. **プロジェクト規約との照合**: プロジェクトのコーディング規約・アーキテクチャパターンとの一貫性を重視
4. **エッジケースの発見**: 指摘が示唆するエッジケースやバグの可能性を検討

### 評価対象

$COMMENTS

### verdict の判定基準

- **fix**: 以下のいずれかに該当する場合
  - 指摘がバグや潜在的不具合を指している
  - 修正によりコード品質が明確に向上する
  - プロジェクト規約・パターンとの一貫性を改善する
  - エラーハンドリングやエッジケースの漏れを補完する
- **no_fix**: 以下のいずれかに該当する場合
  - 指摘が事実誤認に基づいている
  - 修正の価値よりコストが明確に大きい
  - 質問であり回答のみで足りる

### confidence の基準

- **high**: 根拠が明確で判断に迷いがない
- **medium**: 妥当だが別解釈の余地がある
- **low**: 判断材料が不足、またはトレードオフが拮抗

### 出力フォーマット

各コメントについて JSON 配列で出力:

```json
[
  {
    "thread_id": "<スレッドID>",
    "verdict": "fix または no_fix",
    "confidence": "high または medium または low",
    "reasoning": "<修正すべき理由 or 修正不要の理由（2-3文）>",
    "fix_category": "defect または improvement または convention または clarification_only",
    "suggested_action": "<具体的な修正内容 or 返信内容の概要>"
  }
]
```

必ずコード実体を Read で確認してから評価する。

---

## 付録 B: Challenger（挑戦者）プロンプト

PRレビューコメントを**批判的・防御的に**検証する。レビュワーの指摘が本当に正しいのか、こちらの設計意図と整合しているかを厳格に検証する。

### プロジェクトコンテキスト

$PROJECT_CONTEXT

### 評価原則

1. **設計意図の尊重**: PRの実装者には意図がある。その意図を理解した上で指摘の妥当性を判断する
2. **既存パターンとの一貫性**: プロジェクトの既存パターンと一致しているなら現状維持が正当
3. **指摘の正確性検証**: レビュワーの理解が正しいか、コードを実際に読んで検証する
4. **AI由来の過剰指摘の検出**: AI Botや一般的ベストプラクティスの機械的適用を疑う
5. **スコープの適切性**: この指摘はこのPRのスコープに含めるべきか

### レビュワー属性の扱い

コメントに付与されたレビュワー属性（Phase 2-3 参照）を判断材料に含める:

| 属性 | 懐疑レベル |
|------|-----------|
| AI Bot（`[bot]`サフィックス） | 高い。AIは文脈を誤解しやすい |
| AI代弁（人間アカウントだがAI的文体） | 中程度。人間の判断が介在している可能性 |
| 人間 | 標準。内容そのもので判断 |

AI文体の検出ヒント: 過度に構造化された箇条書き、「〜する可能性があります」「〜を検討してください」の多用、コードベース全体を見渡せていない指摘（ローカルな視点のみ）、一般的なベストプラクティスの引用（プロジェクト固有の文脈無視）。

### 評価対象

$COMMENTS

### 設計コンテキスト

$DESIGN_CONTEXT

### verdict の判定基準

- **fix**: 以下のいずれかに該当する場合
  - こちらが本当に見落としていたバグ・問題がある
  - 既存パターンとの不一致がこちら側にある
  - 指摘内容が正確で、設計意図と矛盾しない改善である
- **no_fix**: 以下のいずれかに該当する場合
  - こちらの意図的な設計判断とレビュワーの提案が異なる
  - レビュワーの指摘自体が事実誤認
  - プロジェクトの既存パターンとの一貫性がこちらにある
  - このPRのスコープ外の改善提案（別Issue化が適切）
  - AI由来の文脈無視の一般論

### rejection_basis（verdict が no_fix の場合のみ出力）

- **design_intent**: 設計意図との不一致
- **pattern_consistency**: 既存パターンとの一貫性
- **factual_error**: レビュワーの事実誤認
- **scope_mismatch**: PRスコープ外
- **none**: 上記4カテゴリに該当しない場合（質問への回答など）

> verdict が fix の場合は `rejection_basis` フィールドを省略すること。Phase 4-2 の細分化テーブルがこの値をそのまま使う。

### confidence の基準

- **high**: コードを確認済みで根拠が明確
- **medium**: 妥当だが設計意図の推測に依存
- **low**: 判断材料が不足、追加情報が必要

### 出力フォーマット

各コメントについて JSON 配列で出力:

```json
[
  {
    "thread_id": "<スレッドID>",
    "verdict": "fix または no_fix",
    "confidence": "high または medium または low",
    "reasoning": "<修正すべき理由 or 修正不要の理由（2-3文）>",
    "rejection_basis": "design_intent または pattern_consistency または factual_error または scope_mismatch または none（verdict が no_fix の場合のみ）",
    "suggested_action": "<修正内容 or 反論の根拠>"
  }
]
```

必ずコード実体を Read で確認してから評価する。
