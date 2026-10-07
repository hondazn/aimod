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

# ─── Nerdfont Powerline Extra glyphs for the band outline ───
# Ends are ice waveforms; the divider is a ◣◥ pair whose gap is a one-cell slanted stripe.
# Ghostty widens a symbol to two cells only rightward and only over a blank next cell
# (renderer/cell.zig constraintWidth), so the left end is followed by an unpainted space:
# its wave then spreads over the terminal bg, mirroring the right end, not into the band.
ICE_L=$(printf '\xee\x83\x8a')   # U+E0CA ice waveform mirrored (solid on the right)
ICE_R=$(printf '\xee\x83\x88')   # U+E0C8 ice waveform (solid on the left)
LL=$(printf '\xee\x82\xb8')      # ◣ lower-left
UR=$(printf '\xee\x82\xbe')      # ◥ upper-right

# ─── Palette (Ghostty theme 0x96f, bg #262427) ───
# 地はティールから青への横グラデーション1本、色はアイコンに任せる。文字は主と副の明度2段で
# 優先度を表し、アクセント色は状態（差分・PR・ゲージ）にだけ使う。地が中明度なので、
# 文字のアクセントはテーマ色を淡くした値にしてコントラストを保つ。ゲージは自前の暗い空きの上に
# 塗るので、淡くしない。
C_GRAD_FROM="#2A6B65"    # band gradient, left edge (teal)
C_GRAD_TO="#2B5A88"      # band gradient, right edge (blue)
C_FG="#FCFCFA"           # primary
C_SUB="#D4E9E5"          # secondary
C_DIM="#93BDB8"          # placeholder before data arrives
C_RED="#FFA3A8"
C_GREEN="#D2F58A"
C_YELLOW="#FFE07A"
C_CYAN="#CFF8FC"
C_LAVENDER="#E0D8FF"
# Gauge fills (not text)
C_TRACK="#1B3B45"        # empty track: recessed band shade, not a hole
C_USE_OK="#9ECE6A"
C_USE_WARN="#E0AF68"
C_USE_CRIT="#F7768E"
C_TIME="#7DCFFF"         # window time elapsed

# ─── Text / pill builders ───
# Strings carry literal \033 escapes, interpreted once by `echo -e` at output.
_t() { printf '\\033[38;2;%sm%s' "$(h2r "$1")" "$2"; }               # $1=color $2=text
_b() { printf '\\033[1;38;2;%sm%s\\033[22m' "$(h2r "$1")" "$2"; }    # bold

# Markers resolved by the gradient painter at output: \001 = band background on,
# \002 = next char is an outline glyph (fg takes the gradient colour at its column).
_BG="\001"
_CAP="\033[0m\002"

_join() {  # non-empty items → one cell body, separated by two spaces
  local out="" it
  for it in "$@"; do
    [ -z "$it" ] && continue
    [ -n "$out" ] && out+="${_BG}  "
    out+="${_BG}${it}"
  done
  printf '%s' "$out"
}

# Display width as the terminal draws it: escapes 0, East Asian Wide/Fullwidth 2,
# combining marks / ZWJ / VS16 0. Ambiguous (▀, …) counts 1 like Ghostty.
_w() {
  printf '%s' "$1" | perl -CS -0777 -ne '
    s/\\033\]8;;.*?\\007//g; s/\\033\[[0-9;]*m//g; s/\\00[12]//g;
    my $n = () = /./gs; my $wide = () = /[\p{EA=W}\p{EA=F}]/g; my $zero = () = /[\p{Mn}\x{200D}\x{FE0F}]/g;
    print $n + $wide - $zero'
}

_trunc() {  # $1=text $2=max display width; cut with … when wider
  printf '%s' "$1" | MAX="$2" perl -CS -0777 -ne '
    my @c = split //; my $cw = sub { $_[0] =~ /[\p{EA=W}\p{EA=F}]/ ? 2 : 1 };
    my $tot = 0; $tot += $cw->($_) for @c;
    if ($tot <= $ENV{MAX}) { print join "", @c; exit }
    my ($w, $o) = (0, ""); for (@c) { last if $w + $cw->($_) > $ENV{MAX} - 1; $o .= $_; $w += $cw->($_) }
    print "$o\x{2026}"'
}

