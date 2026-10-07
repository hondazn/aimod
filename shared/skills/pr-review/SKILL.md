---
name: pr-review
description: PR の変更を構造的に解説し、汎用のコード品質・安全性観点でレビューして GitHub にコメントする。Phase 6 の投稿（または正規早期終了の明示報告）まで到達して初めて完了する。コード修正はしない（→ resolve-review）。
argument-hint: "[PR番号 例: #123 / 123 / URL]"
allowed-tools:
  - Agent
  - Skill
  - Read(*)
  - Glob(*)
  - Grep(*)
  - Bash(gh:*)
  - Bash(git:*)
  - Bash(ls:*)
  - Bash(jq:*)
  - Bash(sort:*)
  - Bash(kill:*)
  - Bash(ruby:*)
  - Bash(*/mojiemoji_markdown.rb:*)
---

# PRレビュー（汎用）

## ユーザー入力

```text
$ARGUMENTS
```

## 目的と完了条件

PR の変更を構造的に解説し、コード品質・安全性の観点でレビューして GitHub に投稿する。コードは修正しない。

完了は次のどちらかをユーザーへ報告した時点に限る。findings 表・サマリー文面・エージェント出力ができた時点は途中であり、非対話実行でも変わらない。

1. Phase 6 の投稿が成功し、URL を報告した
2. 正規早期終了を理由とともに報告した: PR が `OPEN` でない（1-1）／再レビューガードで停止した（R-2）／`post_approval_mode` で fatal も must もなく、明示依頼でもないため投稿しない（6-1）

---

## Phase 1: PR情報取得

### 1-1. PR番号と基本情報

`$ARGUMENTS` から PR 番号を取る（`#123` / `123` / `https://github.com/{owner}/{repo}/pull/123`）。引数が無ければ `gh pr view --json number --jq '.number'` でカレントブランチの PR を使い、それも無ければユーザーに聞く。

```bash
gh pr view <番号> --json number,title,state,headRefName,baseRefName,url,body,labels,author,reviewRequests
```

取得エラー（存在しない・権限不足）は報告して停止する。`state` が `OPEN` でなければ「このPRは既に{状態}です」と報告して停止する。

リポジトリ（以降の `{owner}/{repo}` にリテラルで埋める）: !`gh repo view --json nameWithOwner --jq '.nameWithOwner'`

自分のログイン名: !`gh api user --jq '.login'`

### 1-2. 既存レビューの確認

```bash
gh api repos/{owner}/{repo}/pulls/<番号>/reviews \
  --jq '[.[] | {user: .user.login, state, body, submitted_at: .submitted_at}]'
```

自分のレビューが1件以上あれば `is_re_review = true` とし、最新のものから `previous_review_state`（`CHANGES_REQUESTED` / `COMMENTED` / `APPROVED`）と `previous_review_body` を記録して、「再レビュー」節の R-1〜R-3 を実行する。無ければ `is_re_review = false`。

### 1-3. 関連Issue

PR本文の `Closes #N` / `Fixes #N` / `Resolves #N` / `Refs #N` / `#N` から Issue を取る。見つからなければ無視して続ける。

```bash
gh issue view <番号> --json number,title,body,labels
```

### 1-4. 変更ファイルと差分

```bash
gh pr view <番号> --json files --jq '.files[] | "\(.path)\t\(.additions)\t\(.deletions)"'
gh pr diff <番号>
```

変更ファイルが30超、または差分が合計2000行超なら、ビジネスロジック（テスト・設定・自動生成より優先）→ 変更量の大きいファイル → 新規ファイルの順に重点対象を選ぶ。

---

## Phase 2: コンテキスト理解

差分だけでなく周辺コードを読む。コードは必ずリモートの PR ブランチ最新版を参照し、比較基準のベースブランチも最新化しておく。

### 2-1. ベースブランチの最新化とレビュー用worktree

