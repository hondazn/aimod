#!/usr/bin/env bash
# classify-branches.sh — branch-sweep スキル用の読み取り専用ブランチ分類スクリプト。
#
# 全ブランチ（ローカル + リモート）を以下のセクションに分類してレポート出力する:
#   SAFE_LOCAL / SAFE_REMOTE       — 今すぐ安全に削除できる
#   CONFIRM_LOCAL / CONFIRM_REMOTE — 未マージ/未プッシュの作業を含む。削除前に確認
#   SKIPPED                        — 絶対に削除しない（default/current/protected/open-PR/worktree）
#
# このスクリプトは何も削除・fetch・変更しない。状態を読み取って分類するだけ。
# 呼び出し側（SKILL.md）がレポートを受け取って表示し、削除コマンドを実行する。
# 副作用がないため、何度でも（dry-run としても）安全に実行できる。
#
# 使い方: classify-branches.sh [remote]        (remote のデフォルトは "origin")
# 環境変数: BRANCH_SWEEP_PROTECT="glob1 glob2 …" で保護ブランチの glob を上書きできる。
#
# bash 3.2（macOS システム bash）向けに記述: 連想配列なし、mapfile なし、
# `set -u` 下で空配列に対する `${arr[@]}` を使わない。

set -euo pipefail

REMOTE="${1:-origin}"

git rev-parse --git-dir >/dev/null 2>&1 || { echo "ERROR: not inside a git repository" >&2; exit 1; }

# --- デフォルトブランチ: リモートの HEAD symref を優先し、無ければローカルの main/master にフォールバック ---
default_branch=""
if git symbolic-ref -q "refs/remotes/$REMOTE/HEAD" >/dev/null 2>&1; then
  default_branch="$(git symbolic-ref --short "refs/remotes/$REMOTE/HEAD" 2>/dev/null | sed "s#^$REMOTE/##")"
fi
if [ -z "$default_branch" ]; then
  for cand in main master; do
    if git show-ref --verify -q "refs/heads/$cand"; then default_branch="$cand"; break; fi
  done
fi
default_branch="${default_branch:-main}"

# --- リモートブランチの安全判定の基準 ref ---
# リモートブランチがマージ済みかどうかは、ローカルの $default_branch ではなく
# リモート追跡しているデフォルト（例: origin/main）を基準に判定する。ローカル main が
# マージ済みでも未プッシュの場合に、origin/main にまだ含まれていないリモートブランチを
# 誤って SAFE_REMOTE に分類して削除してしまうのを防ぐ。
remote_default_ref="$default_branch"
if git show-ref --verify -q "refs/remotes/$REMOTE/$default_branch"; then
  remote_default_ref="refs/remotes/$REMOTE/$default_branch"
fi

current_branch="$(git branch --show-current 2>/dev/null || true)"

# --- 保護 glob（絶対に自動削除しない）。長期運用ブランチはここに含める。 ---
read -r -a protect_globs <<< "${BRANCH_SWEEP_PROTECT:-main master develop dev staging production release/* hotfix/*}"

is_protected() {
  local b="$1" g
  [ "$b" = "$default_branch" ] && return 0
  [ "$b" = "$current_branch" ] && return 0
  for g in "${protect_globs[@]}"; do
    # shellcheck disable=SC2254  # 意図的な glob マッチ
    case "$b" in $g) return 0 ;; esac
  done
  return 1
}

# --- worktree でチェックアウト中のブランチは削除できない ---
worktree_branches="$(git worktree list --porcelain 2>/dev/null | sed -n 's#^branch refs/heads/##p' || true)"
is_in_worktree() { printf '%s\n' "$worktree_branches" | grep -qxF "$1"; }
worktree_path_for() {
  git worktree list --porcelain 2>/dev/null \
    | awk -v want="refs/heads/$1" '/^worktree /{p=$2} /^branch /{if($2==want) print p}' \
    | head -1
}

# --- リモートの有無 ---
have_remote=false
if git remote get-url "$REMOTE" >/dev/null 2>&1; then have_remote=true; fi

