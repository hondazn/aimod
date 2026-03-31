#!/usr/bin/env bash

input=$(cat)

# jqを使用して値を抽出
MODEL_DISPLAY="🤖$(echo "$input" | jq -r '.model.display_name')"
current_path=$(echo "$input" | jq -r '.workspace.project_dir')
# gitリポジトリならremoteからowner/repoを取得、なければbasename
CURRENT_DIR=""
if remote_url=$(git remote get-url origin 2>/dev/null); then
  remote_url="${remote_url%.git}"
  repo="${remote_url##*/}"
  owner="${remote_url%/*}"
  owner="${owner##*[:/]}"
  if [ -n "$owner" ] && [ -n "$repo" ]; then
    CURRENT_DIR="🚀${owner}/${repo}"
  fi
fi
if [ -z "$CURRENT_DIR" ]; then
  CURRENT_DIR="🚀${current_path##*/}"
fi
VERSION="💥$(echo "$input" | jq -r '.version')"
#TOTAL_COST="💰$(echo "$input" | jq -r '.cost.total_cost_usd')"

GIT_BRANCH=""
if git rev-parse --git-dir > /dev/null 2>&1; then
    BRANCH=$(git branch --show-current 2>/dev/null)
    if [ -n "$BRANCH" ]; then
        GIT_BRANCH="⚡$BRANCH"
    fi
fi

function gstat() {
    # 1. 追跡中ファイルの変更行数を集計 (ステージング済み + 未ステージング)
    local diff_summary
    diff_summary=$(git diff HEAD --numstat | awk '
        { added += $1; deleted += $2 }
        END {
            output = "";
            if (added > 0) {
                output = sprintf("\033[38;2;0;212;0m+%d\033[0m", added);
            }
            if (deleted > 0) {
                if (output != "") { output = output " "; }
                output = output sprintf("\033[38;2;255;96;96m-%d\033[0m", deleted);
            }
            printf "%s", output;
        }')

    # 2. Untracked fileの数を集計
    local untracked_summary
    untracked_summary=$(git status --short | awk '
        /^\?\?/ { count++ }
        END {
            if (count > 0) {
                printf "\033[38;2;212;212;0m?%d\033[0m", count;
            }
        }')

    # 3. 結果を結合して出力
    local final_output=""
    if [ -n "$diff_summary" ]; then
        final_output="$diff_summary"
    fi
    if [ -n "$untracked_summary" ]; then
        # ここが修正点です
        if [ -n "$final_output" ]; then
            final_output="$final_output "
        fi
        final_output="$final_output$untracked_summary"
    fi

    if [ -n "$final_output" ]; then
        echo "$final_output"
    fi
}

GIT_STATUS=$(gstat)

# context_window から直接取得
CONTEXT_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size')
USAGE=$(echo "$input" | jq '.context_window.current_usage')

if [ "$USAGE" != "null" ] && [ "$CONTEXT_SIZE" != "null" ] && [ "$CONTEXT_SIZE" != "0" ]; then
  # 現在のコンテキスト使用量を計算
  CURRENT_TOKENS=$(echo "$USAGE" | jq '(.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)')

  # パーセンテージ計算
  percentage=$((CURRENT_TOKENS * 100 / CONTEXT_SIZE))

  # トークン表示フォーマット（カンマ区切り）
  token_display=$(printf "%'d" "$CURRENT_TOKENS")

  # 色分け
  if [ "$percentage" -ge 90 ]; then
    color="\033[31m"  # Red
  elif [ "$percentage" -ge 70 ]; then
    color="\033[33m"  # Yellow
  else
    color="\033[32m"  # Green
  fi

  TOKEN_COUNT="🧠${token_display}"
else
  TOKEN_COUNT="🧠-"
fi

# rate_limits の表示
RATE_LIMITS_LINE=""
FIVE_H=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
SEVEN_D=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

if [ -n "$FIVE_H" ] || [ -n "$SEVEN_D" ]; then
  rate_color() {
    local pct_int=${1%.*}
    if [ "$pct_int" -ge 90 ]; then
      echo "\033[31m"  # Red
    elif [ "$pct_int" -ge 70 ]; then
      echo "\033[33m"  # Yellow
    else
      echo "\033[32m"  # Green
    fi
  }

  # ゲージを生成: gauge <pct> <width>
  # 例: 45% width=10 → "████▌     "
  gauge() {
    local pct=$1
    local width=${2:-10}
    local pct_int=${pct%.*}
    # 塗りつぶしブロック数を計算 (half-block対応)
    local filled_x2=$(( pct_int * width * 2 / 100 ))
    local full_blocks=$(( filled_x2 / 2 ))
    local half=$(( filled_x2 % 2 ))
    local empty=$(( width - full_blocks - half ))

    local bar=""
    local i
    for (( i=0; i<full_blocks; i++ )); do bar+="█"; done
    if [ "$half" -eq 1 ]; then bar+="▌"; fi
    for (( i=0; i<empty; i++ )); do bar+="░"; done
    printf "%s" "$bar"
  }

  remaining_time() {
    local resets_at=$1
    local now
    now=$(date +%s)
    local diff=$((resets_at - now))
    if [ "$diff" -le 0 ]; then
      printf "reset soon"
      return
    fi
    local hours=$((diff / 3600))
    local mins=$(( (diff % 3600) / 60 ))
    if [ "$hours" -gt 0 ]; then
      printf "%dh%02dm" "$hours" "$mins"
    else
      printf "%dm" "$mins"
    fi
  }

  parts=""
  if [ -n "$FIVE_H" ]; then
    five_pct=$(printf '%.0f' "$FIVE_H")
    five_color=$(rate_color "$five_pct")
    five_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
    five_remaining=""
    if [ -n "$five_reset" ]; then
      five_remaining=" $(remaining_time "$five_reset")"
    fi
    five_gauge=$(gauge "$five_pct" 10)
    parts="5h ${five_color}${five_gauge}\033[0m ${five_color}${five_pct}%\033[0m${five_remaining}"
  fi

  if [ -n "$SEVEN_D" ]; then
    seven_pct=$(printf '%.0f' "$SEVEN_D")
    seven_color=$(rate_color "$seven_pct")
    seven_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
    seven_remaining=""
    if [ -n "$seven_reset" ]; then
      seven_remaining=" $(remaining_time "$seven_reset")"
    fi
    seven_gauge=$(gauge "$seven_pct" 10)
    seven_part="7d ${seven_color}${seven_gauge}\033[0m ${seven_color}${seven_pct}%\033[0m${seven_remaining}"
    if [ -n "$parts" ]; then
      parts="$parts │ $seven_part"
    else
      parts="$seven_part"
    fi
  fi

  RATE_LIMITS_LINE="⏳$parts"
else
  # rate limitデータ未取得時（起動直後等）はプレースホルダーを表示
  dim="\033[2m"
  reset="\033[0m"
  empty_gauge="░░░░░░░░░░"
  RATE_LIMITS_LINE="⏳5h ${dim}${empty_gauge} --%${reset} │ 7d ${dim}${empty_gauge} --%${reset}"
fi

echo -en "\033[0m"
echo -e "${CURRENT_DIR} ${GIT_BRANCH} ${GIT_STATUS} ${MODEL_DISPLAY} ${VERSION} ${TOKEN_COUNT}"
echo -e "${RATE_LIMITS_LINE}"
