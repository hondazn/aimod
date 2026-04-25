---
name: create-pr
description: |
  GitHub Pull Requestを作成する。現在のブランチの差分とコミット履歴・関連Issue・既存PRのパターンを読み取り、
  タイトル・本文（変更概要・動作確認エビデンス・Test Plan・Issue紐付け・レビュー重点確認ポイント）を生成し、`gh pr create`で即起票する。
  確認ゲートは置かず、仮決め即実行を基本とする。push 未実施でも無条件で `git push -u origin <branch>` を実行してから起票する。
  トリガー: 「PRを作って」「プルリクを作って」「この変更でPR立てて」「PR出して」「Pull Requestを作成」
  「変更をPRにまとめて」「作業をPRにして」「PR化して」。
  明示的に「PR」という語を含まなくても、コミット後の「共有準備」「リモートに出して」「レビュー依頼して」
  といった依頼や、dev-orchestrationのPhase 6でPR作成が必要と判定された場合にも使用する。
  コミット作成は`/git-commit`の役割なので、このスキルはPR作成に限定する。
argument-hint: "[補足 例: base ブランチ指定・draft PR 指示 など。省略可]"
allowed-tools:
  - Read(*)
  - Glob(*)
  - Grep(*)
  - Bash(gh:*)
  - Bash(git:*)
  - Bash(cat:*)
  - Bash(ls:*)
  - Bash(rm:*)
---

# 新規PR作成

## ユーザー入力

```text
$ARGUMENTS
```

`$ARGUMENTS`が空の場合は、現在のブランチ・差分・Issue文脈から PR の種類と範囲を推論する。

## 目的

**「このPRだけ読んでレビュアーが変更意図・検証方法・確認ポイントを把握できる」**状態で PR を起票する。
完璧を目指さず、仮決めで即起票する。レビュー時の確認ポイントは末尾のチェックリストに集約し、レビュアーとのコミュニケーション起点を明示する。

このスキルが存在する理由:

- dev-orchestration の Phase 6 から呼ばれる「統合チェックポイント」としての役割
- 「PR を作って」の独立トリガーからも同品質で起票できる再利用性
- タイトル・本文・Test Plan・Issue 紐付け・レビュー重点ポイントのノウハウを一箇所に集約

---

## 運用原則: 仮決め即実行

- **確認ゲートは置かない**。push 未実施でも無条件で `git push -u origin <branch>` して続行する
- **事前確認ではなく事後報告**で、ユーザーが差し戻せる余地を残す
- draft PR にするかレビュー準備完了の PR にするかは、以下のヒューリスティクスで仮決め:
  - 変更行数が 500 行超、または設計判断を含む → draft
  - それ以外 → ready（draft フラグなし）
  - ユーザー指示 (`--draft` など) があればそれに従う

---

## Phase 1: 前提確認

以下を並列で確認する:

```bash
git branch --show-current       # 現在のブランチ
git log --oneline main..HEAD    # main との差分コミット
git diff main..HEAD --stat      # 変更ファイル一覧と行数
git status                      # 未コミット変更がないか
```

### 1-1. 前提のバリデーション

| 状況 | 対応 |
|------|------|
| 現在が `main` / `master` / `trunk` | 中止。dev-orchestration の Phase 2-1 で worktree を切るべきだったと報告 |
| 未コミット変更あり | 中止。`/git-commit` を先に呼ぶようユーザーに提案 |
| main との差分コミット数が 0 | 中止。「差分がないため PR を作れません」と報告 |
| リモートに push 未実施 | 無条件で `git push -u origin <branch>` を実行してから Phase 1-2 に進む（確認しない） |

### 1-2. 関連 Issue の特定

以下の優先順位で関連 Issue 番号を特定する:

1. ブランチ名に Issue 番号が埋め込まれている（例: `feat/123-user-auth`, `fix/456`）
2. コミットメッセージに `#NN` / `refs #NN` / `closes #NN` が含まれる
3. `git log` のタイトルに完全一致する Open Issue が `gh issue list` に見つかる
4. 見つからない場合は「Issue なし」として処理する

