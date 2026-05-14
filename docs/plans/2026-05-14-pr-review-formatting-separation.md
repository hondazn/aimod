# pr-review コメント整形分離 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** reviewer エージェントからコメント整形責務（バッジ URL 構築・アニメローテ・先頭装飾）を剝がし、`pr-review` スキル側に集約する。reviewer は構造化フィールド（`title` / `rationale` / `suggestion` / `evidence`）のみを返す統一仕様に切り替える。

**Architecture:** reviewer は素材を返す → `pr-review` Phase 4-7 が決定的に整形 → GitHub に投稿。`juggernaut` セルフレビューは整形フェーズを通さず構造化フィールドを直接消費する。

**Tech Stack:** Markdown スキル定義（`shared/agents/*.md`, `shared/skills/*/SKILL.md`, `shared/rules/*.md`）。実行系は claude エージェント / Bash / GitHub API（`gh api`）。コードベースに自動テストは無く、検証は実 PR とセルフレビューでの e2e 確認となる。

**関連ドキュメント:**
- 設計: `docs/specs/2026-05-14-pr-review-formatting-separation-design.md`

---

## File Structure

変更対象ファイルと責務:

- `shared/skills/pr-review/SKILL.md` — オーケストレータ。Phase 4-7（整形）を新設、Phase 4-4/4-5/4-6/5-2/6-2 を改訂
- `shared/agents/meta-reviewer.md` — reviewer。出力フォーマット節を構造化スキーマへ全面差し替え
- `shared/agents/pdm-reviewer.md` — 同上
- `shared/agents/techlead-reviewer.md` — 同上
- `shared/rules/review-badges.md` — pr-review 専用参照表へ再定義
- `shared/skills/juggernaut/SKILL.md` — 監査（変更は最小限）

## コミット戦略

dotfiles として `dotter deploy` した瞬間に整合する必要がある。安全側に倒し、**「reviewer 出力スキーマと pr-review 消費側を同じコミットに含める」** ことを基本ルールとする。具体的には:

- Task 1（pr-review に Phase 4-7 追加＋消費側準備）→ commit
- Task 2-4（3 reviewer の出力スキーマ移行 + pr-review の旧整形依存除去）→ **すべてまとめて 1 commit**
- 以降の clean-up は個別 commit で OK

---

## Task 1: pr-review Phase 4-7「コメント整形」を新設する

新フェーズを追加する。この時点では reviewer 側は旧スキーマのままなので、Phase 4-7 のロジックは「`body` または `rationale` のどちらかが入っていればそれを使う」というブリッジは入れない（Task 2-4 と同時にしか動かない前提）。このコミットは Task 2-4 と一緒にデプロイされるので、独立にデプロイされる想定をしない。

**Files:**
- Modify: `shared/skills/pr-review/SKILL.md`

### Step 1-1: Phase 4-7 セクションを追加

- [ ] **Phase 4-6 直後に Phase 4-7 を追加**

`shared/skills/pr-review/SKILL.md` の `### 4-6. 検出結果の整理` セクション末尾（`問題が0件の場合はその旨を報告し、Phase 5でAPPROVEコメントのみ作成する。` の直後、`---` の直前）に以下を挿入する:

````markdown
### 4-7. コメント整形

dedup・ソート済みの `findings[]` を入力に、GitHub Pull Request Review API に投稿する `comments[]` を組み立てる決定的処理。reviewer は素材（`title` / `rationale` / `suggestion` / `evidence`）のみを返すので、ここでバッジ・アニメ・本文の合成を一括で行う。

**前提:** Phase 4-4 で各 reviewer の `findings[]` を平坦化する際、各 finding に `reviewer` フィールド（出所エージェント名、例: `"techlead-reviewer"`）を注入してある。dedup で勝った side の `reviewer` 名がそのまま生き残る。

**マッピング定義:**

```text
ANIMATION_POOL = {
  "meta-reviewer":     ["shuchusen", "bure", "gatagata", "poyoon"],
  "pdm-reviewer":      ["yoko_scroll", "mochimochi", "bane", "shuchusen", "poyoon"],
  "techlead-reviewer": ["chuuou_zoom", "gatagata", "bure", "shuchusen", "poyoon"],
}
# ANIMATION_POOL に存在しない reviewer 名（プロジェクト固有エージェント等）は ["chuuou_zoom"] にフォールバック

SEVERITY_MAP = {
  "must":       {"label": "要修正",              "color": "vivid-red"},
  "suggestion": {"label": "オススメ",            "color": "vivid-blue"},
  "nit":        {"label": "ちょっと%0A気になる", "color": "vivid-green"},
  "good":       {"label": "いいね",              "color": "pastel-green"},
}
```

**手順:**

1. `reviewer_indices = {}` を用意（reviewer 名 → カウンタ）
2. dedup・ソート済みの `findings[]` を順に走査する
3. `file == null` の finding は GitHub の `comments[]` には載せない（Phase 6-2 の Reviews API が `path` 必須のため）。代わりに「PR レベル所感」としてユーザーへの最終報告（Phase 6-3）に列挙する
4. `file != null` の各 finding について:
   - `reviewer = finding["reviewer"]`
   - `pool = ANIMATION_POOL.get(reviewer, ["chuuou_zoom"])`
   - `i = reviewer_indices.get(reviewer, 0)`
   - `animation = pool[i % len(pool)]`
   - `reviewer_indices[reviewer] = i + 1`
   - `sev = SEVERITY_MAP[finding["severity"]]`
   - `badge_url = "https://mojiemoji.jozo.beer/emoji/" + sev["label"] + "?color=" + sev["color"] + "&animation=" + animation + "&font=gothic-bold"`
   - `badge_md = "![" + sev["label"] + "](" + badge_url + ")"`
   - `body = badge_md + "\n\n" + finding["rationale"]`
   - `finding["suggestion"]` があれば `body += "\n\n**改善案:** " + finding["suggestion"]` を末尾追加
   - `comments[]` に `{"path": file, "line": line, "side": side or "RIGHT", "body": body}` を append（`start_line` / `start_side` が finding にあれば併せて入れる）
