# レビューコメント用バッジ定義（mojiemoji 版）

`pr-review` の 4-6（コメント整形）と Phase 5（LGTM バッジ）が参照する表。画像は <https://mojiemoji.jozo.beer/> が返す。

インラインバッジは3要素から成る。重要度は色で、内容はラベルで伝えるので、ラベルが揺れても重要度は読み取れる。

| 要素 | 決まり方 | 役割 |
|---|---|---|
| ラベル | reviewer の `badge_label`（違反時はフォールバック） | 何の話か |
| color | severity から固定 | 重要度 |
| animation | reviewer 名のプールをローテーション | 誰の指摘か |

## ヘルパー

URL は `mojiemoji-github` スキルのヘルパー `mojiemoji_markdown.rb` で作り、手書きしない。ヘルパーは `background=transparent` を必ず付け、ダークモードでバッジが見えなくなる事故を防ぐ。

パスは `$CLAUDE_PLUGIN_ROOT/skills/mojiemoji-github/scripts/mojiemoji_markdown.rb`、無ければ `~/.claude/plugins/marketplaces/mojiemoji-plugin/skills/mojiemoji-github/scripts/mojiemoji_markdown.rb`。どちらも無ければ報告して停止する。

```bash
ruby "$HELPER" --text $'見事な\n抽象化' --color pastel-green --animation shuchusen --font gothic-bold
# 出力: ![見事な抽象化](https://mojiemoji.jozo.beer/emoji/見事な%0A抽象化?color=pastel-green&animation=shuchusen&font=gothic-bold&background=transparent)
```

ラベルは生の日本語のまま渡せる。改行は literal `\n` で渡すと `%0A` になる。`font` は `gothic-bold` 固定。

## badge_label の制約とフォールバック

制約: 改行を除いて合計15文字以内、1行5文字以内、改行2回まで（最大3行）、各行に日本語を1文字以上含む（`N+1` のように記号・英数字が日本語と混じるのは可）。

例: `根本原因外` / `AC漏れ` / `見事な\n抽象化` / `テスト\nが薄い` / `N+1\n警戒`

空・未指定、または制約に違反したら、severity 別のラベルに差し替え、件数を 6-3 で報告する。

| severity | color | フォールバックラベル |
|---|---|---|
| `fatal` | `vivid-red` | `致命` |
| `must` | `vivid-red` | `要修正` |
| `suggestion` | `vivid-blue` | `オススメ` |
| `nit` | `vivid-green` | `ちょっと\n気になる` |
| `good` | `pastel-green` | `いいね` |

`vivid-*` / `pastel-*` は mojiemoji のサーバ側プリセット名。レビューバッジは mojiemoji-github の「アクションバッジ」例外として、重要度が読み取れるようこの固定色を使う。

## reviewer → animation

| reviewer | プール（ローテーション順） |
|---|---|
| `fatal-reviewer` | `gatagata` → `shuchusen` → `bure` → `chuuou_zoom` |
| `lead` | `shuchusen` → `bure` → `gatagata` → `poyoon` |
| `meta-reviewer` | `shuchusen` → `bure` → `gatagata` → `poyoon`（`self_review` 用。レビュー経路では使わない） |
| その他（スペシャリスト） | `yoko_scroll` → `mochimochi` → `bane` → `poyoon` |

統合・並べ替え後の順に走査し、reviewer 名ごとのカウンタ `i`（0始まり）で `pool[i % len(pool)]` を使う。各 reviewer の1件目は必ず先頭のアニメになる。severity とラベルはアニメに影響しない。

## APPROVE 時の LGTM バッジ

ラベルは `LGTM` 固定で、装飾は毎回変える。reviewer のプールや severity の色は使わない。`mojiemoji-selector` サブエージェントに次の契約で依頼する:

```text
SURFACE: review-summary-body
MODE:    lgtm-badge
TONE:    loud
PHRASES:
- LGTM — マージ可の宣言
CONSTRAINTS:
- Every URL MUST include &background=transparent
- ラベルは "LGTM" 固定（差し替え禁止）
- 装飾（color / animation / font）はバリエーション最大化
- block ではなく inline `<img>` スニペットで返す
```
