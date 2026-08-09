---
name: readme-badges
description: |
  README ファイルに shields.io バッジを追加・整理・メンテナンスする。関連するバッジを自動検出し、重複を避け、一貫した順序で整える。
  トリガー: 「バッジ」「shields」「badges」「README バッジ」「バッジ追加」「add badge」「バッジ整理」、あるいは README の見栄えをステータス表示で改善したいとき。バッジが無い・古い README をレビューしている際にも先回りして使用する。
allowed-tools: Read(*) Write(*) Edit(*) Glob(*) Grep(*) WebFetch(*) WebSearch(*)
---

# README Badges

README ファイルに shields.io バッジを追加する。関連するものを検出し、重複を避け、整理された状態に保つ。

## 手順

### 1. プロジェクトの分析

バッジを提案する前に、プロジェクトを理解する:

- `README.md` を読んで既存のバッジを確認する
- `Package.swift`, `package.json`, `Cargo.toml`, `pyproject.toml` などで言語・プラットフォームを確認する
- `.github/workflows/` で CI ワークフローを確認する
- `LICENSE` でライセンス種別を確認する
- 各種連携を確認する: Codecov, CodeRabbit, Dependabot など
- `git remote -v` でリポジトリのオーナー/リポジトリ名を取得する

### 2. 適用可能なバッジの判定

以下のカテゴリから順に選択する。実際に関連するバッジのみを提案すること:

#### Tier 1 — 必須（どのプロジェクトにもあるべき）

| バッジ | 条件 | URL パターン |
|---|---|---|
| Version / Tag | 常に | `https://img.shields.io/github/v/tag/{owner}/{repo}?label=version` |
| Platform | 言語依存 | 静的バッジ、例: `macOS-14+-blue`, `node-18+-green` |
| Language | 常に | バージョン付きの静的バッジ、例: `Swift-6.0-orange` |
| License | LICENSE ファイルがある | `https://img.shields.io/github/license/{owner}/{repo}` |

#### Tier 2 — 品質（CI/カバレッジが整備されている場合）

| バッジ | 条件 | URL パターン |
|---|---|---|
| CI Status | GitHub Actions がある | `https://img.shields.io/github/actions/workflow/status/{owner}/{repo}/{workflow}?label=tests` |
| Coverage | Codecov 設定済み | `https://codecov.io/gh/{owner}/{repo}/graph/badge.svg`（`<a>` リンクで囲む） |
| Code Review | CodeRabbit 設定済み | `https://img.shields.io/coderabbit/prs/github/{owner}/{repo}?utm_source=oss&...` |

#### Tier 3 — コミュニティ（成熟したプロジェクト）

| バッジ | 条件 | URL パターン |
|---|---|---|
| Stars | 公開リポジトリ | `https://img.shields.io/github/stars/{owner}/{repo}` |
| Downloads | Homebrew/npm/PyPI | プロバイダ固有 |
| Contributors | 複数のコントリビューター | `https://img.shields.io/github/contributors/{owner}/{repo}` |
| Last Commit | 活動状況を示す | `https://img.shields.io/github/last-commit/{owner}/{repo}` |
| Open Issues | エンゲージメントを示す | `https://img.shields.io/github/issues/{owner}/{repo}` |

#### Tier 4 — おまけ（状況に応じて）

| バッジ | 条件 | URL パターン |
|---|---|---|
| Open Source ❤ | OSS プロジェクト | 静的バッジ: `open%20source-❤-red` |
| Homebrew | tap がある | `https://img.shields.io/homebrew/v/{formula}` |
| Swift Package Index | Swift パッケージ | SPI バッジ |
| Docker | Dockerfile がある | `https://img.shields.io/docker/v/{owner}/{repo}` |

### 3. 重複チェック

バッジを追加する前に、README の既存バッジを確認する:

- 既存の `<img src="...shields.io..."` および `![...](...shields.io...` パターンを解析する
- URL からバッジの種別を抽出する（例: `/github/license/`, `/github/actions/`）
- 既に存在するバッジはスキップする
- 既存バッジの URL 形式が古い場合は、更新を提案する

