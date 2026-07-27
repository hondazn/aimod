---
name: write-release-notes
description: |
  まだ本文（ノート）が書かれていない GitHub リリースに対して、リリースノートを生成する。タグ間のコミットを解析し、プロジェクトの主要言語でノートを書き起こす。
  トリガー: 「リリースノート」「release notes」「リリースのノートを書いて」「リリースに説明がない」、あるいは GitHub のリリースに本文が無いことに気づいたとき。「changelog」「更新履歴」、または CI で `--generate-notes` を使ってリリースを作成したものの内容を厚くしたい場合にも使用する。
argument-hint: "[tag1 tag2 ...] (任意 — 省略すると全タグをスキャン)"
allowed-tools: Read(*) Write(*) Bash(gh:*) Bash(git:*)
---

# リリースノート作成

GitHub リリース向けに、高品質で人間が読みやすいリリースノートを生成する。

## 入力

任意: 1 つ以上のタグ名（例: `v2.3.0 v2.4.0`）。

- **タグ指定あり**: 指定されたタグのみリリースノートを書く。
- **タグ指定なし**: 全タグをスキャンし、リリースノートが無いものを抽出してユーザーに一覧提示し、確認を取ってから進める。

## 手順

### 1. プロジェクトの言語を判定する

リリースノートをどの自然言語で書くかを決める:

1. CLAUDE.md に言語のヒントがないか確認する
2. README.md を確認する — 主に日本語なら日本語、英語なら英語を使う
3. 直近のコミットメッセージの言語パターンを確認する
4. 判別できない場合は英語をデフォルトとする

### 2. ノートが必要なリリースを特定する

全タグを列挙し、各タグに本文付きの GitHub Release が存在するか確認する:

```bash
# 全タグを列挙
git tag --sort=-v:refname

# リリースが存在し、ノートを持っているか確認する（タグごと）
gh release view $TAG --json body --jq '.body' 2>/dev/null
```

以下のいずれかに該当するリリースはノートが必要:

- タグに対応する GitHub Release が一切存在しない
- リリースは存在するが `.body` が空、または自動生成された内容のみ

**引数でタグが指定されている場合**は、このスキャンを省略し、指定タグを直接対象にする。

**タグが指定されていない場合**は、ノートが必要なタグの一覧を提示して次のように尋ねる:
「リリースノートのない N 個のタグが見つかりました: [一覧]。すべてに対してノートを書きますか？」
確認が取れるまで進めない。

### 3. コミット履歴を収集する

ノートが必要な各リリースについて、直前のタグとの間のコミットを取得する:

```bash
# 順序付きでタグを取得
TAGS=($(git tag --sort=-v:refname))

# 直前のタグを見つける
# TAG が TAGS[i] のとき、直前は TAGS[i+1]

# コミットを取得
git log ${PREV_TAG}..${TAG} --format="%h %s" --no-merges
```

直前のタグが存在しない場合（最初のリリース）は `git log $TAG --format="%h %s" --no-merges` を使う。

コミットに含まれる PR 参照も確認し、リンクできるようにする。

### 4. リリースノートを書く

全リリースで書式を統一するため、テンプレートに厳密に従う。各コミットを以下のセクションのいずれかに分類する。該当するエントリが無いセクションは省略する。

**ルール:**

- 具体的に書く: 「`config edit` コマンドを追加し、$EDITOR で設定を開けるようにした」＞「config edit を追加」
- 可能な場合は PR / Issue を参照する（`(#123)`）
- バージョンバンプ、マージコミット、書式のみの変更はスキップする
- 複雑な機能はサブ項目で補足する（例: サブコマンドの列挙）

#### テンプレート（英語）

```markdown
## What's Changed

### New
- {description} ({#PR})

### Improved
- {description} ({#PR})

### Fixed
- {description} ({#PR})

### Internal
- {description} ({#PR})
```

#### テンプレート（日本語）

```markdown
## 変更内容

### 新機能
- {description} ({#PR})

### 改善
- {description} ({#PR})

### 修正
- {description} ({#PR})

### 内部変更
- {description} ({#PR})
```

#### 出力例

```markdown
## What's Changed

### New
- Add config subcommands: `template`, `init`, `edit`, `open` (#42)
  - `app config template` — print default config to stdout
  - `app config init` — generate config file
  - `app config edit` — open config in $EDITOR
  - `app config open` — open config file in GUI app

### Improved
- Unify data store with generics, move cache to Repository (#38)

### Internal
- Add linter/formatter with CI integration (#40)
```

### 5. リリースを作成または更新する

生成したノートを `Write` ツールで `/tmp/release-notes-$TAG.md` に書き出してから、
そのファイルを `--notes-file` に渡す（複数行・マークダウンを安全に渡すため）。

タグに対応する GitHub Release が存在しない場合:

```bash
gh release create $TAG --title "$TAG" --notes-file /tmp/release-notes-$TAG.md
```

リリースは存在するがノートが空、または自動生成のみの場合:

```bash
gh release edit $TAG --notes-file /tmp/release-notes-$TAG.md
```

### 6. 報告する

何を、どのリリースに書いたかをユーザーに示す。複数のリリースを更新した場合は、ハイライトとともにすべてを列挙する。