関連 Issue が見つかったら、閉じる (`Closes #N`) か参照のみ (`Refs #N`) かを以下で判定:

- PR で Issue の完了条件を**すべて満たす** → `Closes #N`
- 一部のみ満たす、あるいは関連 PR の一つ → `Refs #N`
- 判定に迷ったら `Closes` で仮決めし、不適切ならユーザーが差し戻せる

---

## Phase 2: 既存パターンの学習

### 2-1. 既存 PR 命名規則

```bash
gh pr list --state all --limit 20 --json number,title,body
```

以下を読み取る:

- タイトルのprefix慣習（`feat:`, `fix:`, `[feat]`, `Add:`, prefix無し等）
- 言語（英語・日本語・混在）
- 本文の定型セクション（Summary / Test Plan / Screenshots 等）
- Issue 紐付けの書き方（`Closes #N` / `Fixes #N` / `関連 Issue: #N` 等）

**明確なパターンがある場合**はそれに従う。**履歴が乏しい**場合は以下のフォールバック構造を使う。

### 2-2. PR テンプレートの確認

```bash
ls .github/pull_request_template.md .github/PULL_REQUEST_TEMPLATE/ 2>/dev/null
```

- テンプレートがあればそのセクション構造を採用
- 無ければ Phase 3 のフォールバック構造を使う

---

## Phase 3: タイトルと本文の生成

### 3-1. タイトル生成

**優先順位:**

1. 関連 Issue のタイトルを prefix 変換して使う（`feat:` Issue → `feat:` PR）
2. コミットが 1 つだけなら、そのコミットメッセージを採用
3. 複数コミットなら、変更の主題から Conventional Commits 形式で合成

**ルール:**

- 簡潔に（60文字以内目安）
- 動詞で始める（命令形）
- 末尾にピリオドを付けない

### 3-2. 本文生成

**テンプレートがある場合**: そのセクション構造を採用し、分かる範囲で埋める。

**テンプレートが無い場合**: 以下のフォールバック構造を使う。**末尾に「レビュー時の重点確認ポイント」セクションを必須で付ける**。

```markdown
## 概要

<何を変更したか、なぜ変更したかの簡潔な説明。2-4 行>

## 変更内容

<箇条書きで主要な変更を列挙。ファイル単位ではなく **機能単位** で書く>

- 項目1
- 項目2

## 関連 Issue

Closes #<番号>
（または Refs #<番号>、該当なしなら本セクション自体を省略）

## 動作確認

<作者が既に実施した動作確認とエビデンス。Phase 3-4 のルール参照>

- [x] <実施済みの確認項目1>（コマンド・結果・ログ・スクショ等）
- [x] <実施済みの確認項目2>

## Test Plan

<この PR に対するレビュアー側・CI 側の追加検証計画。未実施のチェック項目のみ>

- [ ] <レビュアー/CI が確認する項目1>
- [ ] <レビュアー/CI が確認する項目2>

## レビュー時の重点確認ポイント

<レビュアーに特に見てほしい箇所。Phase 3-3 のルール参照>

- [ ] <確認ポイント1>
- [ ] <確認ポイント2>
```

### 3-3. 「レビュー時の重点確認ポイント」セクション（必須）

本文末尾に **`## レビュー時の重点確認ポイント`** を必ず付ける。**レビュアーの注意を方向づけるためのチェックリスト**であり、以下を含める:

**書き方のルール:**

- **チェックリスト形式**で書く（`- [ ] <項目>`）
- **項目は 2〜6 件**を目安にする（0 件は「確認ポイントがない PR は存在しない」ので例外。粒度が細かすぎるなら機能単位に丸める）
- **一項目は具体的**に書く。「全体をレビュー」は禁止、「`UserService.validate()` の null 安全性」「既存呼び出し箇所への影響範囲」のように箇所を特定する
- **「作者が自信がない箇所」「設計判断が分かれる箇所」を優先**。単純な書き換えは書かなくてよい

**典型パターン:**

