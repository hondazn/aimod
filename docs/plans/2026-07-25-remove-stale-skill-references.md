# 削除済みスキル参照の掃除とドキュメント整合 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `copilot-review` / `cursor-code` / `dev-orchestration` / `juggernaut` の削除で宙に浮いた 18 箇所の参照を実在するスキルへ差し替え、`shared/rules/` 導入で生じたドキュメントのズレを解消する。

**Architecture:** 参照を機械的に消すのではなく、消えたスキルが担っていた役割ごとに実在の受け皿へ差し替える（worktree 運用 → `superpowers:using-git-worktrees`、実装着手フロー → `superpowers:brainstorming` → `writing-plans` → `executing-plans`、PR レビュー → `pr-review`）。挙動に影響する 1 箇所（`create-pr` の main ブランチ検出）だけ `fix` として先に切り出し、残りは `docs` として文言のみを変える。

**Tech Stack:** Markdown（`shared/agents/*.md`, `shared/skills/*/SKILL.md`, `CLAUDE.md`, `README.md`）+ bash（`scripts/deploy.sh` のコメントのみ）。自動テストは無く、検証は `rg` による参照残存チェックと `deploy.sh` の冪等再実行。

**関連コミット:**
- `4a24a91` refactor(skills): drop copilot-review, cursor-code, dev-orchestration, juggernaut
- `00f3014` feat(rules): extract coding rules from instructions.md into rules/coding.md
- `599fe53` feat(deploy): link shared/rules to Claude/Cursor/Codex without clobbering foreign rules

## Global Constraints

- `docs/specs/` と `docs/plans/` 配下は**書き換えない**。当時の設計・計画の歴史的記録であり、過去の事実として `juggernaut` / `dev-orchestration` / `shared/rules/review-badges.md` を含んでいてよい
- frontmatter の `description` はスキル一覧として毎セッション全文ロードされトリガー判定に使われる。ここに存在しないスキル名を残さない（本文中の記述より優先度が高い）
- 存在しないスキル名の**単純削除で意味が壊れる箇所**は、実在するスキル名または自己完結した手順に差し替える
- `self_review` モードは**撤去しない**。`meta-reviewer` / `fatal-reviewer` を直接起動すれば現状のまま機能し、`pr-review/SKILL.md:411` の「動作モード自動判定」記述とも整合するため、起動経路をドキュメントに明記するだけに留める
- 1 タスク 1 コミット。コミットメッセージは Conventional Commits（既存履歴の慣習）

---

## File Structure

| ファイル | 変更の責務 |
|---|---|
| `shared/skills/create-pr/SKILL.md` | main ブランチ検出時の案内を実在手順へ（挙動）+ `dev-orchestration` 参照 4 箇所の除去 |
| `shared/skills/create-issue/SKILL.md` | `dev-orchestration` 参照 7 箇所の除去 |
| `shared/skills/cleanup-stale-worktrees/SKILL.md` | 「他スキルとの関係」表から `dev-orchestration` 行を削除 |
| `shared/skills/consult-specialists/SKILL.md` | `juggernaut` 参照 2 箇所を `pr-review` / superpowers 系へ差し替え |
| `shared/agents/meta-reviewer.md` | `description` の example から `juggernaut` を除去 |
| `CLAUDE.md` | `juggernaut` 参照 2 箇所の除去 + セルフレビュー起動経路の明文化 + repo 内ミラーが非網羅である旨の注記 |
| `README.md` | ルール追加手順の追記と見出しの統一 |
| `scripts/deploy.sh` | `link_rule_path` のコメントを実態（Codex は native ではない）に合わせる |

---

## Task 1: `create-pr` の main ブランチ検出時に実行可能な案内を出す

削除済みスキル参照のうち唯一**ユーザーに表示される挙動**に影響する箇所。`/create-pr` を `main` 上で呼ぶと存在しない `dev-orchestration` を名指しで報告し、次に取るべき行動が示されない。

**Files:**
- Modify: `shared/skills/create-pr/SKILL.md:58`

**Interfaces:**
- Consumes: なし
- Produces: なし（他タスクは本タスクの結果に依存しない）

- [ ] **Step 1: 現状の文言を確認する**

Run:

```bash
rg -n 'dev-orchestration の Phase 2-1' shared/skills/create-pr/SKILL.md
```

