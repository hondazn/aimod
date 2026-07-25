# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## リポジトリ概要

AIコーディングアシスタント（Claude Code、Cursor、Codex CLI）のカスタム設定（指示・agents・skills）を一元管理し、`scripts/deploy.sh` で各ツールのホームディレクトリにシンボリックリンクとしてデプロイするdotfilesリポジトリ。外部依存は bash のみ。

## アーキテクチャ

```
shared/          ← 実体（3ツール共通の正本）
  instructions.md ← グローバル指示（CLAUDE.md / AGENTS.md の正本）。汎用ルールのみ
  agents/        ← PRレビュー用 2 体 + スペシャリスト 12 体（Claude/Cursorのみ）
  skills/        ← スラッシュコマンドで呼び出すスキル群
  rules/         ← タスク別ルール（`coding.md`: コード変更時に適用）。3ツール共通
claude/          ← Claude Code用のツール固有ファイル
  CLAUDE.md -> ../shared/instructions.md
  agents -> ../shared/agents
  skills -> ../shared/skills
  settings.json / statusline.sh
cursor/          ← Cursor用（repo内参照用symlink）
  agents -> ../shared/agents
  skills -> ../shared/skills
codex/           ← Codex用（repo内参照用symlink）
  AGENTS.md -> ../shared/instructions.md
scripts/
  deploy.sh / undeploy.sh
```

**設計方針**: `shared/` に実体を置き、`deploy.sh` がホームディレクトリへ直接 symlink する。agents は Claude / Cursor のみ（Codex は同型の agents をサポートしない）。Codex skills は `~/.codex/skills/.system` 共存のためスキル単位でリンクする。Cursor へは instructions を `~/AGENTS.md` として配る（ワークスペースから上へ辿って拾われる唯一の経路 — 後述）。

`claude/` / `cursor/` / `codex/` 配下の symlink は repo 内から辿るための**参照用ミラーであり、網羅的ではない**（例: `codex/` に skills / rules のミラーは無い）。正本は常に `shared/`、実際の配置先は `deploy.sh` が唯一の真実。ミラーを増やすと追加のたび手作業が要りズレの再発源になるため、意図的に揃えていない。

**instructions.md と rules/ の切り分け**: `instructions.md` には作業種別を問わず常に効く汎用ルールだけを置き、特定作業のルールは `rules/<task>.md` に分離する。Claude Code は `~/.claude/rules/` をネイティブに自動ロードするが、Codex は AGENTS.md 一枚のみで import も glob スコープも持たない。そのため `instructions.md` 末尾の「タスク別ルール」表が **Cursor / Codex 側の入口**を兼ねる（どちらも rules を自動ロードしないので、表を見て自分でファイルを開く）。

Claude Code では `~/.claude/rules/` の内容が **subagent にも届く**（`claude -p` から subagent を起動して実測、2026-07-25 / v2.1.220）。公式ドキュメントが subagent へ届くものとして列挙しているのは project rules だけで user-level rules の記載がないため、バージョン更新時は再確認すること。

**Cursor へのグローバル指示は `~/AGENTS.md` 経由で配る。** Cursor はワークスペースから上へ辿って `AGENTS.md` を拾い、`~` はすべてのリポジトリの祖先なので、ここに置けば全プロジェクトに効く。rules 自体は自動ロードされないため、`~/.cursor/rules` は **`AGENTS.md` の「タスク別ルール」表から参照される置き場**として使う（エージェントが必要なときに開く）。

実測（2026-07-25 / `cursor-agent` v2026.07.23-e383d2b）。**ファイルに「返答の先頭に特定の文字列を書け」と指示し、出力に現れるかで判定**した（自己申告の照会は偽陽性が出たため採用しない）:

| 配置先 | cursor-agent | 備考 |
|---|---|---|
| **`~/AGENTS.md`** | **届く** | 指示に従った。これが唯一機能する経路 |
| `~/.cursor/AGENTS.md` | 届かない | ワークスペースの祖先ではないため拾われない |
| `~/.cursor/rules/*` | 届かない | 自動ロードなし。参照される置き場としてのみ使う |
| `~/.cursor/skills`, `~/.cursor/agents` | 届く | Cursor が文書化しているユーザーレベル配置先 |

`~/AGENTS.md` は **Claude Code と Codex では読まれない**（同じ方法で確認。どちらも指示に従わなかった）。したがって `~/.claude/CLAUDE.md` / `~/.codex/AGENTS.md` との二重ロードは起きない。

Cursor 本来の rules 機構は別にあり、いずれも今回は使っていない: User Rules は UI 管理（Customize → Rules）で symlink できず、Project Rules（`.cursor/rules/*.mdc`、frontmatter 必須、**frontmatter の無い `.md` は無視**）とプロジェクト直下の `AGENTS.md` はリポジトリ単位。プラグイン（`~/.cursor/plugins/local/<name>` に symlink、`rules/*.mdc` 同梱）はユーザー単位で配れるが、`.mdc` の frontmatter が要り `shared/rules/*.md` をそのままリンクできないため採らなかった。