5. 整形済み `comments[]` を Phase 6-2 へ渡す

**判断ルール:**

- `title` は本文に出さない（triage 表とユーザー報告での要約用途のみ）
- `rationale` 内に既にある絵文字（👀⚠️💡🙏👍🎉）はそのまま尊重する。post-process しない
- アニメインデックスは dedup・ソート後の配列を走査しながら reviewer 名ごとに再カウントする。reviewer 元出力時の i は使わない
````

- [ ] **Run check:** 挿入後にファイル末尾の `## 完了前セルフチェック` が存在することを `grep -n "完了前セルフチェック" shared/skills/pr-review/SKILL.md` で確認

Expected: 行番号が返る

### Step 1-2: Phase 4-4 を改訂し reviewer フィールド注入を明示

- [ ] **`### 4-4. 結果の受信` の本文を以下に差し替え**

検索キー: `### 4-4. 結果の受信`

旧:

```markdown
### 4-4. 結果の受信

全エージェントの結果を待つ。各エージェントは JSON `findings` 配列を返す。プロジェクト固有エージェントが JSON 以外（テーブル/テキスト）で返した場合は finding 形式に変換し、重要度を4段階に正規化する（不明ラベルは `suggestion`）。`source` に `"<agent-name> (project)"` を付与する。パース失敗時はそのエージェントの結果を除外して続行する。
```

新:

```markdown
### 4-4. 結果の受信

全エージェントの結果を待つ。各エージェントは JSON `findings` 配列を返す。受信した `findings[]` を平坦化する際に、各 finding へ **`reviewer` フィールド（出所エージェント名、例: `"techlead-reviewer"`）** を注入する。これは Phase 4-7 の整形でアニメプールを引くために必須。

プロジェクト固有エージェントが JSON 以外（テーブル/テキスト）で返した場合は finding 形式に変換し、重要度を4段階に正規化する（不明ラベルは `suggestion`）。`reviewer` フィールドには `"<agent-name> (project)"` を付与する（旧 `source` 列に相当）。パース失敗時はそのエージェントの結果を除外して続行する。
```

- [ ] **commit を保留**: Task 2-4 と atomic にコミットするため、ここではコミットしない。`git status` で変更内容を確認するのみ

Run: `git diff --stat shared/skills/pr-review/SKILL.md`

Expected: `shared/skills/pr-review/SKILL.md` に変更行数が表示される

---

## Task 2: meta-reviewer の出力スキーマを構造化スキーマへ移行

旧 `body`（バッジ URL を含む整形済み markdown）を `title` / `rationale` / `suggestion` / `evidence` の 4 フィールドに分解する。アニメプール・URL ビルド規則・severity マッピング表は全削除。

**Files:**
- Modify: `shared/agents/meta-reviewer.md`

### Step 2-1: 出力フォーマット JSON 例を差し替え

- [ ] **`## 出力フォーマット` セクション全体を差し替え**

検索キー: `## 出力フォーマット`

旧（86 行目付近）:

````markdown
## 出力フォーマット

以下のJSON形式で結果を返してください。必ずこのフォーマットに従い、JSON以外のテキストを出力に含めないでください。

```json
{
  "reviewer": "meta-reviewer",
  "mode": "pr_review",
  "findings": [
    {
      "file": null,
      "line": null,
      "side": "RIGHT",
      "start_line": null,
      "start_side": null,
      "severity": "must",
      "category": "方向性",
      "title": "問題の1行要約",
      "body": "![要修正](https://mojiemoji.jozo.beer/emoji/要修正?color=vivid-red&animation=shuchusen&font=gothic-bold) 詳細な説明と根拠。ですます調で、メタレビュアーとして方向性に対する判断を述べる。must/suggestionでは「〜です」「〜してください」を使う。nitでは柔らかい表現を許容する。たまに「!」や絵文字（👀💡⚠️🤔）を添えて温かみを出してもいい"
    }
  ]
}
```

### フィールド仕様

- `mode`: `"pr_review"` | `"self_review"` のいずれか（実際に動いたモード）
- `file`: 行レベルコメントが妥当な場合のみパスを記載。方向性指摘は通常 PR/計画全体に対するものなので `null` のことが多い
- `line`: `file` を指定する場合は行番号、それ以外 `null`
- `side`: `"RIGHT"`（既定）。`null` も可（PR 全体コメント）
- `start_line` / `start_side`: 複数行コメントのときのみ。不要なら `null`
- `severity`: `"must"` | `"suggestion"` | `"nit"` | `"good"` のいずれか
  - `must`: 方向性が根本的に間違っている、前提の致命的誤解、明確な車輪の再発明、長期方針との重大な矛盾
  - `suggestion`: 方向性は通るが、別アプローチや既存資産活用の提案
  - `nit`: 些細なメタ観点（参考情報）
  - `good`: 方向性として優れた判断（根本原因への適切な対処、長期方針との整合）
- `category`: 原則 `"方向性"`。サブカテゴリとして `"根本原因"` `"前提"` `"再発明"` `"長期整合"` を必要に応じて使ってよい
- `body`: severity に対応するバッジを先頭に付与する。**meta-reviewer のアニメプール**（正典: `shared/rules/review-badges.md`）は `shuchusen`(base) → `bure` → `gatagata` → `poyoon`。i 番目（0-indexed）の finding には `pool[i % 4]` のアニメを採用する（severity に依らずローテーション）。ベース（i=0）の URL 例:
  - `![要修正](https://mojiemoji.jozo.beer/emoji/要修正?color=vivid-red&animation=shuchusen&font=gothic-bold)`
  - `![オススメ](https://mojiemoji.jozo.beer/emoji/オススメ?color=vivid-blue&animation=shuchusen&font=gothic-bold)`
  - `![ちょっと気になる](https://mojiemoji.jozo.beer/emoji/ちょっと%0A気になる?color=vivid-green&animation=shuchusen&font=gothic-bold)`
  - `![いいね](https://mojiemoji.jozo.beer/emoji/いいね?color=pastel-green&animation=shuchusen&font=gothic-bold)`

  ローテーション枠（i ≥ 1）では URL の `animation=` を `bure` / `gatagata` / `poyoon` のいずれかに差し替える。ですます調で、根拠（引用元・既存資産・過去 Issue/PR 番号）を明示する
