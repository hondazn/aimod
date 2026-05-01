---
name: juggernaut
license: MIT
description: |
  コード変更・多ファイル横断の理解を伴うタスクで、claude が手を動かす前に委譲ワークフロー（Issue → worktree → subagent 調査 → 計画レビュー → TDD 実装 → 並列レビュー → PR）を確立する自律オーケストレーションスキル。
  トリガー: 実装系（実装・修正・追加・直して・書いて・作って・リファクタ・変更・更新・機能追加・バグ修正）／調査系（調査・調べて・リサーチ・プランニング・計画・原因・根本原因・影響範囲・仕組みを理解・構造を調べて）を検知したら起動する。ソースコードへの Edit/Write、GitHub Issue/PR URL、暗黙の実装依頼にも適用。
  詳細（強制内容・運用原則・例外パス・レッドフラグ）は本文参照。「skill を呼ぶほどではない」「自分でやった方が早い」が浮かんだ瞬間こそ必要な兆候。undertriggering より overtriggering を優先。
---

# 開発ワークフローの自律オーケストレーション

## このスキルが存在する理由

claude 単独でコードを書くと **独立した第二の視点** が失われ、自分の早合点・命名のクセ・
盲点がそのまま PR に流れ込みやすい。このスキルは、claude を「判断のハブ」、subagent を
「観点別の独立調査者・レビュアー」に分けて、**外部視点による相互検証**を毎ターン強制する。

過去に発生した失敗:

- `main` ブランチ上で直接 CI ワークフローを編集した
- Issue を作らずに作業へ着手した
- 「軽い調査だから」と subagent 委譲を省略し grep を繰り返した
- auto mode の「即時実行」を盾に計画レビューを飛ばした
- claude が一気書きしたコードを self-review だけで PR に出し、レビュー段階で must 級の指摘を受けた

これらは**一つ一つは部分的に正当な判断**だが、積み重ねるとワークフローの骨格が崩れる。
このスキルは、その骨格を明示的なチェックポイントで再構築する。

---

## 運用原則: 全自動・仮決め即実行

ユーザーは「原則、全部自動で進める」ことを期待している。**確認ゲートは置かない**。

- ブランチ名・Issue タイトル / 種別 / スコープ・起票粒度が曖昧でも、claude が
  仮決めして進める。仮決めの根拠を一文で宣言してから実行する
- 事前確認ではなく**事後報告**でユーザーに差し戻し余地を残す
- ワークフローの骨格 (Phase 1→6 の順序、subagent 委譲、worktree、並列レビュー) は崩さない。
  骨格をスキップするのは禁止。骨格「内部」の確認のみ省略する

### 確認が許される例外

以下の場合に限り、事前にユーザーへ確認する:

- 破壊的で取り返しがつかない操作 (force-push, 本番データ削除, 公開 API 破壊的変更)
- ユーザーがそのセッションで明示的に「確認してから進めて」と指示した場合
- 外部サービスへの課金や副作用を伴う操作

「曖昧だから一応確認しておこう」は **禁止**。仮決めして走る。

---

## Phase 1: リクエスト分類

ユーザーの直近メッセージを読み、分類する:

| 分類 | シグナル | 進むべき Phase |
|------|---------|---------------|
| 実装タスク | 「実装」「修正」「追加」「書いて」「作って」「リファクタ」「直して」 | 2 → 3 → 4 → 5 → 6 |
| 調査/計画タスク | 「調査」「調べて」「原因」「仕組み」「計画」「影響範囲」「設計検討」 | 2 → 3 のみ |
| 設定/ドキュメントの軽微変更 | typo 修正、定数調整、README 追記、`.github/**` の単発修正、`.claude/**` 設定変更など、機能仕様・公開 API・CI 挙動に影響しない変更 | 2 → 4 (claude 直接) → 5 (軽量) → 6 |
| 会話/質問 | 「どう思う？」「なぜ？」「〜について教えて」 | 通常応答。スキル終了 |

判定に迷ったら**より重い分類**を選ぶ。過剰な委譲のコストより、骨格崩壊のコストの方が大きい。

---

## Phase 2: 前提確認 (ブランチ + Issue)

