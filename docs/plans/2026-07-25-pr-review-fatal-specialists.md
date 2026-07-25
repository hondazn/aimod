# pr-review fatal-reviewer + dynamic specialists Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `pr-review` の固定レビュアーを `meta-reviewer` + `fatal-reviewer` にし、差分に応じて既存スペシャリストを 0〜3 体追加。`CHANGES_REQUESTED` は `fatal` のみ。

**Architecture:** Phase 4 冒頭でメインがスペシャリストを選定 → `meta` / `fatal` / specialists を並列起動 → findings を severity 優先で統合 → 投稿イベントは `fatal` 有無で決定。スペシャリスト本体は書き換えず、呼び出し prompt で findings JSON 契約を上書きする。

**Tech Stack:** Markdown（`shared/agents/*.md`, `shared/skills/*/SKILL.md`, `shared/rules/*.md`）。検証は `rg` による参照掃除チェックとドキュメント整合。自動テストスイートは無し。

**関連ドキュメント:**
- 設計: `docs/specs/2026-07-25-pr-review-fatal-specialists-design.md`

## Global Constraints

- `fatal` severity は `fatal-reviewer` 専用。他エージェントが返したら `must` に降格
- `CHANGES_REQUESTED` / `REQUEST_CHANGES` は findings に `severity == "fatal"` が1件以上あるときのみ
- `must` だけでは COMMENT（または従来の APPROVE 判定）に留め、マージブロックしない
- スペシャリスト選定上限は 0〜3。観点重複は代表1体
- 削除済みの `pdm-reviewer` / `techlead-reviewer` への参照を残さない

---

## File Structure

| ファイル | 責務 |
|---|---|
| `shared/agents/fatal-reviewer.md` | 新規。fatal 専用レビュアー |
| `shared/skills/pr-review/SKILL.md` | Phase 4 選定・並列・統合・投稿判定の改訂 |
| `shared/rules/review-badges.md` | `fatal` 色・フォールバック・アニメプール |
| `CLAUDE.md` | レビュー構成の説明を新モデルに更新 |
| `README.md` | 必要なら1行タッチ（深くは書かない） |

---

## Task 1: `fatal-reviewer` エージェントを追加する

**Files:**
- Create: `shared/agents/fatal-reviewer.md`
- Consumes: `shared/agents/meta-reviewer.md` の JSON 出力骨格
- Produces: `subagent_type: fatal-reviewer` で起動可能なエージェント定義

- [ ] **Step 1: エージェントファイルを作成**

`shared/agents/fatal-reviewer.md` を次の内容で作成する（フロントマター + 本文）:

````markdown
---
name: fatal-reviewer
description: |
  PRの「マージしたら壊れる／機能が成立しない」致命問題だけを拾うレビュアー。
  クラッシュ確実、データ破損、権限漏洩、破壊的マイグレーション、明らかなセキュリティ穴、
  AC未達で機能が成立しない、既存API/契約の破壊のみを対象にする。
  スタイル・命名・リファクタ提案・テスト不足単体・将来負債は出さない。迷ったら出さない。
  「致命的な問題だけ見て」「マージブロッカーを探して」「fatalレビュー」で使う。
color: red
---

あなたはマージ阻害の安全網です。関心は1つ: **「このままマージすると利用者・本番・契約を壊すか」**。

## 動作モード

入力に `pr_number` / PR URL / `gh pr` があれば PRレビューモード。`mode` は `"pr_review"`。

- `gh pr view` / `gh pr diff` / 関連 Issue を読んでよい（コード本文を読んでよい）
- worktree パスが渡されていればそこを基点にする

## fatal の定義（これ以外は出さない）

含める:
- 本番・利用者を壊しうる: クラッシュ確実、データ破損、権限漏洩、破壊的マイグレーション、明らかなセキュリティ穴
- 仕様の根本ズレ: AC未達で機能が成立しない、既存 API/契約の破壊

含めない:
- スタイル、命名、リファクタ提案、テスト不足単体、将来の負債懸念、方向性の好み

迷ったら findings を空にする。

## 出力フォーマット