本体ツリーの未コミット変更や作業を壊さないよう、`git checkout` / `gh pr checkout` / `git pull` は使わず、fetch と detached の worktree だけで進める。ベースは 1-1 の `baseRefName`（デフォルトブランチとは限らない）。

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
WORKTREE_DIR="$REPO_ROOT/.worktrees/pr-<番号>"
BASE=<baseRefName>
git fetch origin "$BASE"   # origin/$BASE を最新化する
if git show-ref --verify --quiet "refs/heads/$BASE"; then
  # ローカルの $BASE は fast-forward できるときだけ進める。checkout 中・分岐ありなら git が拒否するので、その旨を報告して続行する
  git fetch origin "$BASE:$BASE"
fi
git fetch origin "pull/<番号>/head"   # FETCH_HEAD を PR の HEAD にするため最後に取る
if git worktree list --porcelain | grep -q "^worktree $WORKTREE_DIR$"; then
  git -C "$WORKTREE_DIR" reset --hard FETCH_HEAD   # 既存なら最新に合わせ直す
else
  git worktree add --detach "$WORKTREE_DIR" FETCH_HEAD
fi
```

- `WORKTREE_DIR` は絶対パスで保持し、Read/Glob/Grep とエージェントへの prompt にそのまま使う。`cd` はしない
- ベース側のコードは `origin/$BASE` で見る（例: `git show "origin/$BASE:<path>"`）。「この PR が持ち込んでいない既存の問題」（4-4）かどうかはここで確かめる
- worktree の作成に失敗したら状況を報告して停止する。`--force` や強制削除は使わない

### 2-2. 周辺コード

差分から必要な範囲だけ `$WORKTREE_DIR` 配下で読む。関数シグネチャの変更なら呼び出し元、型定義なら使用箇所、インターフェースなら実装箇所、インポート追加なら依存先の API を確認する。

### 2-3. プロジェクト規約

`CLAUDE.md` / `.cursorrules` 等、`CONTRIBUTING.md`、`.github/pull_request_template.md` があれば読む。

---

## Phase 3: 変更内容の構造的解説

良し悪しは判断せず、何が変わったかだけを解説する。

1. **変更内容**: 追加/変更/削除されたファイル（各1行の主旨つき）と型・関数・クラス、それぞれの目的
2. **設計意図の推論**: 解決する課題、選んだアプローチとその理由、スコープ（含むもの・含まないもの）。不確かな点は「〜と読めますが、意図が違ったら教えてください」と確認を促す
3. **影響分析**: 直接依存しているコードと、API・スキーマ変更などによる間接影響
4. **着眼点**: PRの文脈に即したオープンクエスチョンを3〜5個

---

## Phase 4: コードレビュー

変更ファイルだけを対象に、Phase 2-3 の規約も加味する。些末な指摘を量産するより重要な問題を正確に指摘する。「テックリードとしてマージを承認する立場で何が気になるか」で考える。

### 4-1. Lead がレビューし、足りない視点だけ外注する

親が Lead。Phase 1–3 で Issue・PR本文・diff を読んだ親が、方向性と致命を自分で書く。親の finding の `reviewer` は `"lead"` で、親は `fatal` を付けてよい。

レビュー用サブエージェントの既定は **0体**。`meta-reviewer` はレビュー経路では起動しない（`self_review` 用に定義は残す）。追加起動は、親が「自分では判断できない」と1文で言えるときだけ:

| 条件 | 起動 | 上限 |
|---|---|---|
| 通常 | なし | 0 |
| 親が欠けている視点を1文で名付けた | そのスペシャリスト（プールは `consult-specialists` と同じ12体。重なる候補は代表1体） | 合計 2 |
| 認可・秘密情報・データ消失の差分があり、親が fatal 候補に自信がない | `fatal-reviewer` | 別枠 1 |

| 差分の兆し | 候補 |
|---|---|
| テスト / AC / 仕様記述 | `qa` |
| auth / 権限 / 秘密情報 / 公開 API | `safety-skeptic` |
| 障害・リトライ・監視・デプロイ | `failure-pessimist` |
| UI / 文言 / オンボーディング | `taste` or `friction-maximalist` |
| 大きな構造変更 / 新モジュール | `architect` or `tech-lead` |
| 暫定フラグ・二重実装 | `debt-auditor` |
| 計測・ログ追加 | `data-realist` |

選定をユーザーへ「親レビュー / 追加: …（理由）」と一行報告する。追加が無ければ「親レビュー / 追加: なし」とし、4-2 を飛ばして 4-3 へ進む。

自動検査が緑でも検証されない面は Lead が読む:

- 追加・変更された散文（コメント・文書・PR本文・エラーメッセージ）が意味を成し、事実と合うか
- 挙動を変えたのに README・コメント・スキーマ記述が同じ差分で更新されていなければ finding にする
- 命名と抽象の妥当性

**重要度:**

| 重要度 | 意味 | 付けられる者 |
|---|---|---|
| **fatal** | マージしたら本番・契約・利用者を壊す。唯一のマージブロック | `lead` と `fatal-reviewer` のみ |
| **must** | 正しく動作しない、セキュリティリスク、要件未充足 | 全員 |
| **suggestion** | より良い実装がある | 全員 |
| **nit** | typo・スタイル統一などの些細な点 | 全員 |
| **good** | 良い実装、学びになるパターン | 全員 |

**finding の書き方:** 親も追加レビュアーも 4-2 の JSON と同じフィールドで書く。`rationale` は次を守る（バッジと改善案の配置は 4-6 が行う）。

- ですます調で、何が問題で何をすべきかを根拠つきで言い切る。良い例「ここ、nullが来るとクラッシュします。チェックを入れてください」、悪い例「null参照の可能性が検出されました。適切なバリデーションの実装が推奨されます」
- must/suggestion では「〜かも」「〜な気がします」を使わない。柔らかい表現は nit だけ
- 改善案は `suggestion` フィールドに分ける
- ごくたまに文末へ絵文字を1つ添えてよい（👀 注目 / 👍 賛同 / 🎉 称賛 / ⚠️ リスク / 💡 提案 / 🙏 感謝）。「!」は称賛・感謝など肯定的な文脈だけで使う

### 4-2. 追加レビュアーの並列起動

4-1 で選んだレビュアーを同一メッセージで並列起動する（`subagent_type` は `shared/agents/` の名前）。prompt には原則すべてを渡す: PR情報（番号・URL・タイトル・ブランチ・作成者）、PR本文、関連Issue、Phase 3 の設計意図、変更ファイルと主旨、`gh pr diff` 全文、規約、コード参照ルート `$WORKTREE_DIR`（本体ツリーは読まないと明示）。PR番号と URL を含めると各エージェントは `pr_review` モードで動く。再レビュー時は R-4 の指示も付ける。

スペシャリストはネイティブの出力が Markdown 散文なので、prompt 末尾に次を付けて JSON を優先させる:

```text
## 期待する出力（必須・自エージェント定義の Markdown 出力フォーマットより優先する）
助言モード。次の JSON 以外を出力しない:
{"reviewer": "<your-name>", "mode": "pr_review", "note": null, "findings": [
  {"file": null, "line": null, "side": "RIGHT", "start_line": null, "start_side": null,
   "severity": "must|suggestion|nit|good（fatal は付けない）",
   "category": "<自分の専門領域の短いカテゴリ名>",
   "badge_label": "合計15文字以内 / 1行5文字以内 / 改行2回まで / 日本語主体",
   "title": "1行要約", "rationale": "根拠つきの説明（ですます調）",
   "suggestion": "改善案 or null", "evidence": "参照元 or null"}]}
