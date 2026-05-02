# レビューコメント用バッジ定義（mojiemoji 版）

このドキュメントは **レビューコメント先頭に付ける重要度バッジの正典** です。
`shared/agents/{meta,pdm,techlead}-reviewer.md` と `shared/skills/pr-review/SKILL.md` から参照されます。
URL を変更したい場合はここを更新してから、参照元を `sed` で一括置換してください。

画像生成 API は <https://mojiemoji.jozo.beer/> （Slack 絵文字サイズの PNG / GIF を返す）を利用します。

## URL ビルド規則

```
https://mojiemoji.jozo.beer/emoji/{ラベル}?color={color}&animation={animation}&font=gothic-bold
```

- ラベルは生の日本語のまま埋めてよい（パスは percent-encode 不要、サーバ側で解釈される）
- `font` は `gothic-bold` 固定
- `color` は severity ごとに固定。`animation` はエージェント別ベース＋サブから選ぶ

## severity → ラベル / color

| severity | 日本語ラベル | color | 意味 |
|---|---|---|---|
| `must` | `要修正` | `vivid-red` | 正しく動作しない、セキュリティリスク、要件未充足 |
| `suggestion` | `オススメ` | `vivid-blue` | より良い実装が存在する |
| `nit` | `ちょっと` | `vivid-green` | 些細な改善点 |
| `good` | `いいね` | `pastel-green` | 良い実装、学びになるパターン |

## エージェント → アニメーション

各エージェントは **アニメプール** を持つ。先頭はベース（エージェント識別用に固定）、2 番目以降はローテーション枠。

| エージェント | アニメプール（ローテーション順） | 意味付け |
|---|---|---|
| `meta-reviewer` | `shuchusen` → `bure` → `gatagata` → `poyoon` | 集中線で前提に視線を奪う／グリッチで前提崩れ／弾みでやわらかく |
| `pdm-reviewer` | `yoko_scroll` → `mochimochi` → `bane` → `shuchusen` → `poyoon` | ユーザー体験の流れ／弾むリズムで網羅性ハイライト／たまに集中線で焦点化 |
| `techlead-reviewer` | `chuuou_zoom` → `gatagata` → `bure` → `shuchusen` → `poyoon` | 核心ズーム／ガタガタでバグの匂いを煽る／集中線で核心へ視線誘導 |

### ローテーション規則

エージェントは finding を出力するとき、自分の **finding 出力順インデックス `i` (0-indexed)** に対して `pool[i % len(pool)]` のアニメを採用する。

- `i = 0`（1 件目）は必ずベース。findings が 1 件のみのときも識別性が確保される。
- `i = 1, 2, ...` は順にローテーション枠を消費。プールを使い切ったら先頭に戻る。
- ローテーション値は **エージェント側で finding 生成時に確定**させる。`pr-review` の dedup 統合で勝った side のアニメをそのまま採用し、tiebreak のたびに再計算しない。
- severity（must/suggestion/nit/good）はアニメ選択に影響しない。色とラベルだけが severity を表す。

## バッジ URL 一覧

各エージェントが finding[].body の先頭に貼る Markdown 画像参照は、ベース（i=0）の例を以下に示す。
ローテーション枠（i ≥ 1）では URL の `animation=` 部分のみ差し替える。

### meta-reviewer（ベース: shuchusen / プール: shuchusen → bure → gatagata → poyoon）

```markdown
![要修正](https://mojiemoji.jozo.beer/emoji/要修正?color=vivid-red&animation=shuchusen&font=gothic-bold)
![オススメ](https://mojiemoji.jozo.beer/emoji/オススメ?color=vivid-blue&animation=shuchusen&font=gothic-bold)
![ちょっと](https://mojiemoji.jozo.beer/emoji/ちょっと?color=vivid-green&animation=shuchusen&font=gothic-bold)
![いいね](https://mojiemoji.jozo.beer/emoji/いいね?color=pastel-green&animation=shuchusen&font=gothic-bold)
```

### pdm-reviewer（ベース: yoko_scroll / プール: yoko_scroll → mochimochi → bane → shuchusen → poyoon）