# --- gh による PR 状態（ベストエフォート）: 1 回の呼び出しで open + merged + closed を網羅 ---
# 各行: "STATE<TAB>headRefName<TAB>headRefOid<TAB>isCrossRepository"
# headRefOid と isCrossRepository も取得する理由: MERGED 判定を「ブランチ名一致」だけで
# 行うと、squash マージ後に同名ブランチが作り直された場合や、同名 head を持つ fork PR が
# あった場合に、無関係な未マージブランチを「マージ済み」とみなして強制削除してしまう。
# MERGED 判定は名前だけでなく head の SHA 一致（かつ same-repo）まで突き合わせる。
pr_data=""
pr_note=""
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  if ! pr_data="$(gh pr list --state all --limit 300 \
                    --json state,headRefName,headRefOid,isCrossRepository \
                    --jq '.[] | "\(.state)\t\(.headRefName)\t\(.headRefOid)\t\(.isCrossRepository)"' 2>/dev/null)"; then
    pr_data=""
    pr_note="gh pr lookup failed — OPEN-PR PROTECTION IS OFF (open-PR branches are NOT in SKIPPED) and squash-merged branches may show as CONFIRM; do not auto-delete, confirm each"
  fi
else
  pr_note="gh unavailable/unauthed — OPEN-PR PROTECTION IS OFF (open-PR branches are NOT in SKIPPED) and squash-merged branches may show as CONFIRM; do not auto-delete, confirm each"
fi

# has_pr STATE NAME — 指定 state かつ headRefName 一致の PR が（リポジトリを問わず）あれば真。
# OPEN（アクティブ作業のスキップ）と CLOSED（注記）に使う。保守的に名前一致で十分。
has_pr() {
  printf '%s\n' "$pr_data" | awk -F'\t' -v s="$1" -v n="$2" '$1==s && $2==n{f=1} END{exit !f}'
}

# has_merged_same_head NAME SHA — headRefName 一致かつ head の SHA がこのブランチ tip と
# 一致する same-repo（isCrossRepository=false）の MERGED PR があれば真。名前の再利用や
# fork PR による誤検出を防ぐ。SHA は短縮せずフル長で突き合わせる（桁数はリポジトリの
# ハッシュ方式に従う。文字列一致なので SHA-1 / SHA-256 いずれでもコードは変わらない）。
has_merged_same_head() {
  printf '%s\n' "$pr_data" | awk -F'\t' -v n="$1" -v sha="$2" \
    '$1=="MERGED" && $2==n && $3==sha && $4=="false"{f=1} END{exit !f}'
}

# --- アキュムレータ（改行区切りの文字列。bash 3.2 互換）---
safe_local=""; safe_remote=""; conf_local=""; conf_remote=""; skipped=""
n_safe=0; n_conf=0; n_skip=0
add_safe_l() { safe_local+="$1"$'\n'; n_safe=$((n_safe+1)); }
add_safe_r() { safe_remote+="$1"$'\n'; n_safe=$((n_safe+1)); }
add_conf_l() { conf_local+="$1"$'\n'; n_conf=$((n_conf+1)); }
add_conf_r() { conf_remote+="$1"$'\n'; n_conf=$((n_conf+1)); }
add_skip()   { skipped+="$1"$'\n'; n_skip=$((n_skip+1)); }

# --- ローカルブランチ ---
while IFS= read -r b; do
  [ -z "$b" ] && continue
  if is_protected "$b"; then add_skip "$b	(protected / default / current)"; continue; fi
  if is_in_worktree "$b"; then add_skip "$b	(checked out in worktree: $(worktree_path_for "$b"))"; continue; fi
  if has_pr "OPEN" "$b"; then add_skip "$b	(open PR — active work, kept)"; continue; fi

  sha="$(git rev-parse --short "$b")"

  merged=false
  if git merge-base --is-ancestor "$b" "$default_branch" 2>/dev/null; then merged=true; fi

  upstream="$(git rev-parse --abbrev-ref "$b@{upstream}" 2>/dev/null || true)"
  ahead_up=""
  [ -n "$upstream" ] && ahead_up="$(git rev-list --count "$upstream..$b" 2>/dev/null || echo '?')"

  if $merged; then
    add_safe_l "$b	$sha	merged into $default_branch  [git branch -d]"
  elif has_merged_same_head "$b" "$(git rev-parse "$b")"; then
    add_safe_l "$b	$sha	PR merged (squash) — absent from $default_branch graph  [git branch -D]"
  elif [ -n "$upstream" ] && [ "$ahead_up" = "0" ]; then
    # 未マージだが全コミットが既にリモート上にある: ローカルのコピーを消しても
    # 何も失わない（`git checkout -b <b> <upstream>` で復元可能）。これは
    # CONFIRM 項目の中で最も安全 — 自動削除にしないのは、PR がまだ無い状態で
    # バックアップとしてプッシュした未マージブランチが、ユーザーが作業途中の WIP
    # である可能性があるため。
    add_conf_l "$b	$sha	unmerged but fully pushed per $upstream — VERIFY with: git ls-remote --heads <remote> refs/heads/$b (this compares against a local cache; a failed fetch --prune leaves residue refs for branches already gone/rewound on the server)"
  else
    if [ -n "$upstream" ]; then
      add_conf_l "$b	$sha	$ahead_up commit(s) not in $upstream, not merged"
    else
      n="$(git rev-list --count "$default_branch..$b" 2>/dev/null || echo '?')"
      add_conf_l "$b	$sha	no upstream, $n commit(s) not in $default_branch"
    fi
  fi
