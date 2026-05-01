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

## レビュー用エージェント

`juggernaut` スキル（セルフレビュー）と `pr-review` スキル（PRレビュー）の両方で同じ 3 体を使う。観点が排他的に設計されているので並列起動しても指摘が重複しない。すべてのエージェントが統一された JSON 出力（`findings[]` + `severity: must/suggestion/nit/good` + `mode`）を返す。

### 主レビュー（3分割、観点が排他的）

| エージェント | 観点 | 見るもの | 見ないもの |
|---|---|---|---|
| `meta-reviewer` | 方向性（根本原因・Issue自体の妥当性・前提誤解・再発明と代替案・既存アーキ整合・長期整合） | Issue / 実装計画 (or PR本文) / 関連ドキュメント | コード本文 |
| `pdm-reviewer` | 価値・網羅性（AC充足とスコープ整合・エッジケース・UXと後方互換・仕様曖昧さと矛盾・テスト網羅） | Issue / 実装計画 (or PR本文) / テストコード | 実装ロジック |
| `techlead-reviewer` | 技術品質（正しさと堅牢性・性能・保守性・セキュリティ・運用・持続性とテスト構造） | コード全体 / 実装計画 (or PR本文) | Issue／Linterで検知できる事項 |

排他性の核は **「見ない境界」**: meta はコードを読まず、pdm は実装ロジックを読まず、techlead は Issue を読まない。観点が増えてもこの境界は維持する。

各エージェントは入力プロンプトから動作モード（`pr_review` / `self_review`）を自動判定する。出力 JSON の `mode` フィールドで実モードを追跡できる。

### 旧4体観点の吸収マッピング

新3体は旧4体（specification / correctness / quality-test / security-perf）の観点を吸収済み。観点ごとに担当先を整理:

- `specification-reviewer` の「基本方針の妥当性」「設計判断の妥当性（代替案・既存アーキ整合）」 → **meta-reviewer**
- `specification-reviewer` の「未実装/過剰実装/部分実装/スコープクリープ」「仕様の曖昧さ・矛盾」「ユーザーから見た影響範囲・後方互換」 → **pdm-reviewer**
- `correctness-reviewer` 全観点（ロジック誤り・境界条件・エラーハンドリング・null安全・並行性・型安全） → **techlead-reviewer** に「正しさ・堅牢性」セクションとして明示
- `quality-test-reviewer` のテスト構造品質（アサーション品質・テスト可読性・テスト容易性） → **techlead-reviewer** の「開発持続性」セクションに統合（テスト網羅は **pdm-reviewer** 担当のまま）
- `security-perf-reviewer` 全観点（セキュリティ・パフォーマンス・運用） → **techlead-reviewer**（既存カバー済み）

### 合議用

- `review-acceptor` / `review-challenger`: 上記 3 体の判断レベルが衝突したときに合議で採否を決める

### レガシー（現状未使用、削除候補）

以下は旧 4 分割 reviewer。観点は新3体に吸収済みで、`juggernaut` でも `pr-review` でも使われなくなったが、ファイルは残置している。完全に不要と判断したら削除してよい。

- `specification-reviewer` / `correctness-reviewer` / `quality-test-reviewer` / `security-perf-reviewer`

## 注意事項

- `claude/CLAUDE.md` はグローバル設定（`~/.claude/CLAUDE.md`）としてデプロイされるため、変更の影響範囲が広い
- `shared/` 配下の変更は Claude Code と Cursor の両方に影響する
