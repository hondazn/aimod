# Cursor cli-config のキー単位マージ

- 作成日: 2026-08-21
- 関連: `cursor/cli-config.json`, `scripts/manage-cursor-cli-config.sh`, `scripts/deploy.sh`, `scripts/undeploy.sh`, `scripts/manage-codex-statusline.sh`

## 背景

Claude は `settings.json` を symlink で配れる。中身が共有設定だけだから。
Cursor の `~/.cursor/cli-config.json` は同じファイルに共有設定と `authInfo`・選択中モデル・キャッシュが混ざる。CLI はモデル切替のたびに書き戻す。丸ごと symlink すると認証が git に入るか、aimod が毎セッション汚れる。

そのため `deploy.sh` は `cursor/statusline.sh` だけリンクし、`statusLine` の有効化は手動だった。新しい環境ではスクリプトだけ置かれて表示されない。

## ゴール

- 共有してよいキーを aimod 正本から `./scripts/deploy.sh` でどの環境にも反映する
- `authInfo` / モデル状態 / キャッシュは読まない・書かない
- Codex の `tui.status_line` マージと同じ所有権モデルにする

## ノンゴール

- `~/.cursor/cli-config.json` の symlink 化
- 正本に無いキーの同期（CLI が後から足したネストフィールドの保持）
- Cursor 本体が `cli-config.json` を欠落キー付きで初回生成したときの挙動の保証

## 決定

| 項目 | 決定 |
|---|---|
| 正本 | `cursor/cli-config.json`（マージしてよいキーだけ） |
| live | `~/.cursor/cli-config.json`（実体。symlink にしない） |
| 許可リスト | 正本のトップレベルキー |
| マージ | 許可キーをトップレベルごと置換。他キーは触らない |
| 拒否リスト | 正本に混入していたら apply を失敗させる |
| JSON | `jq`（`cursor/statusline.sh` が既に依存） |
| undeploy | 値が正本と完全一致するキーだけ削除 |

拒否リスト: `authInfo`, `model`, `selectedModel`, `modelParameters`, `hasChangedDefaultModel`, `modelSelectionHistory`, `privacyCache`, `autoReviewAvailabilityCache`, `serverConfigCache`, `showSandboxIntro`, `conversationClassificationScoredConversations`, `version`, `runEverythingSettingsPromptStreak`

初期の正本は、このマシンの live から許可キーだけを写す。

## 動作

`scripts/manage-cursor-cli-config.sh apply|remove CONFIG_PATH MANAGED_PATH`

Codex の `manage-codex-statusline.sh` と同じ呼び出し形。`deploy.sh` / `undeploy.sh` から呼ぶ。

**apply**

1. 正本が JSON object でなければ失敗
2. 正本が拒否キーを含めば失敗（黙ってスキップしない）
3. live が無ければ `{}` から始める
4. live が不正 JSON / object 以外なら何も書かず失敗
5. live が symlink なら解決先へ書く。ダングリングは拒否
6. 解決先が aimod リポジトリ内なら拒否（正本へ auth が書き戻るのを防ぐ）
7. 正本の各キーを live へ代入（既存キーは位置維持、新規は末尾）
8. 一時ファイルへ `jq` 出力 → 差分が無ければ mtime を保つ → `mv`

**remove**

1. live が無ければ何もしない
2. 値が正本と `==` のキーだけ `del`
3. ユーザーが後から変えたキーは残す
4. ファイル自体は消さない（`{}` になっても残す）

## テスト

`tests/cursor-cli-config-test.sh`（`tests/codex-statusline-config-test.sh` と同じ形）

- apply が許可キーを書き、他キーを残す
- 再 apply でバイト列が変わらない
- live 欠落時は正本だけで作成する
- 不正 JSON では失敗し、元ファイルを残す
- 正本に拒否キーがあれば失敗する
- 解決先が aimod 内なら失敗する
- remove は一致キーだけ消し、不一致キーは残す
- `HOME=` を付けた `deploy.sh` / `undeploy.sh` でも同じ

## ドキュメント

README / CLAUDE.md の「`cli-config.json` は管理しない」を、キー単位マージに書き換える。
`deploy.sh` のリンク処理は bash のまま。このヘルパーだけ `jq` を必要とする（statusline と同じ）。
