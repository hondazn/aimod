# Cursor cli-config キー単位マージ Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 共有してよい Cursor CLI 設定キーを aimod 正本から `deploy.sh` で live の `~/.cursor/cli-config.json` へマージし、auth / モデル / キャッシュは触らない。

**Architecture:** Codex の `manage-codex-statusline.sh` と同じ apply/remove ヘルパー。正本 `cursor/cli-config.json` のトップレベルキーが許可リスト。`jq` で live の該当キーだけ置換する。拒否キーが正本に混入していたら失敗する。live は実体ファイルのまま（symlink にしない）。

**Tech Stack:** bash, jq, `scripts/deploy.sh` / `scripts/undeploy.sh`

**関連ドキュメント:**
- 設計: `docs/specs/2026-08-21-cursor-cli-config-merge-design.md`

## Global Constraints

- JSON 処理は `jq`。python は使わない
- `~/.cursor/cli-config.json` を symlink にしない
- 許可リストは正本のトップレベルキー。マージはトップレベルごと置換（ネストの deep merge はしない）
- 拒否リスト: `authInfo`, `model`, `selectedModel`, `modelParameters`, `hasChangedDefaultModel`, `modelSelectionHistory`, `privacyCache`, `autoReviewAvailabilityCache`, `serverConfigCache`, `showSandboxIntro`, `conversationClassificationScoredConversations`, `version`, `runEverythingSettingsPromptStreak`
- 正本に拒否キーがあれば apply を失敗させる（黙ってスキップしない）
- 書き先が aimod リポジトリ内に解決したら失敗する
- undeploy は値が正本と完全一致するキーだけ削除する。ファイル自体は消さない
- `deploy.sh` のリンク処理は bash のまま。このヘルパーだけ `jq` を必要とする

---

## File Structure

| ファイル | 責務 |
|---|---|
| `scripts/manage-cursor-cli-config.sh` | live JSON へ許可キーを apply / remove |
| `cursor/cli-config.json` | マージしてよいキーだけの正本 |
| `tests/cursor-cli-config-test.sh` | ヘルパーと deploy/undeploy の固定 |
| `scripts/deploy.sh` | ヘルパーを apply で呼ぶ |
| `scripts/undeploy.sh` | ヘルパーを remove で呼ぶ |
| `README.md` / `CLAUDE.md` | 「管理しない」をキー単位マージに更新 |

---

### Task 1: マージヘルパーをテスト先行で実装する

**Files:**
- Create: `tests/cursor-cli-config-test.sh`
- Create: `scripts/manage-cursor-cli-config.sh`

**Interfaces:**
- Consumes: なし
- Produces: `scripts/manage-cursor-cli-config.sh apply\|remove CONFIG_PATH MANAGED_PATH`（exit 0 成功、2 用法誤り、1 その他失敗）。apply は許可キーを live へトップレベル置換し他キーを残す。remove は値が正本と `==` のキーだけ消す

- [ ] **Step 1: 失敗するテストを書く**

`tests/cursor-cli-config-test.sh` を次の内容で作成する。この時点ではヘルパーが無いので実行は失敗する。

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANAGER="$ROOT/scripts/manage-cursor-cli-config.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

assert_eq() {
  local expected="$1" filter="$2" file="$3" actual
  actual="$(jq -c "$filter" "$file")"
  [[ "$actual" == "$expected" ]]
}

fail_apply() {
  local config="$1" managed="$2" rc=0
  "$MANAGER" apply "$config" "$managed" || rc=$?
  [[ "$rc" -ne 0 ]]
}

MANAGED="$TMP_ROOT/managed.json"
printf '%s\n' '{
  "statusLine": {
    "type": "command",
    "command": "~/.cursor/statusline.sh",
    "padding": 0
  },
  "permissions": {
    "allow": ["Shell(ls)"],
    "deny": []
  }
}' > "$MANAGED"

existing="$TMP_ROOT/existing.json"
printf '%s\n' '{
  "authInfo": {"email": "keep-me"},
  "statusLine": {"type": "command", "command": "old", "padding": 2},
  "version": 1
}' > "$existing"

"$MANAGER" apply "$existing" "$MANAGED"
assert_eq '"~/.cursor/statusline.sh"' '.statusLine.command' "$existing"
assert_eq '0' '.statusLine.padding' "$existing"
assert_eq '["Shell(ls)"]' '.permissions.allow' "$existing"
assert_eq '"keep-me"' '.authInfo.email' "$existing"
assert_eq '1' '.version' "$existing"
[[ "$(jq -c 'keys_unsorted' "$existing")" == '["authInfo","statusLine","version","permissions"]' ]]