Phase 3〜5 に進むすべての分類で必ず通過する。`main`/`master`/既存ブランチの状態を確認し、
Issue の有無も確認する。

### 2-1. ブランチ確認 (worktree 前提)

```bash
git branch --show-current
```

ブランチ作成は必ず **`git worktree add -b <branch> <path> <start-point>`** または
`EnterWorktree` ツール (ToolSearch で schema 取得後) を使う。`git checkout -b` /
`git switch -c` は本ワークフローでは使わない（worktree を分離しないと CI 編集や設計変更で
作業ブランチが混線する）。

`<path>` の選定は `superpowers:using-git-worktrees` スキルが正本:

1. 既存の `.worktrees/` があればそこ
2. 既存の `worktrees/` があればそこ
3. CLAUDE.md に worktree ディレクトリ指定があればそれ
4. なければ `.worktrees/<branch>` を既定とする (初回は `.gitignore` 追加+コミットを skill が実施)

迷ったら `superpowers:using-git-worktrees` を明示的に呼び出す。directory selection・
`.gitignore` 安全確認・baseline test まで面倒を見てくれる。

結果が `main` / `master` / `trunk` の場合:

1. タスクから仮のブランチ名を決める (例: `fix/ci-path-filter`, `feat/user-auth`,
   `refactor/font-loader`, `docs/readme-update`)
2. ブランチ名と一文の根拠を宣言する
3. そのまま worktree を作成し、作業ディレクトリとして使う
4. 確認は求めない

すでに作業ブランチ上にいる場合はそのまま進む。タスクと明らかに乖離するブランチ名なら
新 worktree を切る (これも確認不要、事後報告で差し戻し可能にする)。

### 2-2. Issue 確認

```bash
gh issue list --search "<タスクのキーワード>" --state open --json number,title,state,url
```

#### 関連 Issue が見つかった場合

- タイトルと本文を `gh issue view` で確認
- 内容が今回のタスクと十分に合致していれば番号を記録し Phase 3 に進む
- 微妙にズレていても claude が仮判断で「紐付ける / 新規起票する」を選び即実行する

#### 関連 Issue が見つからなかった場合

claude が `gh issue create` で起票する。タイトル / 種別 / 本文 /
`## 明確にすべきポイント` チェックリストは仮決めで埋め、起票後に番号を記録して Phase 3 へ。
`/refine-issue` skill が利用できる場合は、起票直後に呼んで未確定箇所を精緻化する選択肢もある。

### 2-3. 例外: 極めて軽微な変更

すべてを満たす場合のみ Issue 起票を省略してよい:

- Phase 1 で「設定/ドキュメントの軽微変更」に分類された
- 変更内容が typo 修正 / 定数値の軽微な調整 / 追記のみ
- 機能仕様・CI/デプロイ挙動・公開 API に影響しない

「軽微だと思い込みたい」自体がレッドフラグ。確信が持てないなら起票側に倒す。
ブランチ確認 (2-1) はこのケースでもスキップしない。

---

## Phase 3: 調査フェーズ (subagent 委譲)

以下のいずれかに該当する場合、**Agent ツールで subagent に委譲**する:

| トリガー | 例 | 推奨 subagent |
|---------|-----|--------------|
| 多ファイル横断のキーワード探索 | 「認証関連のコードを集めて」 | `Explore` |
| 仕組み・設計の説明を求められた | 「なぜこのデータ構造なのか」 | `feature-dev:code-explorer` |
| 根本原因の特定 | 「このバグの原因を特定して」 | `feature-dev:code-explorer` |
| 影響範囲の分析 | 「この関数を変えたら何が壊れる？」 | `feature-dev:code-explorer` |
| 実装計画の策定 | 「〜を実装する計画を立てて」 | `feature-dev:code-architect` (Phase 4-2 と兼ねる) |

claude が自分で grep / read を **3 回以上**繰り返したくなったら、その時点で止めて
subagent に委譲する。claude が直接読んでよいのは**ブランチ・Issue 判定に必要な最小限**
(`git status`, `ls`, `CLAUDE.md` 冒頭, 1〜2 ファイル程度) のみ。

委譲時のプロンプトには以下を含める:

