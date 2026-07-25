# aimod

Claude Code・Cursor・Codex CLI の指示・agents・skills を一元管理し、ホームディレクトリへシンボリックリンクでデプロイする。

外部依存は **bash のみ**（`./scripts/deploy.sh`）。

## 特徴

- **3ツール共通の正本**: `shared/` を編集すれば Claude / Cursor / Codex に同じ設定が届く
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
  instructions.md   # グローバル指示の正本（CLAUDE.md / AGENTS.md）
  agents/           # Claude / Cursor 用
  skills/           # 3ツール共通
  rules/
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
| `shared/instructions.md` | `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.cursor/rules/AGENTS.md` |
| `shared/agents` | `~/.claude/agents`, `~/.cursor/agents` |
| `shared/skills` | `~/.claude/skills`, `~/.cursor/skills` |
| `shared/skills/<name>` | `~/.codex/skills/<name>` |
| `claude/settings.json` | `~/.claude/settings.json` |
| `claude/statusline.sh` | `~/.claude/statusline.sh` |

管理しないもの: `~/.codex/config.toml`、auth / credentials、`~/.cursor/cli-config.json`、`~/.cursor/skills-cursor/`

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

### gh skill について

- OK: `gh skill search` / `preview`
- NG: `gh skill install --scope user`（実体コピーで symlink を壊す）
- 取り込み: 外部スキルは `shared/skills/` にコピーし、競合時は新しい方を採用してから `./scripts/deploy.sh`

## ドキュメント

- リポジトリ内の詳細（レビュー用エージェントなど）: [`CLAUDE.md`](CLAUDE.md)
- 設計メモ: [`docs/specs/2026-07-24-unified-ai-config-design.md`](docs/specs/2026-07-24-unified-ai-config-design.md)
