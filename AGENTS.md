# AGENTS.md

AI コーディングアシスタント（Claude Code・Cursor・Codex CLI・opencode）の指示・agents・skills を一元管理し、`scripts/deploy.sh` でホームディレクトリへ symlink として配る dotfiles リポジトリ。外部依存は bash のみ。

## 構成

- `shared/` が正本。`instructions.md`（グローバル指示）、`agents/`、`skills/`、デプロイしない退避先の `skills-archive/`
- `claude/` / `cursor/` / `codex/` / `opencode/` はツール固有ファイルと、repo 内から辿るための参照用 symlink。ミラーは網羅的でなく、意図的に揃えていない
- 配置先の唯一の真実は `scripts/deploy.sh`
- `.opencode-agents/` は `opencode-agent-transform.sh` の生成物。直接編集しない
- 各クライアントがどこから何を読むかの実測は [`docs/clients.md`](docs/clients.md)。デプロイ先や呼び出し制御を変える前に読み、クライアントのバージョンが変わっていたら再測定する

## コマンド

```bash
./scripts/deploy.sh          # symlink を作成・更新（idempotent）
./scripts/undeploy.sh        # aimod 由来の symlink だけ削除
./scripts/check-skills.sh    # SKILL.md の frontmatter・相対リンク・呼び出し制御
./scripts/check-md-wrap.sh   # Markdown の1段落1物理行
for t in tests/*-test.sh; do bash "$t" || echo "FAIL: $t"; done
```

## 変更するときの規約

### 指示とスキル

- `shared/instructions.md` は4ツールのグローバル指示として毎セッション全文ロードされる。足してよいのは作業種別を問わず効く汎用ルールだけ。特定作業の知識はスキル本文へ、特定スキルしか使わない長い参照表はそのスキルの補助ファイル（例: `pr-review/REVIEW-BADGES.md`）へ置く
- rules というカテゴリは持たず、タスク別ルールもスキルとして配る。過去の `~/.*/rules` 配下のリンクは `deploy.sh` が `migrate:` として削除する
- スキル追加は `shared/skills/<name>/SKILL.md` を書き、`check-skills.sh` → `deploy.sh`
- description は一覧として毎セッション全スキル分ロードされる。「何をするか + いつ使うか」を 1〜2 文、200 字以内で書く。Codex は約 328 字で切り詰める
- 手動専用のスキルは、frontmatter の `disable-model-invocation: true`、description での宣言（`/name` か「自動選択してはならない」）、`agents/openai.yaml` の `policy.allow_implicit_invocation: false` を必ず3点そろえる。クライアントごとに見る場所が違うため（`docs/clients.md`）。`check-skills.sh` が整合を検査する
- 外部スキルは逐語コピーせず日本語で再構成し、本文末尾に `## 出典`（原典 URL・ライセンス・再構成時点）を置く。`gh skill install --scope user` は実体コピーで symlink を壊すので使わない
- 使わなくなったスキルは `git mv shared/skills/<name> shared/skills-archive/<name>` で退避し、残ったスキルからの参照切れを grep で確かめる
- 設計・実装系スキルの参照は一方向: `code-complete` → (`design-code`, `coding-standards`) → `design-principles`

### agents

- `shared/agents/<name>.md` は Claude / Cursor / opencode へ配る（Codex には同型の機構がない）。opencode 向けには transform が `mode: subagent` を注入し、色名を hex に写像する。`color` には transform の写像にある色名だけを使う
- エージェントの出力 JSON（`findings[]` / `severity` / `mode`）は `pr-review` が依存する契約。運用は `pr-review` と `consult-specialists` の SKILL.md にある

### デプロイ

- aimod 由来でないファイルは壊さない。ユーザーや他ツールと共有しうる配置先（`~/AGENTS.md`、`~/.config/opencode/AGENTS.md`、`~/.agents/skills/<name>`、`~/.config/opencode/plugins/<name>`）は `link_guarded_path` を通し、既存の実体や外部管理のリンクがあれば SKIP する
- aimod が所有する配置先（`~/.claude/CLAUDE.md`、`~/.codex/AGENTS.md`、`~/.config/opencode/opencode.json`）は既存の実体を置換する。SKIP にすると初回デプロイが何も反映しない
- エントリ単位のリンク（Codex skills、`~/.agents/skills`、opencode plugins）は、`prune_stale_link` が「aimod 由来かつリンク先が消えた」ものだけを除去する
- `~/.codex/config.toml` は `tui.status_line` だけをマージし、`undeploy.sh` は値が定義と完全一致するときだけ消す
- opencode の config は厳格に検証され、不正なフィールドで起動ごと落ちる。`opencode/opencode.json` を編集したら JSON の妥当性を確かめてからデプロイし、opencode を一度起動して確認する
- `claude/settings.json` は `worktree.bgIsolation` を `none` にしている。worktree を強制したいプロジェクトだけ、その `.claude/settings.json` で `"worktree"` に戻す

### Markdown

段落・リスト項目の途中で折り返さない（1段落1物理行）。表・見出し・フェンス・インデント付きコードブロックは対象外。`docs/specs/` などの凍結記録は検査しない。
