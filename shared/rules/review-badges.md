# レビューコメント用バッジ定義（mojiemoji 版）

このドキュメントは `pr-review` スキルの **コメント整形フェーズ（Phase 4-7）専用の参照表** です。reviewer エージェント（`meta-reviewer` / `pdm-reviewer` / `techlead-reviewer`）は構造化フィールド（`title` / `rationale` / `suggestion` / `evidence` / **`badge_label`**）を返し、Phase 4-7 がそれらを mojiemoji-github スキル経由でバッジ Markdown に組み立てます。

画像生成 API は <https://mojiemoji.jozo.beer/>（Slack 絵文字サイズの PNG / GIF を返す）を利用します。

## mojiemoji-github スキルへの委譲（必須）

実際の URL 構築は **`mojiemoji-github` スキル**（プラグイン ID: `mojiemoji-github:mojiemoji-github`）のヘルパースクリプト `scripts/mojiemoji_markdown.rb` 経由で行います。pr-review 側でハードコード URL は使いません。

ヘルパー経由にする理由:

- `background=transparent` が常時付与され、ダークモード GitHub での不可視事故（2026-05-12 triage-review batch の前例）を構造的に防止
- `animation` / `font` / `color` のキャノニカル値検証が mojiemoji-github 側で集約管理される
- 将来 mojiemoji.jozo.beer のクエリ仕様が変わっても、pr-review を触らずヘルパー側更新で吸収できる

このドキュメントが定義するのは **「pr-review レビュー識別性」のための severity → color / reviewer → animation の決定的マッピングと、`badge_label` の文字制約・フォールバック規則** であり、URL 文字列そのものではありません。

## バッジの構成要素

インラインバッジ（finding ごと）は次の 3 要素から成る:

| 要素 | 決定主体 | 役割 |
|---|---|---|
| **ラベル**（`badge_label`） | reviewer エージェント | この finding が何の話かを端的に表す |
| **color** | severity から決定的に決まる | severity を視認させる SSOT |
| **animation** | reviewer 名のプール + ローテーション | どの reviewer が指摘したかの識別 |

severity の伝達は **色**、内容の伝達は **ラベル** に分離することで、ラベルが揺れても重要度の視認性は崩れない設計です。

## badge_label の制約（mojiemoji 仕様準拠）

reviewer が出力する `badge_label` は以下の制約に従う:

- **合計 15 文字以内**（日本語）
- **1 行あたり 5 文字以内**
- **改行（`\n`）は 2 回まで**（最大 3 行表示）
- 文字種は **日本語**（漢字・ひらがな・カタカナ）を主とする。記号・英数字は単発でなら混在可（例: `N+1`）だが、語の中心は日本語に置く
- 改行は `\n` リテラルで表現（ヘルパースクリプトが `%0A` にエンコードする）

例:

| ラベル | 構造 |
|---|---|
| `根本原因外` | 5 文字 × 1 行 |
| `AC漏れ` | 4 文字 × 1 行 |
| `ちょっと\n気になる` | 4 文字 + 5 文字 = 2 行 |
| `見事な\n抽象化` | 3 文字 + 4 文字 = 2 行 |
| `テスト\nが薄い` | 3 文字 + 4 文字 = 2 行 |
| `N+1\n警戒` | 3 文字 + 2 文字 = 2 行 |

### バリデーションとフォールバック

Phase 4-7 は `badge_label` が以下のいずれかに該当する場合、severity ごとの **フォールバックラベル** へ差し替える:

- 空文字 / null / 未指定
- 合計 15 文字を超過
- 1 行あたり 5 文字を超過
- 改行が 3 回以上
- 制約外の文字種が支配的（記号・英数字のみで構成される等）

フォールバックラベル:

| severity | フォールバックラベル |
|---|---|
| `must` | `要修正` |
| `suggestion` | `オススメ` |
| `nit` | `ちょっと\n気になる` |
| `good` | `いいね` |

## severity → color

| severity | color | 意味 |
|---|---|---|
| `must` | `vivid-red` | 正しく動作しない、セキュリティリスク、要件未充足 |
| `suggestion` | `vivid-blue` | より良い実装が存在する |
| `nit` | `vivid-green` | 些細な改善点 |
| `good` | `pastel-green` | 良い実装、学びになるパターン |

色は severity から決定的に決まる。reviewer は color を出力しない（Phase 4-7 で付与される）。

## reviewer → animation

各 reviewer は **アニメプール** を持つ。先頭はベース（reviewer 識別用に固定）、2 番目以降はローテーション枠。

| reviewer | アニメプール（ローテーション順） | 意味付け |
|---|---|---|
| `meta-reviewer` | `shuchusen` → `bure` → `gatagata` → `poyoon` | 集中線で前提に視線を奪う／グリッチで前提崩れ／弾みでやわらかく |
| `pdm-reviewer` | `yoko_scroll` → `mochimochi` → `bane` → `shuchusen` → `poyoon` | ユーザー体験の流れ／弾むリズムで網羅性ハイライト／たまに集中線で焦点化 |
| `techlead-reviewer` | `chuuou_zoom` → `gatagata` → `bure` → `shuchusen` → `poyoon` | 核心ズーム／ガタガタでバグの匂いを煽る／集中線で核心へ視線誘導 |

### ローテーション規則