done < <(git for-each-ref --format='%(refname:short)' refs/heads/)

# --- リモートブランチ ---
# short ではなくフル refname で走査する: refs/remotes/<remote>/HEAD の short 形は
# 単なる "<remote>" に潰れてしまい、そのままだと幻のブランチとして混入する。
if $have_remote; then
  while IFS= read -r ref; do
    [ -z "$ref" ] && continue
    name="${ref#"refs/remotes/$REMOTE/"}"
    [ "$name" = "HEAD" ] && continue   # ブランチではなく、シンボリックな origin/HEAD ポインタ
    if is_protected "$name"; then add_skip "$REMOTE/$name	(protected / default)"; continue; fi
    if has_pr "OPEN" "$name"; then add_skip "$REMOTE/$name	(open PR — active work, kept)"; continue; fi

    sha="$(git rev-parse --short "$ref")"
    merged=false
    if git merge-base --is-ancestor "$ref" "$remote_default_ref" 2>/dev/null; then merged=true; fi

    if $merged; then
      add_safe_r "$name	$sha	merged into $REMOTE/$default_branch"
    elif has_merged_same_head "$name" "$(git rev-parse "$ref")"; then
      add_safe_r "$name	$sha	PR merged (squash)"
    else
      n="$(git rev-list --count "$remote_default_ref..$ref" 2>/dev/null || echo '?')"
      closed_note=""
      has_pr "CLOSED" "$name" && closed_note=", PR closed unmerged"
      add_conf_r "$name	$sha	$n commit(s) not in $default_branch, no merged PR$closed_note"
    fi
  done < <(git for-each-ref --format='%(refname)' "refs/remotes/$REMOTE/")
fi

# --- 出力 ---
section() {  # section <title> <body>
  printf '## %s\n' "$1"
  if [ -z "$2" ]; then printf '(none)\n\n'; else printf '%s\n' "$2"; fi
}

printf 'DEFAULT_BRANCH=%s\n' "$default_branch"
printf 'CURRENT_BRANCH=%s\n' "${current_branch:-<detached>}"
printf 'REMOTE=%s (present=%s)\n' "$REMOTE" "$have_remote"
printf 'COUNTS=safe:%s confirm:%s skipped:%s\n' "$n_safe" "$n_conf" "$n_skip"
[ -n "$pr_note" ] && printf 'PR_NOTE=%s\n' "$pr_note"
printf '\n'

section "SAFE_LOCAL  — auto-delete: git branch -d <names> (escalate to -D for PR-merged refusals)" "$safe_local"
section "SAFE_REMOTE — auto-delete (one round trip): git push --force-with-lease=<name>:<sha> ... $REMOTE --delete <names>  (lease is mandatory: these refs were classified from possibly-stale refs/remotes)" "$safe_remote"
section "CONFIRM_LOCAL  — unmerged; CONFIRM each, then git branch -D (fully-pushed = recoverable ONLY after the ls-remote live re-check; local-only commits = data loss — see each reason)" "$conf_local"
section "CONFIRM_REMOTE — unique commits, no merged PR; CONFIRM each (data loss)" "$conf_remote"
section "SKIPPED — never deleted" "$skipped"
