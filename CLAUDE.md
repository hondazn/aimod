# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## リポジトリ概要

AIコーディングアシスタント（Claude Code、Cursor）のカスタム設定（agents、skills）を一元管理し、[dotter](https://github.com/SuperCuber/dotter) で各ツールのホームディレクトリにシンボリックリンクとしてデプロイするdotfilesリポジトリ。

## アーキテクチャ

```
shared/          ← agents・skillsの実体（Claude/Cursor共通）
  agents/        ← PRレビュー用エージェント（3種: correctness, quality-test, security-perf）
  skills/        ← スラッシュコマンドで呼び出すスキル群
  rules/         ← 共通ルール（現在空）
claude/          ← Claude Code用設定
  CLAUDE.md      ← グローバルCLAUDE.md（~/.claude/ に配置される）
  agents -> ../shared/agents
  skills -> ../shared/skills
cursor/          ← Cursor用設定
  agents -> ../shared/agents
  skills -> ../shared/skills
.dotter/         ← dotterの設定ファイル
```

**設計方針**: `shared/` に実体を置き、`claude/` と `cursor/` からシンボリックリンクで参照することで、ツール間で設定を共有している。

## デプロイ

```bash
dotter deploy    # シンボリックリンクを作成・更新
dotter undeploy  # シンボリックリンクを削除
```

デプロイ先は `.dotter/global.toml` で定義:
- `claude/agents` → `~/.claude/agents`
- `claude/skills` → `~/.claude/skills`
- `cursor/agents` → `~/.cursor/agents`
- `cursor/skills` → `~/.cursor/skills`

## スキル・エージェントの追加

- **スキル追加**: `shared/skills/<skill-name>/SKILL.md` を作成（フロントマター付きMarkdown）
- **エージェント追加**: `shared/agents/<agent-name>.md` を作成（フロントマター付きMarkdown）
- 補助ファイル（EXAMPLES.md、TEMPLATES.md等）は同じディレクトリに配置可能

## 既存のエージェント（PRレビュー用3分割構成）

| エージェント | 観点 | JSON出力 |
|---|---|---|
| `correctness-reviewer` | ロジック誤り、境界条件、エラーハンドリング、null安全性、競合状態 | `findings[]` |
| `quality-test-reviewer` | テスト有無・品質、命名、複雑さ、重複、デッドコード | `findings[]` |
| `security-perf-reviewer` | インジェクション、認証認可、N+1クエリ、メモリリーク | `findings[]` |

3エージェントとも統一されたJSON出力フォーマット（`severity`: must/suggestion/nit/good）を使用する。

## 注意事項

- `claude/CLAUDE.md` はグローバル設定（`~/.claude/CLAUDE.md`）としてデプロイされるため、変更の影響範囲が広い
- `shared/` 配下の変更は Claude Code と Cursor の両方に影響する
