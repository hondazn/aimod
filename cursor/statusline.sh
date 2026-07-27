#!/usr/bin/env bash

input=$(cat)

# ─── Color helpers ───
h2r() { local h="${1#\#}"; echo "$((16#${h:0:2}));$((16#${h:2:2}));$((16#${h:4:2}))"; }

# ─── mtime helper (epoch seconds) ───
# GNU stat を先に試す。BSD の `stat -f` は Linux では FS 情報を stdout に吐いて
# 終了するため、素の `-f` フォールバックだと数値でない出力が混入する。
_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

# ─── OSC 8 hyperlink helper ───
_link() { echo "\033]8;;${1}\007${2}\033]8;;\007"; }

# ─── Powerline separator (nerdfont U+E0B0) ───
PL=$(printf '\xee\x82\xb0')

# ─── Segment palette (harmonized — semantic hues at unified saturation/lightness) ───
# Each background is its semantic hue rendered at the same S≈40% / L≈28%, so the
# blocks read as one coordinated set; backdrops (status/gauges) sit darker on purpose.
# L1 identity
BG_VER="#363C4E"         # slate (metadata)
BG_MODEL="#2B3E64"       # blue
BG_MODE="#432B64"        # purple
# L2 workspace
BG_REPO="#2B645C"        # teal
BG_BRANCH="#2B4C64"      # sky blue
BG_WORKTREE="#2B643E"    # green
BG_ISSUE="#6A2F6A"       # magenta (ticket)
BG_STATUS="#22262F"      # dark neutral (git-count backdrop)
# L3 resources
BG_GAUGE="#2F364C"       # ctx

# Foreground colors
FG_LIGHT="#C0CAF5"       # Tokyo Night foreground (cool white)
FG_MODE="#ECE6FF"        # light purple

# ─── Segment builder (Powerline: each separator carries the previous bg) ───
_prev=""
_out=""

_sep() {  # transition from previous segment bg into next bg ($1)
  [ -n "$_prev" ] && _out+="\033[38;2;$(h2r "$_prev")m\033[48;2;$(h2r "$1")m${PL}"
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

_end() {  # trailing separator drawn on the terminal background
  [ -n "$_prev" ] && _out+="\033[0m\033[38;2;$(h2r "$_prev")m${PL}\033[0m"
  _prev=""
}

# ─── Single-tier gauge (▀ U+2580) ───
# $1=% ("" → dim)  $2=width(default 12)
# Emits literal \033 escape sequences (interpreted later by `echo -e`).
gauge() {
  local pct="$1" w="${2:-12}"
  local filled=0 ta="40;44;64"
  if [ -n "$pct" ]; then
    filled=$(( pct * w / 100 ))
    if   [ "$pct" -ge 90 ]; then ta="247;118;142"   # red
    elif [ "$pct" -ge 70 ]; then ta="224;175;104"   # amber
    else                         ta="158;206;106"; fi # green
  fi
  local td="40;44;64" i bar="" fg
  for (( i=0; i<w; i++ )); do
    if [ "$i" -lt "$filled" ]; then fg="$ta"; else fg="$td"; fi
    bar+="\033[38;2;${fg}m\033[48;2;${td}m▀"
  done
  printf '%s' "$bar"
}

# ═══════════════════════════════════════
#  Extract data from JSON (all guarded with // empty)
# ═══════════════════════════════════════
MODEL=$(echo "$input" | jq -r '.model.display_name // empty')
VER=$(echo "$input" | jq -r '.version // empty')
PARAM_SUMMARY=$(echo "$input" | jq -r '.model.param_summary // empty')
MAX_MODE=$(echo "$input" | jq -r '.model.max_mode // false')
STYLE=$(echo "$input" | jq -r '.output_style.name // empty')
AUTORUN=$(echo "$input" | jq -r '.autorun // false')
CWD=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
WORKTREE=$(echo "$input" | jq -r '.worktree.name // empty')
CTX_PCT=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
CUR_TOK=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')
CTX_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // empty')

# Prefer explicit token count; else estimate from percentage × window size
if [ -z "$CUR_TOK" ] || [ "$CUR_TOK" = "null" ]; then
  CUR_TOK=""
  if [ -n "$CTX_PCT" ] && [ "$CTX_PCT" != "null" ] && [ -n "$CTX_SIZE" ] && [ "$CTX_SIZE" != "null" ]; then
    CUR_TOK=$(awk -v p="$CTX_PCT" -v s="$CTX_SIZE" 'BEGIN { printf "%d", p * s / 100 }')
  fi
fi
CTX_PCT_INT=""
if [ -n "$CTX_PCT" ] && [ "$CTX_PCT" != "null" ]; then
  CTX_PCT_INT="${CTX_PCT%.*}"
fi

# ─── Repo: owner/repo from git remote, fallback to dirname ───
DIR=""
owner=""; repo=""; remote_url=""
if remote_url=$(git remote get-url origin 2>/dev/null); then
  remote_url="${remote_url%.git}"
  repo="${remote_url##*/}"; owner="${remote_url%/*}"; owner="${owner##*[:/]}"
  [ -n "$owner" ] && [ -n "$repo" ] && DIR="${owner}/${repo}"
fi
[ -z "$DIR" ] && DIR="${CWD##*/}"

# ─── GitHub HTTPS base URL (for OSC 8 hyperlinks) ───
GH_BASE_URL=""
if [ -n "$owner" ] && [ -n "$repo" ]; then
  case "$remote_url" in
    *github.com*) GH_BASE_URL="https://github.com/${owner}/${repo}" ;;
  esac
