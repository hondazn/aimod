# Unified AI config via aimod + deploy.sh

- 作成日: 2026-07-24
- 更新: 2026-07-24 — dotter を廃し `scripts/deploy.sh` に移行
- 関連: `shared/`, `claude/`, `cursor/`, `codex/`, `scripts/deploy.sh`, `scripts/undeploy.sh`

## 背景

aimod は Claude Code / Cursor 向けに設定を共有する想定だったが、`gh skill install --scope user` がホスト別ディレクトリへ実体コピーしたため symlink が壊れ、aimod 正本が orphan 化した。Codex CLI は未統合で、グローバル指示も別管理だった。

当初は dotter でデプロイしていたが、実態は symlink 列挙のみで、Codex の `.system` 共存のために追加スクリプトも必要だった。依存を減らすため bash の `deploy.sh` / `undeploy.sh` に置き換えた。

## ゴール

- Claude Code / Cursor / Codex CLI で指示・skills・agents（対応ツールのみ）を aimod 正本から共通利用する
- デプロイは外部依存なし（bash + `ln`）
- 重複スキルは新しい方を aimod に吸収する

## ノンゴール

- `jozobeer/agent-skills` リポジトリ自体の統合
- Codex `config.toml` / Cursor `cli-config.json` などシークレット・ランタイム設定の管理
- skills のツール別フィルタリング
- project-scope（各リポジトリの `.agents/skills`）の統一

## 決定事項

| 項目 | 決定 |
|---|---|
| 正本 | `aimod/shared/` |
| デプロイ | `./scripts/deploy.sh` / `./scripts/undeploy.sh` |
| 重複時 | 新しい方を aimod に吸収 |
| `gh skill` | search / preview のみ。`--scope user` インストール禁止 |
| agents | Claude / Cursor のみ。Codex にはデプロイしない |

## アーキテクチャ

```
shared/
  instructions.md
  agents/
  skills/
  rules/
claude/          # ツール固有ファイル + repo内参照用symlink
cursor/
codex/
scripts/deploy.sh
scripts/undeploy.sh
```

`deploy.sh` がホームへ直接リンクする。Codex だけは `shared/skills/<name>` → `~/.codex/skills/<name>` の個別リンク（`.system` を消さないため）。

## デプロイ先

- `shared/instructions.md` → `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.cursor/rules/AGENTS.md`
- `shared/agents` → `~/.claude/agents`, `~/.cursor/agents`
- `shared/skills` → `~/.claude/skills`, `~/.cursor/skills`
- `shared/skills/<name>` → `~/.codex/skills/<name>`
- `claude/settings.json` / `statusline.sh` → `~/.claude/`

管理しない: `config.toml`, `auth.json`, `cli-config.json`, `skills-cursor/`, credentials

## 外部スキル取り込み手順

1. `gh skill search` / `preview` で探索
2. 気に入ったスキルを `shared/skills/<name>/` にコピー
3. 競合時は新しい方を採用。`gh skill` metadata は削除してよい
4. `./scripts/deploy.sh`

## 移行メモ

- 旧ライブ skills のバックアップ例: `~/.aimod-skills-backup-*`
- dotter (`.dotter/`) と `scripts/sync-codex-skill-links.sh` は削除済み
