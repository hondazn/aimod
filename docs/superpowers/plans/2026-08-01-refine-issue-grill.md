# refine-issue grill 型尋問化 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `shared/skills/refine-issue/SKILL.md` の Phase 3 をチェックリスト穴埋め型から grill 型尋問（前提への挑戦・決定木順・推奨回答つき質問・台帳収束）に置き換える。

**Architecture:** 対象は SKILL.md 1ファイルのマークダウン改訂。Phase 1/2/4 の骨格は維持し、Phase 3 を全面置換、Phase 4 と frontmatter を整合更新する。テストは無いため、検証は grep による旧記述の残存チェックと見出し構造の確認で行う。

**Tech Stack:** Markdown（スキル定義）、git、gh は不要（Issue 操作はしない）

## Global Constraints

- スペック: `docs/superpowers/specs/2026-08-01-refine-issue-grill-design.md` が正本
- frontmatter の `allowed-tools` / `argument-hint` / `name` は変更しない（`description` のみ更新）
- 既存のカテゴリ別チェックリスト（機能系/不具合系/運用系）は削除せず「網羅表」として保持する
- Phase 1（取得・分析）/ Phase 2（コードベース調査）の本文は変更しない
- コミットメッセージはリポジトリ既存の Conventional Commits 形式（例: `feat(skills): ...`）
- 実装時は superpowers:writing-skills スキルを併用してスキル文書の品質を確認する
- このリポジトリの `~/.claude/skills` / `~/.cursor/skills` / `~/.codex/skills/refine-issue` は symlink 済みのため deploy.sh の再実行は不要（Task 2 で確認する）
- 変更中の `shared/skills/round-slicer/SKILL.md`（別作業の未コミット差分）をコミットに含めないこと

---

### Task 1: SKILL.md の grill 型改訂

**Files:**
- Modify: `shared/skills/refine-issue/SKILL.md`

**Interfaces:**
- Consumes: 現行 SKILL.md の構造（Phase 1: L29-113 / Phase 2: L115-148 / Phase 3: L150-307 / Phase 4: L310-366。行番号は改訂前時点）
- Produces: grill 型 Phase 3 を持つ SKILL.md（Task 2 の検証対象）

- [ ] **Step 1: frontmatter の description を更新**

`description` ブロック（トリガー行は変更しない）を以下に置換する:

```yaml
description: |
    既存のGitHub Issueを分析し、grill型の尋問で仕様を精緻化してIssueを更新する。
    前提・価値（そもそも解くべき問題か）から決定木順に、コードベース調査を根拠とした
    推奨回答つきの質問で深掘りし、共有理解台帳で収束を管理する。前提が崩れた場合は
    クローズ/再定義まで提案する。
    トリガー: 「Issueをリファインして」「Issue #NNを精緻化して」「Issueの仕様を詰めて」
    「Issueに情報を追加して」「Issueを整理して」「このIssueで実装に着手できるようにして」
    Issue番号やURLが含まれるIssue改善の依頼には必ずこのスキルを使うこと。
```

- [ ] **Step 2: 「目的」セクションを更新**

現行:

```markdown
既存のGitHub Issueを、「このIssueだけ読めば実装に着手できる」状態にする。
プロジェクトのIssueテンプレートとの照合・種別判定・コードベース調査を踏まえて不足情報を特定し、ユーザーとの対話を通じて仕様を精緻化してIssueを更新する。
```

を以下に置換:

```markdown
既存のGitHub Issueを、「このIssueだけ読めば実装に着手できる」かつ「解くべき問題だと検証済み」の状態にする。
プロジェクトのIssueテンプレートとの照合・種別判定・コードベース調査を踏まえ、前提から順に grill 型の尋問で判断を確定させ、Issueを更新する。
```

- [ ] **Step 3: Phase 3 を全面置換**

`## Phase 3: 対話的補完` の見出しから `## Phase 4: Issue更新` の直前までを、以下の全文に置換する。既存のチェックリスト3種（機能系/不具合系/運用系）と共通チェック項目は**そのままの本文で**「網羅表」節の配下に移動する（内容の書き換えはしない）:

````markdown
## Phase 3: grill 型尋問

