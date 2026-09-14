# feature map の実例

`verify-<app>/features/` の形。対象アプリに合わせて語とコマンドを差し替える。ここに置くのは粒度の見本で、そのままコピーする雛形ではない。実在しないアプリの話を生成物に残さない。

## README.md（索引）

索引は前提と運転の約束を持ち、機能ファイルは手順だけを持つ。同じ注意を各機能ファイルに繰り返さない。

```markdown
# <app> 検証マップ

このディレクトリは <app> のユーザー向け振る舞いを検証する正本である。運転の前に索引を読み、
対象の機能ファイルを手順として使う。

## 前提

- 使い捨てのデータディレクトリで起動する（`<app>_DATA_DIR=/tmp/<app>-verify-$RUN_ID`）。
  並行実行が状態を共有しないため。
- シードを入れる（例: `<seed command>`）。
- この検証実行が起動していないインスタンスを運転しない。

## 運転の約束

- 各手順は、その前提に別段の記載がない限り基準状態から始める。
- CSS セレクタや DOM の位置より、ARIA のロールとアクセシブル名を優先する。
- コマンドは逐語で実行する。引用符とフラグを変えない。
- 変更を加えたらシード状態へ戻す。Cleanup で証拠を消さない。

## 証拠と skip の報告

- 操作と、その結果の状態を撮る。最後の画面だけでは足りない。
- UI の証拠は ARIA スナップショットと、アプリの素性が写ったスクリーンショット。
- CLI の証拠はコマンド、stdout、stderr、exit code。
- 変更の証拠は、保存された値を別の読み取り専用の見方で確かめたもの。
- 到達できなかった経路は、試したコマンドと満たせなかった前提を書く。
- 別の経路を通ったことをもって、skip した入口を verified と報告しない。

## 機能

- [<機能A>](./<feature-a>.md) — 一言で何を覆うか
- [<機能B>](./<feature-b>.md) — 一言で何を覆うか
```

## 機能ファイル

H1 の下にユーザーから見た振る舞いを1段落。続いて H2 を**4つだけ**、この順で置く。

1. `## Sub-features` — 短い ID と1行の対応
2. `## How to get to it (user POV)` — ユーザーの入口を全て
3. `## Driving it with <harness>` — 前提と、操作・正確なコマンド・観測できる結果の組
4. `## Gotchas` — 検証を無駄にするか無効にする罠

実装の詳細をマップに書かない。書くのはユーザーの経路、安定したハンドル、必要な状態、コマンド、観測できる証拠だけ。

```markdown
# ノートを検索する

検索は、タイトルまたは本文でノートを探し、一致したノートを開き、一致なしと検索不能を区別する。

## Sub-features

- `search-open` 対応する各入口から検索を開く。
- `search-match` タイトルと本文の一致を、ノートのデータを変えずに返す。
- `search-empty` 一致の無いクエリに完全な空状態を出す。
- `search-clear` クエリを消し、最近のノートの表示に戻す。

## How to get to it (user POV)

- ツールバーの `Search` ボタンを選ぶ。
- 編集可能なフィールドの外にフォーカスがあるとき `/` を押す。
- 端末で `notes search <query>` を実行する。

## Driving it with control-notes

前提:

- Notes が `http://127.0.0.1:4173` で healthy。
- 使い捨てデータディレクトリに `Quarterly plan`（本文 `Draft budget`）がある。
- `control-notes doctor` が期待する URL とデータディレクトリを報告する。

- **ツールバーから。** `Search` を選ぶ。`control-notes browser click --role button --name "Search"`。
  `Search notes` という名前のダイアログが出て、その searchbox にフォーカスがある。
- **キーボードから。** ダイアログを閉じ、ページにフォーカスして `/` を押す。
  `control-notes browser press --key "/"`。同じダイアログが出て、ページにスラッシュが入らない。
- **一致。** `quarterly` を入れる。`control-notes browser fill --role searchbox --name "Search notes" --value "quarterly"`。
  `Search results` に `Quarterly plan` があり、`Grocery list` は無い。
- **空状態。** 検索を開き直し `volcano` を入れる。`No matching notes` という名前の status が検索完了後に出る。
- **証拠。** 一致が並んだ状態を撮る。`control-notes browser snapshot --aria --path artifacts/search/results.aria.txt`
  と `control-notes browser screenshot --path artifacts/search/results.png`。
  どちらにも Notes、クエリ、`Quarterly plan` が写る。

## Gotchas

- エディタか searchbox にフォーカスがあるとき `/` を押すと、検索ではなく文字が入る。
- 結果は短い debounce の後に更新される。固定の sleep ではなく結果リストか空状態を待つ。
- アーカイブ済みのノートは、ユーザーが `Include archived` を有効にしない限り除外される。
- CLI の既定出力は人間向け。安定した assert には `--format json` を使う。
```

## よくある崩れ

| 崩れ | 直し方 |
|---|---|
| 「開く」だけで「結果がどうなるか」が無い | 各操作に観測できる結果を対にする |
| 入口を1つだけ書いている | ルート・キーボード・コマンドを洗い、ユーザーの入口を全て挙げる |
| 実装の関数名や内部状態がマップにある | ユーザーの経路、安定したハンドル、コマンド、観測できる証拠に戻す |
| `Gotchas` が空 | 一度運転すると必ず詰まる箇所がある。debounce、フォーカス、既定の出力形式、除外条件を探す |
| 前提が README と機能ファイルに二重に書かれている | 共通の前提は README に1つ置き、機能固有の前提だけ機能ファイルに残す |
