---
name: git-commit
description: gitの差分を分析し、Conventional Commitsに従ったコミットメッセージを生成してコミットする。「コミットして」「変更をまとめて」「git commit」「差分をコミット」「変更を保存」などのリクエストで使用する。ステージング済み・未ステージングの変更を論理的な粒度で分割し、適切なコミットメッセージを自動生成する。
allowed-tools:
  - Bash(git status:*)
  - Bash(git diff:*)
  - Bash(git log:*)
  - Bash(git add:*)
  - Bash(git commit:*)
  - Bash(git push:*)
  - Bash(git stash:*)
  - Bash(git restore:*)
---

# Git Commit - Conventional Commits準拠のコミット作成

変更内容を分析し、論理的に適切な粒度でConventional Commitsに従ったコミットを作成する。

## ワークフロー

### Step 1: 現状把握

以下を並列で実行して現在の状態を把握する:

- `git status` で変更ファイルの一覧を取得
- `git diff` と `git diff --staged` でステージ済み・未ステージの差分を確認
- `git log --oneline -10` で直近のコミットスタイルを確認

### Step 2: 変更の分析とグループ化

差分を読み、変更を**論理的な単位**にグループ化する。1つのコミットに含めるべき変更の判断基準:

- **同じ目的の変更**: 1つの機能追加、1つのバグ修正、1つのリファクタリングに関連する変更はまとめる
- **同じスコープの変更**: 同一のモジュール・コンポーネントに対する関連変更はまとめる
- **異なる目的は分割**: 機能追加とバグ修正が混在する場合は別々のコミットにする
- **設定変更は独立**: 設定ファイルの変更が機能変更と無関係なら別コミットにする

1つの変更しかない場合は素直に1コミットでよい。無理に分割しない。

### Step 3: コミットメッセージの作成

Conventional Commitsの形式に従う:

```
<type>(<scope>): <description>

[本文（任意）]
```

#### type一覧

| type | 用途 |
|------|------|
| `feat` | 新機能の追加 |
| `fix` | バグ修正 |
| `docs` | ドキュメントのみの変更 |
| `style` | コードの意味に影響しない変更（空白、フォーマット、セミコロン等） |
| `refactor` | バグ修正でも機能追加でもないコード変更 |
| `perf` | パフォーマンス改善 |
| `test` | テストの追加・修正 |
| `build` | ビルドシステムや外部依存関係の変更 |
| `ci` | CI設定ファイルやスクリプトの変更 |
| `chore` | その他の変更（ソースやテストを含まない） |

#### scope

変更対象のモジュール・コンポーネント名を括弧内に記載する。明確なスコープがある場合のみ付与する。

#### description

- 英語で記述する（リポジトリの既存コミットが日本語の場合はそれに合わせる）
- 命令形で書く（"add", "fix", "update" など、"added", "adds" ではない）
- 先頭は小文字
- 末尾にピリオドを付けない
- 変更の「何を」ではなく「なぜ」を意識する

### Step 4: ステージングとコミット

```bash
# 対象ファイルを個別にステージング（git add -A は使わない）
git add <file1> <file2>

# コミット実行
git commit -m "<type>(<scope>): <description>"
```

複数コミットに分割する場合は、依存関係を考慮して適切な順序でコミットする。

## 例

**例1: 単一の機能追加**

変更: 認証モジュールにJWTトークンのバリデーションを追加

```
feat(auth): add JWT token validation
```

**例2: 複数の変更を分割**

変更: ESLintの設定変更 + 新しいAPIエンドポイント追加

```
# コミット1
chore(eslint): update rules for stricter type checking

# コミット2
feat(api): add user profile endpoint
```

**例3: スコープなしの変更**

変更: READMEにインストール手順を追加

```
docs: add installation instructions to README
```

## 注意事項

- `.env`、`credentials`、秘密鍵などの機密ファイルは絶対にコミットしない。検出した場合はユーザーに警告する
- ユーザーが明示的にpushを要求しない限り、pushは行わない
- 既存のコミットの`--amend`はユーザーの明示的な指示がない限り行わない
- コミット前にユーザーにメッセージと対象ファイルの確認を取る