- findings が0件の場合は空配列 `[]` を返す
- 情報不足で判定不能な場合（PR/Issue 双方が空、計画が渡されない等）: 空配列を返し、`"note": "方向性の判定に必要な情報（Issue 本文 / 実装計画 / 関連ドキュメント）が不足しています"` を追加する
````

新:

````markdown
## 出力フォーマット

以下のJSON形式で結果を返してください。必ずこのフォーマットに従い、JSON以外のテキストを出力に含めないでください。コメントのバッジ装飾・アニメーション選択・本文整形は呼び出し側（`pr-review` スキル）が担当するため、ここでは行わない。

```json
{
  "reviewer": "meta-reviewer",
  "mode": "pr_review",
  "findings": [
    {
      "file": null,
      "line": null,
      "side": "RIGHT",
      "start_line": null,
      "start_side": null,
      "severity": "must",
      "category": "方向性",
      "title": "問題の1行要約（triage 表とユーザー報告で使用）",
      "rationale": "詳細な説明と根拠。ですます調で、メタレビュアーとして方向性に対する判断を述べる。must/suggestionでは「〜です」「〜してください」を使う。nitでは柔らかい表現を許容する。",
      "suggestion": "具体的な改善案。あれば文字列、無ければ null",
      "evidence": "参照元（引用元 URL / 既存資産パス / 過去 Issue・PR 番号 など）。無ければ null"
    }
  ],
  "note": null
}
```

### フィールド仕様

- `mode`: `"pr_review"` | `"self_review"` のいずれか（実際に動いたモード）
- `file`: 行レベルコメントが妥当な場合のみパスを記載。方向性指摘は通常 PR/計画全体に対するものなので `null` のことが多い
- `line`: `file` を指定する場合は行番号、それ以外 `null`
- `side`: `"RIGHT"`（既定）。`null` も可（PR 全体コメント）
- `start_line` / `start_side`: 複数行コメントのときのみ。不要なら `null`
- `severity`: `"must"` | `"suggestion"` | `"nit"` | `"good"` のいずれか
  - `must`: 方向性が根本的に間違っている、前提の致命的誤解、明確な車輪の再発明、長期方針との重大な矛盾
  - `suggestion`: 方向性は通るが、別アプローチや既存資産活用の提案
  - `nit`: 些細なメタ観点（参考情報）
  - `good`: 方向性として優れた判断（根本原因への適切な対処、長期方針との整合）
- `category`: 原則 `"方向性"`。サブカテゴリとして `"根本原因"` `"前提"` `"再発明"` `"長期整合"` を必要に応じて使ってよい
- `title`: 1 行要約（推奨 40 字以内）。GitHub コメント本文には出さないが、triage 表とユーザー報告での見出しとして使われる
- `rationale`: 「なぜそれが問題か」を根拠付きで書く本文。Markdown 可。ですます調・断定トーン（must/suggestion）/ 柔らかいトーン（nit）。たまに「!」や絵文字（👀💡⚠️🤔）を添えて温かみを出してもよい。**バッジ URL や severity マークは付けない**（呼び出し側で付与される）
- `suggestion`: 具体的な改善案。無ければ `null`
- `evidence`: 引用元 URL / 既存資産パス / 過去 Issue・PR 番号 など、根拠の参照ポインタ。無ければ `null`
- findings が0件の場合は空配列 `[]` を返す
- `note`: 情報不足で判定不能な場合の補足。例: `"方向性の判定に必要な情報（Issue 本文 / 実装計画 / 関連ドキュメント）が不足しています"`。不要なら `null`
````

- [ ] **整合性チェック**: 差し替え後にバッジ URL / `https://mojiemoji.jozo.beer` への参照が残っていないことを確認

Run: `grep -n "mojiemoji\|animation=\|アニメプール\|pool\[i" shared/agents/meta-reviewer.md`

Expected: マッチなし（空出力）

---

## Task 3: pdm-reviewer の出力スキーマを構造化スキーマへ移行

Task 2 と同じパターン。

**Files:**
- Modify: `shared/agents/pdm-reviewer.md`

### Step 3-1: 出力フォーマット節を差し替え

- [ ] **`## 出力フォーマット` セクション全体を差し替え**

検索キー: `## 出力フォーマット`

旧（99 行目付近）の JSON 例とフィールド仕様（`body` フィールド・URL 例・アニメプール `yoko_scroll → mochimochi → ...` の説明を含む箇所）を以下に差し替える。

````markdown
## 出力フォーマット

以下のJSON形式で結果を返してください。必ずこのフォーマットに従い、JSON以外のテキストを出力に含めないでください。コメントのバッジ装飾・アニメーション選択・本文整形は呼び出し側（`pr-review` スキル）が担当するため、ここでは行わない。

```json
{
  "reviewer": "pdm-reviewer",
  "mode": "pr_review",
  "findings": [
    {
      "file": "spec/users/billing_spec.rb",
      "line": 42,
      "side": "RIGHT",
      "start_line": null,
      "start_side": null,
      "severity": "must",
      "category": "AC充足",
      "title": "問題の1行要約（triage 表とユーザー報告で使用）",
      "rationale": "詳細な説明と AC 番号 / シナリオ名を引いた根拠。ですます調で、PdM 視点としてユーザーへの影響を述べる。must/suggestionでは「〜です」「〜してください」を使う。nitでは柔らかい表現を許容する。",
      "suggestion": "具体的な改善案。あれば文字列、無ければ null",
      "evidence": "AC 番号、シナリオ名、UX 影響箇所など。無ければ null"
    }
  ],
  "note": null
}
```

### フィールド仕様

