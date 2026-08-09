---
name: issue-sweep
description: |
  ユーザーが起票した、またはアサインされているオープンな GitHub Issue を走査し、作業が既に完了していないか（マージ済み PR、完了済みサブ Issue）を確認し、根拠となる PR をリンクして完了済みのものをクローズする。陳腐化／代替済み／緩和済みの Issue や、リフレッシュ（本文更新または再作成）が必要な Issue も、リポジトリ横断でフラグ付けする。
  トリガー: 「issue sweep」「issue整理」「クローズできるissue」「issueの棚卸し」「close stale issues」「outdated issues」「陳腐化」「バックログ整理」。セッション終盤や、複数の PR をマージした後に proactive に起動する。
argument-hint: "[--auto] [--repo owner/repo] [--all-repos] [--min-age Nd] [--include-recent] [--fast]"
allowed-tools: Read(*) Write(*) Edit(*) Glob(*) Grep(*) Bash(gh:*) Bash(git:*) Agent(*)
---

# Issue Sweep

既に完了している、もはや関係がない、または陳腐化したオープン Issue を見つけ出し、クローズ・リフレッシュ・報告する。Issue は、PR が Issue 番号を参照せずにマージされたとき、作業が複数リポジトリにまたがるとき、あるいはコードベースが古い提案を追い越して進化したときに溜まっていく。このスキルはそのギャップを埋める。

## 入力

```text
$ARGUMENTS
```

引数が与えられなかった場合は対話的に確認する。

## Phase 1: 取得とフィルタ

### スコープの決定

| 引数 | 挙動 |
|----------|----------|
| （なし） | カレントリポジトリのみ |
| `--repo owner/repo` | 指定リポジトリ |
| `--all-repos` | ユーザーがオープン Issue を持つ、組織内の全リポジトリ |

> 注: `--all-repos` は組織（org）に所属していることを前提とする。`gh search issues --owner {org}` で組織を指定して横断検索するため、個人アカウント単独の場合は意図通りに動かない。

### Issue の取得

```bash
# カレントリポジトリ（デフォルト）
gh issue list --assignee=@me --state=open --json number,title,labels,body,createdAt --limit 100
gh issue list --author=@me --state=open --json number,title,labels,body,createdAt --limit 100
```

`--all-repos` の場合は検索を使う:

```bash
gh search issues --assignee=@me --state=open --owner={org} \
  --json repository,number,title,url --limit 100
gh search issues --author=@me --state=open --owner={org} \
  --json repository,number,title,url --limit 100
```

重複を除去する（1 つの Issue が author と assignee の両方にマッチしうる）。

### 直近の Issue をスキップ

`--min-age`（デフォルト: **7 日**）より新しい Issue はアクティブな作業中である可能性が高いため、スキップすべきである。これにより、起票されたばかりの Issue を調査してサブエージェントのトークンを浪費するのを避ける。

`--min-age 0d` または `--include-recent` を渡すとこのフィルタを上書きできる。

### クイック表示

進捗が見えるよう、候補リストを即座に表示する:

```text
オープン Issue を {N} 件発見（直近のため {M} 件スキップ）:

| # | タイトル | 経過 |
|---|-------|-----|
| #213 | 同期トランザクションの冪等性 | 71d |
| #266 | データ取り込みモジュールの分割 | 61d |
| ...  | ...                            | ... |

調査中...
```

## Phase 2: 並列調査

Issue ごと（または関連する 3〜5 件のバッチごと）に 1 つのサブエージェントを起動し、並列で調査する。各サブエージェントは、その Issue がクローズ可能か、リフレッシュが必要か、オープンのままにすべきかを判断する。

**モデル選択**: サブエージェントを起動する前に、ユーザーに確認する:
「トークン予算 — 調査エージェントは opus と sonnet どちらにする？」
Issue 調査は抽象的な推論（代替済み vs 陳腐化、コードベースの進化、設計判断）を伴うため opus が望ましい。トークン予算が厳しいとユーザーが示した場合は sonnet を使う。`--fast` を渡すとこの確認をスキップして sonnet を使う。