JSON以外を出力しない。

```json
{
  "reviewer": "fatal-reviewer",
  "mode": "pr_review",
  "findings": [
    {
      "file": "path/to/file.rs",
      "line": 42,
      "side": "RIGHT",
      "start_line": null,
      "start_side": null,
      "severity": "fatal",
      "category": "致命",
      "badge_label": "本番破壊",
      "title": "1行要約",
      "rationale": "なぜ致命か。根拠付き。ですます調。",
      "suggestion": "回避策があれば文字列、無ければ null",
      "evidence": "参照ポインタ。無ければ null"
    }
  ],
  "note": null
}
```

### フィールド制約

- `severity` は常に `"fatal"`。それ以外を付けない
- `badge_label` 例: `本番破壊` / `権限漏洩` / `契約破壊` / `AC不成立`（合計15文字 / 1行5文字 / 改行2回まで）
- findings 0件なら `[]`
````

- [ ] **Step 2: 参照可能か確認**

Run:

```bash
test -f shared/agents/fatal-reviewer.md
rg -n '^name: fatal-reviewer$|severity.: .fatal.|迷ったら' shared/agents/fatal-reviewer.md
```

Expected: ファイルが存在し、3パターンともヒット。

- [ ] **Step 3: Commit**

```bash
git add shared/agents/fatal-reviewer.md
git commit -m "$(cat <<'EOF'
feat(agents): add fatal-reviewer for merge-blocking findings only

EOF
)"
```

---

## Task 2: `review-badges.md` に fatal と新アニメプールを入れる

**Files:**
- Modify: `shared/rules/review-badges.md`
- Produces: Phase 4-7 が参照する `fatal` / `fatal-reviewer` / specialist 共通プール

- [ ] **Step 1: 冒頭の reviewer 列挙を更新**

先頭付近の `meta-reviewer` / `pdm-reviewer` / `techlead-reviewer` 言及を次に置換:

```markdown
reviewer エージェント（`meta-reviewer` / `fatal-reviewer` / 動的スペシャリスト）は構造化フィールド（`title` / `rationale` / `suggestion` / `evidence` / **`badge_label`**）を返し、Phase 4-7 がそれらを mojiemoji-github スキル経由でバッジ Markdown に組み立てます。
```

- [ ] **Step 2: フォールバック表と severity→color に fatal を追加**

フォールバック表の先頭に:

```markdown
| `fatal` | `致命` |
```

severity → color 表の先頭に:

```markdown
| `fatal` | `vivid-red` | マージしたら本番・契約・利用者を壊す |
```

（`must` 行は残す。色が同じでも識別はラベル側）

- [ ] **Step 3: reviewer → animation 表を差し替え**

`pdm-reviewer` / `techlead-reviewer` 行を削除し、次にする:

```markdown
| reviewer | アニメプール（ローテーション順） | 意味付け |
|---|---|---|
| `fatal-reviewer` | `gatagata` → `shuchusen` → `bure` → `chuuou_zoom` | 致命を揺らし集中線で止める |
| `meta-reviewer` | `shuchusen` → `bure` → `gatagata` → `poyoon` | 集中線で前提に視線を奪う／グリッチで前提崩れ／弾みでやわらかく |
| `*`（スペシャリスト共通フォールバック） | `yoko_scroll` → `mochimochi` → `bane` → `poyoon` | 動的スペシャリスト共通。個別プールは持たない |
```

本文中の「ANIMATION_POOL に存在しない reviewer 名は `["chuuou_zoom"]`」系の記述があれば、**スペシャリスト共通プールを先に使い、それでも無いときだけ `["chuuou_zoom"]`** と書き換える。

- [ ] **Step 4: 検証**

Run:

```bash
rg -n 'pdm-reviewer|techlead-reviewer' shared/rules/review-badges.md
rg -n 'fatal|fatal-reviewer|致命' shared/rules/review-badges.md
```

Expected: 前者0件、後者は複数ヒット。

- [ ] **Step 5: Commit**

```bash
git add shared/rules/review-badges.md
git commit -m "$(cat <<'EOF'
docs(review-badges): add fatal severity and update reviewer animation pools

EOF
)"
```

---

## Task 3: `pr-review` Phase 4 を固定2体 + 動的スペシャリストに書き換える

**Files:**
- Modify: `shared/skills/pr-review/SKILL.md`（Phase 4 全体、特に 4-1〜4-5 と 4-7 の ANIMATION_POOL / SEVERITY_MAP）
- Consumes: Task 1 の `fatal-reviewer`、Task 2 のバッジ定義
- Produces: 新しい Phase 4 オーケストレーション

**重要:** 小規模PR用の「頭の中で3観点」4-2 は廃止する。常にエージェント起動（meta + fatal + 選んだ specialists）。

- [ ] **Step 1: 再レビュー閾値表に fatal を組み込む**

Phase 4 冒頭の投稿対象表を次に更新:

```markdown
| モード | GitHub投稿対象 | 抑制（ユーザー報告のみ） |
|---|---|---|
| 初回レビュー | fatal, must, suggestion, nit, good | なし |
| 再レビュー | fatal, must, suggestion | nit, good |
| APPROVE後再レビュー (`post_approval_mode`) | fatal, must | suggestion, nit, good |
```

一貫性ルールの「must のみ」言及は「fatal または must」に更新（追い打ち禁止は suggestion/nit のまま）。

- [ ] **Step 2: 4-1 をスペシャリスト選定に置換**

`### 4-1. レビュー方式の決定` 〜 4-2 全体を削除し、次で置き換える:

````markdown
### 4-1. スペシャリスト選定（メインが実施）

固定で起動するレビュアーは常に次の2体:

- `meta-reviewer`（方向性。コード本文は見ない）
- `fatal-reviewer`（致命のみ。`severity: fatal` 専用）

追加で、差分・PR本文・変更ファイルから **既存スペシャリストを 0〜3 体** 選ぶ。プールは `consult-specialists` と同じ12体。観点が重なる候補は代表1体だけ。

選定ヒューリスティック（目安。強制ではない）:

| 差分の兆し | 候補 |
|---|---|
| テスト / AC / 仕様記述 | `qa` |
| auth / 権限 / 秘密情報 / 公開 API | `safety-skeptic` |
| 障害・リトライ・監視・デプロイ | `failure-pessimist` |
| UI / 文言 / オンボーディング | `taste` or `friction-maximalist` |
| 大きな構造変更 / 新モジュール | `architect` or `tech-lead` |
| 暫定フラグ・二重実装 | `debt-auditor` |
| 計測・ログ追加 | `data-realist` |

選定結果を `selected_specialists: string[]`（0〜3）として記録し、ユーザーへ「固定: meta, fatal / 追加: …」と一行報告してから起動する。
````

- [ ] **Step 3: 4-3 を固定2 + specialists 並列に書き換え**

エージェント表を:

```markdown
| エージェント名 | 担当 | 見るもの | severity |
|---|---|---|---|
| `meta-reviewer` | 方向性 | Issue / PR本文 / ドキュメント / ファイル一覧（コード本文は見ない） | must/suggestion/nit/good |
| `fatal-reviewer` | 致命 | diff + Issue + PR本文 | **fatal のみ** |
| `selected_specialists[]` | 深掘り | 各専門領域 | must/suggestion/nit/good |
```

起動は **同一メッセージで並列**。specialists への prompt 末尾に必ず次を付ける:

```text
## 期待する出力（必須）
助言モード。次の JSON 以外を出力しない:
{
  "reviewer": "<your-name>",
  "mode": "pr_review",
  "findings": [ { ... meta-reviewer と同じフィールド ... } ],
  "note": null
}
severity は must|suggestion|nit|good のみ。fatal は付けるな（付けた場合は呼び出し側で must に降格する）。
```

プロジェクト固有エージェント（4-3A）は残してよい。起動タイミングは「固定2 + specialists と同時」。

- [ ] **Step 4: 4-5 統合ルールを更新**