- `mode`: `"pr_review"` | `"self_review"` のいずれか（実際に動いたモード）
- `file`: テストファイルへの行レベル指摘の場合はパスを記載。AC 全体への指摘は `null`
- `line`: `file` を指定する場合は行番号、それ以外 `null`
- `side`: `"RIGHT"`（既定）。`null` も可（PR 全体コメント）
- `start_line` / `start_side`: 複数行コメントのときのみ。不要なら `null`
- `severity`: `"must"` | `"suggestion"` | `"nit"` | `"good"` のいずれか
  - `must`: AC 未充足、ビジネスロジックの致命的漏れ、UX 上のブロッカー、AC 自体が定義されていない、後方互換を壊しているのに移行導線がない、仕様矛盾を放置している
  - `suggestion`: より良い網羅性、テスト名の改善、UX のより親切な振る舞いの提案、スコープ過多への分割提案
  - `nit`: 些細な UX / テスト記述改善
  - `good`: ユーザー価値として優れた判断、エッジケースを的確にテスト化している、スコープが適切に絞られている
- `category`: `"AC充足"` | `"エッジケース"` | `"UX"` | `"テスト網羅"` | `"仕様曖昧さ"` | `"スコープ"` のいずれか
- `title`: 1 行要約（推奨 40 字以内）。GitHub コメント本文には出さないが、triage 表とユーザー報告での見出しとして使われる
- `rationale`: 「なぜそれが問題か」を AC 番号やシナリオ名を引きながら書く本文。Markdown 可。ですます調・断定トーン（must/suggestion）/ 柔らかいトーン（nit）。たまに「!」や絵文字（🙏👀💡⚠️🎉）を添えて温かみを出してもよい。**バッジ URL や severity マークは付けない**（呼び出し側で付与される）
- `suggestion`: 具体的な改善案。無ければ `null`
- `evidence`: AC 番号、シナリオ名、UX 影響箇所など。無ければ `null`
- findings が0件の場合は空配列 `[]` を返す
- AC が PR / Issue 双方に未記載の場合: 空配列ではなく `severity: "must"` の findings として「AC が定義されていません」を必ず返す
- `note`: テストファイルが diff に存在しない場合は `"テストファイルが diff に含まれないため、テスト網羅性の検証はスキップしました"` を入れる。不要なら `null`
````

- [ ] **整合性チェック**

Run: `grep -n "mojiemoji\|animation=\|アニメプール\|pool\[i" shared/agents/pdm-reviewer.md`

Expected: マッチなし

---

## Task 4: techlead-reviewer の出力スキーマを構造化スキーマへ移行

Task 2-3 と同じパターン。**Task 1-4 を 1 つの atomic commit にまとめる。**

**Files:**
- Modify: `shared/agents/techlead-reviewer.md`

### Step 4-1: 出力フォーマット節を差し替え

- [ ] **`## 出力フォーマット` セクション全体を差し替え**

検索キー: `## 出力フォーマット`

旧（106 行目付近）の JSON 例とフィールド仕様を以下に差し替える。

````markdown
## 出力フォーマット

以下のJSON形式で結果を返してください。必ずこのフォーマットに従い、JSON以外のテキストを出力に含めないでください。コメントのバッジ装飾・アニメーション選択・本文整形は呼び出し側（`pr-review` スキル）が担当するため、ここでは行わない。

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
      "title": "問題の1行要約（triage 表とユーザー報告で使用）",
      "rationale": "詳細な説明と計算量・脅威モデル・運用影響などの根拠。ですます調で、テックリードとして判断を述べる。must/suggestionでは「〜です」「〜してください」を使う。nitでは柔らかい表現を許容する。",
      "suggestion": "具体的な改善案。あれば文字列、無ければ null",
      "evidence": "計算量の根拠、再現手順、観測値、関連 CVE など。無ければ null"
    }
  ],
  "note": null
}
```

### フィールド仕様

- `mode`: `"pr_review"` | `"self_review"` のいずれか（実際に動いたモード）
- `file`: PR diff / git diff 上のファイルパス（リポジトリルートからの相対パス）
- `line`: 変更後ファイルの行番号（diff hunk 内）
- `side`: 原則 `"RIGHT"`（変更後側）。削除行に対するコメントのみ `"LEFT"`
- `start_line` / `start_side`: 複数行コメントのときのみ。不要なら `null`
- `severity`: `"must"` | `"suggestion"` | `"nit"` | `"good"` のいずれか
  - `must`: 正しく動作しない / クラッシュ / データ破壊リスク、パフォーマンス致命傷（運用に影響する N+1 など）、セキュリティ脆弱性、保守不能なコード、運用不能、競合状態・null参照などの堅牢性欠陥
  - `suggestion`: より良い品質・性能・運用性の提案、デザイン改善、テスト構造の改善
  - `nit`: 些細な可読性・保守性改善（Linter で拾えないもの）
  - `good`: 技術的に優れた判断（適切な抽象、堅牢なエラーハンドリング、運用配慮、テスト容易な構造）
- `category`: `"正しさ"` | `"パフォーマンス"` | `"可読性"` | `"セキュリティ"` | `"運用"` | `"持続性"` | `"テスト品質"` のいずれか
- `title`: 1 行要約（推奨 40 字以内）。GitHub コメント本文には出さないが、triage 表とユーザー報告での見出しとして使われる
- `rationale`: 「なぜそれが問題か」を計算量・脅威モデル・運用影響などの根拠付きで書く本文。Markdown 可。ですます調・断定トーン（must/suggestion）/ 柔らかいトーン（nit）。たまに「!」や絵文字（👀⚠️💡🙏🚀）を添えて温かみを出してもよい。**バッジ URL や severity マークは付けない**（呼び出し側で付与される）
- `suggestion`: 具体的な改善案。無ければ `null`
- `evidence`: 計算量の根拠、再現手順、観測値、関連 CVE など。無ければ `null`
- findings が0件の場合は空配列 `[]` を返す
- `note`: diff が極小（例: typo 修正のみ）で技術品質の論点が無い場合は `"技術品質の論点が見当たりませんでした"`。不要なら `null`
````

- [ ] **整合性チェック**

Run: `grep -n "mojiemoji\|animation=\|アニメプール\|pool\[i" shared/agents/techlead-reviewer.md`

Expected: マッチなし

### Step 4-2: pr-review 旧整形依存ルールの除去

ここで Task 1 で挿入した Phase 4-7 と整合させるために、pr-review の Phase 4-5 / 4-6 / 5-2 / 6-2 の **旧整形前提の記述を改訂** する。

- [ ] **Phase 4-5 から「勝った side のアニメをそのまま採用」の特殊ルールを削除**

検索キー: `### 4-5. 結果統合`