| 変更種別 | よく出る確認ポイント |
|---------|--------------------|
| feat | I/F 設計、エラーハンドリング、既存 API との互換性、テストカバレッジ |
| fix | 根本対処か対症療法か、回帰リスクの範囲、他の類似バグの有無 |
| refactor | 意味的同値性、既存テストのパス、パフォーマンス影響 |
| perf | ベンチマーク結果、負荷条件の妥当性、キャッシュ戦略の副作用 |
| docs | 事実関係の正確性、用語統一、リンク切れ |
| ci | ローカル検証結果、リリースへの影響範囲、ロールバック手順 |

**良い例:**

```
## レビュー時の重点確認ポイント

- [ ] `AuthService.validateEmpty()` の例外 → 400 変換が他ハンドラと整合しているか
- [ ] 既存の `/api/users` 呼び出しに破壊的影響がないか
- [ ] 追加した `empty_password_returns_400` テストの期待値が仕様とズレていないか
```

**避ける書き方:**

```
- [ ] レビューをお願いします  ← 抽象すぎる
- [ ] 問題ないか確認         ← 何をか分からない
```

### 3-4. 「動作確認」セクション（必須）

本文に **`## 動作確認`** を必ず付ける。作者（= PR 起票前にコードを触った人）が**既に実施済みの確認**とその**エビデンス**を記録する場所であり、レビュアーに「少なくともここまでは動くことを作者が確認した」という事実を伝える。

**書き方のルール:**

- **チェックリスト形式**で書き、実施済みの項目は必ず `- [x]` にする
- 各項目に**エビデンスを添える**。可能なら以下の形式を推奨:
  - コマンドと標準出力: `` `cargo test auth::empty_password` → 1 passed ``
  - curl/HTTP の結果: `` `curl -X POST /login -d '{"password":""}'` → 400 Bad Request ``
  - ログ抜粋（コードブロックで囲む、機密情報は除外）
  - スクリーンショット / 画面キャプチャへの相対パス or URL（例: `![](./docs/assets/before-after.png)`）
  - ベンチマーク・計測結果（perf 系 PR の場合）
- **エビデンスが無い確認は書かない**。「一通り動いた」のような主観記述は禁止
- **実施できない確認**は 3-5 の Test Plan に回す（未実施項目として分離）
- 項目数は目安 2〜6 件。網羅性より**決定的な証拠**を優先

**典型パターン:**

| 変更種別 | 典型的な動作確認エビデンス |
|---------|---------------------------|
| feat | 新機能の正常系コマンド/API 出力、スクショ、サンプル入力→出力の対応 |
| fix | バグが再現しなくなったことを示すコマンド出力（before/after）、テスト pass ログ |
| refactor | 既存テスト全 pass のログ、型チェッカー/lint 結果、挙動不変であることを示す差分（I/O 同一）|
| perf | ベンチマーク計測結果（before/after 比較表）、プロファイリング結果 |
| docs | プレビュー URL、ビルド結果（エラー無しの出力）、スクショ |
| ci | ローカルで `act` 等で実行した結果、ダミー PR での実行結果 URL |

**良い例:**

```
## 動作確認

- [x] 新規テストが pass: `npx jest tests/auth/empty_password.test.ts`
  ```
  PASS  tests/auth/empty_password.test.ts
    ✓ empty_password_returns_400 (12 ms)
  ```
- [x] curl で 400 を確認: `curl -sS -X POST http://localhost:3000/login -H 'Content-Type: application/json' -d '{"email":"a@b.c","password":""}' -w '%{http_code}\n'` → `400`
- [x] 既存の認証系テストが regression なし: `npx jest tests/auth/` → 24 passed, 0 failed
```

**避ける書き方:**

```
## 動作確認

- [x] 動作確認した            ← エビデンスなし
- [x] ローカルで問題ないのを確認  ← 何をどう確認したか不明
```

### 3-5. Test Plan の書き方

**「動作確認（3-4）に書けなかった未実施項目」**だけをここに書く。このセクションはレビュアー・CI 側に委ねる検証計画。

- 全項目が実施済みで動作確認で済むなら、`## Test Plan` セクションは**省略してよい**
- 未実施項目は `- [ ]` で列挙し、何を検証するかを具体的に書く（例: `- [ ] ステージング環境で 1 時間連続稼働し 5xx が発生しないこと`）
- 「CI に委譲」など、誰が実施するかも明記する

