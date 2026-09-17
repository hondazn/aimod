#!/usr/bin/env bash
# shared/skills 配下のスキルを機械的に検査する。壊れたスキルはデプロイ前にここで落とす。
#
#   ./scripts/check-skills.sh [SKILLS_DIR]   # 既定は shared/skills
#
# 検査項目:
#   - SKILL.md が存在する
#   - frontmatter に name と description がある
#   - name がディレクトリ名と一致し、kebab-case である
#   - description が1行で 200 字以内
#   - 相対リンクが実在し、スキルディレクトリの外へ出ていない
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILLS_DIR="${1:-$ROOT/shared/skills}"
MAX_DESC=200

# description は日本語で書くため、文字数は UTF-8 ロケールで数える。
if printf 'あ' | LC_ALL=C.UTF-8 wc -m 2>/dev/null | grep -qx '1'; then
  export LC_ALL=C.UTF-8
fi

problems=0
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  problems=$((problems + 1))
}

frontmatter() {
  awk '/^---[[:space:]]*$/{c++; if(c==2) exit; next} c==1{print}' "$1"
}

# 引用符付きの値を素の値に戻す
unquote() {
  local v="$1"
  case "$v" in
    \"*\") v="${v#\"}"; v="${v%\"}" ;;
    \'*\') v="${v#\'}"; v="${v%\'}" ;;
  esac
  printf '%s' "$v"
}

# フェンス付きコードブロックとインラインコードを外してから markdown リンクを抜く。
# テンプレート中の `![](./path)` のような例を参照切れとして数えないため。
extract_links() {
  awk '/^[[:space:]]*```/{fence=!fence; next} !fence' "$1" \
    | sed 's/`[^`]*`//g' \
    | grep -oE '\]\([^)]*\)' || true
}

if [ ! -d "$SKILLS_DIR" ]; then
  printf 'FAIL: スキルディレクトリが無い: %s\n' "$SKILLS_DIR" >&2
  exit 1
fi

shopt -s nullglob
for dir in "$SKILLS_DIR"/*/; do
  dir="${dir%/}"
  name="$(basename "$dir")"
  case "$name" in
    synced|*-workspace) continue ;;
  esac
  file="$dir/SKILL.md"

  if [ ! -f "$file" ]; then
    fail "$name: SKILL.md が無い"
    continue
  fi

  fm="$(frontmatter "$file")"
  fm_name="$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*//p' | head -1)"
  fm_desc="$(printf '%s\n' "$fm" | sed -n 's/^description:[[:space:]]*//p' | head -1)"
  fm_name="$(unquote "$fm_name")"
  fm_desc="$(unquote "$fm_desc")"

  if [ -z "$fm_name" ]; then
    fail "$name: frontmatter に name が無い"
  else
    if [ "$fm_name" != "$name" ]; then
      fail "$name: frontmatter の name \"$fm_name\" がディレクトリ名と違う"
    fi
    case "$fm_name" in
      *[!a-z0-9-]*|'-'*|*'-'|*'--'*)
        fail "$name: name \"$fm_name\" が kebab-case でない" ;;
    esac
  fi

  if [ -z "$fm_desc" ]; then
    fail "$name: frontmatter に description が無い"
  else
    # description の直後がインデント付きの行なら複数行の値
    # （allowed-tools 等、別キーの YAML リストと区別するため直後の1行だけを見る）
    if printf '%s\n' "$fm" | awk '/^description:/{getline nxt; if (nxt ~ /^[[:space:]]+[^[:space:]]/) bad=1; exit} END{exit !bad}'; then
      fail "$name: description が複数行。1行に収める"
    fi
    len=${#fm_desc}
    if [ "$len" -gt "$MAX_DESC" ]; then
      fail "$name: description が ${len} 字。上限 ${MAX_DESC} 字を超えている"
    fi
  fi

  # 呼び出し制御の frontmatter。解釈はクライアントごとに割れており、Codex と opencode は
  # disable-model-invocation を無視する（実測表は CLAUDE.md）。一覧から消えることへの
  # 依存は危険なので、手動起動の契約は description 側でも宣言させる。
  fm_dmi="$(printf '%s\n' "$fm" | sed -n 's/^disable-model-invocation:[[:space:]]*//p' | head -1)"
  fm_ui="$(printf '%s\n' "$fm" | sed -n 's/^user-invocable:[[:space:]]*//p' | head -1)"

  if printf '%s\n' "$fm" | grep -qE '^[[:space:]]*(disableModelInvocation|userInvocable)[[:space:]]*:'; then
    fail "$name: camelCase の呼び出し制御キー。kebab-case（disable-model-invocation / user-invocable）で書く"
  fi

  for kv in "disable-model-invocation:$fm_dmi" "user-invocable:$fm_ui"; do
    key="${kv%%:*}"
    val="$(unquote "${kv#*:}")"
    [ -n "$val" ] || continue
    case "$val" in
      true|false) ;;
      *) fail "$name: $key の値 \"$val\" が不正。true か false だけを許す（fail-closed）" ;;
    esac
  done

  if [ "$(unquote "$fm_dmi")" = true ]; then
    case "$fm_desc" in
      *"/$name"*|*手動起動*|*手動専用*|*自動選択してはならない*) ;;
      *) fail "$name: disable-model-invocation: true なのに description が手動起動を宣言していない。Codex と opencode はこのフラグを無視するため、description に /$name か手動起動である旨を書く" ;;
    esac
    if [ "$(unquote "$fm_ui")" = false ]; then
      fail "$name: disable-model-invocation: true と user-invocable: false の併用は到達不能。モデルからもユーザーからも呼べない"
    fi
  fi

  # Codex は SKILL.md の frontmatter を無視するが、スキル直下の agents/openai.yaml にある
  # policy.allow_implicit_invocation は尊重する（実測は CLAUDE.md）。片方だけ書くと
  # 「Claude では手動・Codex では自動」に割れるため、フラグと yaml を一致させる。
  codex_policy="$dir/agents/openai.yaml"
  codex_val=""
  if [ -f "$codex_policy" ]; then
    if ! grep -qE '^[[:space:]]*policy:' "$codex_policy"; then
      fail "$name: agents/openai.yaml に policy: が無い"
    fi
    if grep -qE 'allowImplicitInvocation' "$codex_policy"; then
      fail "$name: agents/openai.yaml のキーが camelCase。allow_implicit_invocation で書く"
    fi
    codex_val="$(unquote "$(sed -n 's/^[[:space:]]*allow_implicit_invocation:[[:space:]]*//p' "$codex_policy" | head -1)")"
    case "$codex_val" in
      true|false) ;;
      '') fail "$name: agents/openai.yaml に allow_implicit_invocation が無い" ;;
      *) fail "$name: agents/openai.yaml の allow_implicit_invocation \"$codex_val\" が不正。true か false だけを許す" ;;
    esac
  fi

  if [ "$(unquote "$fm_dmi")" = true ]; then
    if [ ! -f "$codex_policy" ]; then
      fail "$name: disable-model-invocation: true なのに agents/openai.yaml が無い。Codex は frontmatter を無視するので、Codex でも手動専用にするには $name/agents/openai.yaml に policy.allow_implicit_invocation: false を置く"
    elif [ "$codex_val" != false ]; then
      fail "$name: disable-model-invocation: true と agents/openai.yaml の allow_implicit_invocation: $codex_val が矛盾する"
    fi
  elif [ -f "$codex_policy" ] && [ "$codex_val" = false ]; then
    fail "$name: agents/openai.yaml で Codex だけ手動専用になっている。Claude 側にも disable-model-invocation: true を書くか、yaml を消す"
  fi

  while IFS= read -r raw; do
    [ -n "$raw" ] || continue
    target="${raw#](}"
    target="${target%)}"
    target="${target%%[[:space:]]*}"   # タイトルを落とす
    target="${target#<}"
    target="${target%>}"
    case "$target" in
      ''|'#'*|http://*|https://*|mailto:*|ftp://*) continue ;;
    esac
    case "$target" in
      *'{'*|*'}'*|*'<'*|*'>'*) continue ;;   # テンプレートのプレースホルダ
    esac
    target="${target%%#*}"
    case "$target" in
      */*|.*) ;;
      *) continue ;;                          # 同一ディレクトリの裸のファイル名は対象外
    esac
    case "$target" in
      ../*|*/../*|*/..)
        fail "$name: 相対リンクがスキルディレクトリの外を指す: $target" ;;
      *)
        if [ ! -e "$dir/$target" ]; then
          fail "$name: 相対リンクが解決しない: $target"
        fi ;;
    esac
  done < <(extract_links "$file")
done

if [ "$problems" -gt 0 ]; then
  printf '\n%d 件の問題\n' "$problems" >&2
  exit 1
fi

printf 'OK: %d スキルを検査した\n' "$(find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)"