行レベルの指摘は file/line を埋め、PR全体への指摘は file: null。バッジ URL や重要度マークは付けない。0件なら findings: []。
```

フィールドの詳しい意味は `shared/agents/meta-reviewer.md` の「フィールド仕様」節と同じ。

### 4-3. 結果の統合

- 親の finding と各エージェントの `findings[]` を平坦化し、エージェント由来には出所名（例: `"fatal-reviewer"`）を `reviewer` に入れる。4-6 のアニメ選択に使う
- `lead` と `fatal-reviewer` 以外が返した `fatal` は `must` に降格する
- **完全重複**（同一ファイル・行番号差5行以内・内容が実質同一）→ 重要度の高い方を残す。同点なら `lead` → `fatal-reviewer` → その他の順で採る
- **部分重複**（同一ファイル・行番号差5行以内・観点が異なる）→ `rationale` / `suggestion` / `evidence` を1件にまとめ、重要度は最も高いもの、`reviewer` は高重要度側（同点は `lead`）
- 再レビュー時は R-4 の除外も適用する
- fatal → must → suggestion → nit → good、同一重要度内はファイルパス順に並べる

### 4-4. Lead 判定（投稿フィルタ）

親は中立な集計係ではない。各 finding に判定を1つ付ける。重要度は変えない。

| 判定 | 意味 | GitHub | ユーザー報告 |
|---|---|---|---|
| **Act on** | 正しさ・安全・今の目的に照らして手を入れる | 投稿する（R-4 の閾値も適用） | 出す |
| **Consider** | 妥当だが、今直すコストに見合うか不明 | 初回レビューの must/suggestion だけ投稿する | 出す |
| **Noted** | 妥当だが今は動かさない | 出さない | 件数と一行 |
| **Dismissed** | 誤り・文脈違い・揚げ足 | 出さない | 捨てた理由を一行（覆せるように） |

Dismissed の典型は、lint・型・テストが既に落とす指摘、この PR が持ち込んでいない既存の問題、リポジトリ規約が既に決めている好みの差。較正は「この指摘で作者が実際に手を動かすか」の1問に置く。

### 4-5. 検出結果の整理

判定列つきの表にまとめる。「問題の内容」は `title` をそのまま転記する。0件ならその旨を報告し、Phase 5 で APPROVE のサマリーだけ作る。

```text
| # | ファイル:行 | 問題の内容 | 重要度 | 判定 | 観点 | ソース |
|---|-----------|-----------|--------|------|------|--------|
| 1 | src/foo.rs:42 | 認可チェックが抜けていて他ユーザーのデータが読める | fatal | Act on | 致命 | lead |
| 2 | crates/app/src/bar.rs | AC #3 のシナリオに対応するテストが存在しない | must | Consider | テスト網羅性 | qa |
| 3 | （PR全体） | 既存の `lib/auth/middleware.rs` と同じ機能を再実装している | suggestion | Noted | 方向性 | lead |
```

ここはスキルの中間地点。表ができても止まらず Phase 5 へ進む。

### 4-6. コメント整形

投稿対象の finding から GitHub Reviews API の `comments[]` を組み立てる。バッジ（ラベル検証・色・アニメ・ヘルパー呼び出し）は `REVIEW-BADGES.md` に従う。URL は手書きしない。

1. `Skill` ツールで `mojiemoji-github:mojiemoji-github` を読み込み、`REVIEW-BADGES.md` の手順でヘルパーのパスを確定する
2. `file == null` の finding は `comments[]` に載せず（API が `path` 必須）、6-3 の報告に「PR レベル所感」として列挙する
3. 残りを並び順に走査し、`body = バッジ + "\n\n" + rationale`、`suggestion` があれば末尾に `"\n\n**改善案:** " + suggestion` を足す。`title` は本文に出さず、`rationale` は装飾しない
4. `{"path", "line", "side"（既定 "RIGHT"）, "body"}` を追加する。`start_line` / `start_side` があれば入れる

---

## Phase 5: レビューサマリー

サマリーは Reviews API の `body` として投稿する。テックリードとしてのマージ判断と PR 全体の評価を伝える場で、個別の指摘はインラインが担う。

**構成:**

1. 冒頭の一文でマージ判断を示す。fatal があれば「修正が必要です」、無ければ「マージしてOKです」。must だけなら「気になる点はありますが、マージ自体は問題ありません」のようなトーン
2. fatal/must があれば問題の **領域** には触れてよい（「エラーハンドリング周りに気になるところがあります」）。具体的な指摘内容はインラインに任せる
3. 設計方針の議論が必要なときだけ補足する
4. 全体で1〜4行。件数の統計表・Markdown 見出し・「詳細はインラインで」のような言及は書かない

**文の型:** 直近のレビューと違う型を選ぶ。「印象から入る + ただ、」の連続は避ける。

- 判断から入る: 「問題ありません。マージしてOKです。テストも十分です。」
- 変更の核心から入る: 「キャッシュ戦略の見直し、設計・実装ともに良いです。」
- 端的に評価する: LGTM バッジだけ（APPROVE 時）
- 修正要求から入る: 「並行処理周りに修正が必要です。修正してからマージしましょう。」

| ルール | NG | OK |
|--------|-----|-----|
| 冗長な前置きを入れない | 「PRの変更内容を確認しました。全体として〜」 | 「設計・実装ともに良さそうです。」 |
| 件数で語らない | 「must: 2件を検出しました」 | 「2点ほど直したほうがよさそうなところがあります」 |
| 敬語は軽めに | 「ご修正いただけますと幸いです」 | 「直してもらえると助かります」 |
| 判断を明確にする | 「問題がある可能性が考えられます」 | 「ここはバグです。修正してください」 |
| 絵文字・!は控えめに | 「LGTM 🎉👍✨」 | 「LGTM 🎉」 |

**LGTM バッジ:** イベントが `APPROVE` のときだけ、テキストの LGTM の代わりに mojiemoji の LGTM バッジを本文に入れる。`mojiemoji-selector` サブエージェントに `REVIEW-BADGES.md` の契約で依頼し、返った `<img>` をそのまま貼る。`COMMENT` / `REQUEST_CHANGES` には付けない。

投稿前に確かめる: インラインと同じ指摘を繰り返していないか、初回なのに「前回」に触れていないか（再レビューなら R-5 に沿っているか）、同僚に口頭で伝えて不自然でないか。

---

## Phase 6: GitHub投稿

### 6-1. レビューイベント

| 条件 | イベント |
|------|---------|
| 投稿対象に fatal がある | `REQUEST_CHANGES` |
| fatal なし、must/suggestion/nit がある | `COMMENT` |
| fatal なし、good のみ / 指摘なし | `APPROVE` |

マージブロックは fatal の有無だけで決まり、must 単独では `REQUEST_CHANGES` にしない。

`post_approval_mode` のときは上の表より次を優先する:

| 条件 | イベント |
|------|---------|
| fatal または must がある | `COMMENT`（`REQUEST_CHANGES` にしない。must を握り潰さない） |
| どちらも無く、`is_requested_re_review == true` | `APPROVE` |
| どちらも無く、`is_requested_re_review == false` | **投稿しない**（正規早期終了。ユーザーにだけ報告） |

### 6-2. 投稿

```bash
gh pr view <番号> --json headRefOid --jq '.headRefOid'