---

## Phase 4: 起票

### 4-1. draft 判定

Phase 1-2 の変更規模・Phase 3 の設計判断から以下で仮決め:

- 500 行超の変更、または設計判断を含む → `--draft`
- それ以外 → ready
- ユーザー引数 `--draft` / `--ready` があればそちらを優先

### 4-2. base ブランチ判定

`main` を既定とする。以下の場合は変更:

- リポジトリの既定ブランチが `master`/`trunk` → それに合わせる
- ユーザー引数に `--base <name>` があればそれを採用
- `develop` / `staging` 運用のリポジトリは、`gh repo view --json defaultBranchRef` で既定を確認

### 4-3. 起票実行

本文はシェルエスケープを避けて一時ファイル経由で渡す:

```bash
cat > /tmp/pr-body-$$.md << 'PR_EOF'
<生成した本文>
PR_EOF

gh pr create \
  --base <base_branch> \
  --title "<生成したタイトル>" \
  --body-file /tmp/pr-body-$$.md \
  $DRAFT_FLAG

rm -f /tmp/pr-body-$$.md
```

`gh pr create` は作成された PR の URL を返すので、URL と PR 番号を記録する。

### 4-4. エラーハンドリング

- push 未実施エラー → Phase 1-1 で確認済みなら起きないはず。起きたら push 実行の可否を確認
- 既に同ブランチから PR がある → その PR を更新するか、別ブランチで起票し直すかユーザーに確認
- base ブランチが存在しない → ユーザーに報告して中止
- 権限エラー → 認証状態の確認を促す

---

## Phase 5: 報告

ユーザーに以下を簡潔に報告する:

```
PR #<番号> を起票しました: <URL>
タイトル: <生成したタイトル>
base: <base_branch>  head: <current_branch>
変更: <N> files changed, +<M> / -<K>
状態: <draft | ready>
関連 Issue: <Closes #N | Refs #N | なし>

レビュー時の重点確認ポイント (N 項目):
- <主要 3 件を抜粋>
```

---

## 例

### 例1: Issue 紐付け付き fix PR

**前提:**

- ブランチ: `fix/login-empty-password`
- コミット: 2 件（実装 + テスト）
- 関連 Issue: #12 `fix(auth): return 400 instead of 500 for empty password on login`
- 変更規模: 3 files, +80 / -15

**生成:**

- タイトル: `fix(auth): return 400 instead of 500 for empty password on login`
- 本文:

```markdown
## 概要

ログイン画面で password を空のまま送信すると 500 が返る不具合を修正。バリデーション層で空文字を検出し 400 + エラーメッセージを返すよう変更した。

## 変更内容

- `AuthService.validate()` で空 password を検出して `ValidationError` を投げる
- `AuthController` で `ValidationError` を 400 レスポンスに変換
- `empty_password_returns_400` テストを追加

## 関連 Issue

Closes #12

## 動作確認

- [x] 新規テストが pass: `npx jest tests/auth/empty_password.test.ts`
  ```
  PASS  tests/auth/empty_password.test.ts
    ✓ empty_password_returns_400 (12 ms)
  ```
- [x] 既存の認証テストに regression なし: `npx jest tests/auth/` → 24 passed, 0 failed
- [x] curl で 400 を確認:
  ```bash
  curl -sS -X POST http://localhost:3000/login \
    -H 'Content-Type: application/json' \
    -d '{"email":"a@b.c","password":""}' \
    -w 'HTTP %{http_code}\n'
  # → {"error":"password_required"} HTTP 400
  ```

## Test Plan

- [ ] ステージングでの動作確認（CI 通過後、デプロイ担当者に依頼）

## レビュー時の重点確認ポイント

- [ ] `ValidationError` → 400 変換が他認証ハンドラと整合しているか
- [ ] 既存の `/api/users` / `/api/signup` に類似の欠陥が残っていないか（本 PR では対象外）
- [ ] 追加テストの期待値（400 + error code）が API 仕様書と一致しているか
```

状態: ready（80 行程度の軽微な修正）