# ─── Layout: CELL[row*3+col] → one band per row, three blocks split by slanted dividers ───
# Every row has the same width. Each divider sits one column further right than the row above,
# drawing parallel "\" lines, and the text after a divider follows it; the first block stays
# left-aligned against the straight end. The third block (and its divider)
# is drawn only when some row has a cell for it.
# (Flat arrays: macOS /bin/bash is 3.2.)
CELL=()
_sp() { printf '%*s' "$1" ''; }

_render() {  # prints the visible rows
  local r k n rows=() i w0 w1 w2 line
  for (( r=0; r<3; r++ )); do
    [ -n "${CELL[r*3]}${CELL[r*3+1]}${CELL[r*3+2]}" ] && rows+=("$r")
  done
  n=${#rows[@]}
  w0=${COLW[0]:-0}; w1=${COLW[1]:-0}; w2=${COLW[2]:-0}
  for (( k=0; k<n; k++ )); do
    i=$(( ${rows[k]} * 3 ))
    line="${_CAP}${ICE_L} ${_BG} ${CELL[i]}${_BG}$(_sp $(( w0 - ${CW[i]:-0} + k ))) ${_CAP}${LL}${_CAP}${UR}"
    line+="${_BG} ${CELL[i+1]}${_BG}"
    if [ "$w2" -gt 0 ]; then
      line+="$(_sp $(( w1 - ${CW[i+1]:-0} ))) ${_CAP}${LL}${_CAP}${UR}"
      line+="${_BG} ${CELL[i+2]}${_BG}$(_sp $(( w2 - ${CW[i+2]:-0} + n - 1 - k )))"
    else
      line+="$(_sp $(( w1 - ${CW[i+1]:-0} + n - 1 - k )))"
    fi
    printf '%s\\n' "${line} ${_CAP}${ICE_R}\033[0m"
  done
}

# ─── Two-tier gauge (▀ U+2580) ───
# Renders two independent horizontal bars in one row: fg = top tier, bg = bottom tier.
# $1=top% ("" → top dim)  $2=bottom% ("" → bottom dim)  $3=width(default 18)
gauge2() {
  local top="$1" bot="$2" w="${3:-18}"
  local track; track=$(h2r "$C_TRACK")
  local tf=0 bf=0 ta="$track"
  if [ -n "$top" ]; then
    tf=$(( top * w / 100 ))
    if   [ "$top" -ge 90 ]; then ta=$(h2r "$C_USE_CRIT")
    elif [ "$top" -ge 70 ]; then ta=$(h2r "$C_USE_WARN")
    else                         ta=$(h2r "$C_USE_OK"); fi
  fi
  [ -n "$bot" ] && bf=$(( bot * w / 100 ))
  local ba i bar="" fg bg
  ba=$(h2r "$C_TIME")
  for (( i=0; i<w; i++ )); do
    if [ "$i" -lt "$tf" ]; then fg="$ta"; else fg="$track"; fi
    if [ "$i" -lt "$bf" ]; then bg="$ba"; else bg="$track"; fi
    bar+="\033[38;2;${fg}m\033[48;2;${bg}m▀"
  done
  printf '%s' "$bar"
}

# ═══════════════════════════════════════
#  Extract data from JSON (all guarded with // empty)
# ═══════════════════════════════════════
MODEL=$(echo "$input" | jq -r '.model.display_name // empty')
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
CTX_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // empty')
REPO_HOST=$(echo "$input" | jq -r '.workspace.repo.host // empty')
REPO_OWNER=$(echo "$input" | jq -r '.workspace.repo.owner // empty')
REPO_NAME=$(echo "$input" | jq -r '.workspace.repo.name // empty')
SESSION_NAME=$(echo "$input" | jq -r '.session_name // empty')
SESSION_ID=$(echo "$input" | jq -r '.session_id // empty')
FAST=$(echo "$input" | jq -r '.fast_mode // false')
DURATION_MS=$(echo "$input" | jq -r '.cost.total_duration_ms // empty')
LINES_ADD=$(echo "$input" | jq -r '.cost.total_lines_added // empty')
LINES_DEL=$(echo "$input" | jq -r '.cost.total_lines_removed // empty')
CACHE_WARM=$(echo "$input" | jq -r '.prompt_cache.warm | values')  # keeps false (// would drop it)
CACHE_EXPIRES=$(echo "$input" | jq -r '.prompt_cache.expires_at // empty')
CACHE_HIT=$(echo "$input" | jq -r '.prompt_cache.hit_ratio // empty | . * 100 | round')

# Current context token count (input + cache_creation + cache_read)
CUR_TOK=""
if [ -n "$CTX_USAGE" ] && [ "$CTX_USAGE" != "null" ]; then
  CUR_TOK=$(echo "$CTX_USAGE" | jq '(.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)')
fi

# ─── Repo: owner/repo from workspace.repo, fallback to dirname ───
owner="$REPO_OWNER"; repo="$REPO_NAME"
DIR="${PROJECT_DIR##*/}"
[ -n "$owner" ] && [ -n "$repo" ] && DIR="${owner}/${repo}"

# ─── GitHub HTTPS base URL (for OSC 8 hyperlinks) ───
# host can be an ssh alias such as personal.github.com
GH_BASE_URL=""
if [ -n "$owner" ] && [ -n "$repo" ]; then
  case "$REPO_HOST" in
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

# ─── Git status: +added -deleted ?untracked ───
git_stat() {
  local a=0 d=0 u=0
  eval "$(git diff HEAD --numstat 2>/dev/null | awk '{ a+=$1; d+=$2 } END { printf "a=%d d=%d",a+0,d+0 }')"
  u=$(git status --short 2>/dev/null | grep -c '^??')
  local r=""
  [ "$a" -gt 0 ] && r+="$(_t "$C_GREEN" "+${a}")"
  [ "$d" -gt 0 ] && { [ -n "$r" ] && r+=" "; r+="$(_t "$C_RED" "-${d}")"; }
  [ "$u" -gt 0 ] && { [ -n "$r" ] && r+=" "; r+="$(_t "$C_YELLOW" "?${u}")"; }
  [ -n "$r" ] && echo "🚧 $r"
}
GSTAT=""
if git rev-parse --git-dir >/dev/null 2>&1; then
  GSTAT=$(git_stat)
  [ -z "$GSTAT" ] && GSTAT="🚧 $(_t "$C_DIM" clean)"
fi

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

# ═══════════════════════════════════════
#  Cells — columns: identity | this session's usage | state
#    row 0 where:  repo + location + PR | elapsed, lines edited | session name
#    row 1 who:    model + mode         | ctx                   | prompt cache (time left, hit ratio)
#    row 2 budget: 5h/7d gauges         | cost                  | working-tree diff
#  Gauges pair quota usage (top, ▀ fg) with window time-elapsed (bottom, ▀ bg).
# ═══════════════════════════════════════
if [ -n "$GH_BASE_URL" ]; then
  repo_item="🚀 $(_b "$C_FG" "$(_link "$GH_BASE_URL" "$DIR")")"
else
  repo_item="🚀 $(_b "$C_FG" "$DIR")"
fi

# Location: issue title > worktree > branch
loc_item=""
if [ -n "$ISSUE_TITLE" ] && [ -n "$ISSUE_URL" ]; then
  _disp=$(_trunc "$ISSUE_TITLE" 32)
  loc_item="🎫 $(_link "$ISSUE_URL" "$(_t "$C_CYAN" "#${ISSUE_NUM}") $(_t "$C_FG" "$_disp")")"
elif [ -n "$WORKTREE" ]; then
  loc_item="⌥ $(_t "$C_GREEN" "$WORKTREE")"
elif [ -n "$BRANCH" ]; then
  if [ -n "$GH_BASE_URL" ]; then
    loc_item="⚡️$(_t "$C_CYAN" "$(_link "${GH_BASE_URL}/tree/${BRANCH}" "$BRANCH")")"
  else
    loc_item="⚡️$(_t "$C_CYAN" "$BRANCH")"
  fi
fi

# PR (official .pr field — no gh call needed)
pr_item=""
if [ -n "$PR_NUM" ]; then
  case "$PR_STATE" in
    approved)          pr_state=" ✅$(_t "$C_GREEN" approved)" ;;
    changes_requested) pr_state=" ❌$(_t "$C_RED" changes)" ;;
    draft)             pr_state=" 🐤$(_t "$C_SUB" draft)" ;;
    pending)           pr_state=" ✋$(_t "$C_YELLOW" pending)" ;;
    *)                 pr_state="" ;;
  esac
  pr_item="🔀$(_b "$C_FG" "#${PR_NUM}")"
  [ -n "$PR_URL" ] && pr_item=$(_link "$PR_URL" "$pr_item")
  pr_item+="$pr_state"