- 何を達成したいか（背景・前提・既知のこと）
- 答えてほしい問い
- 探索の幅（quick / medium / very thorough）
- 報告の長さ上限（例: 200 語以内）

subagent は会話文脈を持たない別人。**自己完結したプロンプト**を渡すこと。

### 委譲スキップが許される稀なケース

- 直近の会話で同じファイルの内容を既に読んでおり追加調査が不要
- 単一ファイル内の既知の箇所への局所修正で、周辺コンテキストが自明

このスキップを行った場合、**なぜ委譲しなかったか**を一文でユーザーに報告する。

---

## Phase 4: 実装フェーズ

### 4-1. 実装の進め方を決める

| 状況 | 進め方 |
|------|--------|
| 単一ファイル / 局所修正 + テスト容易 | claude が直接 TDD で実装 |
| 多ファイル変更 / 設計判断あり | 4-2 計画レビュー → claude が TDD で実装 |
| 独立した複数タスクが並行可能 | `superpowers:dispatching-parallel-agents` で並列化 |
| 大きな機能追加 (新コンポーネント・新サービス) | `feature-dev:feature-dev` skill or `feature-dev:code-architect` agent |
| 既に書かれた plan を別セッションで実行 | `superpowers:executing-plans` |

**TDD は原則として徹底する** (グローバル CLAUDE.md 規定: 探索 → Red → Green → Refactor)。
claude が直接実装に入る前に `superpowers:test-driven-development` skill を呼び出し、
Red → Green → Refactor の順で進める。テストが書きにくいタスク (UI 微調整、設定変更、
ドキュメント) はこの限りでない。

### 4-2. 計画レビュー (実装前、設計判断を含む場合)

以下のいずれかに該当する場合、実装に手を付ける**前**に計画レビューを受ける:

- 変更ファイルが 3 つ以上
- 設計判断 (新しい抽象, 依存関係の変更, インターフェース設計) を含む
- 破壊的変更 (公開 API, データ構造, 設定互換性の変更)
- セキュリティ・認証・課金など影響が大きい領域

実装計画を文章化し、以下のいずれかでレビューを受ける:

- `Plan` agent (`subagent_type: Plan`): 実装ステップ・重要ファイル・トレードオフを返す
- `feature-dev:code-architect` agent: 既存コードベースのパターンに沿った設計 blueprint を返す
- `meta-reviewer` + `techlead-reviewer` agent を **並列起動**して計画文書をレビュー（meta が方向性、techlead が技術アプローチ妥当性を見る）

軽微な実装では省略してよいが、**省略した判断自体をユーザーに報告する**
(例: 「計画レビューを省略しました。理由: 単一ファイルへの局所修正のため」)。

### 4-3. 実装の実行

- 大規模 / 並列化可能 → `superpowers:subagent-driven-development` を呼ぶ
- 通常 → claude 自身が TDD で実装。Phase 3 の調査結果と Phase 4-2 の計画をコンテキストに保つ
- テストが green になるまで反復する。CLAUDE.md の「KPI やカバレッジ目標が与えられたら、
  達成するまで試行する」を守る

実装は最小差分にとどめる。関係ない箇所のついでの修正は避ける（Phase 5 のレビュー観点が
ぶれる）。

---

## Phase 5: 実装後レビュー + 動作検証（自律実行）

実装が一区切りしたら **subagent で並列レビュー**を実行し、claude 単独の盲点を埋める。
この並列レビューが、本スキルにおける「相互検証」の中核である。

### 5-1. 並列レビュー (単一メッセージ内で同時起動)

セルフレビュー専用の **メタ視点・PdM 視点・テックリード視点** の 3 体を **単一メッセージ内で並列**
に Agent 起動する。3 体は **見るスコープが排他的**（重複しない）に設計されているため、
合議ではなく「異なる観点を埋める」並列実行になる:

| Reviewer | 観点 | 見るもの | 見ないもの |
|----------|------|----------|-----------|
| `meta-reviewer` | そもそもこの方向性は正しいか（根本原因、前提誤解、車輪の再発明、長期方針との整合） | Issue / 実装計画 (or PR 本文) / 関連ドキュメント / ファイル一覧 | コード本文 |
| `pdm-reviewer` | ユーザーに届く価値と仕様網羅性（AC 充足、ビジネスロジックのエッジケース、UX、テスト網羅） | Issue / 実装計画 (or PR 本文) / テストコード | 実装ロジック |
| `techlead-reviewer` | ソフトウェア品質（パフォーマンス、保守性、セキュリティ、運用、開発持続性） | コード全体 / 実装計画 (or PR 本文) | Issue（アプローチと仕様は所与とみなす）/ Linter で検知できる事項 |