Phase 1-2 の結果を材料に、Issue を尋問して精緻化する。テンプレートの穴埋めではなく、前提から順に判断を確定させる。充足度評価で「充足」の枝は確認のみで通過してよい（質問数は Issue の完成度に応じて自然に減る）。

### 決定木と質問順序

上流の判断が確定するまで下流を聞かない。種別ごとの決定木:

| 順序 | 機能系 | 不具合系 | 運用系 |
|------|--------|---------|--------|
| 1 | 前提・価値 | 前提・価値 | 前提・価値 |
| 2 | ゴール・完了条件 | 再現性 | 対象特定 |
| 3 | スコープ | 原因分析 | タスク一覧 |
| 4 | アプローチ | 影響範囲 | 検証方法 |
| 5 | テスト観点 | スコープ | ロールバック |
| 6 | — | テスト観点 | — |

**前提・価値**（全種別共通の最上流）で確認すること:

- この Issue は正しい問題を解こうとしているか（症状ではなく原因に向いているか）
- やる価値があるか（やらない場合に何が起きるか）
- 代替案は検討されたか（より小さい解、既存機能の流用、外部ツール）
- 非ゴール（やらないこと）は何か

### 質問の作り方（grill フォーマット）

1問ずつ深掘りする。同一の枝に属する小問は最大3問まで同時に聞いてよい（ユーザーへの質問機能を使用）。各質問には必ず以下を添える:

- **現在の理解**: Issue 本文とコードベース調査からの要約
- **なぜ重要か / これで何が決まるか**: この質問が解消する下流の判断
- **推奨回答**: コードベース調査の根拠つき。選択肢の第一項に「(推奨)」として置く

**調べれば分かることは聞かない**: リポジトリ・git 履歴・ログ・ドキュメントで答えが取れる質問は、調査して証拠を提示し、判断だけをユーザーに聞く。ユーザーの回答が曖昧な場合は、こちらから仮説を立てて確認する形にする。

### 共有理解台帳と収束

各ラウンドの末尾に台帳を提示する:

```
確定: <ユーザーと合意した判断>
未解決: <実装に影響する未確定の判断>
前提(未検証): <合意したが検証していない仮定>
リスク: <認識済みの懸念>
```

ラウンド数に上限は設けない。終了条件は次のいずれか:

- 「未解決」から実装に影響する項目が尽きた
- ユーザーが打ち切りを指示した（いつでも「もう十分」で Phase 4 へ進める）

### 前提崩壊時の出口

尋問の結果、Issue の前提自体が崩れた場合（別の問題だった、やる価値がない、既存機能で足りる等）は、通常フローを中断して以下の選択肢を提示し、承認された対応を実行する:

1. **クローズ + 再起票** — 経緯コメントを付けてクローズし（`gh issue close <番号> --comment "<経緯>"`）、新しい問題定義での起票は create-issue スキルに委譲する
2. **再定義して更新** — 新しい前提で本文を書き直し、Phase 4 へ進む
3. **そのまま続行** — ユーザーが前提を維持すると判断した場合、尋問に戻る

### 質問の具体例

**機能系（前提・価値の枝）:**

> **現在の理解**: Issue は「ユーザー登録時の重複 email を防ぐ」。`src/validators/email.ts` に形式バリデーションは既存だが、重複チェックはどの層にもない。
>
> **質問**: 重複チェックはどの層の責務にしますか？
> **なぜ重要か**: エラーの返し方（409 か 400 か）と、DB 制約・アプリ検証の二重化方針が決まる。
> **推奨回答**: DB の unique 制約 + `UserService.create()` での事前チェックの二段構え。既存の `src/auth/service.ts` が同じパターンを使っている。

**不具合系（原因分析の枝）:**

> **現在の理解**: `/api/users` に空文字 `name` を POST すると 500 が返る（期待は 400）。`git log` では3日前の `abc1234` で `UserController` のバリデーション処理が変更されている。
>
> **質問**: `abc1234` が原因という仮説で調査を進めてよいですか？
> **なぜ重要か**: 原因コミットが確定すれば、修正範囲と回帰テストの対象が絞れる。
> **推奨回答**: はい。変更差分にバリデーション分岐の削除が含まれており、症状と整合する。