現状の `### 4-5. 結果統合` セクション本文を以下に置き換える（重複検出ルール 1-7 は据え置き、その下の `**ソート:**` 直前にある「アニメは再計算しない」記述は無いが、`### 4-5A. ここで終了しない` セクション含めて整形依存の言及がないか確認しつつ進める）:

旧（重複検出ルールの全文 + ソート行）— そのまま残してよい。**ただし** ルール 1 と 2 の文末に補足:

```markdown
1. **完全重複**（同一ファイル + 行番号差5行以内 + 内容が実質同一）→ 重要度が高い方を採用。整形は Phase 4-7 で reviewer 名から再計算するので、ここでバッジやアニメを引き継ぐ必要はない
2. **部分重複**（同一ファイル + 行番号差5行以内 + 異なる観点からの指摘）→ rationale / suggestion / evidence を統合して 1 finding にまとめる（reviewer 名は高重要度側を採用）。重要度ラベルは最も高いものを適用
```

3-7 はそのまま。

- [ ] **Phase 4-6 の triage 表を新スキーマに合わせる**

検索キー: `### 4-6. 検出結果の整理`

旧の表の列は `# | ファイル:行 | 問題の内容 | 重要度 | 観点 | ソース` だが、`問題の内容` は新スキーマでは `title` を使う。表の説明文に「`title` 列は finding[].title をそのまま転記、本文（rationale）は表に展開しない」と注記を追加する。

旧:

```markdown
### 4-6. 検出結果の整理

単一フロー（4-2）またはサブエージェント統合（4-5）の結果を以下の表形式で整理する。プロジェクト固有エージェントが起動された場合はソース列を追加する。
```

新（直後の表は据え置き）:

```markdown
### 4-6. 検出結果の整理

単一フロー（4-2）またはサブエージェント統合（4-5）の結果を以下の表形式で整理する。プロジェクト固有エージェントが起動された場合はソース列を追加する。**「問題の内容」列には各 finding の `title` フィールドをそのまま転記する**。本文（`rationale`）は表には展開せず、Phase 4-7 で整形して GitHub に投稿される。
```

`ソース` 列のセル値は新スキーマでは `reviewer` フィールドそのものを使う（例: `techlead-reviewer`、`spec-reviewer (project)`）。

- [ ] **Phase 5-2 を「reviewer に残る文化」と「整形は機械化された」の 2 軸で再構成**

検索キー: `### 5-2. インラインコメントの書き方`

旧の `### 5-2. インラインコメントの書き方` セクション全体を以下に差し替え:

````markdown
### 5-2. インラインコメントの書き方

インラインコメント本文の **整形（バッジ・先頭装飾・suggestion 追記）は Phase 4-7 で機械的に処理される**。reviewer エージェントは構造化フィールド（`title` / `rationale` / `suggestion` / `evidence`）を返すだけで、URL や severity マークの構築は行わない。

**reviewer に残る「文化」（rationale 内で守られるべきもの）:**

- ですます調で書く
- テックリードとして根拠を明示した判断を述べる。曖昧な表現を避け、何が問題で何をすべきかを明確にする
  - 良い例: 「ここ、nullが来るとクラッシュします。チェックを入れてください」
  - 悪い例: 「null参照の可能性が検出されました。適切なバリデーションの実装が推奨されます」
- must/suggestion では「〜かも」「〜しそう」「〜な気がします」を使わない。「〜です」「〜してください」「〜しましょう」で判断を明示する。nit のみ「〜でもいいかもしれません」のような柔らかい表現を許容する
- 改善案は `suggestion` フィールドに分離して書く（rationale 末尾に書いてもよいが、できれば構造化する）
- たまに「!」や絵文字を rationale 内で使って、人間らしい温かみを出す
  - 頻度は各 reviewer の感覚で「ごくたまに」程度。連続して使うと不自然なので、使わない finding の方が多くてよい
  - 「!」は肯定的な文脈で使う（称賛、感謝、同意）。問題指摘では使わない
  - 絵文字は文末に 1 つだけ添える。以下から選ぶ:
    - 👀 注目してほしい箇所
    - 👍 良い実装への賛同
    - 🎉 LGTM・称賛
    - ⚠️ 潜在的リスクへの注意喚起
    - 💡 提案・アイデア
    - 🙏 感謝
  - 例: 「このエラーハンドリング、丁寧でいいですね 👍」
- サマリーとインラインコメントは別物。サマリーは PR 全体の印象を伝える場で、個別の指摘内容を繰り返す場ではない

**整形フェーズ（Phase 4-7）が機械的に処理するもの:**

- severity → 日本語ラベル / color の決定（`要修正`/`vivid-red`、`オススメ`/`vivid-blue`、`ちょっと\n気になる`/`vivid-green`、`いいね`/`pastel-green`）
- reviewer 別アニメプールからの選択とローテーション
- バッジ URL の構築と rationale 先頭への prepend
- `suggestion` フィールドの末尾追記（`**改善案:** ...`）

バッジ URL ビルド規則の正典は `shared/rules/review-badges.md` を参照。
````

- [ ] **Phase 6-2 の API 投稿節に「Phase 4-7 で整形済みの comments[] を使う」旨を追記**

検索キー: `### 6-2. コメントJSONの構築と投稿`

