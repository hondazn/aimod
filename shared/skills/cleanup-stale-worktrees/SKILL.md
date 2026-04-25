---
name: cleanup-stale-worktrees
description: リモートで削除済みのブランチに紐付いたローカルの git worktree を安全に検出・削除する。「マージ済み worktree を消したい」「stale worktree を整理して」「remote から消えたブランチの worktree をクリーンアップ」といったリクエストで使用する。既定は dry-run で、未コミット変更や未 push commit を持つ worktree は保護される。
allowed-tools:
  - Bash(git fetch:*)
  - Bash(git worktree:*)
  - Bash(git branch:*)
  - Bash(git ls-remote:*)
  - Bash(git status:*)
  - Bash(git rev-list:*)
  - Bash(git rev-parse:*)
  - Bash(git for-each-ref:*)
  - Bash(git remote:*)
---

# Cleanup Stale Worktrees - リモート削除済みブランチの worktree 整理

PR がマージされてリモート (`origin/<branch>`) から削除されたブランチに紐付くローカルの git worktree を検出し、安全に削除する。

**核となる安全方針**:

1. **dry-run 既定** — 実行コマンド `cleanup-stale-worktrees` 単体では削除しない。一覧と判定理由を表示するのみ
2. **保護優先** — 未コミット変更・未 push commit・detached HEAD・リモート確認失敗、いずれかに該当する worktree は削除候補から外す
3. **メイン worktree 除外** — リポジトリ本体（`git rev-parse --git-common-dir` の親）は対象外

## 現在の状態（自動取得）

### worktree 一覧

!`git worktree list --porcelain`

### remote とデフォルト remote 名

!`git remote -v | head -4`

### 直近の fetch 状態

!`git for-each-ref --format='%(refname:short) %(upstream:short)' refs/heads | head -20`

## いつ使うか

- マージ済み PR のブランチが `origin` から削除されたが、ローカル worktree が残っている
- `git worktree list` の出力が膨らみ、どれが現役か分からない
- ディスクや一覧の整理を一括で済ませたい

**使わない場面**:

- リモートブランチ自体を削除したい → `git push origin --delete <branch>`（このスキルは読み取り専用）
- 新しい worktree を作りたい → `superpowers:using-git-worktrees`
- worktree が壊れて `git worktree remove` でも消えない → `git worktree repair` / `prune` を先に試す

## 引数仕様

```
cleanup-stale-worktrees [--apply] [--force] [--keep-branch] [--remote <name>]
```

| フラグ | 効果 |
|--------|------|
| なし（既定） | dry-run。削除候補と保護理由を表示するのみ |
| `--apply` | 保護対象でない候補を実削除する |
| `--force` | dirty・未 push commit を持つ worktree も含めて削除（`git worktree remove --force`）。`--apply` と併用 |
| `--keep-branch` | worktree のみ削除し、ローカルブランチ参照 `refs/heads/<branch>` は残す |
| `--remote <name>` | 判定に使う remote 名。既定は `origin` |

破壊的なフラグ（`--force`）を伴う場合、対象一覧をユーザーに提示してから実行する。

## ワークフロー

### Step 1: 最新状態の取得

```bash
REMOTE="${REMOTE:-origin}"
git fetch --prune "$REMOTE"
```

`--prune` でローカルの `refs/remotes/<remote>/<branch>` から削除済みブランチを取り除く。判定の信頼性に必須。

### Step 2: worktree とブランチの突合

`git worktree list --porcelain` をパースし、各 worktree について以下を抽出:

- `worktree <path>` — ディレクトリパス
- `HEAD <sha>` — 現在の HEAD
- `branch refs/heads/<name>` — チェックアウト中のブランチ（detached の場合は欠落）
- `bare` / `detached` — 状態フラグ

メイン worktree（`git rev-parse --show-toplevel` の出力に一致）は除外する。

各 worktree のブランチについて:

```bash
if git ls-remote --exit-code --heads "$REMOTE" "$BRANCH" >/dev/null 2>&1; then
    # remote にまだ存在する → 対象外
else
    # remote から消えている → 候補に追加
fi
```

`git ls-remote` は実際にリモートへ問い合わせるため、`fetch --prune` を忘れていても正しく判定できる。

### Step 3: 保護判定

各候補について以下を順に判定し、いずれかに該当すれば**保護**（削除候補から除外、ただし dry-run の出力には保護理由付きで表示）:

| 判定 | コマンド | 保護理由 |
|------|---------|---------|
| detached HEAD | `branch` 行が無い worktree | `detached: ブランチ未チェックアウト` |
| upstream 未設定 | `git -C "$WT" rev-parse --abbrev-ref "@{upstream}" 2>/dev/null` が失敗 | `no-upstream: 追跡先なし` |
| dirty | `git -C "$WT" status --porcelain` が非空 | `dirty: 未コミット変更あり` |
| 未 push commit | `git -C "$WT" rev-list --count "@{upstream}..HEAD"` が `0` 以外 | `unpushed: N commits ahead of upstream` |

`--force` は **dirty** と **unpushed** の保護を解除する。`no-upstream` と `detached` は `--force` でも解除しない（意図せず孤立した作業を消す事故を防ぐため）。

#### upstream ref が prune されているケース

`git fetch --prune` で `refs/remotes/<remote>/<branch>` が削除されると、`@{upstream}` 名は branch.\<name\>.merge 設定値から解決できる（`rev-parse --abbrev-ref` は成功）が、`rev-list @{upstream}..HEAD` は ref を解決できず失敗する。

これは **PR がマージされて remote から削除された典型ケース** であり、削除候補として扱う。ただし「未 push commit 判定」が成立しないため、出力に `(upstream ref pruned)` のノートを付けてユーザーに目視確認を促す。

実装上は `rev-list` 失敗時に `unpushed=0` を代入し、ノートだけ出す:

```bash
local note=""
if ! unpushed="$(git -C "$current_path" rev-list --count "@{upstream}..HEAD" 2>/dev/null)"; then
    unpushed=0
    note=" (upstream ref pruned — verify no orphan local commits)"
fi
```

注意: このパスを通る worktree でローカルに **未 push commit を意図的に積んでいる** 場合、それは検出されず削除候補に並ぶ。`--apply` 前に dry-run の `(upstream ref pruned)` 表示で必ず確認する。

### Step 4: dry-run 出力（既定）

候補と保護対象を分けて表示する:

```
=== 削除候補 (3) ===
  .worktrees/feat-old-feature      [feat/old-feature]
  .worktrees/fix-typo              [fix/typo]
  .worktrees/refactor-auth         [refactor/auth]

=== 保護 (2) ===
  .worktrees/wip-experiment        [wip/experiment]      dirty: 未コミット変更あり
  .worktrees/feat-incomplete       [feat/incomplete]     unpushed: 2 commits ahead

実行する場合: cleanup-stale-worktrees --apply
```

候補が 0 件なら `すべての worktree がリモートで生存中、または保護対象です。` と報告して終了。

### Step 5: 削除実行（`--apply` 指定時）

各候補について順に実行:

```bash
git worktree remove "$WT_PATH"          # 通常モード
# または
git worktree remove --force "$WT_PATH"  # --force 指定時
```

`--keep-branch` が指定されていなければブランチ参照も削除:

```bash
git branch -D "$BRANCH"
```

成功・失敗を 1 行ずつ報告し、最後にサマリーを出す:

```
✓ removed .worktrees/feat-old-feature  (branch feat/old-feature deleted)
✓ removed .worktrees/fix-typo          (branch fix/typo deleted)
✗ failed  .worktrees/refactor-auth     (git worktree remove returned 1)

3 candidates / 2 removed / 1 failed
```

失敗があってもループは継続する（1 件の失敗で残り全部を諦めない）。

## 実装スクリプト（一発実行版）

スキル本体のロジックを bash 関数化したもの。コマンド呼び出し時に inline 実行する想定:

```bash
cleanup_stale_worktrees() {
    local apply=0 force=0 keep_branch=0 remote="origin"
    while [ $# -gt 0 ]; do
        case "$1" in
            --apply) apply=1 ;;
            --force) force=1 ;;
            --keep-branch) keep_branch=1 ;;
            --remote) shift; remote="$1" ;;
            *) echo "unknown arg: $1" >&2; return 2 ;;
        esac
        shift
    done

    git fetch --prune "$remote" >/dev/null

    local main_dir
    main_dir="$(git rev-parse --show-toplevel)"

    local current_path="" current_branch="" detached=0
    local -a candidates=() protected=()

    flush() {
        [ -z "$current_path" ] && return
        [ "$current_path" = "$main_dir" ] && return
        if [ "$detached" = 1 ] || [ -z "$current_branch" ]; then
            protected+=("$current_path|(detached)|detached: ブランチ未チェックアウト")
            return
        fi
        if git ls-remote --exit-code --heads "$remote" "$current_branch" >/dev/null 2>&1; then
            return  # remote 健在
        fi
        local dirty unpushed upstream note=""
        dirty="$(git -C "$current_path" status --porcelain 2>/dev/null)"
        upstream="$(git -C "$current_path" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)"
        if [ -z "$upstream" ]; then
            protected+=("$current_path|$current_branch|no-upstream: 追跡先なし")
            return
        fi
        if ! unpushed="$(git -C "$current_path" rev-list --count "@{upstream}..HEAD" 2>/dev/null)"; then
            unpushed=0
            note=" (upstream ref pruned — verify no orphan local commits)"
        fi
        if [ -n "$dirty" ] && [ "$force" != 1 ]; then
            protected+=("$current_path|$current_branch|dirty: 未コミット変更あり")
            return
        fi
        if [ "$unpushed" != 0 ] && [ "$force" != 1 ]; then
            protected+=("$current_path|$current_branch|unpushed: $unpushed commits ahead")
            return
        fi
        candidates+=("$current_path|$current_branch|$note")
    }

    while IFS= read -r line; do
        case "$line" in
            "worktree "*) flush; current_path="${line#worktree }"; current_branch=""; detached=0 ;;
            "branch refs/heads/"*) current_branch="${line#branch refs/heads/}" ;;
            "detached") detached=1 ;;
        esac
    done < <(git worktree list --porcelain; echo)
    flush

    echo "=== 削除候補 (${#candidates[@]}) ==="
    for c in "${candidates[@]}"; do
        IFS='|' read -r p b note <<<"$c"
        printf "  %-50s [%s]%s\n" "$p" "$b" "$note"
    done
    echo
    echo "=== 保護 (${#protected[@]}) ==="
    for c in "${protected[@]}"; do
        IFS='|' read -r p b reason <<<"$c"
        printf "  %-50s [%s]  %s\n" "$p" "$b" "$reason"
    done

    if [ "$apply" != 1 ]; then
        echo
        echo "実行する場合: cleanup-stale-worktrees --apply"
        return 0
    fi

    local removed=0 failed=0
    for c in "${candidates[@]}"; do
        IFS='|' read -r p b _note <<<"$c"
        local remove_args=("$p")
        [ "$force" = 1 ] && remove_args=("--force" "$p")
        if git worktree remove "${remove_args[@]}"; then
            if [ "$keep_branch" != 1 ]; then
                git branch -D "$b" >/dev/null 2>&1 \
                    && echo "✓ removed $p  (branch $b deleted)" \
                    || echo "✓ removed $p  (branch $b kept: delete failed)"
            else
                echo "✓ removed $p  (branch kept)"
            fi
            removed=$((removed + 1))
        else
            echo "✗ failed  $p"
            failed=$((failed + 1))
        fi
    done
    echo
    echo "${#candidates[@]} candidates / $removed removed / $failed failed"
}
```