各 reviewer に渡すプロンプトには **作業ブランチ / Issue 番号 / 主要差分の概要 /
重点で見て欲しい論点 / セルフレビューモードである旨** を含める。各 reviewer は会話文脈を
持たないので自己完結したプロンプトにすること。各 reviewer 内の動作モード判定が
セルフ/PR を切り替えるので、呼び出し側は単に該当の情報を渡せばよい。

軽微な変更 (Phase 1 で「設定/ドキュメントの軽微変更」分類) は `techlead-reviewer`
1 体だけでよい。設計判断を含む大きな変更は 3 体すべてを必ず並列で回す。

各 reviewer は `findings[]` JSON で `severity: must/suggestion/nit/good` を返す:

- `must` がある場合 → claude 側で修正してから Phase 6 に進む
- `suggestion` / `nit` → その場で直すか PR 本文の TODO に積むかをコストで判断
- `good` → そのまま Phase 6 へ進む根拠材料に使う

3 体の出力には `mode: "self_review" | "pr_review"` フィールドが含まれるので、想定通りの
モードで動いているかも合わせて確認する。

### 5-2. 異論・対立があるケース

3 体は観点が排他的なので原則対立しないが、同一の差分に対して `meta-reviewer` が「方向性 NG」、
`techlead-reviewer` が「実装は良い」のように **判断レベルが衝突** することがある。
このときは **`review-acceptor` / `review-challenger` agent** を呼んで合議し、採否を決める。
両者の合議で結論を出し、判断根拠を Phase 6 の PR 本文に残す。

PR レビューフローへ載せた方が良いほど重いケース（例: アーキテクチャ大変更）では
`superpowers:requesting-code-review` skill を呼び、ガイド付きの形式でレビューを依頼する
選択肢もある。

#### PR 起票後の追加レビューが必要な場合

セルフレビューの 3 体は両モード対応なので、PR 起票後に同じ 3 体を `pr_number` 付きで
再度呼ぶことで、PR 上の文脈（CI 結果・PR 説明文の更新・他レビュアーのコメント）を踏まえた
レビューもできる。`pr-review` skill で動く既存の 4 体（specification / correctness /
quality-test / security-perf）と棲み分けて使う。

### 5-3. 動作検証は claude が自律実行する

**ユーザーに「あなた側で動かして確認してください」と委ねない**。変更に対応する動作確認は
claude が実機で実行する:

| 変更種別 | 自律検証アクション |
|---------|------------------|
| コード変更 | テスト実行 (`cargo test`, `npm test`, 等) と該当機能の起動確認 |
| 手順ドキュメント変更 | 文書どおりにコマンドを再実行（README の Getting Started など） |
| API / サーバー変更 | 起動 → リクエスト → レスポンス検証までを 1 セット |
| ビルド / CI 変更 | 変更後のフルビルド (`cargo check --all-targets`, `npm run build`) |

claude の環境で **実行不可能** な場合のみ、その理由を明示してユーザーへ依頼する:

- 外部有料サービスへのアクセスが必要 (本番 DB, 課金 API)
- ユーザー個人の認証情報が必要 (特定の SSO, 社内ネットワーク内リソース)
- 本番環境でのみ再現するデータ依存

「時間がかかる」「ビルドが重い」「環境依存が怖い」は **理由にならない**。
`run_in_background` や poll loop で待機すれば済む。完了宣言の前に
`superpowers:verification-before-completion` skill を経由し、検証コマンドの実出力を確認
してから success を主張する。

検証結果は Phase 6 報告の動作確認エビデンスに組み込む。

---

## Phase 6: 統合と報告（コミット + push + PR まで自律完走）

Phase 5 が merge 可の判断に至ったら、**ユーザーの明示指示を待たずに以下まで連続で
仮決め実行する**:

