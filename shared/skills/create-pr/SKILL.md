---
allowed-tools: Read(*) Glob(*) Grep(*) Bash(gh:*) Bash(git:*) Bash(cat:*) Bash(ls:*) Bash(rm:*)
argument-hint: '[補足 例: base ブランチ指定・draft PR 指示 など。省略可]'
description: 現在の差分・コミット履歴・関連 Issue から PR 本文を生成し、push して即起票する。PR テンプレートがあればその見出し構造が正本。確認ゲートは置かず、動作確認エビデンスと Test Plan を含める。
name: create-pr
---
# 新規PR作成

## ユーザー入力

```text
$ARGUMENTS
```

`$ARGUMENTS`が空の場合は、現在のブランチ・差分・Issue文脈から PR の種類と範囲を推論する。

## 目的

**「このPRだけ読んでレビュアーが変更意図・検証方法・確認ポイントを把握できる」**状態で PR を起票する。完璧を目指さず、仮決めで即起票する。本文の見出しはリポジトリの PR テンプレートが正本。テンプレが無いときだけフォールバック構造を使う。

このスキルが存在する理由:

- 実装完了からレビュー依頼までの「統合チェックポイント」としての役割
- 「PR を作って」の独立トリガーからも同じ品質で起票できる再利用性
- テンプレ優先と、テンプレが無いリポジトリ向けのフォールバックを一箇所に集約

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
| 現在が `main` / `master` / `trunk` | 中止。作業ブランチ（または worktree）を切って変更を移してから再実行するよう報告する。worktree 運用は `superpowers:using-git-worktrees` を案内する |
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

## Phase 2: テンプレートと命名規則

### 2-1. PR テンプレート（本文の正本）

先にテンプレートを探し、**見つかったら Read する**。`ls` だけで中身を読まない。

探す場所:

- `.github/PULL_REQUEST_TEMPLATE.md` / `.github/pull_request_template.md`
- `.github/PULL_REQUEST_TEMPLATE/*`
- `docs/pull_request_template.md`

- **ある**: その `##` 見出しの集合が本文の正本。追加・改名・欠落は禁止。HTML コメントの案内は残してよい
- **複数ある**: `default` または種別に合う 1 本を選び、選んだファイルだけに従う
- **無い**: Phase 3 のフォールバック構造を使う

直近 PR の本文構造は、テンプレートがあるときは見ない。

### 2-2. 既存 PR のタイトル慣習

```bash
gh pr list --state all --limit 20 --json number,title
```

タイトルの prefix・言語・Issue 紐付けキーワード（`Closes` / `Refs`）だけ読む。本文見出しは 2-1 で決まっている。

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

**テンプレートがある場合**: その `##` 見出しをすべて残し、分かる範囲で埋める。テンプレに無い見出しは足さない。3-3〜3-6 の書き方は、テンプレ側の相当欄（変更前後の比較・UI変更、動作確認エビデンス、確認観点・注意点 など）に流し込む。相当欄が無ければ書かない。

**テンプレートが無い場合**: 以下のフォールバック構造を使う。**末尾に「レビュー時の重点確認ポイント」セクションを必須で付ける**。

```markdown
## 概要

<何を変更したか、なぜ変更したかの簡潔な説明。2-4 行>

## 変更内容

<箇条書きで主要な変更を列挙。ファイル単位ではなく **機能単位** で書く>

- 項目1
- 項目2

## Before / After

<変更前後の比較。画面がある場合はスクリーンショットを貼る。CLI・API・ロジックの変更の場合はビフォーアフターの挙動や出力を記載。Phase 3-3 のルール参照>

| Before | After |
| --- | --- |
| <変更前（画面ならスクショ）> | <変更後（画面ならスクショ）> |

## 関連 Issue

Closes #<番号>
（または Refs #<番号>、該当なしなら本セクション自体を省略）

## 動作確認

<作者が既に実施した動作確認とエビデンス。Phase 3-4 のルール参照>

- [x] <実施済みの確認項目1>
  ```bash
  <確認コマンド>
  <実行結果>
  ```
- [x] <実施済みの確認項目2（画面の場合は、Playwright が使えるなら動画、難しければスクショ等を添付）>

## Test Plan

<この PR に対するレビュアー側・CI 側の追加検証計画。未実施のチェック項目のみ。Phase 3-5 のルール参照>

- [ ] <レビュアー/CI が確認する項目1>
- [ ] <レビュアー/CI が確認する項目2>

## レビュー時の重点確認ポイント

<レビュアーに特に見てほしい箇所。Phase 3-6 のルール参照>

- [ ] <確認ポイント1>
- [ ] <確認ポイント2>
```