## セーフガード（設計上の不変条件）

- **メイン worktree は絶対に削除しない**（`git rev-parse --show-toplevel` で除外）
- **`--force` でも `no-upstream` / `detached` は保護**（孤立した作業の喪失を防ぐ）
- **`git ls-remote` 失敗時は保護に倒す**（ネットワーク不調・remote 未設定で誤削除しない）
- **dry-run が既定**（`--apply` を明示しない限り何も消さない）
- **ループ中の失敗で停止しない**（部分成功を許容し、最後にサマリーで可視化）

## 動作確認の手順例

新規スキル投入時に実機で確認するシナリオ:

```bash
# 1. 検証用 stale worktree を仕込む
git worktree add .worktrees/test-stale -b test/stale-branch
# remote にプッシュせず、ブランチが remote に存在しない状態を作る

# 2. dry-run
cleanup-stale-worktrees
# 期待: test/stale-branch が "no-upstream" で保護表示される

# 3. upstream を仕立てた dirty ケース
git worktree add .worktrees/test-dirty -b test/dirty-branch
git -C .worktrees/test-dirty push -u origin test/dirty-branch
git -C .worktrees/test-dirty checkout README.md  # 何でもいいので変更
echo "x" >> .worktrees/test-dirty/README.md
git push origin --delete test/dirty-branch
cleanup-stale-worktrees
# 期待: test/dirty-branch が "dirty" で保護される

# 4. クリーンに削除可能なケース
git worktree add .worktrees/test-clean -b test/clean-branch
git -C .worktrees/test-clean push -u origin test/clean-branch
git push origin --delete test/clean-branch
cleanup-stale-worktrees
# 期待: test/clean-branch が削除候補に表示される
cleanup-stale-worktrees --apply
# 期待: 実削除され、ローカルブランチも削除される
```

## 注意事項

- このスキルは**読み取り中心**の判定を行う。リモートブランチの削除はしない
- `--force` を使うと未コミット変更が失われる。実行前に対象一覧をユーザーに提示する
- 複数 remote を扱うリポジトリでは `--remote` を明示する（`upstream` / `fork` など）
- worktree が壊れて `git worktree remove` が失敗する場合、先に `git worktree prune` を試す
- macOS / Linux の bash 4+ を前提とする（連想配列を使うため）。Windows は対象外

## 他スキルとの関係

| 相棒 | 役割 | 関係 |
|------|------|------|
| `superpowers:using-git-worktrees` | worktree 作成 | 対になる入口（作成・整備） |
| `superpowers:finishing-a-development-branch` | PR マージ後の片付け | 個別ブランチの finish 後の一括掃除担当 |
| `dev-orchestration` | ワークフロー判断ハブ | Phase 6 完走後、定期的にこのスキルを回す運用が想定される |

## レッドフラグ

| 思考 | 実態 |
|------|------|
| 「`fetch --prune` 後なら ls-remote しなくていい」 | prune は `refs/remotes` を消すだけ。`ls-remote` で実際に問い合わせる方が堅牢 |
| 「dirty も `--force` で消せばいい」 | 既定の保護を外すのは明示オプトインのみ。提示なしの強制削除は禁止 |
| 「ブランチも消せば一気にきれい」 | `--keep-branch` 経路を残す。ローカルでまだ作業を続ける可能性を尊重 |
| 「メイン worktree も対象でいいだろう」 | 絶対除外。`git rev-parse --show-toplevel` で常に判定する |
| 「ネットワーク不通なら全部 stale 扱い」 | `ls-remote` 失敗は保護に倒す。誤削除のコストの方が大きい |
