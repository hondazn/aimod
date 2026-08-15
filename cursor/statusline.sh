#!/usr/bin/env bash

input=$(cat)

h2r() { local h="${1#\#}"; printf '%d;%d;%d' "$((16#${h:0:2}))" "$((16#${h:2:2}))" "$((16#${h:4:2}))"; }
fg() { printf '\033[38;2;%sm' "$(h2r "$1")"; }
_link() { printf '\033]8;;%s\007%s\033]8;;\007' "$1" "$2"; }
_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

RST=$'\033[0m'
C_DIM="#565F89"
C_MODEL="#7AA2F7"
C_MODE="#BB9AF7"
C_REPO="#73DACA"
C_BRANCH="#7DCFFF"
C_OK="#9ECE6A"
C_WARN="#E0AF68"
C_BAD="#F7768E"

eval "$(printf '%s' "$input" | jq -r '
  def s: (. // "") | tostring | @sh;
  "MODEL=\(.model.display_name | s)",
  "VER=\(.version | s)",
  "PARAM_SUMMARY=\(.model.param_summary | s)",
  "MAX_MODE=\(.model.max_mode // false)",
  "STYLE=\(.output_style.name | s)",
  "AUTORUN=\(.autorun // false)",
  "CWD=\((.workspace.current_dir // .cwd) | s)",
  "WORKTREE=\(.worktree.name | s)",
  "CTX_USED=\(.context_window.used_percentage | s)",
  "CTX_REMAIN=\(.context_window.remaining_percentage | s)",
  "CTX_TOK=\(.context_window.total_input_tokens | s)",
  "CTX_SIZE=\(.context_window.context_window_size | s)"
')"

git_c() {
  if [ -n "$CWD" ]; then git -C "$CWD" "$@"
  else git "$@"
  fi
}

append() {
  local -n _buf=$1
  local val=$2
  [ -z "$val" ] && return
  [ -n "$_buf" ] && _buf+="  "
  _buf+="$val"
}

DIR=""
owner=""
repo=""
remote_url=""
if remote_url=$(git_c remote get-url origin 2>/dev/null); then
  remote_url="${remote_url%.git}"
  repo="${remote_url##*/}"
  owner="${remote_url%/*}"
  owner="${owner##*[:/]}"
  [ -n "$owner" ] && [ -n "$repo" ] && DIR="${owner}/${repo}"
fi
[ -z "$DIR" ] && DIR="${CWD##*/}"

GH_BASE=""
case "$remote_url" in
  *github.com*) [ -n "$owner" ] && [ -n "$repo" ] && GH_BASE="https://github.com/${owner}/${repo}" ;;
esac

git_stat() {
  local added=0 deleted=0 untracked=0 r=""
  read -r added deleted <<EOF
$(git_c diff HEAD --numstat 2>/dev/null | awk '{ a+=$1; d+=$2 } END { print a+0, d+0 }')
EOF
  untracked=$(git_c status --short 2>/dev/null | awk '/^\?\?/ { n++ } END { print n+0 }')
  [ "${added:-0}" -gt 0 ] && r+="$(fg "$C_OK")+${added}${RST}"
  [ "${deleted:-0}" -gt 0 ] && { [ -n "$r" ] && r+=" "; r+="$(fg "$C_BAD")-${deleted}${RST}"; }
  [ "${untracked:-0}" -gt 0 ] && { [ -n "$r" ] && r+=" "; r+="$(fg "$C_WARN")?${untracked}${RST}"; }
  printf '%s' "$r"
}

BRANCH=""
GSTAT=""
if git_c rev-parse --git-dir >/dev/null 2>&1; then
  BRANCH=$(git_c branch --show-current 2>/dev/null)
  GSTAT=$(git_stat)
fi

PR_NUM=""
PR_URL=""
PR_DRAFT=""
PR_DECISION=""
CACHE_DIR="${CURSOR_STATUSLINE_CACHE:-${TMPDIR:-/tmp}/cursor-statusline-cache}"
if [ -n "$owner" ] && [ -n "$repo" ] && [ -n "$BRANCH" ]; then
  cache_file="${CACHE_DIR}/${owner}__${repo}__pr__${BRANCH//\//-}"
  lock_file="${cache_file}.lock"
  if [ -s "$cache_file" ]; then
    PR_NUM=$(jq -r '.number // empty' "$cache_file")
    PR_URL=$(jq -r '.url // empty' "$cache_file")
    PR_DRAFT=$(jq -r '.isDraft // false' "$cache_file")
    PR_DECISION=$(jq -r '.reviewDecision // empty' "$cache_file")
  fi
  cache_age=9999
  [ -f "$cache_file" ] && cache_age=$(( $(date +%s) - $(_mtime "$cache_file") ))
  if [ "$cache_age" -gt 300 ] && [ ! -f "$lock_file" ]; then
    mkdir -p "$CACHE_DIR" 2>/dev/null
    touch "$lock_file" 2>/dev/null
    (
      json=$(gh pr view --repo "${owner}/${repo}" --json number,url,isDraft,reviewDecision 2>/dev/null) || json=""
      if [ -n "$json" ]; then printf '%s' "$json" > "$cache_file"
      else rm -f "$cache_file"
      fi
      rm -f "$lock_file"
    ) &
  fi