Expected: 1 件ヒット（58 行目）

```
58:| 現在が `main` / `master` / `trunk` | 中止。dev-orchestration の Phase 2-1 で worktree を切るべきだったと報告 |
```

- [ ] **Step 2: 表の行を自己完結した案内に差し替える**

`shared/skills/create-pr/SKILL.md` の 58 行目を次に置換する:

```markdown
| 現在が `main` / `master` / `trunk` | 中止。作業ブランチ（または worktree）を切って変更を移してから再実行するよう報告する。worktree 運用は `superpowers:using-git-worktrees` を案内する |
```

- [ ] **Step 3: 置換結果を検証する**

Run:

```bash
rg -n 'dev-orchestration' shared/skills/create-pr/SKILL.md | rg 'Phase 2-1'
rg -n 'superpowers:using-git-worktrees' shared/skills/create-pr/SKILL.md
```

Expected: 1 行目は 0 件（exit 1）、2 行目は 58 行目に 1 件ヒット

- [ ] **Step 4: Commit**

```bash
git add shared/skills/create-pr/SKILL.md
git commit -m "$(cat <<'EOF'
fix(create-pr): report actionable branch guidance instead of a removed skill

main ブランチ上で起動されたとき、削除済みの dev-orchestration を名指しして
中止していた。ユーザーは存在しないスキルを案内されるだけで次の行動が分からない。
作業ブランチ / worktree を切って再実行する手順と、実在する
superpowers:using-git-worktrees を案内するよう差し替える。

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: `create-pr` の残る `dev-orchestration` 参照を除去する

**Files:**
- Modify: `shared/skills/create-pr/SKILL.md:6`（frontmatter description）
- Modify: `shared/skills/create-pr/SKILL.md:26`（このスキルが存在する理由）
- Modify: `shared/skills/create-pr/SKILL.md:395`（例2 の見出し）
- Modify: `shared/skills/create-pr/SKILL.md:459`（他スキルとの関係）

**Interfaces:**
- Consumes: Task 1 で 58 行目が 1 行 → 1 行で置換済み（行数は変わらないため以下の行番号はそのまま使える）
- Produces: なし

- [ ] **Step 1: description のトリガー条件から削除済みスキルを外す**

`shared/skills/create-pr/SKILL.md:6` を次に置換する（末尾の「、または dev-orchestration の Phase 6 で PR 作成が必要と判定された場合」を削除し句点で閉じる）:

```markdown
    トリガー: 「PRを作って」「プルリクを作って」「この変更でPR立てて」「PR出して」「Pull Requestを作成」「変更をPRにまとめて」「作業をPRにして」「PR化して」「共有準備」「リモートに出して」「レビュー依頼して」。
```

- [ ] **Step 2: 「このスキルが存在する理由」を独立トリガー前提に書き換える**

`shared/skills/create-pr/SKILL.md:26` を次に置換する:

```markdown
- 実装完了からレビュー依頼までの「統合チェックポイント」としての役割
```

- [ ] **Step 3: 例2 の見出しから呼び出し元前提を外す**

`shared/skills/create-pr/SKILL.md:395` を次に置換する:

```markdown
### 例2: 実装途中の feat PR（draft）
```

- [ ] **Step 4: 「他スキルとの関係」表から行を削除する**

`shared/skills/create-pr/SKILL.md:459` の次の行を**行ごと削除**する:

```markdown
| `dev-orchestration` | ワークフロー判断ハブ | Phase 6 からこのスキルを呼ぶ |
```

- [ ] **Step 5: 残存参照ゼロを検証する**

Run:

```bash
rg -n 'dev-orchestration|juggernaut|copilot-review|cursor-code' shared/skills/create-pr/SKILL.md
```

Expected: 0 件（exit code 1）

- [ ] **Step 6: Commit**

```bash
git add shared/skills/create-pr/SKILL.md
git commit -m "$(cat <<'EOF'
docs(create-pr): drop references to the removed dev-orchestration skill

description はスキル一覧として毎セッションロードされトリガー判定に使われるため、
存在しないスキルを起動条件に残すとノイズになる。存在理由・例の見出し・
他スキルとの関係表も、ハブから呼ばれる前提を外して独立トリガー前提に揃える。

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: `create-issue` の `dev-orchestration` 参照を除去する

