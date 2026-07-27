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
BG_RATE="#1C2131"        # 5h / 7d gauges (dark so bars pop)
BG_COST="#6D5D2C"        # gold
# PR review_state
BG_PR_APPROVED="#29653D" # green
BG_PR_PENDING="#6D5D2C"  # amber
BG_PR_CHANGES="#762D33"  # red
BG_PR_DRAFT="#424757"    # slate

# Foreground colors
FG_LIGHT="#C0CAF5"       # Tokyo Night foreground (cool white)
FG_MODE="#ECE6FF"        # light purple
FG_COST="#FFF1C9"        # light gold

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

# ─── Two-tier gauge (▀ U+2580) ───
# Renders two independent horizontal bars in one row: fg = top tier, bg = bottom tier.
# $1=top% ("" → top dim)  $2=bottom% ("" → bottom dim)  $3=width(default 18)
# Emits literal \033 escape sequences (interpreted later by `echo -e`).
gauge2() {
  local top="$1" bot="$2" w="${3:-18}"
  local tf=0 bf=0 ta="40;44;64"
  if [ -n "$top" ]; then
    tf=$(( top * w / 100 ))
    if   [ "$top" -ge 90 ]; then ta="247;118;142"   # red
    elif [ "$top" -ge 70 ]; then ta="224;175;104"   # amber
    else                         ta="158;206;106"; fi # green
  fi
  [ -n "$bot" ] && bf=$(( bot * w / 100 ))
  local ba="125;207;255" td="40;44;64" bd="40;44;64" i bar="" fg bg  # ba=cyan(time), td/bd=empty track
  for (( i=0; i<w; i++ )); do
    if [ "$i" -lt "$tf" ]; then fg="$ta"; else fg="$td"; fi
    if [ "$i" -lt "$bf" ]; then bg="$ba"; else bg="$bd"; fi
    bar+="\033[38;2;${fg}m\033[48;2;${bg}m▀"
  done
  printf '%s' "$bar"
}

# ═══════════════════════════════════════
#  Extract data from JSON (all guarded with // empty)
# ═══════════════════════════════════════
MODEL=$(echo "$input" | jq -r '.model.display_name // empty')
VER=$(echo "$input" | jq -r '.version // empty')
EFFORT=$(echo "$input" | jq -r '.effort.level // empty')
THINKING=$(echo "$input" | jq -r '.thinking.enabled // false')
STYLE=$(echo "$input" | jq -r '.output_style.name // empty')
PROJECT_DIR=$(echo "$input" | jq -r '.workspace.project_dir // empty')
WORKTREE=$(echo "$input" | jq -r '.worktree.name // empty')
PR_NUM=$(echo "$input" | jq -r '.pr.number // empty')
PR_STATE=$(echo "$input" | jq -r '.pr.review_state // empty')
PR_URL=$(echo "$input" | jq -r '.pr.url // empty')
CTX_USAGE=$(echo "$input" | jq -c '.context_window.current_usage // empty')
COST_USD=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
FIVE_RESET=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
FIVE_USE=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
SEVEN_RESET=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
SEVEN_USE=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

# Current context token count (input + cache_creation + cache_read)
CUR_TOK=""
if [ -n "$CTX_USAGE" ] && [ "$CTX_USAGE" != "null" ]; then
  CUR_TOK=$(echo "$CTX_USAGE" | jq '(.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)')
fi

# ─── Repo: owner/repo from git remote, fallback to dirname ───
DIR=""
if remote_url=$(git remote get-url origin 2>/dev/null); then
  remote_url="${remote_url%.git}"
  repo="${remote_url##*/}"; owner="${remote_url%/*}"; owner="${owner##*[:/]}"
  [ -n "$owner" ] && [ -n "$repo" ] && DIR="${owner}/${repo}"
fi
[ -z "$DIR" ] && DIR="${PROJECT_DIR##*/}"

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
  CACHE_DIR="${TMPDIR:-/tmp}/claude-statusline-cache"
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

# ─── 5h rate-limit window time-elapsed % (from resets_at) ───
TIME5=""
if [ -n "$FIVE_RESET" ]; then
  fr="${FIVE_RESET%.*}"
  now=$(date +%s)
  remain=$(( fr - now ))
  [ "$remain" -lt 0 ] && remain=0
  [ "$remain" -gt 18000 ] && remain=18000   # cap at 5h window
  TIME5=$(( (18000 - remain) * 100 / 18000 ))
fi

# ─── 7d rate-limit window time-elapsed % (from resets_at) ───
TIME7=""
if [ -n "$SEVEN_RESET" ]; then
  sr="${SEVEN_RESET%.*}"
  now=$(date +%s)
  remain=$(( sr - now ))
  [ "$remain" -lt 0 ] && remain=0
  [ "$remain" -gt 604800 ] && remain=604800   # cap at 7d window
  TIME7=$(( (604800 - remain) * 100 / 604800 ))