### サブエージェントのプロンプト構築

完全なプロンプトテンプレートと調査戦略は同梱の `references/investigation.md` を読むこと。以下をカバーしている:

- 単独 Issue プロンプト（エージェントあたり 1 Issue）
- バッチプロンプト（エージェントあたり関連 3〜5 Issue）
- 調査戦略（直接参照、キーワード検索、リポジトリ横断）
- 判定（verdict）の定義を含むレポート形式

## Phase 3: 結果の提示

全サブエージェントの結果を収集し、グループに分けて提示する:

### クローズ可能（完了）

すべての受け入れ基準がマージ済み PR で満たされている Issue。

### クローズ可能（もはや無関係）

完了以外の理由でクローズすべき Issue。
理由（代替済み / 陳腐化 / 緩和済み / 不実施）でグルーピングする。

### リフレッシュが必要

依然として価値はあるが、内容が古くなっている Issue。
スコープ（minor: その場で更新 / major: 再作成）でグルーピングする。

### 部分的（partial）

一部の基準は満たされているが、すべては満たされていない Issue。

### 未完了 / まだ有効

完了の証拠がなく、依然として関連性のある Issue。

## Phase 4: アクション

### デフォルト（confirm モード）

```text
完了済みの {N} 件をクローズして PR をリンクしますか？ (all / 番号 / none)
```

`all`、カンマ区切りの番号（例: `1,3,4`）、または `none` を受け付ける。

### `--auto` モード

確認なしで、クローズ可能な Issue をすべてクローズする。サマリーは引き続き表示する。

### クローズ手順

各 Issue について、適切なテンプレートとクローズ理由でコメントする。
バッジはすべて 1 行に収めること（バッジ間に改行を入れない）。

#### バッジ定義

| 理由 | バッジ | 色 |
|--------|-------|-----|
| completed | `![swept](https://img.shields.io/badge/swept-completed-green)` | green |
| superseded | `![swept](https://img.shields.io/badge/swept-superseded-blue)` | blue |
| outdated | `![swept](https://img.shields.io/badge/swept-outdated-yellow)` | yellow |
| mitigated | `![swept](https://img.shields.io/badge/swept-mitigated-blue)` | blue |
| not-planned | `![swept](https://img.shields.io/badge/swept-not%20planned-grey)` | grey |
| refresh (minor) | `![swept](https://img.shields.io/badge/swept-refreshed-purple)` | purple |
| refresh (major) | `![swept](https://img.shields.io/badge/swept-recreated-purple)` | purple |

オプションで、証拠の件数を示す 2 つ目のバッジを追加してもよい:
`![evidence](https://img.shields.io/badge/evidence-{N}%20PRs-green)`

#### コメントテンプレート

コメントの言語は Issue 本文に合わせる（日本語の Issue には日本語コメント、英語の Issue には英語コメント）。以下はテンプレートであり、具体的な Issue に合わせて言語と内容を調整すること。

**completed** — 証拠 PR をリンクし、completed としてクローズ:

```text
![swept](https://img.shields.io/badge/swept-completed-green) ![evidence](https://img.shields.io/badge/evidence-{N}%20PRs-green)

## 完了レポート

すべての受け入れ基準を満たしました:

- **{description}**: {owner/repo}#{number}

クローズします。
```

上記テンプレートを `--comment` で渡してクローズする。これを省くと、特に `--auto` モードで
約束した PR リンク・根拠を残さずに Issue を閉じてしまう（`gh issue close` は本文を投稿しない）。

```bash
gh issue close {number} --repo {repo} --reason completed \
  --comment "{上の completed テンプレートをレンダリングした本文}"
```

**superseded / outdated / mitigated / not-planned** — 理由を説明し、not planned としてクローズ:

```text
![swept](https://img.shields.io/badge/swept-{reason}-{color})

## クローズ（{reason}）

{何が Issue を置き換えた/不要にしたかへのリンクを添えた説明。}
```

```bash
gh issue close {number} --repo {repo} --reason "not planned" \
  --comment "{上の {reason} テンプレートをレンダリングした本文}"
```

**refresh (minor)** — Issue 本文をその場で編集してからコメント:

```bash
gh issue edit {number} --repo {repo} --body "{updated_body}"
```

```text
![swept](https://img.shields.io/badge/swept-refreshed-purple)

## リフレッシュ

現在のコードベースの状態を反映するよう Issue 本文を更新しました:

- {何を、なぜ更新したか}
```

**refresh (major)** — 新しい Issue を作成し、相互リンクを張って古い Issue をクローズ:

1. 本文の冒頭に `Supersedes #{old_number}` を入れた新規 Issue を作成する
2. 古い Issue にコメントする:

```text
![swept](https://img.shields.io/badge/swept-recreated-purple)

## 再作成

現在のコードベースの状態を反映した新しい Issue を作成しました:

- **新 Issue**: #{new_number}
- **変更点**: {何が変わり、なぜ再作成が必要だったか}

この Issue はクローズします。
```

```bash
gh issue close {old_number} --repo {repo} --reason "not planned" \
  --comment "{上の recreated テンプレートをレンダリングした本文}"
```

1. ラベル・アサイン・マイルストーンを古い Issue から新しい Issue へ引き継ぐ。

## Phase 5: サマリー

```text
## Issue Sweep 結果

| アクション | 件数 | Issue |
|--------|-------|--------|
| クローズ（completed） | 5 | #689, #790, #179, #266, #151 |
| クローズ（superseded） | 2 | #590, #527 |
| クローズ（outdated） | 1 | #59 |
| クローズ（mitigated） | 1 | #395 |
| クローズ（not planned） | 1 | #33 |
| リフレッシュ（minor） | 0 | |
| 再作成（major） | 0 | |
| 部分的（要対応） | 1 | #716 |
| まだ有効 | 2 | #799, #800 |
| スキップ（直近） | 6 | #906, #885, ... |
```

## ガイドライン

### 証拠の探索

- 幅広く検索すること — 特にリポジトリ横断のワークフローでは、PR が Issue 番号を参照していないことが多い。キーワード検索や作者ベースの検索でこれらを捕捉する。
- Issue にチェックボックス形式の基準がある場合、すべてのボックスがマージ済み PR で満たされていなければならない。確信が持てない場合はクローズしない。
- サブ Issue を持つ親 Issue については、親をクローズ可能とマークする前に、**すべての**サブ Issue がクローズされていることを確認する。

### 関連性の評価

すべてのオープン Issue が、クローズするために作業の完了を必要とするわけではない。以下を問うことで関連性を評価する:

- **文脈はまだ有効か？** 初期段階の設計ドキュメントは、プロジェクトが成熟して実際のコードが真実の源（source of truth）になるにつれて陳腐化する。
- **他の何かがギャップを埋めていないか？** PR をブロックする CI チェックが、マージ後のワークフローを不要にしているかもしれない。グローバルなスキルがプロジェクト固有のスキルを代替しているかもしれない。
- **別の方向性が選ばれていないか？** Issue が提案するものに対して、コードベースが意図的な代替策を示している場合、それは not-planned である。
- **年齢はルールではなくシグナル。** 60 日より古い Issue は関連性について追加の精査に値するが、年齢だけではクローズを正当化しない。

### コミュニケーション

- コメントの言語は Issue 本文に合わせる。
- 「not planned」でクローズする場合は、必ず**なぜ**かを説明する — 代替策・別案・設計判断へのリンクを添える。
- `--auto` フラグは、信頼できる sweep のための便宜である。一部の Issue は人間の判断を要するため、デフォルトは confirm とする。