fi

model_item=""
[ -n "$MODEL" ] && model_item="🤖 $(_b "$C_FG" "$MODEL")"
effort_item="";   [ -n "$EFFORT" ] && effort_item="💭 $(_t "$C_LAVENDER" "$EFFORT")"
thinking_item=""; [ "$THINKING" = "true" ] && thinking_item="✨ $(_t "$C_LAVENDER" thinking)"
style_item="";    [ -n "$STYLE" ] && [ "$STYLE" != "default" ] && style_item="🎨 $(_t "$C_LAVENDER" "$STYLE")"
fast_item="";     [ "$FAST" = "true" ] && fast_item="⏩ $(_t "$C_LAVENDER" fast)"

five_item="";  { [ -n "$FIVE_USE" ]  || [ -n "$TIME5" ]; } && five_item="⏰ $(gauge2 "${FIVE_USE%.*}" "$TIME5" 12)"
seven_item=""; { [ -n "$SEVEN_USE" ] || [ -n "$TIME7" ]; } && seven_item="📆 $(gauge2 "${SEVEN_USE%.*}" "$TIME7" 12)"

# Context: tokens in use / window size (1000000 → 1M, 200000 → 200k)
ctx_item="" size=""
if [ -n "$CTX_SIZE" ]; then
  if [ $(( CTX_SIZE % 1000000 )) -eq 0 ]; then size="$(( CTX_SIZE / 1000000 ))M"; else size="$(( CTX_SIZE / 1000 ))k"; fi
