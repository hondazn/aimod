# 調査サブエージェント用プロンプトテンプレート

調査サブエージェント向けのプロンプトを構築する際は、このテンプレートを使うこと。
`{placeholders}` は実際の値に置き換える。

## 単独 Issue プロンプト

```text
{repo} の GitHub issue #{number} がクローズ可能か、リフレッシュが必要かを調査してください。

Issue タイトル: {title}
Issue 本文（先頭 2000 文字）: {body_excerpt}
Issue 経過日数: {age} 日

適切な判定（verdict）を決定してください。Issue は複数の理由でクローズしうる:

1. **completed** — すべての受け入れ基準がマージ済み PR で満たされている
2. **superseded** — 別のツール・スキル・プロセス・アプローチが、そのニーズを既にカバーしている
3. **outdated** — Issue は以前のプロジェクト段階では関連性があったが、プロジェクトが
   それを追い越して成熟した（例: 今や成熟したリポジトリに対する初期の設計ドキュメント）
4. **mitigated** — Issue が扱うリスクやギャップが、厳密な解決策が実装されていなくても、
   他の手段によって十分に低減されている
5. **not-planned** — 設計判断が別の方向に進んだ
6. **refresh** — 依然として価値はあるが、本文が古いファイルパス・陳腐化したアーキテクチャ・
   クローズ済みの依存関係・もはや成り立たない前提を参照している

手順:

1. Issue 本文の全文を読む: gh issue view {number} --repo {repo}
2. 完了基準を抽出する:
   - チェックボックス項目（- [ ] / - [x]）
   - サブ Issue 参照（#NNN）
   - 記述された成果物
3. リポジトリ横断で関連するマージ済み PR を検索する:
   a. この Issue を直接参照する PR:
      gh search prs --merged "{repo}#{number}" --owner {org} --json number,title,repository,url
   b. Issue タイトルのキーワードによる PR:
      gh search prs --merged "{keywords}" --repo {repo} --json number,title,url
   c. 同じ組織内のリポジトリ横断 PR:
      gh search prs --merged "{keywords}" --owner {org} --json number,title,repository,url
4. サブ Issue については、その状態を確認する:
   gh issue view {sub_number} --repo {repo} --json state
5. 完了の直接的な証拠がない場合、関連性を評価する:
   - コードベースが進化して、これを不要にしていないか？
   - 既に代替の解決策が存在していないか？
   - 別の設計方針が選ばれていないか？
   - 古い Issue（60 日以上）について: 文脈はまだ有効か？
6. 依然として関連性はあるが古くなっている場合、リフレッシュのスコープを評価する:
   - 本文中のファイルパスがまだ存在するか確認する（grep/glob）
   - 参照されている構造体/関数がまだ存在するか確認する
   - 依存関係の Issue の状態が変わっていないか確認する
   - 軽微な陳腐化（数個のパスが変わった程度）→ その場で更新
   - 大きな陳腐化（アーキテクチャが変わった、スコープが変わった）→ 再作成
7. 判定（verdict）を決定する。

レポート形式:
---
issue: {number}
repo: {repo}
verdict: closeable | superseded | outdated | mitigated | not-planned | refresh | partial | not-done
close_reason: completed | not planned | refreshed
refresh_scope: minor | major (refresh 判定の場合のみ)
stale_items:
  - "{何が古いか、なぜか}"
evidence:
  - pr: {owner/repo}#{number}
    title: {title}
    covers: "{この PR がどの基準を満たすか}"
  - note: "{PR ベースのクローズでない場合の説明}"
unchecked_criteria:
  - "{まだ満たされていない基準}"
summary: "{一行の評価}"
---
```

## バッチ Issue プロンプト（関連する 3〜5 件）

複数の Issue を 1 つのサブエージェントにまとめる場合は、先頭に以下を付ける:

```text
以下の {N} 件の Issue を調査してください。上記の形式で各 Issue を個別に報告してください。

Issues:
1. #{number1} — {title1} ({age1}d)
2. #{number2} — {title2} ({age2}d)
...
```

## 調査戦略

PR は Issue を参照していないことが多いため、サブエージェントは幅広く検索すべきである:

1. **直接参照** — `Closes #N`、`Fixes #N`、PR 本文中の Issue 番号
2. **キーワード検索** — Issue タイトルの主要語句を、組織内の全リポジトリで検索
3. **作者検索** — 関連する期間内における、Issue のアサイン担当者による PR
4. **サブ Issue 連鎖** — Issue にサブ Issue がある場合、それらがすべてクローズ済みか確認
5. **リポジトリ横断の意識** — 作業は組織内の複数リポジトリにまたがりうる