旧の節冒頭に以下の 1 段落を挿入する（heredoc のコード例は据え置き）:

旧（冒頭）:

```markdown
### 6-2. コメントJSONの構築と投稿

まずHEAD commit SHAを取得する:
```

新（冒頭）:

```markdown
### 6-2. コメントJSONの構築と投稿

`comments[]` は Phase 4-7 で整形済み（バッジ prepend、rationale 展開、suggestion 末尾追記まで完了）の状態でこのフェーズに渡る。`file == null` の finding はここで投稿しない（Phase 4-7 で除外済み、Phase 6-3 のユーザー報告に列挙する）。

まずHEAD commit SHAを取得する:
```

### Step 4-3: Task 1-4 を atomic にコミット

- [ ] **変更内容を再確認**

Run: `git diff --stat shared/agents/meta-reviewer.md shared/agents/pdm-reviewer.md shared/agents/techlead-reviewer.md shared/skills/pr-review/SKILL.md`

Expected: 4 ファイル分の変更行数が出る

- [ ] **整合性 grep**: reviewer 側に整形系の残骸が無く、pr-review 側に Phase 4-7 が存在することを確認

Run:
```bash
grep -n "mojiemoji\|animation=\|アニメプール" shared/agents/meta-reviewer.md shared/agents/pdm-reviewer.md shared/agents/techlead-reviewer.md
grep -n "4-7" shared/skills/pr-review/SKILL.md
```

Expected:
- 1 行目: マッチなし
- 2 行目: 少なくとも `### 4-7. コメント整形` 行が返る

- [ ] **commit**

```bash
git add shared/agents/meta-reviewer.md shared/agents/pdm-reviewer.md shared/agents/techlead-reviewer.md shared/skills/pr-review/SKILL.md
git commit -m "$(cat <<'EOF'
refactor(pr-review): separate comment formatting from reviewers

reviewer エージェント（meta / pdm / techlead）の出力スキーマを構造化フィールド（title / rationale / suggestion / evidence）に切り替え、コメント整形（バッジ URL 構築・アニメローテ・先頭装飾）を pr-review スキルの新 Phase 4-7 に集約する。これにより:

- バッジ URL ビルド規則の 5 箇所複製を解消（reviewer 側からは消える）
- dedup 統合の特殊ルール「勝った side のアニメをそのまま採用」が不要に
- reviewer prompt から整形指示を削減し、レビュー判断に集中できる構造に
EOF
)"
```

Expected: コミット成功（pre-commit hook が無い前提）

---

## Task 5: review-badges.md を pr-review 専用の参照表に再定義

reviewer から参照されなくなったので、「正典」「sed 一括置換」の運用注意を削除する。

**Files:**
- Modify: `shared/rules/review-badges.md`

### Step 5-1: 冒頭の参照元説明と「sed 一括置換」注意を更新

- [ ] **ヘッダ部分（1-7 行目）を差し替え**

旧:

```markdown
# レビューコメント用バッジ定義（mojiemoji 版）

このドキュメントは **レビューコメント先頭に付ける重要度バッジの正典** です。
`shared/agents/{meta,pdm,techlead}-reviewer.md` と `shared/skills/pr-review/SKILL.md` から参照されます。
URL を変更したい場合はここを更新してから、参照元を `sed` で一括置換してください。

画像生成 API は <https://mojiemoji.jozo.beer/> （Slack 絵文字サイズの PNG / GIF を返す）を利用します。
```

新:

```markdown
# レビューコメント用バッジ定義（mojiemoji 版）

このドキュメントは `pr-review` スキルの **コメント整形フェーズ（Phase 4-7）専用の参照表** です。reviewer エージェント（`meta-reviewer` / `pdm-reviewer` / `techlead-reviewer`）は構造化フィールド（`title` / `rationale` / `suggestion` / `evidence`）のみを返すため、reviewer 側からはこのドキュメントを参照しません。

URL を変更したい場合は、このドキュメントと `shared/skills/pr-review/SKILL.md` Phase 4-7 のアルゴリズム内のマッピング表の 2 箇所を更新します。

画像生成 API は <https://mojiemoji.jozo.beer/> （Slack 絵文字サイズの PNG / GIF を返す）を利用します。
```

### Step 5-2: reviewer 別 URL 例示節を簡素化

reviewer 別の URL 例示 4 セット（meta-reviewer / pdm-reviewer / techlead-reviewer の各セクション）は冗長なため、1 つの汎用例にまとめる。

- [ ] **`## バッジ URL 一覧` セクション全体を差し替え**

旧（48-78 行目）:

````markdown
## バッジ URL 一覧

各エージェントが finding[].body の先頭に貼る Markdown 画像参照は、ベース（i=0）の例を以下に示す。
ローテーション枠（i ≥ 1）では URL の `animation=` 部分のみ差し替える。

### meta-reviewer（ベース: shuchusen / プール: shuchusen → bure → gatagata → poyoon）

```markdown
![要修正](https://mojiemoji.jozo.beer/emoji/要修正?color=vivid-red&animation=shuchusen&font=gothic-bold)
![オススメ](https://mojiemoji.jozo.beer/emoji/オススメ?color=vivid-blue&animation=shuchusen&font=gothic-bold)
![ちょっと気になる](https://mojiemoji.jozo.beer/emoji/ちょっと%0A気になる?color=vivid-green&animation=shuchusen&font=gothic-bold)
![いいね](https://mojiemoji.jozo.beer/emoji/いいね?color=pastel-green&animation=shuchusen&font=gothic-bold)
```

### pdm-reviewer（ベース: yoko_scroll / プール: yoko_scroll → mochimochi → bane → shuchusen → poyoon）

```markdown
![要修正](https://mojiemoji.jozo.beer/emoji/要修正?color=vivid-red&animation=yoko_scroll&font=gothic-bold)
![オススメ](https://mojiemoji.jozo.beer/emoji/オススメ?color=vivid-blue&animation=yoko_scroll&font=gothic-bold)
![ちょっと気になる](https://mojiemoji.jozo.beer/emoji/ちょっと%0A気になる?color=vivid-green&animation=yoko_scroll&font=gothic-bold)
![いいね](https://mojiemoji.jozo.beer/emoji/いいね?color=pastel-green&animation=yoko_scroll&font=gothic-bold)
```