**避けるべき質問:**

- 「完了条件を教えてください」（漠然としすぎ）
- 「スコープはどうしますか？」（何について答えればよいか不明）
- 「テスト観点を挙げてください」（ユーザーに丸投げ）
- 推奨回答のない質問（判断材料を提示せずユーザーに委ねている）
- コードを調べれば分かることの質問（調査してから聞く）

### 網羅表（聞き漏らし確認用チェックリスト）

各枝を閉じる前に、対応するチェックリストで聞き漏らしがないか確認する。

<!-- 以下、現行の「共通チェック項目」「機能系チェックリスト」「不具合系チェックリスト」「運用系チェックリスト」の4節を本文そのままここに配置する -->
````

削除される節: 「カテゴリ別の質問優先順位」（決定木に吸収）、「質問のルール」「質問の組み立て方」「質問テンプレート」（grill フォーマットに吸収）、旧「質問の具体例」（grill 形式の具体例に置換。運用系の例は削除し機能系・不具合系の2例とする）。

- [ ] **Step 4: Phase 4 に台帳反映と未確定事項セクションを追記**

`### 4-2. フォーマット方針` の「共通ルール」リストの末尾に以下の2項目を追加:

```markdown
- 台帳の「確定」を対応するセクションに反映する
- 台帳に「前提(未検証)」「リスク」が残る場合は「## 未確定事項」セクションを設けて明記する
```

- [ ] **Step 5: 変更をレビュー**

superpowers:writing-skills の観点（description とボディの整合、手順の実行可能性、冗長の排除）でセルフチェックし、diff 全体を読み直す。

### Task 2: 整合性検証とコミット

**Files:**
- Modify: なし（検証のみ）

**Interfaces:**
- Consumes: Task 1 の改訂済み SKILL.md
- Produces: コミット済みの変更

- [ ] **Step 1: 旧記述の残存チェック**

```bash
grep -n "最大3ラウンド\|対話的補完\|質問優先順位\|質問の組み立て方" shared/skills/refine-issue/SKILL.md
```

Expected: ヒットなし（exit code 1）

- [ ] **Step 2: 新記述の存在チェック**

```bash
grep -c "前提・価値\|共有理解台帳\|推奨回答\|前提崩壊時の出口" shared/skills/refine-issue/SKILL.md
```

Expected: 10 以上（各概念が本文に定着している）

- [ ] **Step 3: チェックリスト温存の確認**

```bash
grep -n "機能系チェックリスト\|不具合系チェックリスト\|運用系チェックリスト\|共通チェック項目" shared/skills/refine-issue/SKILL.md
```

Expected: 4節すべてヒット（網羅表配下に存在）

- [ ] **Step 4: symlink 反映の確認**

```bash
readlink ~/.claude/skills ~/.cursor/skills ~/.codex/skills/refine-issue
```

Expected: いずれも `shared/skills`（または `shared/skills/refine-issue`）を指す → deploy.sh 不要

- [ ] **Step 5: コミット**

```bash
git add shared/skills/refine-issue/SKILL.md
git commit -m "feat(skills): add grill-style interrogation to refine-issue"
```

round-slicer の未コミット差分を含めないこと（`git status` で確認してから add する）。

### Task 3: メモリ更新（ローカル先行スキル一覧）

**Files:**
- Modify: `/home/zyun/.claude/projects/-home-zyun-git-github-com-hondazn-aimod/memory/project_skills_upstream.md`

**Interfaces:**
- Consumes: Task 2 でコミット済みの変更
- Produces: 更新されたメモリ（リポジトリ外。コミット不要）

- [ ] **Step 1: 「ローカルが上流より先行しているスキル」の一覧に追記**

既存の行:

```markdown
**ローカルが上流より先行しているスキル**（上流から取り込まない）: `pr-review`（`REVIEW-BADGES.md` を分離、+392 行）、`respond-review`（Acceptor/Challenger プロンプトの付録 A/B、+141 行）、`create-pr`（superpowers 参照）、`create-issue`（`/codex-investigate` 参照）。
```

の末尾に `、`refine-issue`（grill 型尋問化）` を追加する（`。` の前に挿入）。