### 3-3. Before / After の書き方

テンプレートが**無い**ときだけ **`## Before / After`** を付ける。テンプレートがあるときは、同趣旨の既存見出し（変更前後の比較、UI 変更 など）に同じ内容を書き、見出し名は変えない。

変更前と変更後の違いが一目でわかるように対比し、変更の意図と影響範囲をレビュアーが即座に把握できるようにする。

**書き方のルール:**

- **画面・UI の変更がある場合**: 必ず Before と After の**スクリーンショット**を並べる（Markdown テーブル形式で `| Before | After |` に並べて貼ることを推奨）
- **CLI・API・ロジックの変更の場合**: 挙動やエラーハンドリング、出力フォーマットの変更前後の違いを表やテキストで明記する
- 画面変更がない純粋なリファクタリングや内部修正等でも、振る舞い不変（挙動同一）であることを明記するか、自明な変更なら省略して変更内容・動作確認に集約する

### 3-4. 動作確認の書き方

テンプレートが**無い**ときだけ **`## 動作確認`** を付ける。テンプレートがあるときは、同趣旨の既存見出し（動作確認エビデンス など）に同じ内容を書き、見出し名は変えない。

作者（= PR 起票前にコードを触った人）が**既に実施済みの確認**とその**エビデンス**を記録する。レビュアーに「少なくともここまでは動くことを作者が確認した」という事実を伝える。

**書き方のルール:**

- **チェックリスト形式**で書き、実施済みの項目は必ず `- [x]` にする
- **コマンドによる確認**: 確認コマンドと実行結果を必ず**セットでコードブロック**として記載する（「`コマンド` → 結果」のようなインライン要約で済ませず、実行したコマンドと得られた出力をセットで読めるようにする）
- **画面（UI）による確認**: **Playwright が使える環境なら動画**（`e2e-video` スキルを活用して WebM/MP4 を添付）を基本とする。Playwright が使えない（または環境構築が困難な）プロジェクトではスクリーンショットや GIF で十分。静止画スクショは Before / After セクションで状態比較を示し、動作確認エビデンスでは動的な振る舞いや操作フローを動画（または操作前後の追加スクショ）で証明する
- 各項目に**エビデンスを添える**。可能なら以下の形式を推奨:
  - コマンドと実行結果のセット（コードブロック形式）
  - 画面操作の動画（Playwright 利用時）またはスクリーンショット
  - ログ抜粋（コードブロックで囲む、機密情報は除外）
  - ベンチマーク・計測結果（perf 系 PR の場合）
- **エビデンスが無い確認は書かない**。「一通り動いた」のような主観記述は禁止
- **実施できない確認**は 3-5 の Test Plan に回す（未実施項目として分離）
- 項目数は目安 2〜6 件。網羅性より**決定的な証拠**を優先

**典型パターン:**

| 変更種別 | 典型的な動作確認エビデンス |
|---------|---------------------------|
| feat | 新機能の確認コマンドと実行結果（コードブロック）、画面操作の動画（Playwright 利用時）やスクショ、サンプル入力→出力の対応 |
| fix | バグが再現しなくなったことを示す確認コマンドと実行結果のセット（コードブロック）、画面操作の動画（Playwright 利用時）やスクショ |
| refactor | 既存テスト全 pass の実行コマンドと結果（コードブロック）、型チェッカー/lint 結果、挙動不変を示す差分 |
| perf | ベンチマーク計測結果（before/after 比較表）、プロファイリング結果 |
| docs | プレビュー URL、ビルド確認コマンドとエラー無しの出力ログ（コードブロック） |
| ci | ローカルで `act` 等を実行したコマンドと出力ログ、ダミー PR での実行結果 URL |

**良い例:**

```
## 動作確認

- [x] 新規テストが pass
  ```bash
  npx jest tests/auth/empty_password.test.ts
  # PASS  tests/auth/empty_password.test.ts
  #   ✓ empty_password_returns_400 (12 ms)
  ```
- [x] curl で 400 を確認
  ```bash
  curl -sS -X POST http://localhost:3000/login \
    -H 'Content-Type: application/json' \
    -d '{"email":"a@b.c","password":""}' \
    -w 'HTTP %{http_code}\n'
  # {"error":"password_required"} HTTP 400
  ```
- [x] ログイン画面のバリデーション挙動（動画）: https://github.com/user-attachments/assets/example-demo-video.mp4
- [x] 既存の認証系テストが regression なし
  ```bash
  npx jest tests/auth/
  # Tests: 24 passed, 24 total
  ```
```

**避ける書き方:**

