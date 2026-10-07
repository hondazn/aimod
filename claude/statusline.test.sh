#!/usr/bin/env bash
# Mock-driven smoke tests for statusline.sh
# Asserts: (1) exit code 0 on every input, (2) expected visible markers present,
#          (3) certain markers ABSENT when their source field is missing.
# Not deployed by dotter (absent from .dotter/global.toml).
set -u

SCRIPT="$(cd "$(dirname "$0")" && pwd)/statusline.sh"
PASS=0; FAIL=0

# Strip ANSI SGR, OSC-8 hyperlinks and the Powerline glyph so we match visible text.
strip() { perl -pe 's/\e\[[0-9;]*m//g; s/\e\]8;;[^\a]*\a//g; s/\xee\x82[\xb0-\xbf]|\xee\x83[\x80-\x94]//g'; }

# run NAME CWD JSON -- WANT... ! NOWANT...
#   tokens after `--` are required substrings; tokens after `!` are forbidden.
run() {
  local name="$1" cwd="$2" json="$3"; shift 3
  [ "$1" = "--" ] && shift
  local want=() forbid=() mode="want"
  for t in "$@"; do
    if [ "$t" = "!" ]; then mode="forbid"; continue; fi
    if [ "$mode" = "want" ]; then want+=("$t"); else forbid+=("$t"); fi
  done

  local out rc vis miss="" bad=""
  out=$( cd "$cwd" && printf '%s' "$json" | bash "$SCRIPT" 2>/dev/null ); rc=$?
  if [ "$rc" -ne 0 ]; then echo "✗ $name — exit code $rc (expected 0)"; FAIL=$((FAIL+1)); return; fi
  vis=$(printf '%s' "$out" | strip)

  local s
  for s in "${want[@]:-}";   do [ -z "$s" ] && continue; case "$vis" in *"$s"*) ;; *) miss+=" [$s]";; esac; done
  for s in "${forbid[@]:-}"; do [ -z "$s" ] && continue; case "$vis" in *"$s"*) bad+=" [$s]";; esac; done

  if [ -n "$miss" ] || [ -n "$bad" ]; then
    echo "✗ $name —${miss:+ missing:$miss}${bad:+ forbidden:$bad}"
    FAIL=$((FAIL+1))
  else
    echo "✓ $name"; PASS=$((PASS+1))
  fi
}

REPO="$(cd "$(dirname "$0")" && pwd)"   # a real git repo → exercises repo/branch paths
TMP="${TMPDIR:-/tmp}"                   # not a git repo → exercises fallback

# 1) full payload — everything present (token count from current_usage = 124,500)
run "full" "$REPO" '{
  "model":{"display_name":"Opus"},"version":"2.1.160",
  "effort":{"level":"high"},"thinking":{"enabled":true},"output_style":{"name":"explanatory"},
  "workspace":{"project_dir":"/x/aimod"},
  "pr":{"number":42,"review_state":"approved","url":"https://github.com/o/r/pull/42"},
  "context_window":{"used_percentage":62,"current_usage":{"input_tokens":50000,"cache_creation_input_tokens":30000,"cache_read_input_tokens":44500}},
  "cost":{"total_cost_usd":0.34,"total_duration_ms":480000,"total_lines_added":156,"total_lines_removed":23},
  "rate_limits":{"five_hour":{"used_percentage":23,"resets_at":9999999999},"seven_day":{"used_percentage":12,"resets_at":9999999999}}
}' -- "🤖 Opus" "💭 high" "💭" "🎨 explanatory" "🔀#42" "approved" "🧠" "124" "⏰" "📆" "💰" '$0.34' ! "🔋" "Σ" "62%" "ctx" "💥" "2.1.160"

# 2) no PR (token count from current_usage, no ctx %)
run "no-pr" "$REPO" '{
  "model":{"display_name":"Opus"},"version":"2.1.160","workspace":{"project_dir":"/x/aimod"},
  "context_window":{"used_percentage":40,"current_usage":{"input_tokens":80000}},
  "rate_limits":{"five_hour":{"used_percentage":10,"resets_at":9999999999},"seven_day":{"used_percentage":5,"resets_at":9999999999}}
}' -- "🧠" "⏰" "📆" ! "🔀" "40%"

# 3) no rate_limits (free tier / before first response) → 5h+7d gauges omitted, ctx still renders
run "no-ratelimits" "$REPO" '{
  "model":{"display_name":"Sonnet"},"version":"2.1.160","workspace":{"project_dir":"/x/aimod"},
  "context_window":{"used_percentage":15,"current_usage":{"input_tokens":33000}}
}' -- "🤖 Sonnet" "🧠" ! "⏰" "📆" "🔋"