### 例2: dev-orchestration 経由の feat PR（draft）

**前提:**

- ブランチ: `feat/doc-style-reviewer`
- コミット: 5 件
- 関連 Issue: #8 `feat(agents): add doc-style-reviewer ...`
- 変更規模: 4 files, +620 / -3（新規エージェント追加）

**生成:**

- タイトル: `feat(agents): add doc-style-reviewer for Japanese technical writing`
- 本文:

```markdown
## 概要

日本語技術文書の校正を担当する新エージェント `doc-style-reviewer` を追加。既存 3 reviewer と同じ JSON 出力インタフェースに揃え、pr-review スキルから横断的に呼び出せるようにした。

## 変更内容

- `shared/agents/doc-style-reviewer.md` を新設（フロントマター + 校正観点 6 項目 + JSON 出力定義）
- `CLAUDE.md` の「既存のエージェント」表に 1 行追記
- dotter 経由で `claude/agents` / `cursor/agents` にシンボリックリンクが張られる構成を確認

## 関連 Issue

Closes #8

## 動作確認

- [x] サンプル `SKILL.md`（`shared/skills/create-issue/SKILL.md`）に対して手動実行し、意味のある指摘 5 件を取得:
  ```
  findings[0] severity=suggestion category=文体 "敬体と常体の混在"
  findings[1] severity=nit    category=表記 "『エージェント』と『agent』の表記揺れ"
  findings[2] severity=suggestion category=語彙 "『〜すること』の重複"
  findings[3] severity=nit    category=表記 "半角英数の前後スペース不足"
  findings[4] severity=good   category=構造 "見出し階層に一貫性あり"
  ```
- [x] 既存 3 reviewer と JSON スキーマが揃うことを目視確認（`severity`/`category`/`message`/`suggestion` フィールド）

## Test Plan

- [ ] `dotter deploy` 後、`~/.claude/agents/doc-style-reviewer.md` と `~/.cursor/agents/doc-style-reviewer.md` にシンボリックリンクが張られていること（レビュアーに依頼）
- [ ] pr-review スキル経由で他 reviewer と並列呼び出しされること（次 PR で対応）

## レビュー時の重点確認ポイント

- [ ] `description` のトリガー文言と `<example>` ブロックの記載内容
- [ ] JSON `category` 値セットが既存 reviewer と衝突しないか
- [ ] `natural-writing` / `redundancy-check` スキルとの責務重複がないか
- [ ] 校正粒度（nit の閾値）が他 reviewer と揃っているか
```

状態: draft（620 行規模・新規抽象の導入のため）

---

## 他スキルとの関係

| 相棒 | 役割 | このスキルとの関係 |
|------|------|-------------------|
| `/git-commit` | ローカルコミット | 前提として呼ばれる。このスキルはコミット作成しない |
| `/create-issue` | 新規 Issue 起票 | 対になる入口。Issue と PR で責務分担 |
| `dev-orchestration` | ワークフロー判断ハブ | Phase 6 からこのスキルを呼ぶ |
| `codex:rescue` | 差分レビュー | PR 作成**前**に呼ぶ想定。このスキルは事前レビュー済み前提で起票 |
| `pr-review` | 起票後の PR レビュー | このスキルで起票した PR を pr-review でチェックする流れ |

---

## レッドフラグ

| 思考 | 実態 |
|------|------|
| 「コミットされてないからコミットも一緒にやろう」 | `/git-commit` の責務。混ぜない |
| 「PR 本文を短くしよう」 | Test Plan と確認ポイントは省略しない。簡潔さより情報密度 |
| 「レビュー確認ポイントが思いつかない」 | 「自信がない箇所」「設計判断が分かれる箇所」を挙げる。無いなら書き直しを検討 |
| 「draft か ready か迷う」 | 500 行ルールで仮決め。後で変更可能 |
| 「動作確認が無いから書かない」 | 無いなら起票前に 1 つでも確認する。0 件の動作確認は PR の価値を伝えられない |
| 「push 未実施なので確認しよう」 | 確認ゲート禁止。無条件で `git push -u origin <branch>` を実行してから続行する |