### techlead-reviewer（ベース: chuuou_zoom / プール: chuuou_zoom → gatagata → bure → shuchusen → poyoon）

```markdown
![要修正](https://mojiemoji.jozo.beer/emoji/要修正?color=vivid-red&animation=chuuou_zoom&font=gothic-bold)
![オススメ](https://mojiemoji.jozo.beer/emoji/オススメ?color=vivid-blue&animation=chuuou_zoom&font=gothic-bold)
![ちょっと気になる](https://mojiemoji.jozo.beer/emoji/ちょっと%0A気になる?color=vivid-green&animation=chuuou_zoom&font=gothic-bold)
![いいね](https://mojiemoji.jozo.beer/emoji/いいね?color=pastel-green&animation=chuuou_zoom&font=gothic-bold)
```
````

新:

````markdown
## バッジ URL 一覧

`pr-review` Phase 4-7 が組み立てる Markdown 画像参照は次の形式を取る:

```text
![{ラベル}](https://mojiemoji.jozo.beer/emoji/{ラベル}?color={color}&animation={animation}&font=gothic-bold)
```

severity ごとの `{ラベル}` / `{color}` は上記「severity → ラベル / color」表、reviewer 別 `{animation}` は「エージェント → アニメーション」表に従う。例（`techlead-reviewer` の i=0、severity=must）:

```markdown
![要修正](https://mojiemoji.jozo.beer/emoji/要修正?color=vivid-red&animation=chuuou_zoom&font=gothic-bold)
```
````

### Step 5-3: 重複統合時のルール節を Phase 4-7 ベースに書き換え

- [ ] **`## 重複統合時のルール` セクションを差し替え**

旧:

```markdown
## 重複統合時のルール

`pr-review` Phase 4-5 で複数エージェントの findings を 1 コメントに統合するとき、バッジは **重要度が高い側のもの（=そのエージェントの確定済みアニメ）** を採用する。重要度が同じ場合は、より具体的な指摘を出した側（通常は techlead）のバッジを採用する。

ローテーションは **エージェント側で finding 生成時に確定済み**なので、統合フェーズで再計算しない。「勝った side のバッジをそのまま使う」だけでよい。
```

新:

```markdown
## 重複統合とバッジ

`pr-review` Phase 4-5 で複数エージェントの findings を 1 finding に統合するとき、`reviewer` フィールドは重要度が高い側のものを採用する（重要度が同じ場合は通常 `techlead-reviewer` を採用）。

バッジ・アニメは Phase 4-7 の整形時に、勝った `reviewer` 名と「Phase 4-7 内での出現順 i」から `pool[i % len(pool)]` で決定する。reviewer 側で事前確定する必要はない。
```

### Step 5-4: ローテーション規則節を Phase 4-7 ベースに書き換え

- [ ] **`### ローテーション規則` セクションを差し替え**

旧:

```markdown
### ローテーション規則

エージェントは finding を出力するとき、自分の **finding 出力順インデックス `i` (0-indexed)** に対して `pool[i % len(pool)]` のアニメを採用する。

- `i = 0`（1 件目）は必ずベース。findings が 1 件のみのときも識別性が確保される。
- `i = 1, 2, ...` は順にローテーション枠を消費。プールを使い切ったら先頭に戻る。
- ローテーション値は **エージェント側で finding 生成時に確定**させる。`pr-review` の dedup 統合で勝った side のアニメをそのまま採用し、tiebreak のたびに再計算しない。
- severity（must/suggestion/nit/good）はアニメ選択に影響しない。色とラベルだけが severity を表す。
```

新:

```markdown
### ローテーション規則

`pr-review` Phase 4-7 が、dedup・ソート後の `findings[]` を走査しながら **reviewer 名ごとに別カウンタ `i` (0-indexed)** を進め、`pool[i % len(pool)]` でアニメを決定する。

- `i = 0`（その reviewer の 1 件目）は必ずベース。findings が 1 件のみのときも識別性が確保される。
- `i = 1, 2, ...` は順にローテーション枠を消費。プールを使い切ったら先頭に戻る。
- severity（must/suggestion/nit/good）はアニメ選択に影響しない。色とラベルだけが severity を表す。
- reviewer エージェントは i を意識する必要が無い（出力時点ではバッジを付けない）。
```

### Step 5-5: commit

- [ ] **commit**

```bash
git add shared/rules/review-badges.md
git commit -m "$(cat <<'EOF'
docs(review-badges): redefine as pr-review-only reference

reviewer エージェント側からのバッジ URL 参照を Phase 4-7 移行で削除したため、本ドキュメントを「pr-review スキルのコメント整形フェーズ専用の参照表」に再定義する。reviewer 別 URL 例示 4 セットを 1 つの汎用例に集約し、「sed 一括置換」の運用注意も削除した。
EOF
)"
```

Expected: コミット成功

---

## Task 6: juggernaut SKILL.md の整合確認

事前 grep で `body` / `バッジ` / `アニメ` への参照が無いことは確認済み。ただし `mode` フィールドの記述や reviewer 出力の取り扱い箇所が新スキーマで違和感ないか目視確認する。**変更が必要なければコミットなし**。

**Files:**
- Modify (場合により): `shared/skills/juggernaut/SKILL.md`

### Step 6-1: 監査

- [ ] **再 grep で `body` への暗黙参照がないか確認**

Run: `grep -n "body\|バッジ\|badge\|アニメ\|integratiom-formatted\|rationale" shared/skills/juggernaut/SKILL.md`

Expected: 出力なし、または `rationale` のような新スキーマフィールドへの言及のみ

- [ ] **Phase 5-1 / 5-2 の reviewer 出力扱い箇所を目視確認**

