# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## リポジトリ概要

AIコーディングアシスタント（Claude Code、Cursor）のカスタム設定（agents、skills）を一元管理し、[dotter](https://github.com/SuperCuber/dotter) で各ツールのホームディレクトリにシンボリックリンクとしてデプロイするdotfilesリポジトリ。

## アーキテクチャ

```
shared/          ← agents・skillsの実体（Claude/Cursor共通）
  agents/        ← PRレビュー用 3 体（meta/pdm/techlead-reviewer）+ 合議用 + スペシャリスト 12 体
  skills/        ← スラッシュコマンドで呼び出すスキル群
  rules/         ← 共通ルール（`review-badges.md`: レビューコメント用バッジ定義の正典）
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

### 合議用

- `review-acceptor` / `review-challenger`: 上記 3 体の判断レベルが衝突したときに合議で採否を決める

## スペシャリスト（認知レンズ）エージェント

`consult-specialists` スキル経由で呼ぶ、**専門性とスタンスを持つ 12 体** のサブエージェント。PR レビュー特化のレビュー用エージェント群（meta/pdm/techlead-reviewer 等）とは独立した枠組み。各エージェントは助言だけでなく専門領域の作業も実行する。最終判断はメインエージェント。

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
- **PR 専用フローは既存スキル優先**: PR レビューは `pr-review`、実装着手は `juggernaut`。本枠組みはそれらの中で「不足する視点を補う」位置付け

詳細は `shared/skills/consult-specialists/SKILL.md` を参照。

## 注意事項

- `claude/CLAUDE.md` はグローバル設定（`~/.claude/CLAUDE.md`）としてデプロイされるため、変更の影響範囲が広い
- `shared/` 配下の変更は Claude Code と Cursor の両方に影響する