出典: <https://cursor.com/docs/context/rules> / <https://cursor.com/docs/plugins>。バージョン更新時は上表を再測定すること。

実測（2026-07-25 / `cursor-agent` v2026.07.23-e383d2b / `gpt-5.4-mini-medium`）:

| 対象 | 結果 |
|---|---|
| `~/.cursor/rules/AGENTS.md`, `~/.cursor/rules/coding.md` | 届かない（中立ディレクトリで 3 マーカー全不在、repo 内でも列挙されず）|
| `~/.cursor/skills` | 届く（aimod の全スキルが列挙された）|
| `~/.cursor/agents` | 届く（14 エージェントすべて列挙された）|
| ワークスペース直下の `CLAUDE.md` | 届く |

いずれも `cursor-agent -p` にロード済みコンテキストを照会した**自己申告ベースの間接的な確認**で、CLI 1 バージョン・1 モデルでの結果。**Cursor IDE の挙動は未確認**。バージョン更新時と Cursor 向けデプロイを変える前に再確認すること。

## デプロイ

```bash
./scripts/deploy.sh     # シンボリックリンクを作成・更新（idempotent）
./scripts/undeploy.sh   # aimod 由来のシンボリックリンクだけ削除
```

デプロイ先:

- `shared/instructions.md` → `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/AGENTS.md`（最後が Cursor 用。ホーム直下はユーザー自身のファイルが置かれうるので、`link_rule_path` を通して**既存の実体があれば SKIP** する）
- `shared/agents` → `~/.claude/agents`, `~/.cursor/agents`
- `shared/skills` → `~/.claude/skills`, `~/.cursor/skills`
- `shared/skills/<name>` → `~/.codex/skills/<name>`（`.system` は触らない）
- `shared/rules` → `~/.claude/rules`, `~/.cursor/rules`, `~/.codex/rules`（自動ロードされるのは `~/.claude/rules` のみ。残り 2 つは「タスク別ルール」表から参照される置き場。いずれも aimod 由来でない実体・外部ツール管理の symlink は破壊せず SKIP する。取り込みたい場合は中身を `shared/rules` へ移してから再実行）

rules 配置先と `~/AGENTS.md` はすべて `link_rule_path` を通す。他ツールやユーザー自身のファイルと共有しうるため、**aimod 由来でないものは一切壊さない**（同名の実体・外部管理 symlink は SKIP し、そのエントリだけ諦めて他のデプロイは続行する）。

過去バージョンは `~/.cursor/rules` の中に `AGENTS.md` と各ルールを**ファイル単位**でリンクしていた。その残骸があるとディレクトリ丸ごとのリンクが永久に SKIP されるため、`deploy.sh` は先に aimod 由来のファイルリンクだけを外してから張り直す（`migrate: drop per-file link` としてログに出る）。

`~/.cursor/rules` については、**過去バージョンが張った aimod 由来のリンクを `deploy.sh` が削除する**（`is_ours` 判定を通すので他ツールやユーザー自身のファイルは残る）。空になればディレクトリごと畳む。

Claude / Cursor の `skills` はディレクトリ丸ごと 1 本の symlink なので削除に自動追随するが、Codex skills はエントリ単位のため取り残しが出る。`deploy.sh` はリンク作成後に `prune_stale_link` で、**aimod 由来かつリンク先が消えた** symlink だけを除去する（`.system`・実体・外部ツール管理のリンクは `is_ours` 判定で保護）。

なお `~/.claude/CLAUDE.md` / `~/.codex/AGENTS.md` は aimod が所有権を持つ配置先として、既存の実体があれば `replace non-symlink` をログに出して置換する（SKIP しない）。ここを SKIP にすると、既存ファイルのあるマシンで初回デプロイが何も反映されなくなるため。
- `claude/settings.json` → `~/.claude/settings.json`
- `claude/statusline.sh` → `~/.claude/statusline.sh`

管理しない: `~/.codex/config.toml`, auth / credentials, `~/.cursor/cli-config.json`, `~/.cursor/skills-cursor/`

## スキル・エージェント・ルールの追加

- **スキル追加**: `shared/skills/<skill-name>/SKILL.md` を作成 → `./scripts/deploy.sh`
- **エージェント追加**: `shared/agents/<agent-name>.md` を作成（Claude/Cursor のみ）→ `./scripts/deploy.sh`
- **ルール追加**: `shared/rules/<task>.md` を作成 → `instructions.md` の「タスク別ルール」表に1行追加 → `./scripts/deploy.sh`
- 補助ファイル（EXAMPLES.md、TEMPLATES.md等）は同じディレクトリに配置可能

