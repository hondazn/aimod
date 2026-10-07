# クライアント別の読み込み挙動（実測記録）

`scripts/deploy.sh` の配置先と `scripts/check-skills.sh` の呼び出し制御検査は、ここの実測に依存する。各クライアントのバージョンを上げたとき、またはデプロイ先を変える前に再測定して表を更新する。

## 判定方法

Cursor の指示経路は、ファイルに「返答の先頭に特定の文字列を書け」と書き、出力に現れるかで判定した。ロード済みコンテキストを自己申告させる方法は偽陽性が出たため、指示経路の判定には使わない。Codex と opencode のスキル一覧は LLM を呼ばずに確認できる:

```bash
codex debug prompt-input ping | grep -c grill-me   # 1 以上ならモデル可視プロンプトに載っている
opencode debug skill | grep -c grill-me            # $HOME への書き込み許可が要る
```

## Cursor

指示（2026-07-25 / `cursor-agent` v2026.07.23-e383d2b、マーカー法）:

| 配置先 | 結果 | 備考 |
|---|---|---|
| `~/AGENTS.md` | 届く | ワークスペースから上へ辿って拾われる。`~` は全リポジトリの祖先なので全プロジェクトに効く |
| `~/.cursor/AGENTS.md` | 届かない | ワークスペースの祖先ではない |
| `~/.cursor/rules/*` | 届かない | 自動ロードなし |

`~/AGENTS.md` は Claude Code と Codex には届かない（同じ方法で確認）ので、`~/.claude/CLAUDE.md` / `~/.codex/AGENTS.md` との二重ロードは起きない。

skills / agents / ワークスペース直下の `CLAUDE.md`（2026-07-25 / 同バージョン / `gpt-5.4-mini-medium`、自己申告による間接確認）: `~/.cursor/skills` は全スキル、`~/.cursor/agents` は 14 体すべてが列挙され、ワークスペース直下の `CLAUDE.md` も届いた。Cursor IDE の挙動は未確認。

Cursor 本来の rules 機構は使っていない。User Rules は UI 管理で symlink できない。Project Rules（`.cursor/rules/*.mdc`。frontmatter の無い `.md` は無視される）とプロジェクト直下の `AGENTS.md` はリポジトリ単位。プラグイン（`~/.cursor/plugins/local/<name>`）はユーザー単位で配れるが、`.mdc` の frontmatter が要り生の `.md` をそのままリンクできない。

出典: <https://cursor.com/docs/context/rules> / <https://cursor.com/docs/plugins>

## cross-client 規約 `~/.agents/skills`

2026-09-15。`~/.agents/skills/<name>` に per-entry symlink を置き、各 CLI に description を出力させた:

| ツール | バージョン | 結果 |
|---|---|---|
| Claude Code | 2.1.270 | 読まない。ユーザーレベルは `~/.claude/skills` のみ |
| cursor-agent | 2026.09.10-fd3934a | 読む |
| Codex CLI | 0.154.0 | 読む |
| opencode | 1.18.30 | 読む。`~/.claude/skills` と同名だと `duplicate skill name` WARN が出るが、後勝ちで同一実体なので実害なし |

Claude Code のバイナリにある `~/.agents/skills` の文字列は、Cursor 設定を取り込む `claude import` 用でネイティブロードではない。

## 手動専用スキル（`disable-model-invocation`）

2026-09-15:

| クライアント | frontmatter のフラグ | 根拠 |
|---|---|---|
| Claude Code 2.1.270 | 尊重する | バイナリの frontmatter スキーマ（"If true, the model cannot invoke this via the Skill tool; only users can type the slash command."）。実セッションでの一覧除外は未確認 |
| cursor-agent 2026.09.10-fd3934a | 尊重する | `versions/<v>/index.js` が `disableModelInvocation: !0===n.data?.["disable-model-invocation"]` で取り込む。一覧のフィルタは未確認 |
| DSH | 尊重する | `~/.agents/skills` に置いた `grill-me` だけがスキル一覧に現れない |
| Codex CLI 0.154.0 | 無視する | `codex debug prompt-input` に `grill-me` が載る。代わりに `agents/openai.yaml` を見る（下表） |
| opencode 1.18.30 | 無視する | `opencode debug skill` に `grill-me` が出る。docs の frontmatter 許容集合は `name` / `description` / `license` / `compatibility` / `metadata` のみ |