fi

# ─── Git branch ───
BRANCH=""
if git rev-parse --git-dir >/dev/null 2>&1; then
  BRANCH=$(git branch --show-current 2>/dev/null)
fi

# ─── Extract issue number from branch name ───
# Patterns: feature/123-desc, fix/GH-123, issue-123, 123-desc
ISSUE_NUM=""
if [ -n "$BRANCH" ]; then
  if [[ "$BRANCH" =~ (^|[/-])(GH-)?([0-9]+)([/-]|$) ]]; then
    ISSUE_NUM="${BASH_REMATCH[3]}"
  fi
fi

# ─── Fetch issue title with background caching ───
ISSUE_TITLE=""
ISSUE_URL=""
if [ -n "$ISSUE_NUM" ] && [ -n "$GH_BASE_URL" ]; then
  ISSUE_URL="${GH_BASE_URL}/issues/${ISSUE_NUM}"
  CACHE_DIR="${TMPDIR:-/tmp}/cursor-statusline-cache"
  CACHE_FILE="${CACHE_DIR}/${owner}__${repo}__${ISSUE_NUM}"
  LOCK_FILE="${CACHE_FILE}.lock"
  CACHE_TTL=300

  mkdir -p "$CACHE_DIR" 2>/dev/null

  if [ -f "$CACHE_FILE" ]; then
    ISSUE_TITLE=$(cat "$CACHE_FILE" 2>/dev/null)
    cache_age=$(( $(date +%s) - $(_mtime "$CACHE_FILE") ))
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

# ─── Git status (fg-colored text with bg maintained for segment) ───
git_stat() {
  local bg_e="\033[48;2;$(h2r "$BG_STATUS")m"
  local a=0 d=0 u=0
  eval "$(git diff HEAD --numstat 2>/dev/null | awk '{ a+=$1; d+=$2 } END { printf "a=%d d=%d",a+0,d+0 }')"
  u=$(git status --short 2>/dev/null | grep -c '^??')
  local r=""
  [ "$a" -gt 0 ] && r+="\033[38;2;158;206;106m${bg_e}+${a}"
  [ "$d" -gt 0 ] && { [ -n "$r" ] && r+=" "; r+="\033[38;2;247;118;142m${bg_e}-${d}"; }
  [ "$u" -gt 0 ] && { [ -n "$r" ] && r+=" "; r+="\033[38;2;224;175;104m${bg_e}?${u}"; }
  echo "$r"
}
GSTAT=$(git_stat)

