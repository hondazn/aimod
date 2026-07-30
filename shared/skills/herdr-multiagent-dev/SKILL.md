---
name: herdr-multiagent-dev
description: Herdr経由で複数のコーディングエージェントCLI（cursor-agent / codex / claude）を操縦し、builder・reviewer等の役割分担で開発を回すときに使う。「cursorに実装させて」「codexにレビューさせて」「マルチエージェントで開発」「クロスレビューを回して」「エージェントを自動操縦」などのリクエスト、またはHerdrペイン内から他エージェントに実装・レビューを委譲する場面で使用する。HERDR_ENV=1 が前提。Herdr CLIの構文はherdrスキルが正本。
---

# Herdr マルチエージェント開発

## 概要

自分（メインエージェント）が指揮者となり、Herdr ペイン内で別のエージェント CLI（cursor-agent / codex / claude）を起動・操縦して、役割分担で開発を回す手法。核心は3つ:

1. **クロスレビュー**: builder と reviewer は別ベンダーのエージェントに割り当てる。異種モデルは盲点が重なりにくく、品質ゲートの独立性が上がる
2. **プロンプト契約**: 各役割に作業ディレクトリ・限定スコープ・機械可読な完了報告を義務付ける
3. **防御的操縦**: TUI への入力は黙殺されうる前提で、送信→受理検証→完了待ちの各段に検証を挟む

**REQUIRED BACKGROUND:** herdr スキル（CLI 操作の正本）。開始前に `test "${HERDR_ENV:-}" = 1` を確認する。

## When to Use

- 実装とレビューを別エージェントに分担させたい（クロスレビュー）
- 複数エージェントを並列・逐次に操縦する半自動〜無人のパイプラインを組みたい
- **使わない**: 単発の調査委譲は codex-investigate、Herdr 外での並列作業は Task/サブエージェントを使う

## 役割設計

| 役割 | 担当 | スコープ |
|---|---|---|
| planner | 自分（または claude 上位モデル） | アイデア→受け入れ条件付き計画（PLAN.md） |
| plan-reviewer | planner と別エージェント | 受け入れ条件の検証可能性・スコープ妥当性のみ |
| builder | cursor 等 | 計画に沿った実装 + 自己検証 |
| reviewer | builder と別エージェント（codex 等） | fatal 問題 + 受け入れ条件の未達のみ。スタイル指摘禁止 |
| fixer | builder と同系 | 不合格時の修正。**1回だけ** |

- 役割→「エージェント+モデル」の割当リストを設定に持ち、先頭が主担当・以降フォールバック。クレジット系エラー（`credit balance` / `usage limit` / `rate limit`）を検出したら次候補で再実行
- 軽い役割は安価なモデルに落とす（例: バックログ補充は sonnet）
- 修正ループは fixer 1回→再レビュー→だめなら打ち切り。**「やめる判断」ができることが無人運用の品質担保**

## セッションライフサイクル

1セッション = 起動→送信→完了→回収→片付け。各段に検証を挟む。

以下のコマンド列は Herdr 0.7.4 実測時の構文（`agent start ... -- <cmd...>` / `agent wait --status`）。herdr スキルが示す新しい構文（`--kind` / `--until`）とはフラグが異なるため、**実行前に必ずインストール済みバイナリの help で現行構文を確認する**（正本はバイナリ）。手順の骨格と防御層はどの版でも変わらない:

```bash
# 1. 起動（無人化フラグはプロファイル表を参照）
herdr agent start <name> --cwd <dir> --split right --no-focus -- <cmd> <flags...>
# 2. 初回 idle まで待つ
herdr agent wait <name> --status idle --timeout 60000
# 3. 起動ゲート処理: 画面をポーリングし、信頼確認ダイアログが出ていたらキー送信
herdr agent read <name> --source recent-unwrapped --lines 40   # パターン照合→ send-keys
# 4. ready delay を置いてからプロンプト送信（+ 必要なら enter 追撃）
herdr pane run <pane_id> "<prompt>"
# 5. working への遷移を検証（受理確認）
# 6. settled 待ち（idle/done = 完了、blocked はデバウンス後に確定）
# 7. 回収して片付け
herdr agent read <name> --source recent-unwrapped --lines 200
herdr pane close <pane_id>   # 失敗時はログ退避後に閉じる
```