```markdown
1. 完全重複 → severity 優先: fatal > must > suggestion > nit（good は別扱い可）。同点は `fatal-reviewer` → `meta-reviewer` → その他
2. fatal と他の部分重複 → fatal を残し、必要なら rationale に他側の根拠を追記
3. スペシャリスト由来で `severity == "fatal"` なら `must` に降格してから統合
```

例表の `techlead-reviewer` / `pdm-reviewer` を `fatal-reviewer` / `qa` 等に差し替え。

- [ ] **Step 5: Phase 4-7 の ANIMATION_POOL / SEVERITY_MAP を更新**

`pr-review/SKILL.md` 内のマップを:

```text
ANIMATION_POOL = {
  "fatal-reviewer": ["gatagata", "shuchusen", "bure", "chuuou_zoom"],
  "meta-reviewer":  ["shuchusen", "bure", "gatagata", "poyoon"],
}
SPECIALIST_ANIMATION_POOL = ["yoko_scroll", "mochimochi", "bane", "poyoon"]
# ANIMATION_POOL に無い reviewer 名は SPECIALIST_ANIMATION_POOL を使う

SEVERITY_MAP = {
  "fatal":      {"fallback_label": "致命",           "color": "vivid-red"},
  "must":       {"fallback_label": "要修正",         "color": "vivid-red"},
  "suggestion": {"fallback_label": "オススメ",       "color": "vivid-blue"},
  "nit":        {"fallback_label": "ちょっと\n気になる", "color": "vivid-green"},
  "good":       {"fallback_label": "いいね",         "color": "pastel-green"},
}
```

（実装上のキー名は既存 SKILL の書き方に合わせる。意味が一致すればよい。）

- [ ] **Step 6: 検証**

Run:

```bash
rg -n 'pdm-reviewer|techlead-reviewer' shared/skills/pr-review/SKILL.md
rg -n 'fatal-reviewer|selected_specialists|SPECIALIST_ANIMATION_POOL|"fatal"' shared/skills/pr-review/SKILL.md
```

Expected: 前者0件。後者は選定・並列・マップのいずれかでヒット。

- [ ] **Step 7: Commit**

```bash
git add shared/skills/pr-review/SKILL.md
git commit -m "$(cat <<'EOF'
refactor(pr-review): use meta+fatal fixed reviewers and dynamic specialists

EOF
)"
```

---

## Task 4: 投稿判定を fatal 基準に切り替える

**Files:**
- Modify: `shared/skills/pr-review/SKILL.md`（Phase 5 サマリー、Phase 6 イベント、再レビュー表、DoD 文言）

- [ ] **Step 1: イベント決定ロジックを置換**

`must` 有無で `REQUEST_CHANGES` している箇所をすべて次の規則に置換:

```markdown
- findings に `severity == "fatal"` が1件以上 → `REQUEST_CHANGES`
- fatal なし、かつ投稿対象の指摘（must/suggestion/nit 等、モードに応じた表）がある → `COMMENT`
- fatal なし、投稿対象の問題指摘が実質ゼロで変更が健全 → `APPROVE`
```

サマリー冒頭の「mustがあれば修正が必要」系も「fatalがあればマージブロック」に更新。must のみのときは「気になる点はあるがマージブロックではない」トーンを許可。

- [ ] **Step 2: 再レビューサマリー表を fatal 基準に**

| 前回の状態 | 今回の結果 | 冒頭のトーン |
|---|---|---|
| `CHANGES_REQUESTED` | fatalなし | 前回の致命指摘が解消されたことを認めつつ肯定的に |
| `CHANGES_REQUESTED` | fatalあり | まだマージできない致命がある旨を端的に |
| （他行） | fatalなし / fatalあり | 同様に must→fatal 読み替え |

- [ ] **Step 3: DoD・完了条件の must 言及を監査**

`post_approval_mode == true` かつ must なし、等の条件を「fatal なし」中心に読み替え。must を完全無視する必要はなく、「マージブロック判定は fatal」と明記すれば足りる。

- [ ] **Step 4: 検証**

Run:

```bash
rg -n 'REQUEST_CHANGES|CHANGES_REQUESTED|mustあり|mustなし|fatal' shared/skills/pr-review/SKILL.md | head -80
```