# ─── Mode cluster text (param_summary / max_mode / output_style / autorun) ───
MODE_PARTS=""
if [ -n "$PARAM_SUMMARY" ]; then
  # Strip surrounding parentheses if present: "(Thinking)" → "Thinking"
  _ps="${PARAM_SUMMARY#(}"; _ps="${_ps%)}"
  MODE_PARTS+="💭 ${_ps}"
fi
if [ "$MAX_MODE" = "true" ]; then
  [ -n "$MODE_PARTS" ] && MODE_PARTS+="  "; MODE_PARTS+="⚡ max"
fi
if [ -n "$STYLE" ] && [ "$STYLE" != "default" ]; then
  [ -n "$MODE_PARTS" ] && MODE_PARTS+="  "; MODE_PARTS+="🎨 ${STYLE}"
fi
if [ "$AUTORUN" = "true" ]; then
  [ -n "$MODE_PARTS" ] && MODE_PARTS+="  "; MODE_PARTS+="▶ autorun"
fi

# ═══════════════════════════════════════
#  Line 1: Cursor info + mode
# ═══════════════════════════════════════
_out=""
[ -n "$VER" ]   && _seg "$BG_VER" "$FG_LIGHT" "💥${VER}"
[ -n "$MODEL" ] && _seg "$BG_MODEL" "#FFFFFF" "🤖 ${MODEL}"
[ -n "$MODE_PARTS" ] && _seg "$BG_MODE" "$FG_MODE" "${MODE_PARTS}"
_end
LINE1="$_out"

# ═══════════════════════════════════════
#  Line 2: Git / GitHub info
# ═══════════════════════════════════════
_out=""

if [ -n "$DIR" ]; then
  if [ -n "$GH_BASE_URL" ]; then
    _seg "$BG_REPO" "#FFFFFF" "🚀 $(_link "$GH_BASE_URL" "$DIR")"
  else
    _seg "$BG_REPO" "#FFFFFF" "🚀 ${DIR}"
  fi
fi

# Location label: issue title > worktree > branch
if [ -n "$ISSUE_TITLE" ] && [ -n "$ISSUE_URL" ]; then
  _disp="$ISSUE_TITLE"
  [ ${#_disp} -gt 40 ] && _disp="${_disp:0:39}…"
  _seg "$BG_ISSUE" "#FFFFFF" "🎫 $(_link "$ISSUE_URL" "#${ISSUE_NUM}: ${_disp}")"
elif [ -n "$WORKTREE" ]; then
  _seg "$BG_WORKTREE" "#FFFFFF" "⌥ ${WORKTREE}"
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
#  Line 3: ctx (gauge + % + token#)
# ═══════════════════════════════════════
_out=""

if [ -n "$CTX_PCT_INT" ] || [ -n "$CUR_TOK" ]; then
  ge="\033[48;2;$(h2r "$BG_GAUGE")m"
  ctx_txt="\033[38;2;$(h2r "$FG_LIGHT")m${ge}🧠"
  if [ -n "$CTX_PCT_INT" ]; then
    ctx_txt+=" $(gauge "$CTX_PCT_INT" 12)${ge} ${CTX_PCT_INT}%"
  fi
  if [ -n "$CUR_TOK" ]; then
    ctx_txt+=" $(printf "%'d" "$CUR_TOK")"
  fi
  _seg_raw "$BG_GAUGE" "$ctx_txt"
fi
_end
LINE3="$_out"

# ─── Output (skip empty lines) ───
echo -en "\033[0m"
[ -n "$LINE1" ] && echo -e "$LINE1"
[ -n "$LINE2" ] && echo -e "$LINE2"
[ -n "$LINE3" ] && echo -e "$LINE3"