```
## 動作確認

- [x] 動作確認した            ← エビデンスなし
- [x] ローカルで問題ないのを確認  ← 何をどう確認したか不明
- [x] `npm test` → pass       ← コマンドと実行結果がコードブロックでセットになっていない
- [x] 画面でボタンを押して動いた ← 画面のエビデンス（動画やスクショ）がない
```

### 3-5. Test Plan の書き方

**「動作確認（3-4）に書けなかった未実施項目」**だけをここに書く。このセクションはレビュアー・CI 側に委ねる検証計画。

- テンプレートに Test Plan（または同趣旨）があるときは、その見出しを残して埋める。省略しない
- テンプレートが無く、全項目が実施済みで動作確認で済むなら、`## Test Plan` セクションは**省略してよい**
- 未実施項目は `- [ ]` で列挙し、何を検証するかを具体的に書く（例: `- [ ] ステージング環境で 1 時間連続稼働し 5xx が発生しないこと`）
- 「CI に委譲」など、誰が実施するかも明記する

### 3-6. レビュー確認ポイントの書き方

テンプレートが**無い**ときだけ、本文末尾に **`## レビュー時の重点確認ポイント`** を付ける。テンプレートがあるときは、同趣旨の既存見出し（確認観点・注意点 など）に同じ内容を書き、見出し名は変えない。

**レビュアーの注意を方向づけるチェックリスト**であり、以下を含める:

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

### 4-3A. 積み重ねた PR はネイティブの stack に載せる

依存する PR を積むときは、GitHub のネイティブな stack と `gh stack` を使う。個別 PR を `gh pr merge` と `gh pr edit` で継ぎ足して stack の意味を再現しない。stack 所属の正本は base ブランチの推測ではなく `PullRequest.stack` / `stackEntry.position` に置く。

GitHub の状態を変える前に `gh stack --version` を実行する。公式拡張またはサーバ側の stack 機能が無ければ、そこで止める（代替の手順に流れない）。既存の stack を自動で分解・並べ替え・再構築しない。`gh stack link` は追加のみで、マージ済み・キュー済みのエントリは外せない。

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

以下は**テンプレートが無い**リポジトリ向け。テンプレートがあるときは、そちらの見出しをそのまま使い、この例の見出し名に読み替えない。

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

## Before / After

| Before | After |
| --- | --- |
| 空 password 送信時に 500 Internal Server Error が発生 | 400 Bad Request と `{"error":"password_required"}` を返却 |

## 関連 Issue

Closes #12

## 動作確認

- [x] 新規テストが pass
  ```bash
  npx jest tests/auth/empty_password.test.ts
  # PASS  tests/auth/empty_password.test.ts
  #   ✓ empty_password_returns_400 (12 ms)
  ```
- [x] 既存の認証テストに regression なし
  ```bash
  npx jest tests/auth/
  # Tests: 24 passed, 24 total
  ```
- [x] curl で 400 を確認
  ```bash
  curl -sS -X POST http://localhost:3000/login \
    -H 'Content-Type: application/json' \
    -d '{"email":"a@b.c","password":""}' \
    -w 'HTTP %{http_code}\n'
  # {"error":"password_required"} HTTP 400
  ```

## Test Plan

- [ ] ステージングでの動作確認（CI 通過後、デプロイ担当者に依頼）

## レビュー時の重点確認ポイント

- [ ] `ValidationError` → 400 変換が他認証ハンドラと整合しているか
- [ ] 既存の `/api/users` / `/api/signup` に類似の欠陥が残っていないか（本 PR では対象外）
- [ ] 追加テストの期待値（400 + error code）が API 仕様書と一致しているか
```

状態: ready（80 行程度の軽微な修正）

### 例2: 実装途中の feat PR（draft）

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

## Before / After

| Before | After |
| --- | --- |
| 日本語文書の校正エージェントが存在せず、手動での確認が必要だった | `doc-style-reviewer` により文体・表記揺れ・構造の一貫性を自動校正可能になった |

## 関連 Issue

Closes #8

## 動作確認

- [x] サンプル `SKILL.md`（`shared/skills/create-issue/SKILL.md`）に対して手動実行し、指摘を取得
  ```bash
  claude-agent run doc-style-reviewer shared/skills/create-issue/SKILL.md
  # findings[0] severity=suggestion category=文体 "敬体と常体の混在"
  # findings[1] severity=nit        category=表記 "『エージェント』と『agent』の表記揺れ"
  # findings[2] severity=suggestion category=語彙 "『〜すること』の重複"
  ```
- [x] 既存 3 reviewer と JSON スキーマが揃うことを目視確認（`severity`/`category`/`message`/`suggestion` フィールド）

## Test Plan

- [ ] `dotter deploy` 後、`~/.claude/agents/doc-style-reviewer.md` と `~/.cursor/agents/doc-style-reviewer.md` にシンボリックリンクが張られていること（レビュアーに依頼）
- [ ] pr-review スキル経由で他 reviewer と並列呼び出しされること（次 PR で対応）

## レビュー時の重点確認ポイント

- [ ] `description` のトリガー文言と `<example>` ブロックの記載内容
- [ ] JSON `category` 値セットが既存 reviewer と衝突しないか
- [ ] `natural-writing` スキルとの責務重複がないか
- [ ] 校正粒度（nit の閾値）が他 reviewer と揃っているか
```