fi
if [ -n "$CUR_TOK" ]; then
  ctx_item="🧠 $(_t "$C_FG" "$(printf "%'d" "$CUR_TOK")")"
  [ -n "$size" ] && ctx_item+=" $(_t "$C_SUB" "/ $size")"
elif [ -n "$size" ]; then  # before the first response current_usage is null
  ctx_item="🧠 $(_t "$C_DIM" "0 / $size")"
fi

# Prompt cache: time until the warm cache expires (yellow in the last minute), then cold
cache_item=""
if [ "$CACHE_WARM" = "true" ] && [ -n "$CACHE_EXPIRES" ] && [ $(( ${CACHE_EXPIRES%.*} - $(date +%s) )) -gt 0 ]; then
  left=$(( ${CACHE_EXPIRES%.*} - $(date +%s) ))
  cache_color="$C_FG"; [ "$left" -le 60 ] && cache_color="$C_YELLOW"
  cache_item="🔥 $(_t "$cache_color" "$(printf '%d:%02d' $(( left / 60 )) $(( left % 60 )))")"
elif [ -n "$CACHE_WARM" ]; then
  cache_item="🧊 $(_t "$C_RED" cold)"
elif [ -n "$MODEL" ]; then  # no request sent yet
  cache_item="🔥 $(_t "$C_DIM" "--:--")"
fi
hit_item=""
if [ -n "$CACHE_HIT" ]; then hit_item="🎯 $(_t "$C_SUB" "${CACHE_HIT}%")"
elif [ -n "$MODEL" ]; then hit_item="🎯 $(_t "$C_DIM" "--%")"; fi

# Session: name, elapsed wall time, lines Claude added/removed
# Unnamed session: the id prefix, enough for `claude --resume`
session_item=""
if   [ -n "$SESSION_NAME" ]; then session_item="💬 $(_t "$C_FG" "$(_trunc "$SESSION_NAME" 28)")"
elif [ -n "$SESSION_ID" ];   then session_item="💬 $(_t "$C_DIM" "${SESSION_ID%%-*}")"; fi
dur_item=""
if [ -n "$DURATION_MS" ]; then
  s=$(( ${DURATION_MS%.*} / 1000 ))
  if   [ "$s" -ge 3600 ]; then dur="$(( s / 3600 ))h$(printf '%02d' $(( s % 3600 / 60 )))m"
  elif [ "$s" -ge 60 ];   then dur="$(( s / 60 ))m"
  else                         dur="${s}s"; fi
  dur_item="⏳ $(_t "$C_SUB" "$dur")"
