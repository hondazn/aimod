#!/usr/bin/env bash

input=$(cat)

# ─── Powerline separator ───
PL=$(printf '\xee\x82\xb0')  # U+E0B0

# ─── Color helpers ───
h2r() { local h="${1#\#}"; echo "$((16#${h:0:2}));$((16#${h:2:2}));$((16#${h:4:2}))"; }

# ─── OSC 8 hyperlink helper ───
_link() { echo "\033]8;;${1}\007${2}\033]8;;\007"; }

# ─── Segment palette ───
BG_REPO="#1A6E6E"
BG_BRANCH="#5B4A8A"
BG_STATUS="#3E3E3E"
BG_MODEL="#2B4570"
BG_VER="#4A4A4A"
BG_RATE="#2A2A2A"
BG_TOK_GREEN="#2E7D32"
BG_TOK_YELLOW="#F57F17"
BG_TOK_RED="#C62828"

# ─── Segment builder ───
# Tracks previous segment bg to render Powerline separator transitions
_prev=""
_out=""

_sep() {
  local next_bg=$1
  if [ -n "$_prev" ]; then
    _out+="\033[38;2;$(h2r "$_prev")m\033[48;2;$(h2r "$next_bg")m${PL}"
  fi
}

_seg() {  # $1=bg $2=fg $3=text
  _sep "$1"
  _out+="\033[48;2;$(h2r "$1")m\033[38;2;$(h2r "$2")m ${3} "
  _prev="$1"
}

_seg_raw() {  # $1=bg $2=content (may contain ANSI fg codes)
  _sep "$1"
  _out+="\033[48;2;$(h2r "$1")m ${2}\033[48;2;$(h2r "$1")m "
  _prev="$1"
}

_end() {
  if [ -n "$_prev" ]; then
    _out+="\033[0m\033[38;2;$(h2r "$_prev")m${PL}\033[0m"
  fi
  _prev=""
}

# ─── Extract data from JSON ───
MODEL=$(echo "$input" | jq -r '.model.display_name')
PROJECT_DIR=$(echo "$input" | jq -r '.workspace.project_dir')
VER=$(echo "$input" | jq -r '.version')

# Repo: owner/repo from git remote, fallback to dirname
DIR=""
if remote_url=$(git remote get-url origin 2>/dev/null); then
  remote_url="${remote_url%.git}"
  repo="${remote_url##*/}"; owner="${remote_url%/*}"; owner="${owner##*[:/]}"
  [ -n "$owner" ] && [ -n "$repo" ] && DIR="${owner}/${repo}"
fi
[ -z "$DIR" ] && DIR="${PROJECT_DIR##*/}"

# GitHub HTTPS base URL (for OSC 8 hyperlinks)
GH_BASE_URL=""
if [ -n "$owner" ] && [ -n "$repo" ]; then
  case "$remote_url" in
    *github.com*) GH_BASE_URL="https://github.com/${owner}/${repo}" ;;
  esac
fi

# Git branch
BRANCH=""
if git rev-parse --git-dir >/dev/null 2>&1; then
  BRANCH=$(git branch --show-current 2>/dev/null)
fi

# Extract issue number from branch name
# Patterns: feature/123-desc, fix/GH-123, issue-123, 123-desc
ISSUE_NUM=""
if [ -n "$BRANCH" ]; then
  if [[ "$BRANCH" =~ (^|[/-])(GH-)?([0-9]+)([/-]|$) ]]; then
    ISSUE_NUM="${BASH_REMATCH[3]}"
  fi
fi

