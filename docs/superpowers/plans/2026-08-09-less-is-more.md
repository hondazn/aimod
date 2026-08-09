# less-is-more スキル実装プラン

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 保存する成果物を生んだ全作業の最終工程として、本質的に必要な変更だけを残す削りパス（`less-is-more` スキル）を導入する。

**Architecture:** `shared/skills/less-is-more/SKILL.md` に判断基準を持つ新スキルを置き、`shared/instructions.md` の「タスク別スキル」節に強制1行を足して毎回発火させる（`coding-standards` と同じ強制パターン）。デプロイは既存の `deploy.sh` に乗るだけで変更不要。

**Tech Stack:** Markdown（SKILL.md）、bash（deploy.sh / 発火テスト）。外部依存なし。

## Global Constraints

- スキル名は `less-is-more`（グリルセッションで決定済み）
- 発火: 保存する成果物（コード・ドキュメント等）を生んだ作業なら規模を問わず毎回、最終工程として自動適用
- デフォルトは自動削除+報告。「候補提示だけにして」等の宣言で提示モードに切り替え
- 判定は二段: ①今回の依頼に必要か → ②コードベースの慣習として確立しているか → 両方 NO なら削る
- **迷ったら削る**。ただし削った項目は報告に明記し、コミット時は削りを独立コミットに分離して監査可能にする
- コードの構造・設計は `coding-standards` / `design-principles` の領分。本スキルのコード対象は**コメント中心**
- ボーイスカウトルール: 触ったファイル全体の既存冗長も削ってよい（削りコミット側に隔離）
- ドキュメント冗長性の判定は `natural-writing` の4観点を参照し、基準を二重管理しない
- `shared/` 配下の変更は Claude Code・Cursor・Codex すべてに影響する

---

### Task 1: SKILL.md の作成

**Files:**
- Create: `shared/skills/less-is-more/SKILL.md`

**Interfaces:**
- Consumes: `natural-writing` の冗長性4観点（情報密度・簡潔性・論理効率・構造最適性）を参照名で使う
- Produces: スキル名 `less-is-more`（Task 2 の instructions.md 行、Task 4 の発火テストが参照）

- [ ] **Step 1: SKILL.md を以下の内容で作成する**

````markdown
---
name: less-is-more
description: |
  保存する成果物（コード・ドキュメント・設定など）を生んだあらゆる作業の最終工程として必ず適用する削りスキル。
  本質的に必要な変更だけを残し、過剰なコメント・水増しされた文章・頼まれていない成果物を削除する。
  トリガー: 成果物を保存した作業の完了報告の直前（毎回・規模を問わず）。
  「余計な変更を削って」「本質だけ残して」「less is more」等の明示リクエストにも応じる。
  ※文章そのものの校正・リライト依頼は natural-writing の領分。本スキルは作業成果物の最終削りに限る。
---

# Less is More — 最終工程の削りパス

推論は冗長でよい。保存する成果物は本質だけ残す。

## 位置付け

- すべての作業の**最終工程**。成果物（コード・ドキュメント・設定など保存されるもの）を
  生んだら、完了報告の前に必ず実行する。規模は問わない（1行修正でも実行する）
- 会話の応答・思考過程は対象外
- コードの構造・設計品質は `coding-standards` / `design-principles` の領分。
  本スキルがコードに対して見るのは**コメントと余剰成果物**が中心で、構造のリファクタは行わない

## 判定 — 二段判定

各変更・各記述に対して順に問う:

1. **今回の依頼に必要か？** — 無くても依頼が満たされるなら削る候補
2. **コードベースの慣習として確立しているか？** — 依頼に不要でも、既存コードの慣習
   （例: 全モジュールにある docstring、全エンドポイントにあるバリデーション）に合致するなら残す

両方 NO なら削る。**迷ったら削る**（削った項目は記録する。「記録」の節を参照）。

## 対象別チェックリスト

### コード（コメント中心）

- コードをなぞるだけのコメント（何をしているかの説明）
- 変更の経緯・レビュアー向け説明のコメント（コミットログ・PR本文へ）
- 「念のため」残したコメントアウト済みコード
- 頼まれていない TODO / FIXME

### ドキュメント

- `natural-writing` の冗長性4観点（情報密度・簡潔性・論理効率・構造最適性）で判定する
- 削除・改名の経緯の記述（コミットログへ）
- 依頼に不要な網羅的説明・前置き・まとめ

### 成果物の点数

- 頼まれていない補助ファイル（README、サンプル、補助スクリプト）
- 依頼スコープ外のテスト（ただし慣習判定を適用する）

## ボーイスカウトルール

今回書いたものに限らず、**触ったファイル全体**の既存の冗長も同じ基準で削る。
触っていないファイルは対象外（削るために探索しない）。

## モード

| モード | 動作 |
|---|---|
| 自動削除（デフォルト） | 削除まで実行 → 作業中に使った検証（テスト・lint 等）を再実行して green を確認 → 報告 |
| 候補提示 | 削除候補の一覧提示で止め、ユーザーの承認を待つ。「候補提示だけにして」等の宣言があったときのみ |