before="$(sha256sum "$existing")"
"$MANAGER" apply "$existing" "$MANAGED"
after="$(sha256sum "$existing")"
[[ "$before" == "$after" ]]

missing="$TMP_ROOT/missing.json"
"$MANAGER" apply "$missing" "$MANAGED"
assert_eq '"~/.cursor/statusline.sh"' '.statusLine.command' "$missing"
[[ "$(jq -c 'keys_unsorted' "$missing")" == '["statusLine","permissions"]' ]]

badjson="$TMP_ROOT/bad.json"
printf '%s' '{' > "$badjson"
fail_apply "$badjson" "$MANAGED"
[[ "$(cat "$badjson")" == '{' ]]

denied="$TMP_ROOT/denied.json"
printf '%s\n' '{"authInfo":{"email":"x"},"statusLine":{"type":"command"}}' > "$denied"
fail_apply "$existing" "$denied"

inside="$TMP_ROOT/inside.json"
ln -s "$ROOT/README.md" "$inside"
readme_before="$(sha256sum "$ROOT/README.md")"
fail_apply "$inside" "$MANAGED"
[[ "$(sha256sum "$ROOT/README.md")" == "$readme_before" ]]

dangling="$TMP_ROOT/dangling.json"
ln -s "$TMP_ROOT/nope.json" "$dangling"
fail_apply "$dangling" "$MANAGED"
[[ -L "$dangling" ]]

"$MANAGER" remove "$existing" "$MANAGED"
assert_eq '"keep-me"' '.authInfo.email' "$existing"
assert_eq '1' '.version' "$existing"
[[ "$(jq -r 'has("statusLine")' "$existing")" == "false" ]]
[[ "$(jq -r 'has("permissions")' "$existing")" == "false" ]]

customized="$TMP_ROOT/customized.json"
printf '%s\n' '{
  "statusLine": {"type": "command", "command": "custom", "padding": 0},
  "authInfo": {"email": "keep-me"}
}' > "$customized"
"$MANAGER" remove "$customized" "$MANAGED"
assert_eq '"custom"' '.statusLine.command' "$customized"
assert_eq '"keep-me"' '.authInfo.email' "$customized"

only_managed="$TMP_ROOT/only-managed.json"
printf '%s\n' '{"statusLine":{"type":"command","command":"~/.cursor/statusline.sh","padding":0},"permissions":{"allow":["Shell(ls)"],"deny":[]}}' > "$only_managed"
"$MANAGER" remove "$only_managed" "$MANAGED"
[[ -f "$only_managed" ]]
[[ "$(jq -c '.' "$only_managed")" == '{}' ]]

absent="$TMP_ROOT/absent.json"
"$MANAGER" remove "$absent" "$MANAGED"
[[ ! -e "$absent" ]]

printf 'ok\n'
```

- [ ] **Step 2: テストを実行して失敗することを確認する**

Run: `bash tests/cursor-cli-config-test.sh`

Expected: ヘルパーが無く `No such file or directory` で非ゼロ終了

- [ ] **Step 3: ヘルパーを実装する**

`scripts/manage-cursor-cli-config.sh` を次の内容で作成し、`chmod +x` する。

```bash
#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-}"
CONFIG_PATH="${2:-}"
MANAGED_PATH="${3:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

DENIED_JSON='["authInfo","model","selectedModel","modelParameters","hasChangedDefaultModel","modelSelectionHistory","privacyCache","autoReviewAvailabilityCache","serverConfigCache","showSandboxIntro","conversationClassificationScoredConversations","version","runEverythingSettingsPromptStreak"]'