# Fetch issue title with background caching
ISSUE_TITLE=""
ISSUE_URL=""
if [ -n "$ISSUE_NUM" ] && [ -n "$GH_BASE_URL" ]; then
  ISSUE_URL="${GH_BASE_URL}/issues/${ISSUE_NUM}"
  CACHE_DIR="${TMPDIR:-/tmp}/claude-statusline-cache"
  CACHE_FILE="${CACHE_DIR}/${owner}__${repo}__${ISSUE_NUM}"
  LOCK_FILE="${CACHE_FILE}.lock"
  CACHE_TTL=300

  mkdir -p "$CACHE_DIR" 2>/dev/null

  if [ -f "$CACHE_FILE" ]; then
    ISSUE_TITLE=$(cat "$CACHE_FILE" 2>/dev/null)
    cache_age=$(( $(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0) ))
    if [ "$cache_age" -gt "$CACHE_TTL" ] && [ ! -f "$LOCK_FILE" ]; then
      touch "$LOCK_FILE" 2>/dev/null
      ( gh issue view "$ISSUE_NUM" --repo "${owner}/${repo}" --json title -q '.title' \
          > "$CACHE_FILE" 2>/dev/null; rm -f "$LOCK_FILE" ) &
    fi
  else
    if [ ! -f "$LOCK_FILE" ]; then
      touch "$LOCK_FILE" 2>/dev/null
      ( gh issue view "$ISSUE_NUM" --repo "${owner}/${repo}" --json title -q '.title' \
          > "$CACHE_FILE" 2>/dev/null; rm -f "$LOCK_FILE" ) &
    fi
  fi
fi

# Git status (fg-colored text with bg maintained for segment)
git_stat() {
  local bg_e="\033[48;2;$(h2r "$BG_STATUS")m"
  local a=0 d=0 u=0
  eval "$(git diff HEAD --numstat 2>/dev/null | awk '{ a+=$1; d+=$2 } END { printf "a=%d d=%d",a+0,d+0 }')"
  u=$(git status --short 2>/dev/null | grep -c '^\?\?')
  local r=""
  [ "$a" -gt 0 ] && r+="\033[38;2;0;212;0m${bg_e}+${a}"
  [ "$d" -gt 0 ] && { [ -n "$r" ] && r+=" "; r+="\033[38;2;255;96;96m${bg_e}-${d}"; }
  [ "$u" -gt 0 ] && { [ -n "$r" ] && r+=" "; r+="\033[38;2;212;212;0m${bg_e}?${u}"; }
  echo "$r"
}
GSTAT=$(git_stat)

# Context token usage
CTX_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size')
CTX_USAGE=$(echo "$input" | jq '.context_window.current_usage')
TOK_TEXT="-"
TOK_BG="$BG_TOK_GREEN"

if [ "$CTX_USAGE" != "null" ] && [ "$CTX_SIZE" != "null" ] && [ "$CTX_SIZE" != "0" ]; then
  CUR_TOK=$(echo "$CTX_USAGE" | jq '(.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)')
  pct=$((CUR_TOK * 100 / CTX_SIZE))
  TOK_TEXT=$(printf "%'d" "$CUR_TOK")
  if [ "$pct" -ge 90 ]; then
    TOK_BG="$BG_TOK_RED"
  elif [ "$pct" -ge 70 ]; then
    TOK_BG="$BG_TOK_YELLOW"
  fi
fi

# ═══════════════════════════════════════
#  Line 1: Claude info
# ═══════════════════════════════════════
_seg "$BG_MODEL" "#FFFFFF" "🤖 ${MODEL}"
_seg "$BG_VER" "#B0B0B0" "💥${VER}"
_end
LINE1="$_out"

# ═══════════════════════════════════════
#  Line 2: Git / GitHub info
# ═══════════════════════════════════════
_prev=""
_out=""

if [ -n "$GH_BASE_URL" ]; then
  _seg "$BG_REPO" "#FFFFFF" "🚀 $(_link "$GH_BASE_URL" "$DIR")"
else
  _seg "$BG_REPO" "#FFFFFF" "🚀 ${DIR}"
fi