## 記録 — 削ったものを監査可能にする

- 最終報告に削った項目を一覧で明記する。**迷って削ったもの**は区別して示す
- コミットする場合は**作業本体と削りを別コミット**に分ける。ボーイスカウト分も削りコミット側に置く。
  作業本体の差分は依頼スコープに閉じたまま保たれ、削りは `git show` で後からいつでも監査できる
````

- [ ] **Step 2: frontmatter の妥当性を確認する**

Run: `head -12 shared/skills/less-is-more/SKILL.md`
Expected: `---` で始まり、`name: less-is-more` と `description: |` が含まれる（既存スキルと同形式）

### Task 2: instructions.md への強制1行追加

**Files:**
- Modify: `shared/instructions.md`（「タスク別スキル」節、現在 16〜18 行目のリスト）

**Interfaces:**
- Consumes: Task 1 のスキル名 `less-is-more`

- [ ] **Step 1: 「タスク別スキル」節の末尾に1行追加する**

追加する行（`design-principles` の行の直後）:

```markdown
- 保存する成果物（コード・ドキュメント等）を生んだ作業では、最後の工程として `less-is-more` スキルを必ず適用する
```

- [ ] **Step 2: symlink 経由で即時反映されていることを確認する**

Run: `grep less-is-more ~/.claude/CLAUDE.md`
Expected: 追加した行が表示される（`~/.claude/CLAUDE.md` は `shared/instructions.md` への symlink なのでデプロイ不要で反映される）

### Task 3: デプロイとリンク検証

**Files:**
- 変更なし（`deploy.sh` は skills ディレクトリを走査するため修正不要）

- [ ] **Step 1: deploy.sh を実行する**

Run: `./scripts/deploy.sh`
Expected: `~/.codex/skills/less-is-more` への link 行がログに出る。エラーなし

- [ ] **Step 2: 3ツールへの配布を確認する**

Run: `ls -la ~/.claude/skills/less-is-more ~/.cursor/skills/less-is-more ~/.codex/skills/less-is-more`
Expected: 3つとも実体（`shared/skills/less-is-more`）に解決される。Claude / Cursor はディレクトリ symlink 経由の自動追随、Codex はスキル単位リンク

### Task 4: 発火テスト

**Files:**
- 作業ディレクトリ: scratchpad 配下の一時ディレクトリ（リポ外）

過去の教訓（feedback_skill_trigger_testing）: スキル発火は `claude -p` で実測してから直す。真因は競合スキルの領土侵食が多い。

- [ ] **Step 1: 発火テスト用の一時ディレクトリを作る**

```bash
TESTDIR=$(mktemp -d) && cd "$TESTDIR" && git init -q
```

- [ ] **Step 2: 成果物を保存する小タスクで発火を実測する**

```bash
claude -p "2つの数を足して表示する add.sh を作って" --output-format stream-json --verbose 2>&1 | grep -c '"skill":"less-is-more"'
```

Expected: 1 以上（Skill ツールの less-is-more 呼び出しイベントが存在する）。
注意: 単純な `grep less-is-more` は常時ロードされる `~/.claude/CLAUDE.md`（強制行を含む）の混入で偽陽性になるため、ツール呼び出しの JSON キーで判定する

- [ ] **Step 3: 競合スキルへの誤発火がないか確認する**

```bash
claude -p "このメール文面をもっと簡潔にして: 「お世話になっております。標記の件につきましてご連絡差し上げました…」" --output-format stream-json --verbose 2>&1 | grep -o '"skill":"[a-z-]*"' | sort | uniq -c
```

Expected: `natural-writing` が発火し、`less-is-more` は発火しない（文章校正依頼は natural-writing の領分。境界は SKILL.md の description 末尾の注記が担う）

- [ ] **Step 4: 発火しなかった場合は description / instructions.md の行を調整して再測定する**

判断基準: Step 2 が 0 の場合、まず instructions.md の行の文言（「保存する成果物」の範囲が伝わっているか）を疑い、次に description のトリガー記述を具体化する。修正ごとに Step 2〜3 を再実行し、両方 Expected を満たすまで繰り返す

### Task 5: コミット

- [ ] **Step 1: 変更をコミットする**

```bash
git add shared/skills/less-is-more/SKILL.md shared/instructions.md docs/superpowers/plans/2026-08-09-less-is-more.md
git commit -m "feat(less-is-more): 成果物の最終削りスキルを追加

保存する成果物を生んだ全作業の最終工程として、本質的に必要な
変更だけを残す削りパスを導入。instructions.md で毎回適用を強制。

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015YyNRNSUVvrnY68fyQAR7w"
```

- [ ] **Step 2: コミット内容を確認する**

Run: `git show --stat HEAD`
Expected: SKILL.md（新規）、instructions.md（1行追加）、プラン文書の3ファイル