APPLY_FILTER='
  def is_denied($k): any($denied[]; . == $k);
  ($managed[0]) as $M
  | ($live[0] // {}) as $L
  | if ($M | type) != "object" then error("managed file must be a JSON object") else . end
  | if ($L | type) != "object" then error("config must be a JSON object") else . end
  | ($M | keys_unsorted | map(select(is_denied(.)))) as $bad
  | if ($bad | length) > 0 then error("refusing to merge denied keys: \($bad | join(", "))") else . end
  | reduce ($M | keys_unsorted[]) as $k ($L; .[$k] = $M[$k])
'

REMOVE_FILTER='
  ($managed[0]) as $M
  | ($live[0] // {}) as $L
  | if ($M | type) != "object" then error("managed file must be a JSON object") else . end
  | if ($L | type) != "object" then error("config must be a JSON object") else . end
  | reduce ($M | keys_unsorted[]) as $k (
      $L;
      if (has($k) and .[$k] == $M[$k]) then del(.[$k]) else . end
    )
'

if [[ "$ACTION" != "apply" && "$ACTION" != "remove" ]]; then
  printf 'usage: %s apply|remove CONFIG_PATH MANAGED_PATH\n' "$0" >&2
  exit 2
fi

if [[ -z "$CONFIG_PATH" || ! -f "$MANAGED_PATH" ]]; then
  printf 'config path and existing managed file are required\n' >&2
  exit 2
fi

if [[ "$ACTION" == "remove" && ! -e "$CONFIG_PATH" && ! -L "$CONFIG_PATH" ]]; then
  exit 0
fi

if [[ -L "$CONFIG_PATH" ]]; then
  resolved="$(readlink -f "$CONFIG_PATH" || true)"
  if [[ -z "$resolved" ]]; then
    printf 'refusing to replace dangling config symlink: %s\n' "$CONFIG_PATH" >&2
    exit 1
  fi
  CONFIG_PATH="$resolved"
elif [[ -e "$CONFIG_PATH" ]]; then
  CONFIG_PATH="$(readlink -f "$CONFIG_PATH")"
else
  parent="$(dirname "$CONFIG_PATH")"
  base="$(basename "$CONFIG_PATH")"
  if [[ -d "$parent" ]]; then
    CONFIG_PATH="$(readlink -f "$parent")/$base"
  else
    [[ "$CONFIG_PATH" == /* ]] || CONFIG_PATH="$PWD/$CONFIG_PATH"
  fi
fi

if [[ "$CONFIG_PATH" == "$ROOT" || "$CONFIG_PATH" == "$ROOT"/* ]]; then
  printf 'refusing to write config inside aimod: %s\n' "$CONFIG_PATH" >&2
  exit 1
fi

if [[ "$ACTION" == "remove" && ! -e "$CONFIG_PATH" ]]; then
  exit 0
fi

CONFIG_DIR="$(dirname "$CONFIG_PATH")"
mkdir -p "$CONFIG_DIR"
TEMP_PATH="$(mktemp "$CONFIG_DIR/.cli-config.json.XXXXXX")"
LIVE_FALLBACK=""
cleanup() {
  rm -f "$TEMP_PATH"
  [[ -n "$LIVE_FALLBACK" ]] && rm -f "$LIVE_FALLBACK"
}
trap cleanup EXIT

LIVE_SRC="$CONFIG_PATH"
if [[ ! -e "$LIVE_SRC" ]]; then
  LIVE_FALLBACK="$(mktemp "$CONFIG_DIR/.cli-config-empty.XXXXXX")"
  printf '%s\n' '{}' > "$LIVE_FALLBACK"
  LIVE_SRC="$LIVE_FALLBACK"
fi

filter="$APPLY_FILTER"
[[ "$ACTION" == "remove" ]] && filter="$REMOVE_FILTER"

if ! jq -e --argjson denied "$DENIED_JSON" \
    --slurpfile managed "$MANAGED_PATH" \
    --slurpfile live "$LIVE_SRC" \
    -n "$filter" > "$TEMP_PATH"
then
  exit 1
fi

if [[ -e "$CONFIG_PATH" ]] && cmp -s "$CONFIG_PATH" "$TEMP_PATH"; then
  exit 0
fi

mv -f "$TEMP_PATH" "$CONFIG_PATH"
```

- [ ] **Step 4: テストを実行して通ることを確認する**

Run: `bash tests/cursor-cli-config-test.sh`

Expected: `ok` と exit 0

キー順の期待値 `["authInfo","statusLine","version","permissions"]` が jq の版でずれたら、代入後に新規キーが末尾へ付く前提を保ったまま期待値を実測に合わせる。既存3キーの相対順が崩れていたら実装を直す。

- [ ] **Step 5: コミット**

```bash
git add tests/cursor-cli-config-test.sh scripts/manage-cursor-cli-config.sh
git commit -m "$(cat <<'EOF'
feat(cursor): cli-configのキー単位マージヘルパーを追加

EOF
)"
```

---

### Task 2: 正本を置き deploy / undeploy とドキュメントを繋ぐ

**Files:**
- Create: `cursor/cli-config.json`
- Modify: `scripts/deploy.sh:195-202`
- Modify: `scripts/undeploy.sh:63-67`
- Modify: `tests/cursor-cli-config-test.sh`（末尾、`printf 'ok\n'` の前）
- Modify: `README.md:5`, `README.md:35-40`, `README.md:54`, `README.md:67-69`
- Modify: `CLAUDE.md:114-119`

**Interfaces:**
- Consumes: Task 1 の `manage-cursor-cli-config.sh apply|remove CONFIG_PATH MANAGED_PATH`
- Produces: `deploy.sh` が `$HOME/.cursor/cli-config.json` へ正本キーを upsert する。`undeploy.sh` は一致キーだけ戻す

- [ ] **Step 1: 正本を live の許可キーから作る**

`cursor/cli-config.json` を次の内容で作成する（`~/.cursor/cli-config.json` から拒否キーを除いたもの）。

```json
{
  "permissions": {
    "allow": [
      "Shell(ls)",
      "Shell(cd)",
      "Shell(cargo check)",
      "Shell(cargo clippy)",
      "Shell(cargo test)",
      "WebFetch(github.com)"
    ],
    "deny": []
  },
  "editor": {
    "vimMode": false
  },
  "display": {
    "showLineNumbers": false,
    "showThinkingBlocks": true,
    "showStatusIndicators": true,
    "showStatusLineRunningTime": true,
    "mode": "zen"
  },
  "notifications": false,
  "hints": true,
  "modelSlashCommands": true,
  "rewind": false,
  "statusLine": {
    "type": "command",
    "command": "~/.cursor/statusline.sh",
    "padding": 0
  },
  "maxMode": true,
  "exploreSubagentModel": "inherit",
  "subagentModels": {
    "explore": "inherit"
  },
  "network": {
    "useHttp1ForAgent": false
  },
  "approvalMode": "unrestricted",
  "autoAcceptWebSearch": false,
  "sandbox": {
    "mode": "disabled",
    "networkAccess": "user_config_with_defaults"
  },
  "attribution": {
    "attributeCommitsToAgent": true,
    "attributePRsToAgent": true
  }
}
```

- [ ] **Step 2: 正本の拒否キー検査と deploy 結合をテストに足す**

`tests/cursor-cli-config-test.sh` の `printf 'ok\n'` の直前に次を挿入する。

```bash
MANAGED_REAL="$ROOT/cursor/cli-config.json"
DENIED_FILTER='["authInfo","model","selectedModel","modelParameters","hasChangedDefaultModel","modelSelectionHistory","privacyCache","autoReviewAvailabilityCache","serverConfigCache","showSandboxIntro","conversationClassificationScoredConversations","version","runEverythingSettingsPromptStreak"]'
bad_keys="$(jq -c --argjson d "$DENIED_FILTER" '[keys_unsorted[] | select(. as $k | any($d[]; . == $k))]' "$MANAGED_REAL")"
[[ "$bad_keys" == "[]" ]]
assert_eq '"~/.cursor/statusline.sh"' '.statusLine.command' "$MANAGED_REAL"

deploy_home="$TMP_ROOT/deploy-home"
mkdir -p "$deploy_home/.cursor" "$deploy_home/.claude" "$deploy_home/.codex" "$deploy_home/.config/opencode"
printf '%s\n' '{"authInfo":{"email":"keep-me"},"version":1}' > "$deploy_home/.cursor/cli-config.json"
printf '%s\n' '[tui]' 'animations = false' > "$deploy_home/.codex/config.toml"
HOME="$deploy_home" "$ROOT/scripts/deploy.sh" >/dev/null
assert_eq '"keep-me"' '.authInfo.email' "$deploy_home/.cursor/cli-config.json"
assert_eq '1' '.version' "$deploy_home/.cursor/cli-config.json"
assert_eq '"~/.cursor/statusline.sh"' '.statusLine.command' "$deploy_home/.cursor/cli-config.json"
assert_eq 'true' '.maxMode' "$deploy_home/.cursor/cli-config.json"
HOME="$deploy_home" "$ROOT/scripts/undeploy.sh" >/dev/null
assert_eq '"keep-me"' '.authInfo.email' "$deploy_home/.cursor/cli-config.json"
assert_eq '1' '.version' "$deploy_home/.cursor/cli-config.json"
[[ "$(jq -r 'has("statusLine")' "$deploy_home/.cursor/cli-config.json")" == "false" ]]
[[ "$(jq -r 'has("maxMode")' "$deploy_home/.cursor/cli-config.json")" == "false" ]]
```

この時点では `deploy.sh` がヘルパーを呼ばないので、結合部分は失敗する。

- [ ] **Step 3: 結合テストを実行して失敗することを確認する**

Run: `bash tests/cursor-cli-config-test.sh`

Expected: Task 1 のケースは通り、`has("statusLine")` が undeploy 後も true のままで非ゼロ終了

- [ ] **Step 4: deploy / undeploy を繋ぐ**

`scripts/deploy.sh` の次を置換する。

```bash
# Cursor-only files (cli-config.json is intentionally not managed)
link "$ROOT/cursor/statusline.sh" "$HOME/.cursor/statusline.sh"
```

置換後:

```bash
# Cursor-only files. cli-config.json is merged by key, never symlinked.
link "$ROOT/cursor/statusline.sh" "$HOME/.cursor/statusline.sh"
"$ROOT/scripts/manage-cursor-cli-config.sh" \
  apply "$HOME/.cursor/cli-config.json" "$ROOT/cursor/cli-config.json"
log "configure $HOME/.cursor/cli-config.json managed keys"
```

`scripts/undeploy.sh` の `unlink_if_ours "$HOME/.cursor/statusline.sh"` の直後に次を足す。

```bash
"$ROOT/scripts/manage-cursor-cli-config.sh" \
  remove "$HOME/.cursor/cli-config.json" "$ROOT/cursor/cli-config.json"
log "undeploy managed keys from $HOME/.cursor/cli-config.json if unchanged"
```

- [ ] **Step 5: テストが通ることを確認する**

Run: `bash tests/cursor-cli-config-test.sh && bash tests/codex-statusline-config-test.sh`

Expected: どちらも `ok` と exit 0

- [ ] **Step 6: ドキュメントを更新する**

`README.md` 5行目を次に置換する。

```
外部依存は **bash**（`./scripts/deploy.sh` のリンク処理）。Cursor の cli-config マージと statusline は **jq**。
```

`README.md` のディレクトリ構成で `cursor/` のコメントを次に置換する。

```
cursor/             # statusline.sh + cli-config.json（キー単位マージ）+ 参照用 symlink
```

`scripts/` の列挙に次を足す（`undeploy.sh` の下）。

```
  manage-cursor-cli-config.sh
  manage-codex-statusline.sh
```

デプロイ先表の `cursor/statusline.sh` の行の直後に次を足す。

```
| `cursor/cli-config.json` | `~/.cursor/cli-config.json` の許可キーだけマージ（auth / モデル / キャッシュは保持）|
```

`README.md` 67-69行付近を次に置換する。

```
`~/.codex/config.toml` はファイル全体を管理せず、`codex/statusline.toml` の `tui.status_line` だけをマージする。`~/.cursor/cli-config.json` もファイル全体を管理せず、`cursor/cli-config.json` のキーだけをマージする。`undeploy.sh` は値が aimod の定義と一致する場合だけ削除し、ユーザーが変更した値や他の設定は保持する。

管理しないもの: `~/.codex/config.toml` のその他の設定、auth / credentials / モデル状態、`~/.cursor/skills-cursor/`、`~/.config/opencode/opencode.json`（ユーザー固有設定）
```

`CLAUDE.md` 114行目を次に置換する。

```
- `cursor/statusline.sh` → `~/.cursor/statusline.sh`
- `cursor/cli-config.json` → `~/.cursor/cli-config.json` の許可キーだけマージ（`statusLine` を含む。auth / モデル / キャッシュは保持）
```

`CLAUDE.md` 119行目を次に置換する。

```
管理しない: `~/.codex/config.toml` のその他の設定, auth / credentials / モデル状態, `~/.cursor/skills-cursor/`, `~/.claude/hooks/`, `~/.config/opencode/opencode.json`（ユーザー固有設定）
```

- [ ] **Step 7: コミット**

```bash
git add cursor/cli-config.json scripts/deploy.sh scripts/undeploy.sh tests/cursor-cli-config-test.sh README.md CLAUDE.md
git commit -m "$(cat <<'EOF'
feat(cursor): cli-configの許可キーをdeployでマージする

EOF
)"
```

---

## Spec coverage

| Spec | Task |
|---|---|
| 正本 `cursor/cli-config.json` | 2 |
| live は実体、symlink にしない | 2（deploy は merge のみ） |
| 許可リスト = 正本キー、トップレベル置換 | 1 |
| 拒否リスト混入で失敗 | 1 |
| 欠落 live は正本だけで作成 | 1 |
| 不正 JSON は失敗し元を残す | 1 |
| 書き先が aimod 内なら失敗 | 1 |
| ダングリング symlink を拒否 | 1 |
| 既存キー位置維持・新規は末尾 | 1（`keys_unsorted`） |
| 再 apply でバイト列不変 | 1 |
| remove は一致キーだけ | 1 |
| `{}` になってもファイルは残す | 1 |
| jq（python なし） | 1 |
| deploy/undeploy 結合 | 2 |
| README / CLAUDE.md | 2 |
| 初期正本は live の許可キー | 2 |