```markdown
![要修正](https://mojiemoji.jozo.beer/emoji/要修正?color=vivid-red&animation=yoko_scroll&font=gothic-bold)
![オススメ](https://mojiemoji.jozo.beer/emoji/オススメ?color=vivid-blue&animation=yoko_scroll&font=gothic-bold)
![ちょっと](https://mojiemoji.jozo.beer/emoji/ちょっと?color=vivid-green&animation=yoko_scroll&font=gothic-bold)
![いいね](https://mojiemoji.jozo.beer/emoji/いいね?color=pastel-green&animation=yoko_scroll&font=gothic-bold)
```

### techlead-reviewer（ベース: chuuou_zoom / プール: chuuou_zoom → gatagata → bure → shuchusen → poyoon）

```markdown
![要修正](https://mojiemoji.jozo.beer/emoji/要修正?color=vivid-red&animation=chuuou_zoom&font=gothic-bold)
![オススメ](https://mojiemoji.jozo.beer/emoji/オススメ?color=vivid-blue&animation=chuuou_zoom&font=gothic-bold)
![ちょっと](https://mojiemoji.jozo.beer/emoji/ちょっと?color=vivid-green&animation=chuuou_zoom&font=gothic-bold)
![いいね](https://mojiemoji.jozo.beer/emoji/いいね?color=pastel-green&animation=chuuou_zoom&font=gothic-bold)
```

## APPROVE 時 LGTM バッジ（特別枠）

`pr-review` スキルがレビューイベント `APPROVE` を投稿するときのサマリー本文で使う。

```markdown
![LGTM](https://mojiemoji.jozo.beer/emoji/LGTM?color=pastel-pink&animation=kira&font=gothic-bold)
```

- ラベル: `LGTM`
- color: `pastel-pink`
- animation: `kira`（色相キラキラ周回）
- 用途: サマリー本文の `LGTM` 表記の代替として使用。インラインコメントでは使わない

## 重複統合時のルール

`pr-review` Phase 4-5 で複数エージェントの findings を 1 コメントに統合するとき、バッジは **重要度が高い側のもの（=そのエージェントの確定済みアニメ）** を採用する。重要度が同じ場合は、より具体的な指摘を出した側（通常は techlead）のバッジを採用する。

ローテーションは **エージェント側で finding 生成時に確定済み**なので、統合フェーズで再計算しない。「勝った side のバッジをそのまま使う」だけでよい。

## 動作確認

最終確認: 2026-05-02

| URL | status | content-type |
|---|---|---|
| `要修正` × `vivid-red` × `shuchusen` | 200 | image/gif |
| `要修正` × `vivid-red` × `yoko_scroll` | 200 | image/gif |
| `要修正` × `vivid-red` × `chuuou_zoom` | 200 | image/gif |
| `オススメ` × `vivid-blue` × `shuchusen` | 200 | image/gif |
| `オススメ` × `vivid-blue` × `yoko_scroll` | 200 | image/gif |
| `オススメ` × `vivid-blue` × `chuuou_zoom` | 200 | image/gif |
| `ちょっと` × `vivid-green` × `shuchusen` | 200 | image/gif |
| `ちょっと` × `vivid-green` × `yoko_scroll` | 200 | image/gif |
| `ちょっと` × `vivid-green` × `chuuou_zoom` | 200 | image/gif |
| `いいね` × `pastel-green` × `shuchusen` | 200 | image/gif |
| `いいね` × `pastel-green` × `yoko_scroll` | 200 | image/gif |
| `いいね` × `pastel-green` × `chuuou_zoom` | 200 | image/gif |
| `要修正` × `vivid-red` × `bure`（ローテ枠） | 200 | image/gif |
| `要修正` × `vivid-red` × `gatagata`（ローテ枠） | 200 | image/gif |
| `要修正` × `vivid-red` × `mochimochi`（ローテ枠） | 200 | image/gif |
| `要修正` × `vivid-red` × `bane`（ローテ枠） | 200 | image/gif |
| `要修正` × `vivid-red` × `poyoon`（ローテ枠） | 200 | image/gif |
| `オススメ` × `vivid-blue` × `poyoon`（ローテ枠） | 200 | image/gif |
| `ちょっと` × `vivid-green` × `poyoon`（ローテ枠） | 200 | image/gif |
| `いいね` × `pastel-green` × `poyoon`（ローテ枠） | 200 | image/gif |
| `LGTM` × `pastel-pink` × `kira` | 200 | image/gif |