状態: draft（620 行規模・新規抽象の導入のため）

### 例3: UI 変更を含む feat PR（画面スクショ・動画エビデンス）

**前提:**

- ブランチ: `feat/user-profile-card`
- コミット: 3 件
- 関連 Issue: #45 `feat(ui): redesign user profile card`
- 変更規模: 5 files, +140 / -35（Playwright 環境あり）

**生成:**

- タイトル: `feat(ui): redesign user profile card with modern layout`
- 本文:

```markdown
## 概要

ユーザープロフィールカードのデザインを刷新。アバター画像の高解像度表示対応、ステータスバッジの追加、およびレスポンシブ対応（モバイル幅での折り返し最適化）を実施した。

## 変更内容

- `UserProfileCard.tsx` のグリッドレイアウトを flex から CSS Grid に移行
- オンライン/オフライン状態を表示する `StatusBadge` コンポーネントを新規追加
- モバイル表示時（< 640px）にアクションボタンを縦並びに折り返すレスポンシブスタイルを追加

## Before / After

| Before | After |
| --- | --- |
| ![Before](https://github.com/user-attachments/assets/before-profile-uuid) | ![After](https://github.com/user-attachments/assets/after-profile-uuid) |

## 関連 Issue

Closes #45

## 動作確認

- [x] デスクトップおよびモバイル幅での表示切り替え・ステータス更新操作（動画）: https://github.com/user-attachments/assets/profile-card-interaction-uuid.mp4
- [x] コンポーネント単体テストが pass
  ```bash
  npm test src/components/UserProfileCard.test.tsx
  # PASS  src/components/UserProfileCard.test.tsx
  #   ✓ renders user info correctly (24 ms)
  #   ✓ toggles status badge (18 ms)
  # Tests: 2 passed, 2 total
  ```
- [x] Storybook のビジュアルリグレッションテストで差分なし
  ```bash
  npm run test:storybook
  # 12 stories passed, 0 failures
  ```

## Test Plan

- [ ] Safari / iOS 実機でのフォントレンダリングおよびアスペクト比の確認（QA 担当に依頼）

## レビュー時の重点確認ポイント

- [ ] モバイル幅（375px）で名前の文字数が長い場合にレイアウト崩れが起きないか
- [ ] `StatusBadge` の色コントラスト比がアクセシビリティ基準（WCAG AA）を満たしているか
```

状態: ready（140 行規模の UI 改善）

---

## 他スキルとの関係

| 相棒 | 役割 | このスキルとの関係 |
|------|------|-------------------|
| `/git-commit` | ローカルコミット | 前提として呼ばれる。このスキルはコミット作成しない |
| `/create-issue` | 新規 Issue 起票 | 対になる入口。Issue と PR で責務分担 |
| `codex:rescue` | 差分レビュー | PR 作成**前**に呼ぶ想定。このスキルは事前レビュー済み前提で起票 |
| `pr-review` | 起票後の PR レビュー | このスキルで起票した PR を pr-review でチェックする流れ |

---

## レッドフラグ

| 思考 | 実態 |
|------|------|
| 「コミットされてないからコミットも一緒にやろう」 | `/git-commit` の責務。混ぜない |
| 「PR 本文を短くしよう」 | テンプレの確認欄は空にしない。テンプレが無いときも Test Plan と確認ポイントは省略しない |
| 「レビュー確認ポイントが思いつかない」 | 「自信がない箇所」「設計判断が分かれる箇所」を挙げる。無いなら書き直しを検討 |
| 「draft か ready か迷う」 | 500 行ルールで仮決め。後で変更可能 |
| 「動作確認が無いから書かない」 | 無いなら起票前に 1 つでも確認する。0 件の動作確認は PR の価値を伝えられない |
| 「push 未実施なので確認しよう」 | 確認ゲート禁止。無条件で `git push -u origin <branch>` を実行してから続行する |
| 「テンプレに無い見出しを足そう」 | テンプレの見出しが正本。相当欄に書くか、無ければ書かない |
| 「最近の PR がこう書いていた」 | テンプレがあるなら直近 PR の本文構造は見ない |