**Files:**
- Modify: `shared/skills/create-issue/SKILL.md:6`（frontmatter description）
- Modify: `shared/skills/create-issue/SKILL.md:26`（このスキルが存在する理由）
- Modify: `shared/skills/create-issue/SKILL.md:333`（呼び出し元へのハンドオフ）
- Modify: `shared/skills/create-issue/SKILL.md:385,387-388`（例2 の見出しと前提）
- Modify: `shared/skills/create-issue/SKILL.md:423`（例2 の締め）
- Modify: `shared/skills/create-issue/SKILL.md:432`（他スキルとの関係）

**Interfaces:**
- Consumes: なし
- Produces: なし

- [ ] **Step 1: description のトリガー条件を書き換える**

`shared/skills/create-issue/SKILL.md:6` を次に置換する:

```markdown
    トリガー: 「Issueを作って」「Issueを起票して」「〜のバグを記録して」「〜の機能要望を登録して」「チケットを切って」「この件でIssue立てて」「タスクとしてIssue化して」「Issueにまとめて」。タスク・バグ・要望の記録依頼全般に使用する。
```

- [ ] **Step 2: 「このスキルが存在する理由」を書き換える**

`shared/skills/create-issue/SKILL.md:26` を次に置換する:

```markdown
- 着手前に作業を Issue として記録する「骨格チェックポイント」としての役割
```

- [ ] **Step 3: ハンドオフ記述を呼び出し元非依存にする**

`shared/skills/create-issue/SKILL.md:333` を次に置換する（振る舞い自体は他スキルから呼ばれたときに有効なので残し、スキル名だけ一般化する）:

```markdown
別のスキルから呼ばれた場合は、Issue 番号を呼び出し元に戻すだけで十分（ユーザー報告は呼び出し元が行う）。
```

- [ ] **Step 4: 例2 の見出しと前提を書き換える**

`shared/skills/create-issue/SKILL.md:385` を次に置換する:

```markdown
### 例2: 会話の文脈からの仮決め起票
```

続けて 387-388 行目（`**呼び出し元の文脈:**` とその引用行）を次に置換する:

```markdown
**会話の文脈:**
> CI ワークフローの pull_request トリガーで path filter が効いていないので修正したい
```

- [ ] **Step 5: 例2 の締めを書き換える**

`shared/skills/create-issue/SKILL.md:423` を次に置換する:

```markdown
起票後、Issue 番号を報告し、実装着手に引き継ぐ。
```

- [ ] **Step 6: 「他スキルとの関係」表から行を削除する**

`shared/skills/create-issue/SKILL.md:432` の次の行を**行ごと削除**する:

```markdown
| `dev-orchestration` | ワークフロー判断ハブ | Phase 2-2 からこのスキルを呼ぶ |
```

- [ ] **Step 7: 残存参照ゼロを検証する**

Run:

```bash
rg -n 'dev-orchestration|juggernaut|copilot-review|cursor-code' shared/skills/create-issue/SKILL.md
```

Expected: 0 件（exit code 1）

- [ ] **Step 8: Commit**

```bash
git add shared/skills/create-issue/SKILL.md
git commit -m "$(cat <<'EOF'
docs(create-issue): drop references to the removed dev-orchestration skill

description のトリガー条件・存在理由・例の前提から消えたハブへの依存を外す。
呼び出し元へ Issue 番号を返す振る舞いは他スキルからの呼び出しでも有効なため、
スキル名の名指しだけを一般化して残す。

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: 残るスキル・エージェント定義から削除済みスキル名を外す

3 ファイルとも「スキル名の差し替えのみ、挙動変更なし」で性質が同じため 1 コミットにまとめる。

**Files:**
- Modify: `shared/skills/cleanup-stale-worktrees/SKILL.md:343`
- Modify: `shared/skills/consult-specialists/SKILL.md:7`（frontmatter description）
- Modify: `shared/skills/consult-specialists/SKILL.md:120`
- Modify: `shared/agents/meta-reviewer.md:23`（frontmatter description の example）

**Interfaces:**
- Consumes: なし
- Produces: なし

- [ ] **Step 1: `cleanup-stale-worktrees` の関係表から行を削除する**

`shared/skills/cleanup-stale-worktrees/SKILL.md:343` の次の行を**行ごと削除**する:

```markdown
| `dev-orchestration` | ワークフロー判断ハブ | Phase 6 完走後、定期的にこのスキルを回す運用が想定される |
```

- [ ] **Step 2: `consult-specialists` の description から `juggernaut` を外す**

`shared/skills/consult-specialists/SKILL.md:7` を次に置換する:

```markdown
  ※PR レビュー専用フローは既存の pr-review スキルを優先する。本スキルは「より良い問題定義と解決」を目的に、専門家を選んで呼ぶ／作業を任せる／レビューを得るためのメタ起動。
```

- [ ] **Step 3: 「使うべきでないとき」の誘導先を実在スキルにする**

`shared/skills/consult-specialists/SKILL.md:120` を次に置換する:

```markdown
- 大きめの実装着手 → `superpowers:brainstorming` → `superpowers:writing-plans` → `superpowers:executing-plans`（その中で必要に応じてこのスキルを併用）
```

- [ ] **Step 4: `meta-reviewer` の example から `juggernaut` を外す**

`shared/agents/meta-reviewer.md:23` を次に置換する:

```markdown
  Context: PR 起票前の実装完了時セルフレビュー
```

- [ ] **Step 5: 残存参照ゼロを検証する**

Run:

```bash
rg -n 'dev-orchestration|juggernaut|copilot-review|cursor-code' \
  shared/skills/cleanup-stale-worktrees/SKILL.md \
  shared/skills/consult-specialists/SKILL.md \
  shared/agents/meta-reviewer.md
```

Expected: 0 件（exit code 1）

- [ ] **Step 6: Commit**

```bash
git add shared/skills/cleanup-stale-worktrees/SKILL.md shared/skills/consult-specialists/SKILL.md shared/agents/meta-reviewer.md
git commit -m "$(cat <<'EOF'
docs(skills): retarget removed-skill references to existing entry points

juggernaut が担っていた実装着手フローは superpowers の
brainstorming → writing-plans → executing-plans に、PR レビューは pr-review に
分解済み。単に消すと誘導先が失われるため、実在するスキルへ差し替える。

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: `CLAUDE.md` をレビュー構成とデプロイ実態に合わせる

`juggernaut` 参照の除去に加え、削除で宙に浮いた `self_review` モードの起動経路と、repo 内 symlink ミラーが非網羅である旨を明記する。

**Files:**
- Modify: `CLAUDE.md:81`（レビュー用エージェント 冒頭）
- Modify: `CLAUDE.md:93`（固定2体の説明）
- Modify: `CLAUDE.md:133`（スペシャリスト運用原則）
- Modify: `CLAUDE.md:32` 直後（設計方針の段落に注記を追加）

**Interfaces:**
- Consumes: なし
- Produces: `README.md`（Task 6）が参照する「ルールの追加」節の見出し表記 `## スキル・エージェント・ルールの追加`（`CLAUDE.md:66` に既存。変更しない）

- [ ] **Step 1: 「レビュー用エージェント」冒頭から `juggernaut` を外す**

`CLAUDE.md:81` を次に置換する:

```markdown
`pr-review` スキル（PRレビュー）では固定2体 + 差分に応じたスペシャリスト 0〜3 体を並列起動する。すべてのエージェントが統一された JSON 出力（`findings[]` + `severity` + `mode`）を返す。
```

- [ ] **Step 2: `self_review` の起動経路を明記する**

`CLAUDE.md:93`（`固定2体は見るスコープが排他的に…` で始まる段落）を次に置換する:

```markdown
固定2体は見るスコープが排他的に設計されている。各エージェントは入力プロンプトから動作モード（`pr_review` / `self_review`）を自動判定する。出力 JSON の `mode` フィールドで実モードを追跡できる。

`self_review` に専用スキルは無い（かつて `juggernaut` が入口だったが撤去済み）。セルフレビューは `meta-reviewer` / `fatal-reviewer` を Task ツールから直接起動し、プロンプトに `branch` / `plan` / 「セルフレビュー」を含めて自動判定させる。
```

- [ ] **Step 3: スペシャリスト運用原則から `juggernaut` を外す**

`CLAUDE.md:133` を次に置換する:

```markdown
- **PR 専用フローは既存スキル優先**: PR レビューは `pr-review`。本枠組みはその中で「不足する視点を補う」位置付け
```