if [ -n "$ISSUE_TITLE" ] && [ -n "$ISSUE_URL" ]; then
  # Issue detected: show issue title instead of branch name
  _disp="$ISSUE_TITLE"
  [ ${#_disp} -gt 40 ] && _disp="${_disp:0:39}…"
  _seg "$BG_BRANCH" "#FFFFFF" "🎫 $(_link "$ISSUE_URL" "#${ISSUE_NUM}: ${_disp}")"
elif [ -n "$BRANCH" ]; then
  if [ -n "$GH_BASE_URL" ]; then
    _seg "$BG_BRANCH" "#FFFFFF" "⚡$(_link "${GH_BASE_URL}/tree/${BRANCH}" "$BRANCH")"
  else
    _seg "$BG_BRANCH" "#FFFFFF" "⚡${BRANCH}"
  fi
fi

[ -n "$GSTAT" ] && _seg_raw "$BG_STATUS" "$GSTAT"
_end
LINE2="$_out"

# ═══════════════════════════════════════
#  Line 3: Token gauge + Rate limits
# ═══════════════════════════════════════
_prev=""
_out=""

gauge() {
  local pct=$1 width=${2:-10}
  local pct_int=${pct%.*}
  local fx2=$(( pct_int * width * 2 / 100 ))
  local full=$(( fx2 / 2 ))
  local half=$(( fx2 % 2 ))
  local empty=$(( width - full - half ))
  local bar="" i
  for (( i=0; i<full; i++ )); do bar+="█"; done
  [ "$half" -eq 1 ] && bar+="▌"
  for (( i=0; i<empty; i++ )); do bar+="░"; done
  printf "%s" "$bar"
}

remaining_time() {
  local now diff hours mins
  now=$(date +%s); diff=$(($1 - now))
  if [ "$diff" -le 0 ]; then printf "reset soon"; return; fi
  hours=$((diff / 3600)); mins=$(( (diff % 3600) / 60 ))
  [ "$hours" -gt 0 ] && printf "%dh%02dm" "$hours" "$mins" || printf "%dm" "$mins"
}

rate_fg() {
  local p=${1%.*}
  if [ "$p" -ge 90 ]; then printf "\033[38;2;255;82;82m"
  elif [ "$p" -ge 70 ]; then printf "\033[38;2;255;183;77m"
  else printf "\033[38;2;102;187;106m"; fi
}

FIVE_H=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
SEVEN_D=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

# Token segment first
_seg "$TOK_BG" "#FFFFFF" "🧠 ${TOK_TEXT}"

# Then rate limits in the same line
if [ -n "$FIVE_H" ] || [ -n "$SEVEN_D" ]; then
  bg_e="\033[48;2;$(h2r "$BG_RATE")m"
  fg_dim="\033[38;2;120;120;120m"
  fg_lbl="\033[38;2;200;200;200m"

  parts=""
  if [ -n "$FIVE_H" ]; then
    p=$(printf '%.0f' "$FIVE_H")
    fc=$(rate_fg "$p")
    g=$(gauge "$p" 10)
    rst_at=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
    rem=""
    [ -n "$rst_at" ] && rem=" ${fg_dim}${bg_e}$(remaining_time "$rst_at")"
    parts+="${fg_lbl}${bg_e}5h ${fc}${bg_e}${g} ${p}%${rem}"
  fi

  if [ -n "$SEVEN_D" ]; then
    p=$(printf '%.0f' "$SEVEN_D")
    fc=$(rate_fg "$p")
    g=$(gauge "$p" 10)
    rst_at=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
    rem=""
    [ -n "$rst_at" ] && rem=" ${fg_dim}${bg_e}$(remaining_time "$rst_at")"
    [ -n "$parts" ] && parts+=" ${fg_dim}${bg_e}│ "
    parts+="${fg_lbl}${bg_e}7d ${fc}${bg_e}${g} ${p}%${rem}"
  fi

  _seg_raw "$BG_RATE" "⏳ ${parts}${bg_e}"
else
  bg_e="\033[48;2;$(h2r "$BG_RATE")m"
  fg_dim="\033[38;2;100;100;100m"
  fg_lbl="\033[38;2;200;200;200m"
  empty_g="░░░░░░░░░░"
  _seg_raw "$BG_RATE" "⏳ ${fg_lbl}${bg_e}5h ${fg_dim}${bg_e}${empty_g} --% ${fg_dim}${bg_e}│ ${fg_lbl}${bg_e}7d ${fg_dim}${bg_e}${empty_g} --%"
fi
_end
LINE3="$_out"

# ─── Output ───
echo -en "\033[0m"
echo -e "$LINE1"
echo -e "$LINE2"
echo -e "$LINE3"