`shared/rules/` に置いたファイルは Claude Code で**毎セッション全文がロードされる**。特定スキルからしか参照しない長大な参照表は rules ではなく、そのスキルの補助ファイルとして `shared/skills/<skill>/` に置くこと（例: `pr-review/REVIEW-BADGES.md`）。

### gh skill との関係

- 探索: `gh skill search` / `preview` は可
- **禁止**: `gh skill install --scope user`（実体コピーで aimod の symlink を壊す）
- 取り込み: 外部スキルは `shared/skills/` にコピーして aimod 正本化し、競合時は新しい方を採用してから `./scripts/deploy.sh`

## レビュー用エージェント

`pr-review` スキル（PRレビュー）では固定2体 + 差分に応じたスペシャリスト 0〜3 体を並列起動する。すべてのエージェントが統一された JSON 出力（`findings[]` + `severity` + `mode`）を返す。

### PRレビュー構成（pr-review）

固定:

| エージェント | 観点 |
|---|---|
| `meta-reviewer` | 方向性（コード本文は見ない） |
| `fatal-reviewer` | 致命のみ（`severity: fatal`）。これだけが CHANGES_REQUESTED |

追加: メインが差分に応じて既存スペシャリストを 0〜3 体選ぶ（`qa` / `safety-skeptic` 等）。

固定2体は見るスコープが排他的に設計されている。各エージェントは入力プロンプトから動作モード（`pr_review` / `self_review`）を自動判定する。出力 JSON の `mode` フィールドで実モードを追跡できる。

`self_review` に専用スキルは無い。セルフレビューは `meta-reviewer` / `fatal-reviewer` を Task ツールから直接起動し、プロンプトに `branch` / `plan` / 「セルフレビュー」を含めて自動判定させる。

## スペシャリスト（認知レンズ）エージェント

`consult-specialists` スキル経由で呼ぶ、**専門性とスタンスを持つ 12 体** のサブエージェント。`pr-review` では差分に応じて 0〜3 体が動的追加メンバーとしても選ばれる。各エージェントは助言だけでなく専門領域の作業も実行する。最終判断はメインエージェント。

### Core Engineering

| エージェント | 専門性 | 何を疑う／重視するか |
|---|---|---|
| `architect` | システム/境界/抽象化/データモデル/API | 長期的な構造整合性 |
| `solver` | 問題解決/突破/プロト/代替案 | まず動く解 / 制約から逆算 |
| `tech-lead` | 実装品質/PR 設計/レビュー/プロセス | チームで保守できるか |
| `qa` | テスト/AC/エッジケース/影響範囲 | 仕様は曖昧、実装は壊れる |

### Product Quality

| エージェント | 専門性 | 何を疑う／重視するか |
|---|---|---|
| `taste` | 体験/情報設計/コピー/一貫性 | 気持ちよさ、わかりやすさ、削ぎ落とし |
| `friction-maximalist` | UX/オンボーディング/認知負荷 | ユーザーは読まない・迷う・離脱する |
| `business-realist` | 事業価値/ROI/優先順位/コスト | いま作る価値があるか / 機会費用 |
| `data-realist` | 計測/ログ/KPI/分析 | 測れない成功を疑う |

### Risk / Sharpness / Optional

| エージェント | 専門性 | 何を疑う／重視するか |
|---|---|---|
| `failure-pessimist` | SRE/監視/復旧/運用 | 正常系より異常系 |
| `safety-skeptic` | セキュリティ/権限/漏洩/ポリシー | 悪用される前提 |
| `contrarian` | 差別化/戦略/尖り/反対意見 | 無難な案を疑う |
| `debt-auditor` | 負債/移行/廃止/所有権 | 撤去条件付きで入れる |

### 運用原則

- **全員を常に呼ばない**: 1〜3 体に絞る。観点が重複するエージェントは代表だけ呼ぶ
- **観点が独立なら並列、依存するなら逐次**: 例）architect + qa + safety-skeptic は並列／solver → tech-lead は逐次
- **助言モード／作業モード**: プロンプトで明示する。作業も任せられる（テスト追加、撤去計画起草、コピー書き換え等）
- **メインエージェントが統合・判断する**: 採用・棄却・保留を分け、衝突は目的／制約／リスク許容度に照らして決める
- **PR 専用フローは既存スキル優先**: PR レビューは `pr-review`。本枠組みはその中で「不足する視点を補う」位置付け

詳細は `shared/skills/consult-specialists/SKILL.md` を参照。

## 注意事項

- `shared/instructions.md` はグローバル設定（`~/.claude/CLAUDE.md` / `~/.codex/AGENTS.md`）としてデプロイされるため、変更の影響範囲が広い
- `shared/` 配下の変更は Claude Code・Cursor・Codex のすべてに影響する（agents は Claude / Cursor のみ）。ただし届き方は違い、rules を自動ロードするのは Claude Code だけ。Cursor / Codex は `AGENTS.md` の「タスク別ルール」表を見て自分で開く