`pr-review` Phase 4-7 が、dedup・ソート後の `findings[]` を走査しながら **reviewer 名ごとに別カウンタ `i` (0-indexed)** を進め、`pool[i % len(pool)]` でアニメを決定する。

- `i = 0`（その reviewer の 1 件目）は必ずベース。findings が 1 件のみのときも識別性が確保される。
- `i = 1, 2, ...` は順にローテーション枠を消費。プールを使い切ったら先頭に戻る。
- severity と `badge_label` はアニメ選択に影響しない。
- reviewer エージェントは i を意識する必要が無い（出力時点ではバッジを付けない）。

## URL ビルド規則

ヘルパースクリプトに以下の引数を渡して生成する:

```bash
ruby "$HELPER" --text "{badge_label}" \
  --color "{color}" --animation "{animation}" --font gothic-bold
```

実体としては概ね次のような URL を出力する（`background=transparent` などはヘルパーが自動付与）:

```
https://mojiemoji.jozo.beer/emoji/{badge_label}?color={color}&animation={animation}&font=gothic-bold&background=transparent
```

- ラベルは生の日本語のまま `--text` に渡せる（ヘルパーがエンコードを担当）
- ラベル内の改行は `--text` に literal `\n` を渡せば `%0A` にエンコードされる
- `font` は `gothic-bold` 固定
- `color` は severity ごとに固定。`animation` は reviewer 別ベース＋サブから選ぶ

## バッジ生成例

`pr-review` Phase 4-7 はヘルパースクリプト経由で Markdown 画像参照を生成する。

通常ケース（reviewer が出した `badge_label` を採用、`techlead-reviewer` の i=0、severity=good）:

```bash
ruby "$HELPER" --text $'見事な\n抽象化' \
  --color pastel-green --animation chuuou_zoom --font gothic-bold
# 出力: ![見事な抽象化](https://mojiemoji.jozo.beer/emoji/見事な%0A抽象化?color=pastel-green&animation=chuuou_zoom&font=gothic-bold&background=transparent)
```

フォールバックケース（`badge_label` が空 / 制約違反だった場合、severity=must）:

```bash
ruby "$HELPER" --text "要修正" \
  --color vivid-red --animation chuuou_zoom --font gothic-bold
# 出力: ![要修正](https://mojiemoji.jozo.beer/emoji/要修正?color=vivid-red&animation=chuuou_zoom&font=gothic-bold&background=transparent)
```

## APPROVE 時 LGTM バッジ（特別枠）

`pr-review` スキルがレビューイベント `APPROVE` を投稿するときのサマリー本文で使う **「装飾バリエーション枠」**。

- **ラベル**: `LGTM` 固定
- **color / animation / font**: 都度バリエーション（**`mojiemoji-github` の loud デフォルトに委譲**）

固定ラベル × 動的装飾とすることで、APPROVE のたびに見た目が変わる「祝祭感」を出す。reviewer 別アニメプールも severity → color マッピングも適用しない（finding ではなくサマリー装飾だから）。

実装上は Phase 5-3 のサマリー本文整形と同じく `mojiemoji-selector` サブエージェントを呼ぶ。コントラクトは:

```text
SURFACE: review-summary-body
MODE:    lgtm-badge
TONE:    loud
PHRASES:
- LGTM — マージ可の宣言
CONSTRAINTS:
- Every URL MUST include &background=transparent
- ラベルは "LGTM" 固定
- 装飾（color / animation / font）はバリエーション最大化（直近の APPROVE と被らない選定が望ましい）
```

`COMMENT` / `REQUEST_CHANGES` のサマリーには LGTM バッジは付けない（マージ判断と矛盾するため）。

## 重複統合とバッジ

`pr-review` Phase 4-5 で複数エージェントの findings を 1 finding に統合するとき、`reviewer` フィールドと `badge_label` は Phase 4-5 のルール 2 に従って決定される（重要度が高い側、同点時は `techlead-reviewer` 優先）。詳細は `shared/skills/pr-review/SKILL.md` Phase 4-5 を参照。

color・animation は Phase 4-7 の整形時に、勝った `reviewer` 名と severity と「Phase 4-7 内での出現順 i」から決定する。reviewer 側で事前確定する必要はない。

## 動作確認

最終確認: 2026-05-23（`badge_label` 動的化に伴う簡素化）

`badge_label` は可変なので個別の URL 検証はしない（ヘルパーがエンコードと必須パラメータを担保する）。color × animation の代表的組合せが 200 / image/gif を返すことだけ確認する。

| color | animation | status | content-type |
|---|---|---|---|
| `vivid-red` | `shuchusen` | 200 | image/gif |
| `vivid-red` | `chuuou_zoom` | 200 | image/gif |
| `vivid-red` | `yoko_scroll` | 200 | image/gif |
| `vivid-blue` | `shuchusen` | 200 | image/gif |
| `vivid-blue` | `bane` | 200 | image/gif |
| `vivid-green` | `gatagata` | 200 | image/gif |
| `vivid-green` | `mochimochi` | 200 | image/gif |
| `pastel-green` | `poyoon` | 200 | image/gif |

LGTM バッジは `mojiemoji-github` 委譲なのでサーバ側で都度生成される。サンプル動作確認:

| ラベル | color | animation | font | status |
|---|---|---|---|---|
| `LGTM` | `orange` | `kira` | `gothic-bold` | 200 |
| `LGTM` | `vivid-pink` | `nijuumaru` | `maru` | 200 |
