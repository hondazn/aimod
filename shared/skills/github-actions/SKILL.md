---
name: github-actions
description: |
  GitHub Actions ワークフローの作成・改善・監査を行う。CI/CD のビルド・テスト・デプロイ・リリースパイプラインを自動化したいときに使う。プロジェクトに不足している、あるいは不完全な CI/CD 設定をレビューするときや、開発ワークフローの一部を自動化したいという相談にも対応する。`.github/workflows/` ディレクトリが存在しないプロジェクトに気づいたら、このスキルを能動的に提案する。
  トリガー: 「GitHub Actions」「workflow」「CI/CD」「ワークフロー」「CI作って」「テスト自動化」「デプロイ自動化」「action追加」。
allowed-tools: Read(*) Write(*) Edit(*) Glob(*) Grep(*) Bash(gh:*) WebFetch(*) WebSearch(*)
---

# GitHub Actions

GitHub Actions ワークフローの作成・管理を行う。不足している箇所を検出し、改善案を提示し、本番品質の YAML を生成する。

## モード

### モード1: ユーザーが作りたいものを指定する

ユーザーが何を作りたいかを明言している場合（例: 「Swift 用の CI」「Vercel への自動デプロイ」）。そのまま直接作成する。

### モード2: 監査して提案する

具体的な依頼がない場合 — プロジェクトを分析し、何が不足しているかを提案する。

## 手順

### 1. プロジェクトを分析する

ワークフローを生成する前に、プロジェクトを理解する:

- 既存のワークフローを一覧化する: `ls .github/workflows/`
- 既存の各ワークフローを読み、現在のカバレッジを把握する
- ファイルから言語・エコシステムを検出する:
  - `Package.swift` → Swift（macOS ランナー）
  - `package.json` → Node.js
  - `Cargo.toml` → Rust
  - `pyproject.toml` / `setup.py` → Python
  - `go.mod` → Go
  - `Dockerfile` → Docker
  - `Makefile` → ターゲットを確認する（build, test, lint, format）
- 以下の有無を確認する: `Brewfile`, `.swift-format`, `.prettierrc`, `rustfmt.toml`, `biome.json`, `.eslintrc`, `Dangerfile`
- `git remote -v` からリポジトリの owner/name を取得する
- バージョンファイルのパターンを確認する（`version.txt`, `package.json` の version, `Cargo.toml` の version）

### 2. 不足を洗い出す

既存ワークフローを下記の全カタログと突き合わせる。不足しているワークフローを優先度別に分類する:

#### 必須（どのプロジェクトにもあるべき）

| ワークフロー | トリガー | 内容 |
|---|---|---|
| **CI (test)** | PR, main への push | ビルド + テスト実行 |
| **CI (lint)** | PR, main への push | コードフォーマット・lint チェック |

#### 推奨（多くのプロジェクトで有益）

| ワークフロー | トリガー | 内容 |
|---|---|---|
| **Release** | タグ push（`v*`） | changelog 付きの GitHub Release を作成 |
| **Auto-tag** | main への push | バージョンファイルを読み取り → git タグを作成・更新 |
| **Dependency update** | スケジュール / Dependabot | 依存関係を最新に保つ |
| **Coverage** | PR, main への push | カバレッジレポートを Codecov/Coveralls にアップロード |

#### あると良い（成熟したプロジェクト向け）

| ワークフロー | トリガー | 内容 |
|---|---|---|
| **Stale issue closer** | スケジュール（日次） | 一定期間活動のない Issue をクローズ |
| **PR labeler** | PR open/sync | 変更ファイルパスに応じて自動ラベリング |
| **Security audit** | スケジュール（週次）, PR | 既知の脆弱性を確認 |
| **Docker build** | PR, main への push | Docker イメージをビルドし、必要に応じて push |
| **Deploy** | main への push / 手動 | ホスティングプラットフォームへデプロイ |
| **Homebrew update** | Release 公開時 | Homebrew tap の formula を更新 |
| **Binary build** | Release 公開時 | 複数プラットフォーム向けにバイナリをビルド |

#### 言語別のパターン

**Swift:**

- ランナー: `macos-latest`
- ビルド: `swift build` / `swift build -c release`
- テスト: `swift test`
- lint: `swift format lint --strict --recursive Sources/ Tests/`
- 可能なら Makefile 経由でフォーマットチェック

**Node.js:**

- ランナー: `ubuntu-latest`
- インストール: `npm ci` / `pnpm install --frozen-lockfile`
- テスト: `npm test` / `pnpm test`
- lint: `npm run lint` / `pnpm lint`
- 型チェック: `tsc --noEmit`

**Rust:**

- ランナー: `ubuntu-latest`
- ビルド: `cargo build`
- テスト: `cargo test`
- lint: `cargo clippy -- -D warnings`
- フォーマット: `cargo fmt -- --check`