fi
lines_item=""
if [ "${LINES_ADD:-0}${LINES_DEL:-0}" = "00" ]; then
  [ -n "$LINES_ADD$LINES_DEL" ] && lines_item="📝 $(_t "$C_DIM" "+0 -0")"
else
  lines_item="📝 $(_t "$C_GREEN" "+${LINES_ADD:-0}") $(_t "$C_RED" "-${LINES_DEL:-0}")"
fi

CELL[0]=$(_join "$repo_item" "$loc_item" "$pr_item")
CELL[1]=$(_join "$dur_item" "$lines_item")
CELL[2]=$(_join "$session_item")
CELL[3]=$(_join "$model_item" "$effort_item" "$thinking_item" "$style_item" "$fast_item")
CELL[4]=$(_join "$ctx_item")
CELL[5]=$(_join "$cache_item" "$hit_item")
CELL[6]=$(_join "$five_item" "$seven_item")
if [ -n "$COST_USD" ]; then
  cost=$(printf '$%.2f' "$COST_USD"); cost_color="$C_SUB"; [ "$cost" = '$0.00' ] && cost_color="$C_DIM"
  CELL[7]=$(_join "💰 $(_t "$cost_color" "$cost")")
fi
CELL[8]=$(_join "$GSTAT")

# Column width = widest cell in that column
CW=(); COLW=()
for (( i=0; i<9; i++ )); do
  [ -z "${CELL[i]}" ] && continue
  CW[i]=$(_w "${CELL[i]}")
  c=$(( i % 3 ))
  [ "${CW[i]}" -gt "${COLW[c]:-0}" ] && COLW[c]=${CW[i]}
done

# ─── Output: one horizontal gradient shared by all rows ───
rows=$(_render)
echo -en "\033[0m"
echo -en "$rows" | GRAD_FROM=$(h2r "$C_GRAD_FROM") GRAD_TO=$(h2r "$C_GRAD_TO") perl -CS -0777 -ne '
  my @from = split /;/, $ENV{GRAD_FROM}; my @to = split /;/, $ENV{GRAD_TO};
  my $tok = qr/\G(\e\[[0-9;]*m|\e\]8;;[^\a]*\a|.)/s;
  sub cw { my $c = shift; $c =~ /[\p{Mn}\x{200D}\x{FE0F}]/ ? 0 : $c =~ /[\p{EA=W}\p{EA=F}]/ ? 2 : 1 }
  my @lines = split /\n/;
  my $W = 1;
  for my $l (@lines) {
    my $w = 0;
    while ($l =~ /$tok/gc) { my $t = $1; $w += cw($t) unless $t =~ /^[\e\x01\x02]/ }
    $W = $w if $w > $W;
  }
  sub grad { my $p = $W > 1 ? $_[0] / ($W - 1) : 0; join ";", map { int($from[$_] + ($to[$_] - $from[$_]) * $p + 0.5) } 0..2 }
  for my $l (@lines) {
    my ($col, $pill, $cap, $out) = (0, 0, 0, "");
    pos($l) = 0;  # the width pass left pos at the end (/c keeps it)
    while ($l =~ /$tok/gc) {
      my $t = $1;
      if    ($t eq "\x01") { $pill = 1 }
      elsif ($t eq "\x02") { $cap = 1 }
      elsif ($t =~ /^\e/)  { $pill = 0 if $t =~ /^\e\[(?:0?m|48;)/; $out .= $t }  # explicit bg (gauge) or reset ends pill paint
      else {
        my $g = grad($col);
        if    ($cap)  { $out .= "\e[49;38;2;${g}m$t\e[39m"; $cap = 0 }
        elsif ($pill) { $out .= "\e[48;2;${g}m$t" }
        else          { $out .= $t }
        $col += cw($t);
      }
    }
    print "\e[0m$out\n";  # Claude Code trims leading spaces; an escape first keeps the indent
  }'
