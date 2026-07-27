#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-}"
CONFIG_PATH="${2:-}"
STATUSLINE_PATH="${3:-}"

if [[ "$ACTION" != "apply" && "$ACTION" != "remove" ]]; then
  printf 'usage: %s apply|remove CONFIG_PATH STATUSLINE_PATH\n' "$0" >&2
  exit 2
fi

if [[ -z "$CONFIG_PATH" || ! -f "$STATUSLINE_PATH" ]]; then
  printf 'config path and existing statusline file are required\n' >&2
  exit 2
fi

mapfile -t assignments < <(
  grep -E '^[[:space:]]*status_line[[:space:]]*=' "$STATUSLINE_PATH" || true
)
if [[ "${#assignments[@]}" -ne 1 ]]; then
  printf 'statusline file must contain exactly one status_line assignment\n' >&2
  exit 2
fi
MANAGED_LINE="${assignments[0]}"

if [[ -L "$CONFIG_PATH" ]]; then
  resolved="$(readlink -f "$CONFIG_PATH" || true)"
  if [[ -z "$resolved" ]]; then
    printf 'refusing to replace dangling config symlink: %s\n' "$CONFIG_PATH" >&2
    exit 1
  fi
  CONFIG_PATH="$resolved"
fi

if [[ "$ACTION" == "remove" && ! -e "$CONFIG_PATH" ]]; then
  exit 0
fi

CONFIG_DIR="$(dirname "$CONFIG_PATH")"
mkdir -p "$CONFIG_DIR"
TEMP_PATH="$(mktemp "$CONFIG_DIR/.config.toml.XXXXXX")"
cleanup() {
  rm -f "$TEMP_PATH"
}
trap cleanup EXIT

if [[ -e "$CONFIG_PATH" ]]; then
  cp -p "$CONFIG_PATH" "$TEMP_PATH"
fi
INPUT_PATH="$CONFIG_PATH"
if [[ ! -e "$INPUT_PATH" ]]; then
  INPUT_PATH="/dev/null"
fi

if [[ "$ACTION" == "apply" ]]; then
  awk -v managed="$MANAGED_LINE" '
    function is_section(line) {
      return line ~ /^[[:space:]]*\[[^][]+\][[:space:]]*(#.*)?$/
    }
    function is_tui(line) {
      return line ~ /^[[:space:]]*\[tui\][[:space:]]*(#.*)?$/
    }
    BEGIN {
      in_tui = 0
      saw_tui = 0
      wrote = 0
      skip_array = 0
    }
    {
      if (skip_array) {
        if ($0 ~ /\]/) {
          skip_array = 0
        }
        next
      }
      if (is_section($0)) {
        if (in_tui && !wrote) {
          print managed
          wrote = 1
        }
        in_tui = is_tui($0)
        if (in_tui) {
          saw_tui = 1
        }
        print
        next
      }
      if (in_tui && $0 ~ /^[[:space:]]*status_line[[:space:]]*=/) {
        if (!wrote) {
          print managed
          wrote = 1
        }
        if ($0 !~ /\]/) {
          skip_array = 1
        }
        next
      }
      print
    }
    END {
      if (in_tui && !wrote) {
        print managed
      } else if (!saw_tui) {
        if (NR > 0) {
          print ""
        }
        print "[tui]"
        print managed
      }
    }
  ' "$INPUT_PATH" > "$TEMP_PATH"
else
  awk -v managed="$MANAGED_LINE" '
    function is_section(line) {
      return line ~ /^[[:space:]]*\[[^][]+\][[:space:]]*(#.*)?$/
    }
    function is_tui(line) {
      return line ~ /^[[:space:]]*\[tui\][[:space:]]*(#.*)?$/
    }
    is_section($0) {
      in_tui = is_tui($0)
      print
      next
    }
    in_tui && $0 == managed {
      next
    }
    {
      print
    }
  ' "$CONFIG_PATH" > "$TEMP_PATH"
fi

if [[ -e "$CONFIG_PATH" ]] && cmp -s "$CONFIG_PATH" "$TEMP_PATH"; then
  exit 0
fi

mv -f "$TEMP_PATH" "$CONFIG_PATH"
