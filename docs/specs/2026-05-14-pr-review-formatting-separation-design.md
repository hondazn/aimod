# pr-review コメント整形を reviewer から pr-review スキルへ集約する設計

- 作成日: 2026-05-14
- 起案: HONDA Jun (jun.honda@spiderplus.co.jp)
- 関連ファイル:
  - `shared/skills/pr-review/SKILL.md`
  - `shared/agents/{meta,pdm,techlead}-reviewer.md`
  - `shared/rules/review-badges.md`
  - `shared/skills/juggernaut/SKILL.md`（参照のみ）

## 背景

現状、`pr-review` スキルは 3 体の reviewer エージェント（`meta-reviewer` / `pdm-reviewer` / `techlead-reviewer`）を並列起動し、各 reviewer が JSON `findings[]` を返す。問題は、各 finding の `body` フィールドに「レビュー判断（severity・指摘内容）」と「コメント整形（バッジ URL 構築・アニメーション選択・先頭装飾）」が同居している点である。

具体的に、現状 reviewer が担当している整形責務:

- severity → 日本語ラベル / color のマッピング適用
- エージェント別アニメプールから `pool[i % len]` でアニメ選択
- バッジ URL `https://mojiemoji.jozo.beer/emoji/{ラベル}?color={color}&animation={animation}&font=gothic-bold` の組立
- `body` の先頭にバッジ Markdown を貼付

この設計には以下の問題がある:

1. **構造的な複製**: バッジ URL ビルド規則が `review-badges.md` / `meta-reviewer.md` / `pdm-reviewer.md` / `techlead-reviewer.md` / `pr-review/SKILL.md` の 5 箇所に複製されている。`review-badges.md` は「正典」とされているが、参照元への伝播は「sed で一括置換してください」という運用に依存している。
2. **dedup 統合の特殊ルール**: `pr-review` Phase 4-5 に「勝った side のアニメをそのまま採用し、再計算しない」というルールが必要になっている。これは整形が reviewer 側にあるからこそ発生する副作用である。
3. **reviewer 出力の脆弱性**: reviewer が手書きで URL を組み立てるため、ラベル内改行の `%0A` エンコード漏れ、アニメ名のタイポ、`i % len` の数え間違いといった出力エラーが起こりうる。
4. **関心の混在**: reviewer は「何が問題か」「どれくらい重要か」の判断が本業のはずだが、出力フォーマット指示が prompt の大部分を占めている。

## ゴール

reviewer エージェントは構造化された「レビューの素材データ」のみを返し、整形は消費者である `pr-review` スキルが担当する。`juggernaut` スキル（セルフレビュー専用）は整形不要なため、構造化 JSON を直接消費する。

## ノンゴール

- 後方互換の維持: dotter で一斉デプロイされるため、両形式を同時サポートする必要はない。
- レビュー判断ロジックの変更: 各 reviewer の観点・severity 判断基準は現状を維持する。
- バッジ画像 API（mojiemoji）自体の変更: URL ビルド規則は据え置き。

## 設計

### 1. reviewer の新出力スキーマ

全 reviewer エージェントは以下の JSON を返す。

```json
{
  "reviewer": "techlead-reviewer",
  "mode": "pr_review",
  "findings": [
    {
      "file": "src/users/repository.rs",
      "line": 87,
      "side": "RIGHT",
      "start_line": null,
      "start_side": null,
      "severity": "must",
      "category": "パフォーマンス",
      "title": "ユーザー一覧取得で N+1 が発生しています",
      "rationale": "list_users() のループで per-user クエリが走っており、ユーザー数に比例して RT が増えます。本番想定の 5,000 ユーザーで RT が約 60 倍になる計算です。",
      "suggestion": "`User.includes(:role)` で eager load してください。",
      "evidence": "src/users/repository.rs:87"
    }
  ],
  "note": null
}
```

#### フィールド責務

| フィールド | 役割 | 必須 |
|---|---|---|
| `reviewer` | エージェント名（整形時のアニメプール選択に使用） | 必須 |
| `mode` | `"pr_review"` または `"self_review"` | 必須 |
| `findings[]` | レビュー結果の配列。0 件なら空配列 | 必須 |
| `note` | 情報不足等のメタコメント。不要なら `null` | 任意 |

各 finding:

| フィールド | 役割 | 必須 |
|---|---|---|
| `file` / `line` / `side` / `start_line` / `start_side` | 行レベル位置情報。PR 全体コメントは `file=null` | 位置情報がある場合 |
| `severity` | `"must"` / `"suggestion"` / `"nit"` / `"good"` | 必須 |
| `category` | エージェントごとの観点カテゴリ（例: `"パフォーマンス"`） | 必須 |
| `title` | 1 行要約。triage 表・ユーザー報告で使用。GitHub コメント本文には出さない | 必須 |
| `rationale` | 「なぜ問題か」を根拠付きで書く本文（Markdown 可、ですます調、断定トーン） | 必須 |
| `suggestion` | 具体的な改善案。なければ `null` | 任意 |
| `evidence` | 参照元（コード位置・既存資産 URL・AC 番号等）。なければ `null` | 任意 |

#### reviewer から削除されるもの

- `body` フィールド（バッジ URL や整形済み文字列の生成責務）
- アニメプールの定義・`pool[i % N]` のローテーション算法
- severity → ラベル/color のマッピング表
- mojiemoji URL の例示

#### reviewer に残るもの（文化）

- ですます調、`must` / `suggestion` での断定、`nit` での柔らかさ
- 計算量・脅威モデル・運用影響を根拠として書く姿勢
- 絵文字（👀⚠️💡🙏👍🎉）は `rationale` 内で自然に書いてよい。`pr-review` 側で post-process しない

### 2. pr-review の新 Phase 4-7「コメント整形」

`Phase 4-5` で dedup・統合・ソートを終えた `findings[]` を入力に、GitHub Pull Request Review API に投稿する `comments[]` を組み立てる決定的処理。

#### 入力の前提

reviewer の出力 JSON では `reviewer` 名はトップレベルにあり、個々の `findings[i]` には付与されていない。`pr-review` の Phase 4-4 で各 reviewer の結果を受信する際に、`findings[]` を平坦化しつつ各 finding に `reviewer` フィールド（出所エージェント名）を注入する。dedup 時に勝った side の `reviewer` 名がそのまま生き残り、Phase 4-7 はそれを参照してアニメプールを引く。

#### アルゴリズム

```text
ANIMATION_POOL = {
  "meta-reviewer":     ["shuchusen", "bure", "gatagata", "poyoon"],
  "pdm-reviewer":      ["yoko_scroll", "mochimochi", "bane", "shuchusen", "poyoon"],
  "techlead-reviewer": ["chuuou_zoom", "gatagata", "bure", "shuchusen", "poyoon"],
}

SEVERITY_MAP = {
  "must":       {"label": "要修正",              "color": "vivid-red"},
  "suggestion": {"label": "オススメ",            "color": "vivid-blue"},
  "nit":        {"label": "ちょっと%0A気になる", "color": "vivid-green"},
  "good":       {"label": "いいね",              "color": "pastel-green"},
}

# プロジェクト固有エージェントは "<agent-name> (project)" 形式で source に入る
# ANIMATION_POOL に無いキーの場合は固定アニメ（例: chuuou_zoom）にフォールバック

reviewer_indices = {}  # reviewer 名 → このフェーズで使った i のカウンタ
comments = []

for finding in findings_after_dedup_sort:
    reviewer = finding["reviewer"]  # dedup で勝った side の reviewer 名
    pool = ANIMATION_POOL.get(reviewer, ["chuuou_zoom"])
    i = reviewer_indices.get(reviewer, 0)
    animation = pool[i % len(pool)]
    reviewer_indices[reviewer] = i + 1

    sev = SEVERITY_MAP[finding["severity"]]
    badge_url = (
        f"https://mojiemoji.jozo.beer/emoji/{sev['label']}"
        f"?color={sev['color']}&animation={animation}&font=gothic-bold"
    )
    badge_md = f"![{sev['label']}]({badge_url})"

    body = f"{badge_md}\n\n{finding['rationale']}"
    if finding.get("suggestion"):
        body += f"\n\n**改善案:** {finding['suggestion']}"

    comments.append({
        "path": finding["file"],
        "line": finding["line"],
        "side": finding.get("side") or "RIGHT",
        # start_line / start_side は finding にあれば追加
        "body": body,
    })
```

#### 設計上の判断

- **`title` は GitHub コメント本文に出さない**: triage 表とユーザー報告での要約用途のみ。本文では `rationale` 冒頭で同等の文脈が伝わるため冗長。
- **アニメーション index の数え方**: dedup・ソート後の `findings[]` を走査しつつ、reviewer 名ごとに別カウンタで i を進める。「勝った side のアニメをそのまま採用」のような特殊ルールは不要。
- **絵文字の機械注入はしない**: reviewer の `rationale` 内で自然に書かれた絵文字をそのまま尊重する。frequency control（3〜4 件に 1 回）も明示ルールから外す。
- **`file=null` の finding**: 整形ロジック自体は行レベル / 全体共通で同じ。投稿先（レビューサマリー追記か PR 全体コメントか）の確定は残論点として実装計画フェーズで詰める。