- [ ] **Step 4: repo 内ミラーが非網羅であることを注記する**

`CLAUDE.md:32`（`**設計方針**: ...ファイル単位でリンクする。` で終わる段落）の直後に、空行を挟んで次の段落を挿入する:

```markdown
`claude/` / `cursor/` / `codex/` 配下の symlink は repo 内から辿るための**参照用ミラーであり、網羅的ではない**（例: `cursor/rules/coding.md` は張っていない）。正本は常に `shared/`、実際の配置先は `deploy.sh` が唯一の真実。ミラーを増やすとルール追加のたび手作業が要りズレの再発源になるため、意図的に揃えていない。
```

- [ ] **Step 5: 残存参照ゼロと追記を検証する**

Run:

```bash
rg -n 'dev-orchestration|juggernaut' CLAUDE.md | rg -v '撤去済み'
rg -n '参照用ミラーであり、網羅的ではない|self_review` に専用スキルは無い' CLAUDE.md
```

Expected: 1 行目は 0 件（Step 2 で追加した「撤去済み」の 1 箇所だけが `juggernaut` を含み、それは除外される）。2 行目は 2 件ヒット

- [ ] **Step 6: Commit**

```bash
git add CLAUDE.md
git commit -m "$(cat <<'EOF'
docs: record the self-review entry point and non-exhaustive repo mirrors

juggernaut 撤去で self_review モードの起動経路が repo 内から消え、仕様が
動かないのか手動起動なのか読み取れなくなっていた。エージェント直接起動である
ことを明記する。あわせて cursor/rules に coding.md ミラーが無い件を「意図的に
揃えていない」と明文化し、次のルール追加時に不整合と誤認されないようにする。

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: `README.md` と `deploy.sh` コメントを rules の実態に合わせる

`shared/rules/` 導入時に `CLAUDE.md` だけ更新され `README.md` が取り残された箇所と、`deploy.sh` のコメントが `CLAUDE.md:34` と矛盾している箇所を直す。

**Files:**
- Modify: `README.md:63`（見出し）
- Modify: `README.md:65-74`（追加手順のコードブロックと後続）
- Modify: `scripts/deploy.sh:94-99`（`link_rule_path` のコメント）

**Interfaces:**
- Consumes: `CLAUDE.md:66` の見出し表記 `## スキル・エージェント・ルールの追加`（Task 5 で変更していない既存値）
- Produces: なし

- [ ] **Step 1: README の見出しを CLAUDE.md と揃える**

`README.md:63` を次に置換する:

```markdown
## スキル・エージェント・ルールの追加
```

- [ ] **Step 2: 追加手順にルールを足す**

`README.md:65-74` のコードブロック全体を次に置換する:

````markdown
```bash
# スキル
mkdir -p shared/skills/my-skill
# shared/skills/my-skill/SKILL.md を書く
./scripts/deploy.sh

# エージェント（Claude / Cursor のみ）
# shared/agents/my-agent.md を書く
./scripts/deploy.sh

# ルール（3ツール共通）
# shared/rules/my-task.md を書く
# shared/instructions.md の「タスク別ルール」表に1行追加する
./scripts/deploy.sh
```

`shared/rules/` のファイルは Claude Code で毎セッション全文がロードされる。特定スキルからしか参照しない長大な参照表は rules ではなく、そのスキルの補助ファイル（`shared/skills/<skill>/`）として置く。
````

- [ ] **Step 3: `deploy.sh` のコメントを実態に合わせる**

`scripts/deploy.sh:94-99` のコメントブロックを次に置換する（`~/.codex/rules` は Codex がネイティブに読む場所ではなく aimod の慣習置き場であることを明示する）:

```bash
# Link a rules path without ever destroying rules we did not create. Only
# ~/.claude/rules is loaded natively by its tool; ~/.codex/rules is an aimod
# convention that Codex reads on demand, since Codex has AGENTS.md alone with
# no rule imports. Either way all three may already hold entries from outside
# aimod, so anything not ours is left exactly as it is. Used for both the
# whole-dir targets (~/.claude/rules, ~/.codex/rules) and the per-file ones
# (~/.cursor/rules/<name>.md), where a generic name like coding.md can collide
# with a rule the user already keeps there.
```