Expected: REQUEST_CHANGES の条件説明に fatal が出る。旧「mustがあれば REQUEST_CHANGES」の単独条件が残っていない。

- [ ] **Step 5: Commit**

```bash
git add shared/skills/pr-review/SKILL.md
git commit -m "$(cat <<'EOF'
fix(pr-review): gate CHANGES_REQUESTED on fatal findings only

EOF
)"
```

---

## Task 5: リポジトリ説明（CLAUDE.md）を新モデルに合わせる

**Files:**
- Modify: `CLAUDE.md`
- Modify: `README.md`（レビュー構成に触れている場合のみ）

- [ ] **Step 1: 「主レビュー（3分割…）」節を置換**

`CLAUDE.md` の該当節を次の趣旨で書き換え:

```markdown
### PRレビュー構成（pr-review）

固定:
| エージェント | 観点 |
|---|---|
| `meta-reviewer` | 方向性（コード本文は見ない） |
| `fatal-reviewer` | 致命のみ（`severity: fatal`）。これだけが CHANGES_REQUESTED |

追加: メインが差分に応じて既存スペシャリストを 0〜3 体選ぶ（`qa` / `safety-skeptic` 等）。
```

合議用 `review-acceptor` / `review-challenger` の節が残っていれば、削除済みなら節ごと削除。

スペシャリスト節の「meta/pdm/techlead とは独立」表現を「pr-review の動的追加メンバーとしても使われる」に更新。

- [ ] **Step 2: 検証**

Run:

```bash
rg -n 'pdm-reviewer|techlead-reviewer' CLAUDE.md README.md || true
rg -n 'fatal-reviewer' CLAUDE.md
```

Expected: pdm/techlead は説明から消え、fatal-reviewer が載る。

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md README.md
git commit -m "$(cat <<'EOF'
docs: update review architecture for meta+fatal and specialists

EOF
)"
```

---

## Task 6: リポジトリ全体の取り残し掃除と最終検証

**Files:**
- Modify: 残存参照があれば該当ファイル
- Test: リポジトリ横断 `rg`

- [ ] **Step 1: 横断検索**

Run:

```bash
rg -n 'pdm-reviewer|techlead-reviewer|review-acceptor|review-challenger' \
  --glob '!docs/specs/**' --glob '!docs/plans/**' --glob '!.git/**'
```

Expected: 運用ドキュメント（CLAUDE / skills / rules / agents）から0件。歴史的 spec/plan に残る分は許容。

- [ ] **Step 2: 新構成の存在確認**

Run:

```bash
test -f shared/agents/fatal-reviewer.md
test -f shared/agents/meta-reviewer.md
rg -n 'selected_specialists|fatal-reviewer|severity == "fatal"|SPECIALIST_ANIMATION_POOL' shared/skills/pr-review/SKILL.md
./scripts/deploy.sh
```

Expected: deploy 成功。skills/agents がホームへリンクされる。

- [ ] **Step 3: 必要なら掃除コミット**

取り残しを直した場合のみ:

```bash
git add -A
git status
git commit -m "$(cat <<'EOF'
chore: remove stale pdm/techlead review references

EOF
)"
```

---

## Spec coverage checklist

| Spec 要件 | Task |
|---|---|
| fatal-reviewer 新規 | Task 1 |
| fatal 定義（本番破壊 + AC/契約） | Task 1 |
| バッジ fatal / アニメプール | Task 2 |
| 固定 meta+fatal、specialists 0-3 | Task 3 |
| 統合ルール・fatal 降格 | Task 3 |
| CHANGES_REQUESTED = fatal only | Task 4 |
| CLAUDE.md 更新 | Task 5 |
| pdm/techlead 参照除去 | Task 3, 5, 6 |

## Self-review notes

- 自動テストは無いため、各 Task の検証は `rg` / `test -f` / `deploy.sh` に固定した
- 4-2 廃止は spec の「常に並列固定2+動的」と整合。サイズ分岐で specialists 数を変える要件は無い
- 歴史的 `docs/specs` / `docs/plans` の旧3体記述は意図的に触らない