gh api repos/{owner}/{repo}/pulls/<番号>/reviews --method POST --input - <<'EOF'
{
  "event": "COMMENT",
  "body": "レビューサマリー本文",
  "commit_id": "<HEAD SHA>",
  "comments": [
    {"path": "src/xxx.rs", "line": 42, "side": "RIGHT", "body": "<バッジ>\n\nコメント内容"}
  ]
}
EOF
```

- `line` は変更後ファイルの行番号。`side` は原則 `"RIGHT"`、削除行だけ `"LEFT"`。複数行なら `start_line` / `start_side` も入れる
- heredoc は `<<'EOF'` で展開を止め、SHA などはリテラルで埋める
- 422（行が diff 範囲外など）→ 該当コメントを外して再試行し、外したものを報告する。403 → 権限不足を報告して停止。その他 → 内容を報告して停止

### 6-3. 完了報告

PR番号とタイトル、イベント、重要度別のコメント件数、Lead 判定の件数（Act on / Consider / Noted / Dismissed）、追加レビュアー（無ければ「追加: なし」）、URL（投稿成功時は必須）、PR レベル所感、バッジのフォールバック件数。再レビュー時は理由別の抑制件数とレビューラウンドも。投稿しなかった場合はそれが 6-1 の正規早期終了であることを明示する。一部失敗は成功と失敗を分けて書く。

### 6-4. worktreeの後始末

投稿しなかった場合も、途中で失敗して停止する場合も `git worktree remove "$WORKTREE_DIR"` で消す（残すと次回に古い HEAD を読む）。未コミット変更などで失敗したら `--force` は使わず、状態を示して判断を仰ぐ。

---

## 再レビュー（`is_re_review == true` のとき）

作者は前回の指摘に対応済みで、同じ箇所への繰り返し指摘は技術的な問題以上に負担になる。diff 全体は読むが投稿基準を上げる。

### R-1. 明示依頼の判定

次のどちらかなら `is_requested_re_review = true`、どちらでもなければ `false`:

1. 1-1 の `reviewRequests` に自分のログイン名がある（re-request review された）
2. `$ARGUMENTS` が「レビューして」「再レビュー」「もう一度レビュー」「review」「re-review」のようにレビュー実行を求めている。「この部分だけ見て」のような部分的な確認依頼は含めない

### R-2. ガード

| 明示依頼 | 前回 | 前回までの自分のレビュー数 | 動作 |
|---|---|---|---|
| あり | `APPROVED` | any | `post_approval_mode = true` で続行（確認しない） |
| あり | その他 | any | 続行 |
| なし | `APPROVED` | any | 「このPRは既にAPPROVEしています」と報告して停止。ユーザーが再レビューを指示したときだけ `post_approval_mode = true` で続行 |
| なし | その他 | 1 | 続行 |
| なし | その他 | 2以上 | 作者の負担を考えてユーザーに確認し、指示がなければ停止 |

### R-3. 既存コメントの収集

```bash
gh api graphql -f query='
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviewThreads(first: 100) {
        nodes {
          isResolved
          isOutdated
          path
          line
          comments(first: 50) { nodes { body, author { login }, createdAt } }
        }
      }
    }
  }
}' -f owner='{owner}' -f repo='{repo}' -F number=<PR番号>
```

- `my_previous_comments`: 自分のコメント
- `other_comments`: 自分以外（bot 含む）のコメントのうち `isResolved == false` かつ `isOutdated == false` のもの。解決済みスレッドは含めない（問題の再発を拾えるように）

### R-4. 投稿基準

| モード | 投稿する | 抑制（件数だけ報告） |
|---|---|---|
| 初回 | fatal, must, suggestion, nit, good | なし |
| 再レビュー | fatal, must, suggestion | nit, good |
| `post_approval_mode` | fatal, must | suggestion, nit, good |

- 自分が指摘済み（同一ファイル・行番号差5行以内・同種）の問題は再指摘しない。`other_comments` と実質同一のものも除外する
- 前回の指摘と矛盾する finding（前回「Aにすべき」→ 今回「Aにすべきでない」）は投稿せず、「前回の指摘と矛盾する可能性があります」とユーザーに相談する
- 前回指摘に沿って直された箇所への新しい指摘は fatal/must のときだけ。suggestion/nit で追い打ちしない
- 前回の指摘が直ったかは暗黙に確かめ、個別の「修正確認しました」コメントは書かない
- 指摘は最大3件に絞り、それを超えるならユーザーに確認する
- 追加レビュアーの prompt には `my_previous_comments` と「これは再レビューです。前回の指摘と矛盾する指摘や、指摘済みの問題の再指摘はしないでください。」を付ける。`post_approval_mode` なら「APPROVE後の再レビューです。fatal / must レベルの問題だけ報告してください。」も付ける

### R-5. サマリー

1〜2行に収め、「前回のレビューでは〜」のような振り返りはしない。fatal も must もなければ「修正確認しました。<LGTM バッジ>」程度で十分。冒頭のトーン:

| 前回 | 今回 | トーン |
|---|---|---|
| `CHANGES_REQUESTED` | fatal なし | 前回の致命が解消したことを認め、肯定的に |
| `CHANGES_REQUESTED` | fatal あり | まだマージできない致命がある旨を端的に |
| `COMMENTED` | fatal なし | 引き続き良い旨を |
| `COMMENTED` | fatal あり | 新たに致命的な点が見つかった旨を |
| `APPROVED` | fatal あり | APPROVE 後に致命的な点に気づいた旨を丁寧に |
| `APPROVED` | fatal・must なし | 明示依頼なら肯定的に（明示依頼でなければ投稿しない） |
| `APPROVED` | fatal なし・must あり | 気になる点が見つかった旨を端的に（`COMMENT` なので LGTM バッジは付けない） |

---

## 完了前チェック

最終報告の直前に確かめる。1つでも「いいえ」なら該当箇所へ戻って続ける。

1. 6-2 の投稿を実行したか、または正規早期終了を確定したか
2. それに対応する 6-3 の報告を書いたか
3. 6-4 の worktree 後始末を実行したか（失敗なら状態を伝えるか）
4. findings 表やサマリー文面を完了報告と取り違えていないか