Run: `sed -n '225,285p' shared/skills/juggernaut/SKILL.md`

Expected: `findings[]` / `severity` / `mode` のみ参照されており、整形系（`body` / バッジ）への依存が無いこと

- [ ] **判断**: 整形系への依存が無いことを確認できれば変更不要としてスキップ（commit せず Task 7 へ進む）。違和感があった箇所のみ最小限の修正を入れる

### Step 6-2: 必要なら微修正してコミット

- [ ] **修正が発生した場合のみ実行**

```bash
git diff shared/skills/juggernaut/SKILL.md
git add shared/skills/juggernaut/SKILL.md
git commit -m "$(cat <<'EOF'
docs(juggernaut): align with new reviewer output schema

reviewer 出力スキーマの構造化（title / rationale / suggestion / evidence）に合わせ、juggernaut セルフレビューの reviewer 出力消費箇所の表現を整える。整形フェーズは pr-review にしか無いため、juggernaut は構造化フィールドを直接消費する旨を明示する。
EOF
)"
```

修正が無ければこの step はスキップする。

---

## Task 7: dotter deploy と e2e 動作確認

シンボリックリンクで参照されている `~/.claude/agents`, `~/.claude/skills` が最新版を指している必要がある。dotter は symbolic link なので通常は自動反映だが、念のため確認する。

**Files:**
- None (運用確認)

### Step 7-1: dotter のシンボリックリンク確認

- [ ] **デプロイ状態を確認**

Run:
```bash
ls -la ~/.claude/agents | head -20
ls -la ~/.claude/skills | head -20
```

Expected: それぞれが `/Users/sp_user/git/personal.github.com/hondazn/aimod/shared/agents` / `.../shared/skills` への symlink になっている

- [ ] **symlink で参照していれば、ファイル内容の最新化は dotter deploy 不要**

Run: `head -5 ~/.claude/skills/pr-review/SKILL.md`

Expected: 編集後の内容（`name: pr-review` / `description: ...`）が表示される

symlink でなくコピーされている場合は `dotter deploy` を実行する。

### Step 7-2: 実 PR で pr-review を走らせる

- [ ] **動作確認対象の PR を選定**

直近 OPEN な PR を 1 件用意する。`gh pr list -L 5 --state open` で候補を確認し、変更規模が小〜中（差分 500 行以内、ファイル 10 個以内）のものを選ぶ。

- [ ] **pr-review 実行（手動 / claude セッション内で）**

`/pr-review <PR番号>` を実行する。ただし e2e 確認なので、実投稿は伴う点に注意（テスト用 PR を選ぶか、ステージング相当のリポジトリで実施することを推奨）。

- [ ] **検証ポイント**:

| 観点 | 期待 |
|---|---|
| バッジ表示 | severity に応じた色 / ラベルが出ている。アニメ GIF が動いている |
| reviewer 別アニメ | meta-reviewer は `shuchusen`、pdm-reviewer は `yoko_scroll`、techlead-reviewer は `chuuou_zoom` がベース i=0 で出ている |
| ローテーション | 同一 reviewer の 2 件目以降でアニメが変わっている |
| `suggestion` 末尾追記 | finding に suggestion がある場合、本文末尾に `**改善案:** ...` が出ている |
| `title` の非表示 | コメント本文に `title` が現れない（rationale 冒頭で文脈が分かる） |
| `file=null` finding | GitHub にコメントとして投稿されず、ユーザーへの最終報告に列挙されている |

### Step 7-3: juggernaut セルフレビューを走らせる

- [ ] **適当な作業ブランチで juggernaut Phase 5 セルフレビューを実行**

セルフレビューが構造化フィールド（`severity` / `rationale` / `title`）から正しく判断材料を読み取れているか、claude の最終報告で確認する。

- [ ] **検証ポイント**:

| 観点 | 期待 |
|---|---|
| `must` 検出 | 3 reviewer のいずれかが `must` を返した場合、claude が修正アクションに進む |
| 整形フェーズ非経由 | バッジや mojiemoji URL がセルフレビュー出力に出ない（ユーザー向け中間出力で構造化 finding がそのまま使われている） |
| `mode` 確認 | 各 reviewer の `mode: "self_review"` が確認できる |

### Step 7-4: e2e 確認結果のメモ

- [ ] **結果を spec / plan のレポジトリにメモ**（任意）

問題があれば該当 Task に戻って修正コミットを追加する。問題なければ完了。

---

## Self-Review チェックリスト

実装中に確認すべき点（plan 完了後、merge 前に通すチェック）:

- [ ] **Spec coverage**: 設計ドキュメント `docs/specs/2026-05-14-pr-review-formatting-separation-design.md` の各セクション 1-5 に対応するタスクが本 plan に存在するか
  - Section 1（新 reviewer 出力スキーマ）→ Task 2-4
  - Section 2（pr-review Phase 4-7）→ Task 1 + Task 4-2
  - Section 3（review-badges.md 再定義）→ Task 5
  - Section 4（juggernaut への影響）→ Task 6
  - Section 5（移行戦略）→ Task 1-4 の atomic コミット運用
- [ ] **Placeholder scan**: `TODO` / `TBD` / `implement later` / 「適切な〜」/「必要に応じて〜」のような曖昧表現が plan 内に残っていないか
- [ ] **Type consistency**: 各タスクで参照しているフィールド名（`title` / `rationale` / `suggestion` / `evidence` / `reviewer` / `severity` / `category`）が全タスクで揃っているか
- [ ] **コミット粒度**: dotter で deploy された瞬間にスキル群が整合する単位でコミットされているか（Task 1-4 atomic、その後は個別 OK）
- [ ] **整合性 grep**: `grep -rn "body.*mojiemoji\|body.*animation" shared/` が空であること（reviewer 側に整形残骸が無いこと）
- [ ] **既存のレガシー reviewer（specification / correctness / quality-test / security-perf）への影響なし**: 本 plan は手を入れていないため、CLAUDE.md の記述どおり「未使用・削除候補」のまま据え置く