防御層の実測根拠（これを省くと無反応セッションの黙殺や誤判定が起きる）:

- **受理検証（ensureWorking）**: 送信後 1秒×5回 working/blocked への遷移をポーリング。遷移しなければ enter を再送、3セット試してだめなら失敗として throw。「送ったのに何も起きない」の黙殺防止
- **blocked デバウンス**: Herdr の blocked 検知には偽陽性がある。検知後 6秒おいて再取得し、まだ blocked なら確定
- **タイムボックス**: セッション待ちに上限（例: 2時間）を必ず設定。超過は打ち切りとして記録
- `agent prompt --wait` を持つ版ではそれを優先してよい（atomic 送信 + stall 検出内蔵）。ただし起動ゲートと起動直後の入力消失はエージェント側 TUI の癖なので、送信手段によらず下表の対処が必要

## エージェント別プロファイル（実測: Herdr 0.7.4 / 2026-07-30）

| エージェント | 無人化フラグ | 起動ゲート | 送信の癖 |
|---|---|---|---|
| cursor-agent | `--force` | Workspace Trust ダイアログ。**`--force` では抑止されない** → キー `a` を送信 | bracketed paste で入力ボックスに載るだけ → **2秒後に enter 追撃が必須**。ready delay 3秒 |
| codex | `-a never -s workspace-write` | なし | **TUI 起動直後に送ったプロンプトは消える** → idle 判定後さらに 5秒待って送信。enter 追撃有効 |
| claude | `--permission-mode acceptEdits` | `Do you trust the files in this folder` → enter で既定選択 | ready delay 3秒。追撃不要 |

- モデル指定フラグ: cursor `--model`（候補は `cursor-agent --list-models`）/ codex `-m` / claude `--model`
- codex は状態行に使用量残量（`weekly N% left`）を表示する — フォールバック判定の補助材料
- codex はサンドボックス外コマンドで本物の blocked（承認UI）になる。無人運用では `-a never` が必須
- **バージョン更新時は再測定すること**（癖は非公開仕様であり変わりうる）

## 合否判定の機械化（独立行契約）

reviewer への契約: 「最終行に必ず『合格』または『不合格』**とだけ**書く。不合格の場合はその前に理由を箇条書き」。

パース側は**下の行から走査**し、装飾を除いて判定語のみの行だけを判定とみなす:

```typescript
// 行中に判定語を含む文（送信プロンプト自体の画面エコー等)は判定として扱わない
const VERDICT_LINE = /^[•\-*\s]*(不合格|合格)[。．\s]*$/;
// 出力を末尾行から上へ走査し、最初に一致した行で判定。一致なしは「判定不明」= 不合格扱い
```

`grep <トークン> | tail -1` による部分一致は禁物: 送信したプロンプト（判定語の説明を含む）が画面にエコーされ、それを拾って誤判定する。

## プロンプト契約の型

```
あなたは <役割> です。作業ディレクトリ: <絶対パス>
<やることを1文で>
ルール:
- <スコープの限定・禁止事項>
- 完了前に <検証コマンド> を実行して通ることを確認
完了したら「<完了トークン or 合否の独立行>」と報告してください。
```

要点: 作業ディレクトリを明記（相手の cwd を信用しない）/ スコープを狭く切る / 自己検証を義務付ける / 報告は機械可読に。エージェント横断の共通指示は `AGENTS.md` に一本化し、`CLAUDE.md` は `@AGENTS.md` インポートのみにする。

## よくある失敗

| 症状 | 原因と対処 |
|---|---|
| 送ったのに何も起きない | TUI が入力を黙殺。working 遷移を検証し、来なければ enter 再送。3回でエラー化 |
| blocked と出たが動いている | 検知の偽陽性。6秒後に再確認してから対処 |
| 合否が常に同じ値になる | プロンプトのエコーを拾っている。独立行契約 + 末尾から走査に切替 |
| 長い出力が途中から読めない | alternate screen 落ち。herdr スキルのファイル出力フォールバックを使う |
| `agent wait` の応答パースで落ちる | 完了応答が `result` キーを持たない JSON の場合がある。防御的にパースする |
| 修正ループが止まらない | fixer は 1回だけと決めておく。だめなら打ち切り、失敗として記録 |
| レビューが細部指摘で埋まる | reviewer のスコープを fatal + 受け入れ条件のみに契約で限定する |