Codex の `agents/openai.yaml`（Codex CLI 0.154.0、`~/.codex/skills/zz-probe/` の計測用スキルをモデル可視プロンプトで確認）:

| 条件 | モデル可視プロンプトに出るか |
|---|---|
| frontmatter `disable-model-invocation: true` のみ | 出る（無視される） |
| 上記 + `policy.allow_implicit_invocation: false` | 出ない |
| 上記 + `allow_implicit_invocation: true` | 出る（yaml が読まれている対照） |
| `allow_implicit_invocation: false` のみ | 出ない |

このため手動専用は、① frontmatter のフラグ ② description での宣言 ③ `agents/openai.yaml` の三重で書く。opencode では ② が唯一の防御になる。pstack も同じ結論で、`host-adapters.mjs` が Claude 用 frontmatter と Codex 用 `agents/openai.yaml` をホスト別に生成している。

## opencode

ソース `anomalyco/opencode` と実測で確認（1.18.18）:

| 項目 | 経路 | 根拠 |
|---|---|---|
| 指示 | `~/.config/opencode/AGENTS.md`。あれば `~/.claude/CLAUDE.md` は読まれない（グローバルは first-match） | `session/instruction.ts` の `globalFiles` ループ |
| スキル | `~/.claude/skills` と `~/.agents/skills` を自動ロード。`~/.config/opencode/skills` に置くと3つ目の同名コピーになる | 実測 |
| agents | `~/.claude/agents` は読まない。`~/.config/opencode/agents/*.md` が正規 | `config/agent.ts` の `Glob.scan("{agent,agents}/**/*.md")` |

検証が厳格で、不正なフィールドは config ロードごと落ちる（`config/config.ts` は catch しない）。そのため `shared/agents` をそのままリンクできない:

- `color` は `#RRGGBB` かテーマ色（`primary` / `secondary` / `accent` / `success` / `warning` / `error` / `info`）のみ。Claude Code の色名は decode に失敗する
- `mode` 未指定は `all` になり、全エージェントがプライマリの Tab 切替に並ぶ

Cursor 用の `~/AGENTS.md` は opencode に漏れない。プロジェクト規則の探索は worktree 内に限られる（`findUp(file, ctx.directory, ctx.worktree)`）。

出典: <https://opencode.ai/docs/rules> / <https://opencode.ai/docs/agents> / <https://opencode.ai/docs/skills> / <https://github.com/anomalyco/opencode>

## Claude Code

### プロジェクトの `AGENTS.md`

2.1.286 のバイナリ（`cc-plugin-agents-md`、機能フラグ `tengu_agents_md_mod`）が設定 `instructionFiles` を持つ。既定の `claude-md-or-agents-md` では、CLAUDE.md が無いプロジェクトに限って AGENTS.md を読む。`claude-md-and-agents-md` では、CLAUDE.md が既に import している AGENTS.md は二重に読まない。aimod は `CLAUDE.md` を `@AGENTS.md` の1行にして、どのモードと旧バージョンでも1回だけ読ませる。バイナリからの読み取りで、実セッションでの確認はしていない。

### `worktree.bgIsolation`

値は `worktree`（本体の既定。バックグラウンドセッションの Edit/Write を、EnterWorktree を呼ぶまで主チェックアウトに対して拒否する）と `none`。メイン設定スキーマにあり、統合設定から読まれるため、ユーザー設定に置けてプロジェクト設定が上書きする。優先順位は環境変数 `CLAUDE_BG_ISOLATION` → セッション状態 → `worktree.bgIsolation`。同じ `worktree` オブジェクトに `baseRef` / `symlinkDirectories` / `sparsePaths` も入る。対話セッションでの編集やブランチ作成は対象外。

出典は 2.1.222 の設定スキーマと読み取り関数。実際にバックグラウンドジョブを走らせての確認はしていない。