# 4) worktree session → ⌥ marker
run "worktree" "$REPO" '{
  "model":{"display_name":"Opus"},"version":"2.1.160","workspace":{"project_dir":"/x/aimod"},
  "worktree":{"name":"feat-foo"},"context_window":{"used_percentage":20,"current_usage":{"input_tokens":12000}}
}' -- "⌥ feat-foo" "🧠"

# 5) not a git repo → repo falls back to project_dir basename, no branch
run "not-git" "$TMP" '{
  "model":{"display_name":"Opus"},"version":"2.1.160","workspace":{"project_dir":"/x/myproj"},
  "context_window":{"used_percentage":30,"current_usage":{"input_tokens":45000}}
}' -- "🚀 myproj" "🧠" ! "⚡"

# 6) effort-less model + default output_style → mode markers absent
run "no-effort-default-style" "$REPO" '{
  "model":{"display_name":"Haiku"},"version":"2.1.160","workspace":{"project_dir":"/x/aimod"},
  "thinking":{"enabled":false},"output_style":{"name":"default"},
  "context_window":{"used_percentage":5,"current_usage":{"input_tokens":7000}}
}' -- "🤖 Haiku" "🧠" ! "🎚" "🎨" "💭"

# 7) empty / minimal payload → must not crash
run "minimal" "$TMP" '{}' --

# 7b) session fields: repo from workspace.repo, session name, fast mode, window size,
#     warm cache time left + hit ratio, elapsed time, lines edited
run "session-fields" "$REPO" '{
  "model":{"display_name":"Opus"},"fast_mode":true,"session_name":"statusline",
  "workspace":{"project_dir":"/x/aimod","repo":{"host":"github.com","owner":"o","name":"r"}},
  "context_window":{"context_window_size":1000000,"current_usage":{"input_tokens":1000}},
  "cost":{"total_duration_ms":24760147,"total_lines_added":312,"total_lines_removed":241},
  "prompt_cache":{"warm":true,"expires_at":'"$(( $(date +%s) + 125 ))"',"hit_ratio":0.9425}
}' -- "🚀 o/r" "💬 statusline" "⏩ fast" "1,000 / 1M" "🔥 2:0" "🎯 94%" "⏳ 6h52m" "📝 +312 -241" ! "🧊"

# 7c) cache gone cold (warm=false) or past expires_at → 🧊 cold, no countdown
run "cache-cold" "$REPO" '{"model":{"display_name":"Opus"},"prompt_cache":{"warm":false,"hit_ratio":0.5}}' \
  -- "🧊 cold" "🎯 50%" ! "🔥"
run "cache-expired" "$REPO" '{"model":{"display_name":"Opus"},"prompt_cache":{"warm":true,"expires_at":1000}}' \
  -- "🧊 cold" ! "🔥"

# 7d) startup (shape captured from 2.1.292 before the first response): current_usage null,
#     no prompt_cache, no session_name → dim placeholders keep every slot filled
run "startup" "$REPO" '{
  "session_id":"72820269-655d-498f-aba4-10e8de828a78","model":{"display_name":"Opus 5.5"},
  "workspace":{"project_dir":"/x/aimod"},
  "cost":{"total_cost_usd":0,"total_duration_ms":10754,"total_lines_added":0,"total_lines_removed":0},
  "context_window":{"context_window_size":1000000,"current_usage":null}
}' -- "🚧" "🧠 0 / 1M" "🔥 --:--" "🎯 --%" "💬 72820269" '💰 $0.00' "📝 +0 -0" ! "🧊" "655d"