**Python:**

- ランナー: `ubuntu-latest`
- インストール: `pip install -e ".[dev]"` / `poetry install`
- テスト: `pytest`
- lint: `ruff check .` / `flake8`
- 型: `mypy .`

**Go:**

- ランナー: `ubuntu-latest`
- ビルド: `go build ./...`
- テスト: `go test ./...`
- lint: `golangci-lint run`

### 3. 提案を提示する

不足しているワークフローを優先度順にユーザーへ提示する:

```text
## 提案ワークフロー

### 必須（不足）
1. ✅ CI (test + lint) — 既に存在
2. ❌ Release — タグ push 時に GitHub Release を作成

### 推奨
3. ❌ Auto-tag — main への push で version.txt → git タグを同期
4. ❌ Dependabot — 週次の依存関係更新

### あると良い
5. ❌ Stale issue closer — 30 日無活動で自動クローズ
6. ❌ PR labeler — ファイルパスでラベリング

どれを作成しますか？（例: 「all」「2,3,4」「必須のものだけ」）
```

### 4. ワークフローを作成する

複数のワークフローを作成する場合は、Agent teams を使って並列で生成する — 各エージェントが 1 つのワークフローファイルを担当する。3 つ以上のワークフローを一度に作成するときに、処理を大きく高速化できる。

各ワークフローは以下を満たすこと:

- `.github/workflows/` に配置する
- 説明的なファイル名にする（例: `test.yml`, `release.yml`, `stale.yml`）
- 自明でない設定には説明コメントを付ける
- アクションのバージョンを固定する（例: `actions/checkout@v4`。`@latest` は使わない）
- 言語に適したランナーバージョンを固定する
- 最小権限の原則に従って `permissions` を使う

#### ワークフロー YAML のベストプラクティス

```yaml
name: Descriptive Name        # GitHub UI 上に表示される

on:
  push:
    branches: [main]          # main への push でトリガー
  pull_request:               # すべての PR でトリガー

permissions:
  contents: read              # 最小権限

jobs:
  job-name:
    runs-on: ubuntu-latest    # Swift/iOS の場合は macos-latest
    steps:
      - uses: actions/checkout@v4
      # ... ステップ
```

- 同一ブランチで進行中の実行をキャンセルするには `concurrency` を使う
- 可能な箇所では依存関係をキャッシュする（`actions/cache`、組み込みキャッシュ）
- ジョブは独立に保つ — 本当に順序依存でない限りチェーンしない
- 条件付き実行にはジョブレベルの `if` を使う
- 複数バージョンのテストには matrix strategy を使う

### 5. Dependabot の設定

Dependabot を提案する場合は、`.github/dependabot.yml` を作成する（ワークフローではない）:

```yaml
version: 2
updates:
  - package-ecosystem: "npm"    # または "swift", "cargo", "pip", "gomod"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 5
```

### 6. サマリ

ワークフロー作成後、以下を提示する:

- 作成・変更したファイル
- 各ワークフローの内容とトリガータイミング
- 必要なシークレットや設定（例: `CODECOV_TOKEN`、ブランチ保護）
- commit して push するよう促す

## よく使うワークフローテンプレート

### Stale issue closer

```yaml
name: Close Stale Issues
on:
  schedule:
    - cron: '0 0 * * *'
permissions:
  issues: write
  pull-requests: write
jobs:
  stale:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/stale@v9
        with:
          days-before-stale: 30
          days-before-close: 7
          stale-issue-label: 'stale'
          stale-issue-message: 'This issue has been inactive for 30 days and will be closed in 7 days.'
```

### PR labeler

```yaml
name: Label PRs
on:
  pull_request:
    types: [opened, synchronize]
permissions:
  contents: read
  pull-requests: write
jobs:
  label:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/labeler@v5
        with:
          repo-token: ${{ secrets.GITHUB_TOKEN }}
```

パス→ラベルのマッピングを記述した `.github/labeler.yml` が必要。

### Security audit（Node.js の例）

```yaml
name: Security Audit
on:
  schedule:
    - cron: '0 0 * * 1'
  pull_request:
permissions:
  contents: read
jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm audit --audit-level=high
```

## 補足

- GitHub Actions には無料枠の上限がある（プライベートリポジトリは月 2,000 分）。macOS ランナーは分を 10 倍消費する。ワークフローを提案する際はこれを念頭に置くこと。
- macOS ランナー上の Swift プロジェクトでは `swift build` と `swift test` が遅くなることがある。`.build/` ディレクトリのキャッシュを検討する。
- GitHub Actions への置き換えを提案する前に、プロジェクトが他サービス（Travis, CircleCI, GitLab CI）で既に CI を持っていないか必ず確認する。