1. `/git-commit` skill に委譲（差分グルーピング + メッセージ生成）
2. push（ブランチ未トラッキングなら `git push -u origin <branch>`）
3. PR 起票（`commit-commands:commit-push-pr` skill が利用可能ならそれに委譲、
   なければ claude 自身で `gh pr create`）

ブランチ名・コミット粒度・コミットメッセージ・PR 本文は既存慣習から自動生成。事後報告で
ユーザーに差し戻し余地を残す。

作業完了時の報告内容:

- 作業ブランチ名
- 参照 / 起票した Issue 番号
- Phase 3 の調査 subagent と要約結果
- Phase 4-2 の計画レビュー結果（省略した場合はその理由）
- Phase 5 並列レビューの結果（reviewer ごとの must / suggestion / nit 件数と要旨）
- 直接編集した場合はそのパスと理由
- 動作検証コマンドと結果
- 作成した PR URL
- 残課題があれば次のアクション候補

### 例外: 事前確認が必要な Phase 6 操作

以下の**破壊的 / 取り返しがつかない**操作のみ事前確認する。それ以外は確認ゲート禁止:

- `main` / `master` / 保護ブランチへの force-push
- 既存の published タグ / リリースの書き換え
- 他コラボレーターのブランチへの push
- 公開済み PR の close（ユーザー同意なし）

### 6-1. `/git-commit` 委譲（Phase 6 内で常時実行）

commit の粒度判断・メッセージ生成・既存慣習への適合は `/git-commit` に集約。claude は
`git add` / `git commit` を直接呼ばない（hook が無くても、慣習適合のため skill 委譲に統一する）。

### 6-2. PR 起票（Phase 6 内で常時実行）

push 未実施なら起票側で push を済ませる。`commit-commands:commit-push-pr` skill が
利用できれば優先。なければ claude が直接 `gh pr create` を実行。本文は以下のセクションを
含める:

- `## Summary` (1〜3 bullet)
- `## 動作確認` (Phase 5-3 で実行したコマンドと結果)
- `## Test Plan` (新規/更新したテストの位置と意図)
- `## レビュー時の重点確認ポイント` (Phase 5-1 reviewer の `suggestion` / 設計判断ポイント)
- `Closes #N` (Phase 2-2 の Issue 番号)

draft / ready の判断は **500 行 + 設計判断有無** で仮決め。

Phase 2-2 で起票/参照した Issue 番号と、Phase 5 reviewer の出力（特に `must` /
`suggestion`）を PR 本文の文脈として使う。

**プロジェクト固有の PR ルール**: プロジェクトの `CLAUDE.md` や `.claude/` 配下に
「PR 作成時の必須ルール」「PR 本文チェックリスト」等が書かれている場合、PR 起票**前に**
チェックリスト項目を全満たしていることを確認する。未達なら先にそれを解消してから
Phase 6-2 に戻る（例: `## サンプル` セクション + 実生成 GIF/PNG の埋め込み必須など）。

### /loop との関係

`/loop` で juggernaut を繰り返すケースでも動作は同じ（1 イテレーションが PR URL
報告まで完走する）。

---

## レッドフラグ集

以下の思考が浮かんだら、それは**このスキルが必要だった兆候**。浮かんだ時点で
Phase 1 から再起動する:

| 内部思考 | 実態 |
|---------|------|
| 「ブランチ名を確認しておこう」 | ユーザーは「仮決めで進めて」と明言済。確認禁止。命名して走る |
| 「Issue の粒度が迷うから先に聞こう」 | 仮決めで起票し、事後報告で差し戻し可能にする |
| 「ドキュメント修正だから Issue もブランチも不要」 | Phase 2-3 の例外条件を**全部**満たすか自問する。1 つでも怪しければ起票・worktree 側に倒す |
| 「自分で grep した方が早い」 | 3 ファイル以上なら `Explore` agent。速度より相互検証の価値が高い |
| 「計画レビューは今回は省略でいいだろう」 | 省略自体を記録してユーザーに見せる |
| 「skill を呼ぶほどではない」 | 呼ばずに失敗した実績があるからこのスキルが存在する |
| 「軽微な変更だから手順は不要」 | 「軽微」の判定も Phase 2〜4 の手順で行うもの |
| 「git checkout -b で十分だろう」 | 必ず `git worktree add -b` (`superpowers:using-git-worktrees`) を使う |
| 「ユーザーが急いでいそうだから省略」 | 急ぐときこそ手戻りのコストが大きい (ただし事前確認のための停止は**禁止**) |
| 「コミット前にユーザー確認を取ろう」 | Phase 6 は自律完走が原則。破壊的操作以外は確認禁止 |
| 「PR 起票は別ターンでいいだろう」 | Phase 6 に PR 起票まで含まれる。1 ターンで完走する |
| 「動作確認はユーザーに任せよう」 | Phase 5-3 で claude が自律実行する。`run_in_background` と poll で待機すれば時間の問題は解決 |
| 「reviewer 1 体だけでいいか」 | 観点は 3 つの reviewer (meta / pdm / techlead) がそれぞれ排他的。設計判断を含む変更は 3 体並列で全部回す |
| 「self-review で大丈夫だろう」 | claude は自分のコードの盲点に気付けない。subagent reviewer に必ず通す |
| 「meta が方向性 OK なら techlead だけでいいか」 | pdm 観点（AC 充足・エッジケース・UX）は別レイヤー。スキップ禁止 |

---

## 他スキル / agent との関係

| 相棒 | 役割 | このスキルとの関係 |
|------|------|-------------------|
| `Explore` agent | 多ファイル横断の調査 | Phase 3 から呼び出す |
| `feature-dev:code-explorer` agent | 既存機能の深い分析 | Phase 3 から呼び出す |
| `Plan` agent | 実装計画の設計 | Phase 4-2 から呼び出す |
| `feature-dev:code-architect` agent | アーキテクチャ blueprint | Phase 4-2 から呼び出す |
| `feature-dev:feature-dev` skill | ガイド付き機能開発 | Phase 4 全体を担うこともある |
| `superpowers:test-driven-development` | TDD 工程の管理 | Phase 4-3 で常時呼ぶ |
| `superpowers:subagent-driven-development` | 並列 subagent による実装 | Phase 4-3 で並列化したいときに |
| `superpowers:dispatching-parallel-agents` | 独立タスクの並列分配 | Phase 3 / 4-3 で 2 つ以上の独立作業があるとき |
| `superpowers:executing-plans` | 既存 plan の別セッション実行 | Phase 4-3 の代替フローとして |
| `superpowers:verification-before-completion` | 完了宣言前の検証 | Phase 5-3 と Phase 6 の境目で必ず通過 |
| `superpowers:requesting-code-review` | ガイド付きレビュー依頼 | Phase 5-2 で重い案件のとき |
| `superpowers:using-git-worktrees` | worktree の安全な作成 | Phase 2-1 から呼び出す |
| `meta-reviewer` agent | 方向性レビュー（根本原因・前提・再発明・長期整合）。コードは見ない | Phase 5-1 で並列起動。両モード対応 |
| `pdm-reviewer` agent | 価値・網羅性レビュー（AC・エッジケース・UX・テスト網羅）。実装ロジックは見ない | Phase 5-1 で並列起動。両モード対応 |
| `techlead-reviewer` agent | 技術品質レビュー（性能・保守性・セキュリティ・運用・持続性）。Issue は見ない | Phase 5-1 で並列起動。両モード対応 |
| `review-acceptor` / `review-challenger` agent | 合議的判断 | Phase 5-2 で判断レベルが衝突したとき |
| `specification-reviewer` / `correctness-reviewer` / `quality-test-reviewer` / `security-perf-reviewer` agent | （レガシー） | juggernaut でも `pr-review` でも使われなくなった旧 4 分割。ファイル残置のみ。完全に不要と判断したら削除可 |
| `/git-commit` skill | コミット生成 | Phase 6-1 で常時委譲 |
| `commit-commands:commit-push-pr` skill | コミット + push + PR | Phase 6-2 で利用可能なら優先 |
| `/refine-issue` skill | Issue 精緻化 | Phase 2-2 で起票直後に呼ぶ選択肢 |

このスキルは**判断のハブ**であり、個別作業は他 skill / subagent に委譲する。ここで実作業を
やり始めたら、そのこと自体がスキル設計の破綻である。