# 8) layout: each ◣◥ divider (U+E0B8 U+E0BE) steps one column right per row (parallel "\"
#    lines across rows), the first block's content starts at the same column on every row,
#    the others start one column right of the row above, and the end glyphs sit at the
#    same columns on every row.
layout=$( cd "$REPO" && printf '%s' '{
  "model":{"display_name":"Opus"},"effort":{"level":"high"},"thinking":{"enabled":true},"session_name":"statusline",
  "workspace":{"project_dir":"/x/aimod"},"pr":{"number":42,"review_state":"approved"},
  "context_window":{"current_usage":{"input_tokens":124500}},"cost":{"total_cost_usd":0.34,"total_duration_ms":60000},
  "prompt_cache":{"warm":false,"hit_ratio":0.9},
  "rate_limits":{"five_hour":{"used_percentage":23,"resets_at":9999999999},"seven_day":{"used_percentage":12,"resets_at":9999999999}}
}' | bash "$SCRIPT" 2>/dev/null | perl -CS -ne '
  s/\e\[[0-9;]*m//g; s/\e\]8;;[^\a]*\a//g; chomp;
  my ($col, $prev, $after, @divs, @starts) = (0, "", 1);
  my ($first, $last) = (-1, -1);
  for my $c (split //) {
    my $glyph = $c =~ /[\x{E0B0}-\x{E0D4}]/;
    $first = $col if $glyph && $first < 0;
    if ($c eq "\x{E0BE}" && $prev eq "\x{E0B8}") { push @divs, $col - 1; $after = 1 }
    elsif ($after && $first >= 0 && !$glyph && $c ne " ") { push @starts, $col; $after = 0 }
    $last = $col if $glyph;
    $col += $c =~ /[\p{Mn}\x{200D}\x{FE0F}]/ ? 0 : $c =~ /[\p{EA=W}\p{EA=F}]/ ? 2 : 1; $prev = $c;
  }
  print join(",", @divs), " ", join(",", @starts), " $first $last\n"' | awk '
  { d[NR] = $1; s[NR] = $2; f[NR] = $3; l[NR] = $4 }
  END {
    ok = (NR == 3 && split(d[1], a, ",") == 2 && split(s[1], b, ",") == 3)
    for (i = 2; i <= NR; i++) {
      split(d[i-1], p, ","); n = split(d[i], c, ",")
      if (n != 2 || c[1] != p[1] + 1 || c[2] != p[2] + 1) ok = 0
      split(s[i-1], q, ","); m = split(s[i], t, ",")
      if (m != 3 || t[1] != q[1] || t[2] != q[2] + 1 || t[3] != q[3] + 1) ok = 0
      if (f[i] != f[1] || l[i] != l[1]) ok = 0
    }
    print ok ? "ok" : "rows=" NR " divs=" d[1] "|" d[2] "|" d[3] " starts=" s[1] "|" s[2] "|" s[3] " ends=" f[1] "-" l[1] "|" f[2] "-" l[2] "|" f[3] "-" l[3]
  }' )
if [ "$layout" = "ok" ]; then echo "✓ layout"; PASS=$((PASS+1)); else echo "✗ layout — $layout"; FAIL=$((FAIL+1)); fi

# 9) no line starts with a space: Claude Code trims it, shifting an indented "<" / ">" row
lead=$( cd "$REPO" && printf '%s' '{"model":{"display_name":"Opus"},"workspace":{"project_dir":"/x/aimod"},
  "context_window":{"current_usage":{"input_tokens":1}},"cost":{"total_cost_usd":1},
  "rate_limits":{"five_hour":{"used_percentage":1,"resets_at":9999999999}}}' | bash "$SCRIPT" 2>/dev/null | grep -c '^ ' )
if [ "$lead" = "0" ]; then echo "✓ no-leading-space"; PASS=$((PASS+1)); else echo "✗ no-leading-space — $lead line(s)"; FAIL=$((FAIL+1)); fi

# 10) the left end glyph is followed by an unpainted space, so Ghostty's two-cell spread
#     of the glyph lands on the terminal bg rather than inside the band
blank=$( cd "$REPO" && printf '%s' '{"model":{"display_name":"Opus"},"workspace":{"project_dir":"/x/aimod"}}' \
  | bash "$SCRIPT" 2>/dev/null | perl -CS -ne '
    my ($bg, $ok) = ("none", 0);
    while (/\G(\e\[([0-9;]*)m|.)/gc) {
      my ($t, $sgr) = ($1, $2);
      if (defined $sgr) { $bg = "none" if $sgr =~ /(^|;)(0|49)(;|$)/ || $sgr eq ""; $bg = "set" if $sgr =~ /(^|;)48;/; next }
      if ($t eq "\x{E0CA}") { $ok = -1; next }
      if ($ok == -1) { $ok = ($t eq " " && $bg eq "none") ? 1 : 0; last }
    }
    print $ok == 1 ? "ok\n" : "bad\n"' | sort -u )
if [ "$blank" = "ok" ]; then echo "✓ left-end-blank"; PASS=$((PASS+1)); else echo "✗ left-end-blank — $blank"; FAIL=$((FAIL+1)); fi

echo "─────────────────────────────"
echo "PASS=$PASS  FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