### 4. バッジ順序の整理

バッジは以下の一貫した順序（左から右）に従う:

1. Version / リリースタグ
2. Platform（macOS, iOS, Linux など）
3. Language（Swift, TypeScript, Python など）
4. License
5. CI / ビルドステータス
6. Coverage
7. Code Review（CodeRabbit, Codacy など）
8. コミュニティ（Stars, Downloads, Contributors）
9. その他（Open Source, カスタム）

並び替える際は、ユーザーが追加したカスタムバッジは保持し、末尾に移動するだけにとどめる。

### 5. 出力フォーマット

バッジを中央寄せで表示するため、常に HTML フォーマットを使う:

```html
<p align="center">
  <img src="..." alt="...">
  <img src="..." alt="...">
  <a href="https://..."><img src="..." alt="..."></a>
</p>
```

ルール:

- ダッシュボードにリンクするバッジ（Codecov, CodeRabbit, CI 実行結果）には `<a>` ラッパーを使う
- 静的な情報バッジ（version, platform, license）には素の `<img>` を使う
- ソース上の可読性のため、各バッジを 1 行ずつ記述する
- 必ず説明的な `alt` テキストを含める

### 6. ユーザーへの提示

ユーザーに以下を示す:

1. 追加するバッジ（その理由とともに）
2. 保持/並び替えした既存バッジ
3. 最終的な HTML ブロック

変更はユーザーの確認後にのみ適用する。ユーザーが具体的な指定なしに「バッジを追加して」とだけ言った場合は、Tier 1 と適用可能な Tier 2 バッジを提案する。

### 7. デモアセットの提案（任意）

バッジはメタデータを示すものだが、ツールが「実際に動いている」短いデモがあると README の訴求力が増す。デモ GIF/PNG は任意で別途生成し（スクリプト化した CLI/TUI のシーンを録画する手段があれば活用する）、（ヒーロー画像などと並べて）`assets/` 配下にコミットし、バッジ付近に相対 markdown パスで埋め込むとよい。自動レンダリングは、デモするコマンドが明らかに安全（`--help` / `--version` / `--dry-run` / 明示的に読み取り専用の例）である場合に限り、ユーザー自身のリポジトリでのみ行う。変更を伴う・ネットワーク通信を行う・認証が必要なコマンド、組織や他人のリポジトリ、シークレットが画面に映り込む可能性がある場合は、シーンを提案して先に確認を取る。

## バッジスタイル

一貫性のため、デフォルトの `flat` スタイルを使う。同一 README 内でスタイルを混在させない。既存バッジが別のスタイル（例: `for-the-badge`）を使っている場合は、新規バッジもそのスタイルに合わせる。

## 例

**最小構成（新規プロジェクト）:**

```html
<p align="center">
  <img src="https://img.shields.io/github/v/tag/owner/repo?label=version" alt="Version">
  <img src="https://img.shields.io/badge/Swift-6.0-orange" alt="Swift">
  <img src="https://img.shields.io/github/license/owner/repo" alt="License">
</p>
```

**フル構成（成熟したプロジェクト）:**

```html
<p align="center">
  <img src="https://img.shields.io/github/v/tag/owner/repo?label=version" alt="Version">
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS">
  <img src="https://img.shields.io/badge/Swift-6.0-orange" alt="Swift">
  <img src="https://img.shields.io/github/license/owner/repo" alt="License">
  <img src="https://img.shields.io/github/actions/workflow/status/owner/repo/test.yml?label=tests" alt="Tests">
  <a href="https://codecov.io/gh/owner/repo"><img src="https://codecov.io/gh/owner/repo/graph/badge.svg" alt="Coverage"></a>
  <a href="https://coderabbit.ai"><img src="https://img.shields.io/coderabbit/prs/github/owner/repo?..." alt="CodeRabbit"></a>
  <img src="https://img.shields.io/badge/open%20source-%E2%9D%A4-red" alt="Open Source">
</p>
```
