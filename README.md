# aimod

Claude Code・Cursor・Codex CLI の指示・agents・skills を一元管理し、ホームディレクトリへシンボリックリンクでデプロイする。

外部依存は **bash のみ**（`./scripts/deploy.sh`）。

## 特徴

- **3ツール共通の正本**: `shared/` を編集すれば Claude / Cursor / Codex に同じ設定が届く（届き方の違いは「デプロイ先」節を参照）
- **agents は Claude / Cursor 向け**: PR レビュー用 2 体 + スペシャリスト 12 体（`pr-review` で動的追加）
- **skills は全ツールへ**: Codex は `~/.codex/skills/.system` と共存するようスキル単位でリンク

## セットアップ

```bash
git clone git@github.com:hondazn/aimod.git
cd aimod
./scripts/deploy.sh
```

外すとき:

```bash
./scripts/undeploy.sh   # aimod 由来の symlink だけ削除
```

## ディレクトリ構成

```
shared/
  instructions.md   # グローバル指示の正本（CLAUDE.md / AGENTS.md）。汎用ルールのみ
  agents/           # Claude / Cursor 用
  skills/           # 3ツール共通
claude/             # settings.json など Claude 固有 + 参照用 symlink
cursor/             # 参照用 symlink
codex/              # 参照用 symlink + status-line 定義
scripts/
  deploy.sh
  undeploy.sh
```

## デプロイ先

| 正本 | 配置先 |
|---|---|
| `shared/instructions.md` | `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/AGENTS.md`（Cursor 用）|
| `shared/agents` | `~/.claude/agents`, `~/.cursor/agents` |
| `shared/skills` | `~/.claude/skills`, `~/.cursor/skills` |
| `shared/skills/<name>` | `~/.codex/skills/<name>` |
| `claude/settings.json` | `~/.claude/settings.json` |
| `claude/statusline.sh` | `~/.claude/statusline.sh` |
| `cursor/statusline.sh` | `~/.cursor/statusline.sh` |
| `codex/statusline.toml` | `~/.codex/config.toml` の `tui.status_line`（他の設定は保持）|

`~/AGENTS.md` は、ユーザー自身のファイルと共有しうるため、同名の実体・外部ツール管理の symlink があれば破壊せず SKIP する。取り込みたい場合は中身を `shared/` へ移してから再実行する。

タスク別ルールは rules という別カテゴリを持たず、すべてスキルとして配る（例: `coding-standards` / `design-principles`）。過去バージョンが `~/.claude/rules` / `~/.codex/rules` / `~/.cursor/rules` に張ったリンクは、次回の `deploy.sh` が aimod 由来のものだけ削除する。

Cursor 向けの instructions が `~/AGENTS.md` なのは、Cursor がワークスペースから上へ辿って `AGENTS.md` を拾い、`~` が全リポジトリの祖先になるため。`~/.cursor/` 配下に置いても拾われないことを実測済み。この経路は Claude / Codex では読まれないので二重ロードにはならない。根拠は [`CLAUDE.md`](CLAUDE.md) を参照。

`shared/` からスキルを消した場合、`~/.codex/skills/<name>` に残る壊れた symlink は次回の `deploy.sh` が自動で除去する（aimod 由来のリンクのみ。実体や外部ツール管理のリンクは残す）。

`~/.codex/config.toml` はファイル全体を管理せず、`codex/statusline.toml` の `tui.status_line` だけをマージする。`undeploy.sh` は値が aimod の定義と一致する場合だけ削除し、ユーザーが変更した値や他の設定は保持する。

管理しないもの: `~/.codex/config.toml` のその他の設定、auth / credentials、`~/.cursor/cli-config.json`、`~/.cursor/skills-cursor/`

## スキル・エージェントの追加

```bash
# スキル
mkdir -p shared/skills/my-skill
# shared/skills/my-skill/SKILL.md を書く
./scripts/deploy.sh

# エージェント（Claude / Cursor のみ）
# shared/agents/my-agent.md を書く
./scripts/deploy.sh
```

`shared/instructions.md` はグローバル設定として毎セッション全文がロードされるため、足してよいのは常に効く汎用ルールだけ。特定作業の知識はスキル本文へ、特定スキルからしか参照しない長大な参照表はそのスキルの補助ファイル（`shared/skills/<skill>/`）として置く。

### gh skill について

- OK: `gh skill search` / `preview`
- NG: `gh skill install --scope user`（実体コピーで symlink を壊す）
- 取り込み: 外部スキルは `shared/skills/` にコピーし、競合時は新しい方を採用してから `./scripts/deploy.sh`

## ドキュメント

- リポジトリ内の詳細（レビュー用エージェントなど）: [`CLAUDE.md`](CLAUDE.md)
- 設計メモ: [`docs/specs/2026-07-24-unified-ai-config-design.md`](docs/specs/2026-07-24-unified-ai-config-design.md)