#### 配置

`pr-review/SKILL.md` に新 Phase 4-7 として記述する。Phase 4-5 の dedup ルールから「アニメの再計算をしない」「勝った side のバッジを採用」の記述は削除する。Phase 5-2 のインラインコメント書き方節は、整形（バッジ・先頭装飾）が機械化される旨と、reviewer に残る文化（文体・絵文字判断）を分離して再構成する。

### 3. review-badges.md の再定義

現状: 「`pr-review/SKILL.md` と `shared/agents/{meta,pdm,techlead}-reviewer.md` から参照される正典」。  
変更後: 「`pr-review/SKILL.md` の整形フェーズ専用の参照表」。reviewer エージェントは参照しない。

合わせて削除:

- 「URL を変更したい場合はここを更新してから、参照元を sed で一括置換してください」の運用注意（複製がなくなるので不要）
- reviewer 別の URL 例示（pr-review の整形ロジック内のアルゴリズムで完全に決定されるため、リファレンスとして 1 セットあれば十分）

LGTM バッジ（APPROVE サマリー用、`pastel-pink` × `kira`）は引き続き `review-badges.md` に記載し、`pr-review` Phase 5-3 から参照する。

### 4. juggernaut スキルへの影響

`juggernaut` はセルフレビュー専用で、同じ 3 reviewer を起動する。reviewer 出力が「整形済み `body`」から「構造化フィールド」に変わると `juggernaut` の消費側を更新する必要がある。

**方針**: `juggernaut` 側で整形しない。`rationale` / `title` / `severity` / `file` / `line` を claude が直接読んで判断する。GitHub に投稿しないセルフレビューではバッジ・アニメは不要。

`juggernaut/SKILL.md` の具体的な改訂箇所（旧 `body` 前提の参照部分の特定と差し替え）は実装計画フェーズで詳細化する。

### 5. 移行戦略

dotter で一斉デプロイされるため、新旧の併存期間は設けない。1 PR で以下をまとめて変更する:

1. `shared/agents/{meta,pdm,techlead}-reviewer.md` の出力フォーマット改訂
2. `shared/skills/pr-review/SKILL.md` への Phase 4-7 追加と Phase 4-5 / 5-2 の整理
3. `shared/rules/review-badges.md` の再定義
4. `shared/skills/juggernaut/SKILL.md` の消費側更新

レビュー対象 PR で実 e2e 動作確認を行う手順を実装計画に含める。

## 影響範囲

| ファイル | 変更タイプ |
|---|---|
| `shared/agents/meta-reviewer.md` | 出力フォーマット節を全面改訂 |
| `shared/agents/pdm-reviewer.md` | 出力フォーマット節を全面改訂 |
| `shared/agents/techlead-reviewer.md` | 出力フォーマット節を全面改訂 |
| `shared/skills/pr-review/SKILL.md` | Phase 4-7 新設・Phase 4-5 / 4-6 / 5-2 改訂 |
| `shared/rules/review-badges.md` | 参照元の説明を更新・運用注意削除 |
| `shared/skills/juggernaut/SKILL.md` | 消費側を構造化フィールドに合わせて更新 |

## 残論点（実装計画で詰める）

- `file=null` の finding（特に `meta-reviewer` の PR 全体コメント）を GitHub にどう投げるか。現状の SKILL.md 挙動を確認したうえで整形フェーズに統合する。
- プロジェクト固有エージェント（`Phase 4-3A`）が JSON 以外を返した場合の正規化方法は現状維持（finding 形式に変換、`source` に `(project)` 付与）。整形フェーズは正規化後の構造化 finding を扱うため、特別扱いは不要。
- `juggernaut` の Phase 5-1 セルフレビュー結果整理が `body` 前提になっていないかの精査は実装計画フェーズで行う。

## 検証方針

- 既存 PR を 1 件選び、整形フェーズ移行後の `pr-review` で実投稿し、バッジ・アニメ・本文が現状と同等または改善されていることを目視確認する。
- `juggernaut` でセルフレビューを 1 回走らせ、構造化フィールドのみで claude が適切に判断できることを確認する。
- 単体テスト相当の整形検証は将来課題とする（現状スキルは自然言語で記述されているため、コード化された自動テストは存在しない）。
