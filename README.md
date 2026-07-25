# aimod

Claude Code・Cursor・Codex CLI の指示・agents・skills を一元管理し、ホームディレクトリへシンボリックリンクでデプロイする。

外部依存は **bash のみ**（`./scripts/deploy.sh`）。

## 特徴

- **3ツール共通の正本**: `shared/` を編集すれば 3 ツールに反映される。ただし受け取る範囲はツールごとに違う（「デプロイ先」節を参照）
- **agents は Claude / Cursor 向け**: PR レビュー用 2 体 + スペシャリスト 12 体（`pr-review` で動的追加）
- **skills は全ツールへ**: Codex は `~/.codex/skills/.system` と共存するようスキル単位でリンク
- **gh skill と役割分担**: 探索は `gh skill`、配置の正本は aimod（user scope インストールは使わない）

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
  rules/            # タスク別ルール（coding.md）。Claude / Codex 用
claude/             # settings.json など Claude 固有 + 参照用 symlink
cursor/             # 参照用 symlink
codex/              # 参照用 symlink
scripts/
  deploy.sh
  undeploy.sh
```

## デプロイ先

| 正本 | 配置先 |
|---|---|
| `shared/instructions.md` | `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md` |
| `shared/agents` | `~/.claude/agents`, `~/.cursor/agents` |
| `shared/skills` | `~/.claude/skills`, `~/.cursor/skills` |
| `shared/skills/<name>` | `~/.codex/skills/<name>` |
| `shared/rules` | `~/.claude/rules`, `~/.codex/rules` |
| `claude/settings.json` | `~/.claude/settings.json` |
| `claude/statusline.sh` | `~/.claude/statusline.sh` |

rules の配置先はどちらも他ツールやユーザー自身のルールと共有しうるため、同名の実体ファイル・外部ツール管理の symlink があれば破壊せず SKIP する。取り込みたい場合は中身を `shared/rules` へ移してから再実行する。

上の表は `deploy.sh` が作る**配置先**であって、各ツールがそれを読み込むかは別問題。自動ロードが確認できているのは `~/.claude/rules` のみで、Codex 向けは `~/.codex/AGENTS.md` 末尾の「タスク別ルール」表を入口に、エージェントが必要なときだけ該当ファイルを読む前提で置いている。

**Cursor は agents と skills だけを受け取る。** Cursor にはユーザーレベルの rules 機構が無く（rules はプロジェクト単位の `.cursor/rules/*.mdc`）、instructions の受け皿も無いため。Cursor にグローバル指示を渡したい場合はリポジトリ単位で `.cursor/rules/*.mdc` を置くか、内容をスキル化する。根拠と実測は [`CLAUDE.md`](CLAUDE.md) を参照。

`shared/` からスキルを消した場合、`~/.codex/skills/<name>` に残る壊れた symlink は次回の `deploy.sh` が自動で除去する（aimod 由来のリンクのみ。実体や外部ツール管理のリンクは残す）。過去バージョンが `~/.cursor/rules/` に張ったリンクも同様に除去される。

管理しないもの: `~/.codex/config.toml`、auth / credentials、`~/.cursor/cli-config.json`、`~/.cursor/skills-cursor/`

## スキル・エージェント・ルールの追加

```bash
# スキル
mkdir -p shared/skills/my-skill
# shared/skills/my-skill/SKILL.md を書く
./scripts/deploy.sh

# エージェント（Claude / Cursor のみ）
# shared/agents/my-agent.md を書く
./scripts/deploy.sh

# ルール（Claude / Codex のみ）
# shared/rules/my-task.md を書く
# shared/instructions.md の「タスク別ルール」表に1行追加する
./scripts/deploy.sh
```

`shared/rules/` のファイルは Claude Code で毎セッション全文がロードされる。特定スキルからしか参照しない長大な参照表は rules ではなく、そのスキルの補助ファイル（`shared/skills/<skill>/`）として置く。

### gh skill について

- OK: `gh skill search` / `preview`
- NG: `gh skill install --scope user`（実体コピーで symlink を壊す）
- 取り込み: 外部スキルは `shared/skills/` にコピーし、競合時は新しい方を採用してから `./scripts/deploy.sh`

## ドキュメント

- リポジトリ内の詳細（レビュー用エージェントなど）: [`CLAUDE.md`](CLAUDE.md)
- 設計メモ: [`docs/specs/2026-07-24-unified-ai-config-design.md`](docs/specs/2026-07-24-unified-ai-config-design.md)