- [ ] **Step 4: 構文と内容を検証する**

Run:

```bash
bash -n scripts/deploy.sh && echo "syntax OK"
rg -n 'native to their tool' scripts/deploy.sh
rg -n 'スキル・エージェント・ルールの追加|shared/rules/my-task.md' README.md
```

Expected: `syntax OK` が出力される。2 行目は 0 件（exit 1）。3 行目は 2 件ヒット

- [ ] **Step 5: Commit**

```bash
git add README.md scripts/deploy.sh
git commit -m "$(cat <<'EOF'
docs: add rule authoring steps to README and correct the rules-path comment

shared/rules 導入時に CLAUDE.md だけ更新され README が取り残されていた。
また link_rule_path のコメントが 3 箇所すべてを native と書いていたが、
CLAUDE.md が記すとおり Codex は AGENTS.md 一枚のみで rules を自動ロードしない。

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: 全体検証

自動テストが無いリポジトリのため、参照掃除の網羅性とデプロイの冪等性を明示的に確認して締める。

**Files:**
- Modify: なし（検証のみ）

**Interfaces:**
- Consumes: Task 1〜6 のすべての変更
- Produces: なし

- [ ] **Step 1: `docs/` を除く全ファイルで削除済みスキル参照がゼロであることを確認する**

Run:

```bash
rg -n 'dev-orchestration|copilot-review|cursor-code' --glob '!docs/**' .
```

Expected: 0 件（exit code 1）

- [ ] **Step 2: `juggernaut` の残存が意図した 1 箇所のみであることを確認する**

Run:

```bash
rg -n 'juggernaut' --glob '!docs/**' .
```

Expected: `CLAUDE.md` の 1 件のみ（Task 5 Step 2 で追加した「かつて `juggernaut` が入口だったが撤去済み」の説明文）。それ以外がヒットしたら該当タスクに戻る

- [ ] **Step 3: 移動済みファイルへの旧パス参照がないことを確認する**

Run:

```bash
rg -n 'shared/rules/review-badges' --glob '!docs/**' .
```

Expected: 0 件（exit code 1）

- [ ] **Step 4: `deploy.sh` を再実行して冪等性と非破壊性を確認する**

Run:

```bash
./scripts/deploy.sh
```

Expected: `deploying from ...` と `done` のみ。`link` / `prune stale` / `replace non-symlink` / `SKIP` の行が 1 つも出ないこと（すべて既に正しい状態なので変更が発生しない）。もし `SKIP` が出た場合はそのパスを個別に調査する

- [ ] **Step 5: デプロイ実体に削除済みスキルの残骸が無いことを確認する**

Run:

```bash
ls ~/.codex/skills/ | rg 'juggernaut|dev-orchestration|copilot-review|cursor-code'
ls -la ~/.cursor/rules/
```

Expected: 1 行目は 0 件（exit 1）。2 行目は `AGENTS.md` と `coding.md` の 2 本の symlink がいずれも aimod 配下を指していること

- [ ] **Step 6: 作業ツリーがクリーンであることを確認する**

Run:

```bash
git status --short
git log --oneline -6
```

Expected: `git status --short` は空。`git log` に Task 1〜6 の 6 コミットが並ぶ

---

## 対応しないもの（意図的なスコープ外）

| 項目 | 理由 |
|---|---|
| `docs/specs/` / `docs/plans/` 内の `juggernaut` / `dev-orchestration` / `shared/rules/review-badges.md` 参照（計 30 箇所以上） | 当時の設計・計画の歴史的記録。書き換えると「その時点で何を前提に決めたか」が失われる |
| `self_review` モード自体の撤去 | Global Constraints 記載のとおり、エージェント直接起動で機能しており撤去の必要がない。撤去すると `pr-review/SKILL.md:411` まで連鎖改修になる |
| `cursor/rules/coding.md` などの repo 内ミラー追加 | ルール追加のたび手作業が要り、忘れれば同じ不整合が再発する。Task 5 Step 4 で「非網羅は意図的」と明文化する方を採る |
| `mojiemoji-github` プラグイン依存（`REVIEW-BADGES.md`） | `~/.claude/plugins/installed_plugins.json` に `mojiemoji-github@mojiemoji-plugin` v0.24.24 がインストール済みであることを確認済み。切れていない |
