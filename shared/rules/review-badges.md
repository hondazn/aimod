# レビューコメント用バッジ定義（mojiemoji 版）

このドキュメントは `pr-review` スキルの **コメント整形フェーズ（Phase 4-7）専用の参照表** です。reviewer エージェント（`meta-reviewer` / `pdm-reviewer` / `techlead-reviewer`）は構造化フィールド（`title` / `rationale` / `suggestion` / `evidence`）のみを返すため、reviewer 側からはこのドキュメントを参照しません。

URL を変更したい場合は、このドキュメントと `shared/skills/pr-review/SKILL.md` Phase 4-7 のアルゴリズム内のマッピング表の 2 箇所を更新します。

画像生成 API は <https://mojiemoji.jozo.beer/> （Slack 絵文字サイズの PNG / GIF を返す）を利用します。

## URL ビルド規則

```
https://mojiemoji.jozo.beer/emoji/{ラベル}?color={color}&animation={animation}&font=gothic-bold
```

- ラベルは生の日本語のまま埋めてよい（パスは percent-encode 不要、サーバ側で解釈される）
- ラベル内の **改行のみ `%0A` でエンコードが必要**（生の `\n` リテラルは backslash + n として描画されるため不可）
- `font` は `gothic-bold` 固定
- `color` は severity ごとに固定。`animation` はエージェント別ベース＋サブから選ぶ

## severity → ラベル / color

| severity | 日本語ラベル | color | 意味 |
|---|---|---|---|
| `must` | `要修正` | `vivid-red` | 正しく動作しない、セキュリティリスク、要件未充足 |
| `suggestion` | `オススメ` | `vivid-blue` | より良い実装が存在する |
| `nit` | `ちょっと\n気になる`（2行表示） | `vivid-green` | 些細な改善点 |
| `good` | `いいね` | `pastel-green` | 良い実装、学びになるパターン |

## エージェント → アニメーション

各エージェントは **アニメプール** を持つ。先頭はベース（エージェント識別用に固定）、2 番目以降はローテーション枠。

| エージェント | アニメプール（ローテーション順） | 意味付け |
|---|---|---|
| `meta-reviewer` | `shuchusen` → `bure` → `gatagata` → `poyoon` | 集中線で前提に視線を奪う／グリッチで前提崩れ／弾みでやわらかく |
| `pdm-reviewer` | `yoko_scroll` → `mochimochi` → `bane` → `shuchusen` → `poyoon` | ユーザー体験の流れ／弾むリズムで網羅性ハイライト／たまに集中線で焦点化 |
| `techlead-reviewer` | `chuuou_zoom` → `gatagata` → `bure` → `shuchusen` → `poyoon` | 核心ズーム／ガタガタでバグの匂いを煽る／集中線で核心へ視線誘導 |

### ローテーション規則

`pr-review` Phase 4-7 が、dedup・ソート後の `findings[]` を走査しながら **reviewer 名ごとに別カウンタ `i` (0-indexed)** を進め、`pool[i % len(pool)]` でアニメを決定する。

- `i = 0`（その reviewer の 1 件目）は必ずベース。findings が 1 件のみのときも識別性が確保される。
- `i = 1, 2, ...` は順にローテーション枠を消費。プールを使い切ったら先頭に戻る。
- severity（must/suggestion/nit/good）はアニメ選択に影響しない。色とラベルだけが severity を表す。
- reviewer エージェントは i を意識する必要が無い（出力時点ではバッジを付けない）。

## バッジ URL 一覧

`pr-review` Phase 4-7 が組み立てる Markdown 画像参照は次の形式を取る:

```text
![{ラベル}](https://mojiemoji.jozo.beer/emoji/{ラベル}?color={color}&animation={animation}&font=gothic-bold)
```

severity ごとの `{ラベル}` / `{color}` は上記「severity → ラベル / color」表、reviewer 別 `{animation}` は「エージェント → アニメーション」表に従う。例（`techlead-reviewer` の i=0、severity=must）:

```markdown
![要修正](https://mojiemoji.jozo.beer/emoji/要修正?color=vivid-red&animation=chuuou_zoom&font=gothic-bold)
![ちょっと気になる](https://mojiemoji.jozo.beer/emoji/ちょっと%0A気になる?color=vivid-green&animation=chuuou_zoom&font=gothic-bold)
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

## 重複統合とバッジ

`pr-review` Phase 4-5 で複数エージェントの findings を 1 finding に統合するとき、`reviewer` フィールドは重要度が高い側のものを採用する（重要度が同じ場合は通常 `techlead-reviewer` を採用）。

バッジ・アニメは Phase 4-7 の整形時に、勝った `reviewer` 名と「Phase 4-7 内での出現順 i」から `pool[i % len(pool)]` で決定する。reviewer 側で事前確定する必要はない。

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
| `ちょっと\n気になる` × `vivid-green` × `shuchusen` | 200 | image/gif |
| `ちょっと\n気になる` × `vivid-green` × `yoko_scroll` | 200 | image/gif |
| `ちょっと\n気になる` × `vivid-green` × `chuuou_zoom` | 200 | image/gif |
| `いいね` × `pastel-green` × `shuchusen` | 200 | image/gif |
| `いいね` × `pastel-green` × `yoko_scroll` | 200 | image/gif |
| `いいね` × `pastel-green` × `chuuou_zoom` | 200 | image/gif |
| `要修正` × `vivid-red` × `bure`（ローテ枠） | 200 | image/gif |
| `要修正` × `vivid-red` × `gatagata`（ローテ枠） | 200 | image/gif |
| `要修正` × `vivid-red` × `mochimochi`（ローテ枠） | 200 | image/gif |
| `要修正` × `vivid-red` × `bane`（ローテ枠） | 200 | image/gif |
| `要修正` × `vivid-red` × `poyoon`（ローテ枠） | 200 | image/gif |
| `オススメ` × `vivid-blue` × `poyoon`（ローテ枠） | 200 | image/gif |
| `ちょっと\n気になる` × `vivid-green` × `poyoon`（ローテ枠） | 200 | image/gif |
| `いいね` × `pastel-green` × `poyoon`（ローテ枠） | 200 | image/gif |
| `LGTM` × `pastel-pink` × `kira` | 200 | image/gif |