fi

# ─── Cost cluster text (dollar only) ───
COST_SEG=""
[ -n "$COST_USD" ] && COST_SEG=$(printf '💰 $%.2f' "$COST_USD")

# ─── Mode cluster text (effort / thinking / output_style) ───
MODE_PARTS=""
[ -n "$EFFORT" ] && MODE_PARTS+="💭 ${EFFORT}"
if [ "$THINKING" = "true" ]; then
  [ -n "$MODE_PARTS" ] && MODE_PARTS+="  "; MODE_PARTS+="✨ thinking"
fi
if [ -n "$STYLE" ] && [ "$STYLE" != "default" ]; then
  [ -n "$MODE_PARTS" ] && MODE_PARTS+="  "; MODE_PARTS+="🎨 ${STYLE}"
fi

# ═══════════════════════════════════════
#  Line 1: Claude info + mode
# ═══════════════════════════════════════
_out=""
[ -n "$VER" ]   && _seg "$BG_VER" "$FG_LIGHT" "💥${VER}"
[ -n "$MODEL" ] && _seg "$BG_MODEL" "#FFFFFF" "🤖 ${MODEL}"
[ -n "$MODE_PARTS" ] && _seg "$BG_MODE" "$FG_MODE" "${MODE_PARTS}"
_end
LINE1="$_out"

# ═══════════════════════════════════════
#  Line 2: Git / GitHub info + PR
# ═══════════════════════════════════════
_out=""

if [ -n "$GH_BASE_URL" ]; then
  _seg "$BG_REPO" "#FFFFFF" "🚀 $(_link "$GH_BASE_URL" "$DIR")"
else
  _seg "$BG_REPO" "#FFFFFF" "🚀 ${DIR}"
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

# PR segment (official .pr field — no gh call needed)
if [ -n "$PR_NUM" ]; then
  pr_label="🔀#${PR_NUM}"
  case "$PR_STATE" in
    approved)          pr_bg="$BG_PR_APPROVED"; pr_label+=" ✅approved" ;;
    changes_requested) pr_bg="$BG_PR_CHANGES";  pr_label+=" ❌changes" ;;
    draft)             pr_bg="$BG_PR_DRAFT";    pr_label+=" 🐤draft" ;;
    pending)           pr_bg="$BG_PR_PENDING";  pr_label+=" ✋pending" ;;
    *)                 pr_bg="$BG_PR_DRAFT" ;;
  esac
  if [ -n "$PR_URL" ]; then
    _seg "$pr_bg" "#FFFFFF" "$(_link "$PR_URL" "$pr_label")"
  else
    _seg "$pr_bg" "#FFFFFF" "$pr_label"
  fi
fi
_end
LINE2="$_out"

# ═══════════════════════════════════════
#  Line 3: ctx (token#) + 5h/7d two-tier gauges + cost
#  Two-tier gauges pair quota usage (top, ▀ fg) with window time-elapsed (bottom, ▀ bg).
# ═══════════════════════════════════════
_out=""

# 🧠 ctx: token count only
if [ -n "$CUR_TOK" ]; then
  ge="\033[48;2;$(h2r "$BG_GAUGE")m"
  _seg_raw "$BG_GAUGE" "\033[38;2;$(h2r "$FG_LIGHT")m${ge}🧠 $(printf "%'d" "$CUR_TOK")"
fi

# ⏰ 5h gauge: usage (top) / time-elapsed (bottom)
if [ -n "$FIVE_USE" ] || [ -n "$TIME5" ]; then
  re="\033[48;2;$(h2r "$BG_RATE")m"
  _seg_raw "$BG_RATE" "\033[38;2;$(h2r "$FG_LIGHT")m${re}⏰ $(gauge2 "${FIVE_USE%.*}" "$TIME5" 12)${re}"
fi

# 📆 7d gauge: usage (top) / time-elapsed (bottom)
if [ -n "$SEVEN_USE" ] || [ -n "$TIME7" ]; then
  re="\033[48;2;$(h2r "$BG_RATE")m"
  _seg_raw "$BG_RATE" "\033[38;2;$(h2r "$FG_LIGHT")m${re}📆 $(gauge2 "${SEVEN_USE%.*}" "$TIME7" 12)${re}"
fi

# Cost ($ only)
[ -n "$COST_SEG" ] && _seg "$BG_COST" "$FG_COST" "$COST_SEG"
_end
LINE3="$_out"

# ─── Output ───
echo -en "\033[0m"
echo -e "$LINE1"
echo -e "$LINE2"
echo -e "$LINE3"