fi

commaize() {
  awk -v n="$1" 'BEGIN {
    s = sprintf("%d", n+0)
    r = ""
    while (length(s) > 3) {
      r = "," substr(s, length(s)-2) r
      s = substr(s, 1, length(s)-3)
    }
    print s r
  }'
}

USED=""
if [ -n "$CTX_USED" ]; then
  USED="${CTX_USED%.*}"
elif [ -n "$CTX_REMAIN" ]; then
  USED=$(awk -v p="$CTX_REMAIN" 'BEGIN { printf "%d", 100 - p }')
fi

TOK=""
if [ -n "$CTX_TOK" ]; then
  TOK="${CTX_TOK%.*}"
elif [ -n "$USED" ] && [ -n "$CTX_SIZE" ]; then
  TOK=$(awk -v p="$USED" -v s="$CTX_SIZE" 'BEGIN { printf "%d", p * s / 100 }')
fi

ctx_color="$C_OK"
if [ -n "$USED" ]; then
  if [ "$USED" -ge 80 ]; then ctx_color="$C_BAD"
  elif [ "$USED" -ge 50 ]; then ctx_color="$C_WARN"
  fi
fi

ctx_txt=""
[ -n "$TOK" ] && ctx_txt="$(commaize "$TOK")"
[ -n "$USED" ] && ctx_txt="${ctx_txt:+$ctx_txt  }${USED}%"

L1=""
[ -n "$VER" ] && append L1 "$(fg "$C_DIM")${VER}${RST}"
[ -n "$MODEL" ] && append L1 "$(fg "$C_MODEL")${MODEL}${RST}"
if [ -n "$PARAM_SUMMARY" ]; then
  ps="${PARAM_SUMMARY#(}"
  ps="${ps%)}"
  append L1 "$(fg "$C_MODE")${ps}${RST}"
fi
[ "$MAX_MODE" = "true" ] && append L1 "$(fg "$C_MODE")max${RST}"
[ -n "$STYLE" ] && [ "$STYLE" != "default" ] && append L1 "$(fg "$C_MODE")${STYLE}${RST}"
[ "$AUTORUN" = "true" ] && append L1 "$(fg "$C_MODE")autorun${RST}"
[ -n "$ctx_txt" ] && append L1 "$(fg "$ctx_color")ctx ${ctx_txt}${RST}"

LOC=""
if [ -n "$WORKTREE" ]; then
  LOC="$(fg "$C_OK")${WORKTREE}${RST}"
elif [ -n "$BRANCH" ]; then
  if [ -n "$GH_BASE" ]; then
    LOC="$(fg "$C_BRANCH")$(_link "${GH_BASE}/tree/${BRANCH}" "$BRANCH")${RST}"
  else
    LOC="$(fg "$C_BRANCH")${BRANCH}${RST}"
  fi
fi

REPO_TXT=""
if [ -n "$DIR" ]; then
  if [ -n "$GH_BASE" ]; then
    REPO_TXT="$(fg "$C_REPO")$(_link "$GH_BASE" "$DIR")${RST}"
  else
    REPO_TXT="$(fg "$C_REPO")${DIR}${RST}"
  fi
fi

PR_TXT=""
if [ -n "$PR_NUM" ]; then
  pr_c="$C_WARN"
  [ "$PR_DRAFT" = "true" ] && pr_c="$C_DIM"
  case "$PR_DECISION" in
    APPROVED) pr_c="$C_OK" ;;
    CHANGES_REQUESTED) pr_c="$C_BAD" ;;
  esac
  if [ -n "$PR_URL" ]; then
    PR_TXT="$(fg "$pr_c")$(_link "$PR_URL" "#${PR_NUM}")${RST}"
  else
    PR_TXT="$(fg "$pr_c")#${PR_NUM}${RST}"
  fi
fi

L2=""
append L2 "$REPO_TXT"
append L2 "$LOC"
append L2 "$GSTAT"
append L2 "$PR_TXT"

printf '%s' "$RST"
[ -n "$L1" ] && printf '%s\n' "$L1"
[ -n "$L2" ] && printf '%s\n' "$L2"
:
