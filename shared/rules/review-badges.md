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

| エージェント | ベースアニメ | サブアニメ候補 | 意味付け |
|---|---|---|---|
| `meta-reviewer` | `shuchusen` | `bure`, `gatagata` | 集中線で前提に視線を奪う／時々グリッチで「前提崩れ」を表現 |
| `pdm-reviewer` | `yoko_scroll` | `mochimochi`, `bane` | ユーザー体験の流れ／弾むリズムで網羅性ハイライト |
| `techlead-reviewer` | `chuuou_zoom` | `gatagata`, `bure` | 核心ズーム／時々ガタガタしてバグの匂いを煽る |

### バリエーション発動ルール

エージェントは原則 **ベースアニメを使う**。同一 PR 内で **3 件以上 findings を出す場合に限り、1 件だけサブアニメから選んでよい**（バリエーション枠は 1 件まで）。findings が 1〜2 件の小規模 PR ではベース固定（誰の指摘かを最優先で判別させるため）。

## バッジ URL 一覧

各エージェントが finding[].body の先頭に貼る Markdown 画像参照は以下の通り。

### meta-reviewer（ベース: shuchusen）

```markdown
![要修正](https://mojiemoji.jozo.beer/emoji/要修正?color=vivid-red&animation=shuchusen&font=gothic-bold)
![オススメ](https://mojiemoji.jozo.beer/emoji/オススメ?color=vivid-blue&animation=shuchusen&font=gothic-bold)
![ちょっと](https://mojiemoji.jozo.beer/emoji/ちょっと?color=vivid-green&animation=shuchusen&font=gothic-bold)
![いいね](https://mojiemoji.jozo.beer/emoji/いいね?color=pastel-green&animation=shuchusen&font=gothic-bold)
```

サブアニメ（バリエーション枠）: `bure` / `gatagata`

### pdm-reviewer（ベース: yoko_scroll）

```markdown
![要修正](https://mojiemoji.jozo.beer/emoji/要修正?color=vivid-red&animation=yoko_scroll&font=gothic-bold)
![オススメ](https://mojiemoji.jozo.beer/emoji/オススメ?color=vivid-blue&animation=yoko_scroll&font=gothic-bold)
![ちょっと](https://mojiemoji.jozo.beer/emoji/ちょっと?color=vivid-green&animation=yoko_scroll&font=gothic-bold)
![いいね](https://mojiemoji.jozo.beer/emoji/いいね?color=pastel-green&animation=yoko_scroll&font=gothic-bold)
```

サブアニメ（バリエーション枠）: `mochimochi` / `bane`

### techlead-reviewer（ベース: chuuou_zoom）

```markdown
![要修正](https://mojiemoji.jozo.beer/emoji/要修正?color=vivid-red&animation=chuuou_zoom&font=gothic-bold)
![オススメ](https://mojiemoji.jozo.beer/emoji/オススメ?color=vivid-blue&animation=chuuou_zoom&font=gothic-bold)
![ちょっと](https://mojiemoji.jozo.beer/emoji/ちょっと?color=vivid-green&animation=chuuou_zoom&font=gothic-bold)
![いいね](https://mojiemoji.jozo.beer/emoji/いいね?color=pastel-green&animation=chuuou_zoom&font=gothic-bold)
```

サブアニメ（バリエーション枠）: `gatagata` / `bure`

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

`pr-review` Phase 4-5 で複数エージェントの findings を 1 コメントに統合するとき、バッジは **重要度が高い側のもの（=そのエージェントのアニメ）** を採用する。重要度が同じ場合は、より具体的な指摘を出した側（通常は techlead）のバッジを採用する。

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
| `要修正` × `vivid-red` × `bure`（サブ） | 200 | image/gif |
| `要修正` × `vivid-red` × `gatagata`（サブ） | 200 | image/gif |
| `要修正` × `vivid-red` × `mochimochi`（サブ） | 200 | image/gif |
| `要修正` × `vivid-red` × `bane`（サブ） | 200 | image/gif |
| `LGTM` × `pastel-pink` × `kira` | 200 | image/gif |
