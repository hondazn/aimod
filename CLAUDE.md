# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## リポジトリ概要

AIコーディングアシスタント（Claude Code、Cursor、Codex CLI、opencode）のカスタム設定（指示・agents・skills）を一元管理し、`scripts/deploy.sh` で各ツールのホームディレクトリにシンボリックリンクとしてデプロイするdotfilesリポジトリ。外部依存は bash のみ。

## アーキテクチャ

```
shared/          ← 実体（4ツール共通の正本）
  instructions.md ← グローバル指示（CLAUDE.md / AGENTS.md の正本）。汎用ルールのみ
  agents/        ← PRレビュー用 2 体 + スペシャリスト 12 体（Claude/Cursor/opencode）
  skills/        ← スラッシュコマンドで呼び出すスキル群
  skills-archive/ ← デプロイ対象外の退避スキル（実体は残すが配らない）
claude/          ← Claude Code用のツール固有ファイル
  CLAUDE.md -> ../shared/instructions.md
  agents -> ../shared/agents
  skills -> ../shared/skills
  settings.json / statusline.sh
cursor/          ← Cursor用（repo内参照用symlink + ツール固有ファイル）
  agents -> ../shared/agents
  skills -> ../shared/skills
  statusline.sh
codex/           ← Codex用（repo内参照用symlink + ツール固有設定）
  AGENTS.md -> ../shared/instructions.md
  statusline.toml
opencode/        ← opencode用のツール固有設定（config と plugins の正本）
  opencode.json
  plugins/
scripts/
  deploy.sh / undeploy.sh / manage-codex-statusline.sh
  check-skills.sh              # shared/skills の frontmatter・相対リンク・呼び出し制御を機械検査
  check-md-wrap.sh             # Markdown の1段落1物理行を機械検査
  opencode-agent-transform.sh  # shared/agents → .opencode-agents/（opencode 形式へ変換）
tests/
  agents-skills-deploy-test.sh / codex-statusline-config-test.sh / opencode-agents-test.sh / opencode-config-test.sh / pr-review-lead-judgment-test.sh
  skills-lint-test.sh / decision-log-test.sh / md-wrap-test.sh
```

**設計方針**: `shared/` に実体を置き、`deploy.sh` がホームディレクトリへ直接 symlink する。agents は Claude / Cursor / opencode へ配る（Codex は同型の agents をサポートしない）。opencode は色スキーマが異なり `mode` 既定が `all` のため、`shared/agents` をそのままリンクせず `opencode-agent-transform.sh` で変換したものを `.opencode-agents/` に生成してリンクする。Codex skills は `~/.codex/skills/.system` 共存のためスキル単位でリンクする。Cursor へは instructions を `~/AGENTS.md` として配る（ワークスペースから上へ辿って拾われる唯一の経路 — 後述）。opencode の instructions は `~/.config/opencode/AGENTS.md`（`~/.claude/CLAUDE.md` フォールバックより優先 — 後述）、skills は Claude Code 互換の `~/.claude/skills` 自動ロードで届く。skills は cross-client 規約の `~/.agents/skills` にもスキル単位で配る（後述）。

`claude/` / `cursor/` / `codex/` 配下の symlink は repo 内から辿るための**参照用ミラーであり、網羅的ではない**（例: `codex/` に skills のミラーは無い）。正本は常に `shared/`、実際の配置先は `deploy.sh` が唯一の真実。ミラーを増やすと追加のたび手作業が要りズレの再発源になるため、意図的に揃えていない。

**設計知識の置き場**: タスク別ルールは rules という別カテゴリを持たず、すべてスキルとして配る。常時ロードを避け、4ツール共通のオンデマンド機構（スキル一覧の description で発火）に一本化するため。`instructions.md` には汎用ルールと、スキル適用を促す「タスク別スキル」節だけを置く。設計・実装系スキルの分担:

- `code-complete` — 開発ループ（探索→モデル化→TDD→学習）のプロセスハブ。各段階を専門スキルへ委譲
- `coding-standards` — コードを書く最中の実装規律（認知負荷閾値・CQS・整理テクニック等）。あらゆるコード変更に適用
- `design-principles` — 結合・凝集・構造投資の経済学という判断理論。コード以外の構造判断にも使う
- `design-code` / `understand-problem` / `devise-plan` — 設計・問題定義・解法戦略のプロセス
- 参照方向は一方向: code-complete → (design-code, coding-standards) → design-principles

**Cursor へのグローバル指示は `~/AGENTS.md` 経由で配る。** Cursor はワークスペースから上へ辿って `AGENTS.md` を拾い、`~` はすべてのリポジトリの祖先なので、ここに置けば全プロジェクトに効く。

実測（2026-07-25 / `cursor-agent` v2026.07.23-e383d2b）。**ファイルに「返答の先頭に特定の文字列を書け」と指示し、出力に現れるかで判定**した（自己申告の照会は偽陽性が出たため採用しない）:

| 配置先 | cursor-agent | 備考 |
|---|---|---|
| **`~/AGENTS.md`** | **届く** | 指示に従った。これが唯一機能する経路 |
| `~/.cursor/AGENTS.md` | 届かない | ワークスペースの祖先ではないため拾われない |
| `~/.cursor/rules/*` | 届かない | 自動ロードなし。aimod は現在この置き場を使わない |
| `~/.cursor/skills`, `~/.cursor/agents` | 届く | Cursor が文書化しているユーザーレベル配置先 |

`~/AGENTS.md` は **Claude Code と Codex では読まれない**（同じ方法で確認。どちらも指示に従わなかった）。したがって `~/.claude/CLAUDE.md` / `~/.codex/AGENTS.md` との二重ロードは起きない。

Cursor 本来の rules 機構は別にあり、いずれも今回は使っていない: User Rules は UI 管理（Customize → Rules）で symlink できず、Project Rules（`.cursor/rules/*.mdc`、frontmatter 必須、**frontmatter の無い `.md` は無視**）とプロジェクト直下の `AGENTS.md` はリポジトリ単位。プラグイン（`~/.cursor/plugins/local/<name>` に symlink、`rules/*.mdc` 同梱）はユーザー単位で配れるが、`.mdc` の frontmatter が要り生の `.md` をそのままリンクできないため採らなかった。

出典: <https://cursor.com/docs/context/rules> / <https://cursor.com/docs/plugins>。バージョン更新時は上表を再測定すること。

実測（2026-07-25 / `cursor-agent` v2026.07.23-e383d2b / `gpt-5.4-mini-medium`）:

| 対象 | 結果 |
|---|---|
| `~/.cursor/rules/AGENTS.md`, `~/.cursor/rules/coding.md` | 届かない（中立ディレクトリで 3 マーカー全不在、repo 内でも列挙されず）|
| `~/.cursor/skills` | 届く（aimod の全スキルが列挙された）|
| `~/.cursor/agents` | 届く（14 エージェントすべて列挙された）|
| ワークスペース直下の `CLAUDE.md` | 届く |

いずれも `cursor-agent -p` にロード済みコンテキストを照会した**自己申告ベースの間接的な確認**で、CLI 1 バージョン・1 モデルでの結果。**Cursor IDE の挙動は未確認**。バージョン更新時と Cursor 向けデプロイを変える前に再確認すること。

**cross-client 規約 `~/.agents/skills` は Cursor / Codex / opencode が読む。** 実測（2026-09-15）: `~/.agents/skills/<name>` に per-entry symlink を置き、各 CLI にその description を出力させた結果:

| ツール | バージョン | `~/.agents/skills` |
|---|---|---|
| Claude Code | 2.1.270 | **読まない**（NONE）。ユーザーレベルは `~/.claude/skills` のみ |
| cursor-agent | 2026.09.10-fd3934a | 読む |
| Codex CLI | 0.154.0 | 読む |
| opencode | 1.18.30 | 読む。`~/.claude/skills` と同名だと `duplicate skill name` WARN が出るが、後勝ちで同一実体なので実害なし（aimod 31 スキルで WARN 31 件を確認） |

Claude Code だけが例外なので `~/.claude/skills` は維持し、`~/.agents/skills` は残り3ツール向けの追加経路として配る。Claude Code のバイナリに `~/.agents/skills` の文字列があるのは Cursor 設定を取り込む `claude import` 用で、ネイティブロードではない。バージョン更新時は上表を再測定すること。

**`disable-model-invocation: true` の解釈はクライアントごとに割れる。** 実測（2026-09-15）:

| クライアント | フラグ | 根拠と確度 |
|---|---|---|
| Claude Code 2.1.270 | 尊重する | ネイティブバイナリ（`~/.local/share/claude/versions/2.1.270`）の frontmatter スキーマに `"disable-model-invocation": …describe("If true, the model cannot invoke this via the Skill tool; only users can type the slash command.")`。スキーマ由来で、実セッションでの一覧除外は未確認 |
| cursor-agent 2026.09.10-fd3934a | 尊重する | `versions/<v>/index.js` が `disableModelInvocation: !0===n.data?.["disable-model-invocation"]` として厳密一致で取り込む。ローダ由来で、一覧のフィルタは未確認 |
| DSH | 尊重する | カタログ実測。`~/.agents/skills` に配置済みの `grill-me` だけがスキル一覧に現れない |
| Codex CLI 0.154.0 | **無視する**（専用の別機構あり） | 実測。`codex debug prompt-input`（モデル可視プロンプト）に `- grill-me: … (file: r0/grill-me/SKILL.md)` が載る。Codex は frontmatter ではなくスキル直下の `agents/openai.yaml` を見る（下の実測表） |
| opencode 1.18.30 | **無視する** | 実測。`opencode debug skill` の一覧に `grill-me` が出る。docs の frontmatter 許容集合は `name` / `description` / `license` / `compatibility` / `metadata` のみ |

したがって **フラグだけでは「モデルが自動選択しない」を4ツールで保証できない。** `grill-me` は ① frontmatter のフラグ ② description の「`/grill-me` と打たれたときだけ使う。モデルは自動選択してはならない。」 ③ Codex 用の `agents/openai.yaml` の三重重ねで手動専用を宣言している。③ が要るのは、Codex が frontmatter を無視する代わりに自前のフィールドを持つため。opencode には相当するフィールドが無いので、そこでは ② の一文が唯一の防御になる。この整合は `scripts/check-skills.sh` が検査する（フラグ付きスキルが description でも手動起動を宣言していなければ落ちる／`agents/openai.yaml` が無いか食い違っていても落ちる）。

**Codex の呼び出し制御は `agents/openai.yaml` の `policy.allow_implicit_invocation`。** 実測（2026-09-15 / Codex CLI 0.154.0 / `~/.codex/skills/zz-probe/` に置いた計測用スキルを `codex debug prompt-input` のモデル可視プロンプトで数えた）:

| 条件 | モデル可視プロンプトに出るか |
|---|---|
| frontmatter `disable-model-invocation: true` のみ | **出る（無視される）** |
| 上記 + `agents/openai.yaml` に `allow_implicit_invocation: false` | **出ない（効く）** |
| 上記 + `allow_implicit_invocation: true` | 出る（yaml が読まれている対照） |
| `allow_implicit_invocation: false` のみ（frontmatter フラグ無し） | 出ない |

Codex のバイナリにも `allow_implicit_invocation` は実在する（0.154.0 に13箇所）。pstack は同じ結論に達しており、`host-adapters.mjs` が Claude 用 frontmatter と Codex 用 `agents/openai.yaml` を**ホスト別に生成**している（同リポジトリの `adapters/` は claude-code と codex の2ホスト分）。したがって Codex を手動専用にするには、フラグと yaml を**必ず対で**書く。

Codex と opencode の判定は LLM を呼ばずに再測定できる:

```bash
codex debug prompt-input ping | grep -c grill-me   # 1 以上なら無視されている
opencode debug skill | grep -c grill-me            # opencode は $HOME への書き込み許可が要る。yaml を知らないので 1 のまま
```

**opencode への配り方（ソース `anomalyco/opencode` と実測で確認済み）:**

| 項目 | 経路 | 根拠 |
|---|---|---|
| 指示 | `~/.config/opencode/AGENTS.md`。**あれば `~/.claude/CLAUDE.md` は読まれない**（グローバルは first-match、積み重ねなし） | `session/instruction.ts` の `globalFiles` ループ。デプロイ前はフォールバックの `~/.claude/CLAUDE.md` 経由でロードされる実測あり |
| スキル | `~/.claude/skills` と `~/.agents/skills` を自動ロード。**`~/.config/opencode/skills` には配置しない**（3つ目の同名コピーになるだけ） | 実測で両経路からロードされ、同名は `duplicate skill name` WARN + 後勝ち。`~/.agents/skills` は cross-client 規約として配る（後述） |
| agents | `~/.claude/agents` は**読まない**。`~/.config/opencode/agents/*.md` が正規 | docs/agents。`config/agent.ts` の `Glob.scan("{agent,agents}/**/*.md")` は `~/.config/opencode` 配下のみ |

`shared/agents` をそのままリンクできない理由（opencode の検証が厳格で、不正なフィールドは config ロードごと死ぬ）: ① `color` は `#RRGGBB` かテーマ色（`primary`/`secondary`/`accent`/`success`/`warning`/`error`/`info`）のみで、Claude Code の色名（`red` 等）は decode 失敗 → `ConfigAgent.load` が throw（`config/config.ts` は catch しない）② `mode` 未指定は `all` になり、14 体がプライマリの Tab 切替に並ぶ。そのため `opencode-agent-transform.sh` が `mode: subagent` を注入し、色名を hex へ写像する（`name`/`description`/本文は忠実コピー）。

Cursor 用の `~/AGENTS.md` が opencode に漏れない理由: プロジェクト規則の探索は worktree 内に限定される（`instruction.ts` の `findUp(file, ctx.directory, ctx.worktree)`）。実測でも `~/AGENTS.md` は指示として現れず、グローバルには `~/.claude/CLAUDE.md` が使われた。

出典: <https://opencode.ai/docs/rules> / <https://opencode.ai/docs/agents> / <https://opencode.ai/docs/skills> / <https://github.com/anomalyco/opencode>（`session/instruction.ts`, `config/agent.ts`, `config/config.ts`, `core/v1/config/agent.ts`）。opencode 1.18.18 で確認。バージョン更新時は再確認すること。

## デプロイ

```bash
./scripts/deploy.sh     # シンボリックリンクを作成・更新（idempotent）
./scripts/undeploy.sh   # aimod 由来のシンボリックリンクだけ削除
```

デプロイ先:

- `shared/instructions.md` → `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/AGENTS.md`（最後が Cursor 用。ホーム直下はユーザー自身のファイルが置かれうるので、`link_guarded_path` を通して**既存の実体があれば SKIP** する）, `~/.config/opencode/AGENTS.md`（opencode 用。同じく guarded）
- `shared/agents` → `~/.claude/agents`, `~/.cursor/agents`
- `shared/agents`（`opencode-agent-transform.sh` で変換）→ `.opencode-agents/`（生成物）→ `~/.config/opencode/agents`（opencode 用。`mode: subagent` 注入 + 色名を hex へ写像）
- `shared/skills` → `~/.claude/skills`, `~/.cursor/skills`
- `shared/skills/<name>` → `~/.codex/skills/<name>`（`.system` は触らない）
- `shared/skills/<name>` → `~/.agents/skills/<name>`（cross-client 規約。Cursor / Codex / opencode が読む。Claude Code は読まないため `~/.claude/skills` は維持。スキル単位の guarded link で、skills CLI 等が置いたエントリは SKIP して共存する）

`~/AGENTS.md` は `link_guarded_path` を通す。他ツールやユーザー自身のファイルと共有しうるため、**aimod 由来でないものは一切壊さない**（同名の実体・外部管理 symlink は SKIP し、そのエントリだけ諦めて他のデプロイは続行する）。

rules カテゴリは廃止済みで、`deploy.sh` は過去バージョンが張った `~/.claude/rules` / `~/.codex/rules` / `~/.cursor/rules` 配下の aimod 由来リンクを削除する（`migrate:` としてログに出る。`is_ours` 判定を通すので他ツールやユーザー自身のファイルは残り、`~/.cursor/rules` は空になればディレクトリごと畳む）。

Claude / Cursor の `skills` はディレクトリ丸ごと 1 本の symlink なので削除に自動追随するが、Codex skills と `~/.agents/skills` はエントリ単位のため取り残しが出る。`deploy.sh` はリンク作成後に `prune_stale_link` で、**aimod 由来かつリンク先が消えた** symlink だけを除去する（`.system`・実体・外部ツール管理のリンクは `is_ours` 判定で保護）。

なお `~/.claude/CLAUDE.md` / `~/.codex/AGENTS.md` は aimod が所有権を持つ配置先として、既存の実体があれば `replace non-symlink` をログに出して置換する（SKIP しない）。ここを SKIP にすると、既存ファイルのあるマシンで初回デプロイが何も反映されなくなるため。
- `claude/settings.json` → `~/.claude/settings.json`
- `claude/statusline.sh` → `~/.claude/statusline.sh`
- `cursor/statusline.sh` → `~/.cursor/statusline.sh`（`cli-config.json` の `statusLine` は手動で有効化）
- `codex/statusline.toml` → `~/.codex/config.toml` の `tui.status_line`（既存ファイルへマージし、他の設定は保持）
- `opencode/opencode.json` → `~/.config/opencode/opencode.json`（aimod 所有。既存の実体は置換する）
- `opencode/plugins/<name>` → `~/.config/opencode/plugins/<name>`（エントリ単位で guarded。手で置いたプラグインや外部管理リンクは SKIP、aimod 由来の壊れたリンクだけ prune）

opencode の config は厳格に検証され、フィールドを間違えると起動ごと落ちる（`ConfigAgent.load` 等は catch しない）。そのため `opencode/opencode.json` を編集したら `./scripts/deploy.sh` の前に JSON としての妥当性を確認し、デプロイ後は opencode を一度起動して確認する。

Codex は Claude のような command-based status line をサポートせず、組み込み項目 ID の配列を `tui.status_line` に設定する。`deploy.sh` はこのキーだけを追加・置換する。`undeploy.sh` は現在値が `codex/statusline.toml` と完全一致する場合だけ削除し、ユーザーが変更した値は残す。

管理しない: `~/.codex/config.toml` のその他の設定, auth / credentials, `~/.cursor/cli-config.json`, `~/.cursor/skills-cursor/`, `~/.claude/hooks/`, `~/.agents/skills` 配下の aimod 由来でないエントリ（skills CLI 等のインストール先。スキル単位の guarded link で保護）, `~/.config/opencode/opencode.json` 以外の `~/.config/opencode` 配下（`package.json` / `node_modules` 等のプラグイン依存解決用ファイル）

### worktree の強制は本体設定を使い、既定は無効

aimod は worktree 関連のフックを配らない。Claude Code 本体が同じ目的の設定 `worktree.bgIsolation` を持つため。値は `worktree` と `none` で、**本体の既定は `worktree`**（バックグラウンドセッションの Edit/Write を、EnterWorktree を呼ぶまで主チェックアウトに対して拒否する）。

`claude/settings.json` で全体を `none` に倒し、**worktree を使いたいプロジェクトだけ opt-in** する:

```json
{ "worktree": { "bgIsolation": "worktree" } }   ← 該当プロジェクトの .claude/settings.json
```

`bgIsolation` は `hooks` や `skillOverrides` と同じメイン設定スキーマにあり、統合設定 `co()` から読まれる（`language` / `enabledPlugins` と同じ経路）ため、ユーザ設定に置けて、プロジェクト設定が上書きする。環境変数 `CLAUDE_BG_ISOLATION=worktree|none` が最優先。同じ `worktree` オブジェクトに `baseRef` / `symlinkDirectories` / `sparsePaths` も入る。

出典: claude バイナリ 2.1.222 の設定スキーマ（description 原文: "Isolation mode for background sessions in this repo. 'worktree' (default) blocks Edit/Write in the main checkout until EnterWorktree is called. 'none' lets background jobs edit the working copy directly."）と読み取り関数（`process.env.CLAUDE_BG_ISOLATION` → セッション状態 → `co().worktree?.bgIsolation` の順）。**対話セッションでの編集やブランチ作成は対象外**。スキーマからの読み取りであり、実際にバックグラウンドジョブを走らせての動作確認は未実施。バージョン更新時に再確認すること。

## スキル・エージェントの追加

- **スキル追加**: `shared/skills/<skill-name>/SKILL.md` を作成 → `./scripts/check-skills.sh` → `./scripts/deploy.sh`
- **エージェント追加**: `shared/agents/<agent-name>.md` を作成（Claude / Cursor / opencode へ配布。opencode 用の変換は `deploy.sh` が自動実行）→ `./scripts/deploy.sh`
- 補助ファイル（EXAMPLES.md、TEMPLATES.md等）は同じディレクトリに配置可能
- **追加時の検査**: `./scripts/check-skills.sh` が、SKILL.md の存在、frontmatter の `name` とディレクトリ名の一致、kebab-case、`description` の1行・200字以内、相対リンクの解決（スキルディレクトリ外への逸脱を含む）、呼び出し制御フラグの値と二重化を機械的に検査する。契約は `tests/skills-lint-test.sh` が固定する。リンク検査はフェンス付きコードブロックとインラインコードを除外するため、例示した `![](...)` は参照切れとして数えない
- **呼び出し制御**: `disable-model-invocation: true` のスキルは description でも手動起動を宣言し（`/name` か「手動起動」「自動選択してはならない」）、**さらに `agents/openai.yaml` に `policy.allow_implicit_invocation: false` を併置する**。値は `true` / `false` のみ、キーは kebab-case（yaml は snake_case）のみ。フラグ・yaml・description の3点が揃っていないと `./scripts/check-skills.sh` が落ちる。理由は上の実測表（Claude Code / cursor / DSH は frontmatter、Codex は yaml、opencode は description が唯一の防御）
- **Markdown は1段落1物理行**: 段落・リスト項目の途中で折り返さない。表・見出し・フェンス・インデント付きコードブロックは対象外。`./scripts/check-md-wrap.sh` が検査し、契約は `tests/md-wrap-test.sh` が固定する。対象は `shared/`（`skills-archive` を除く）と `README.md` / `CLAUDE.md` で、凍結記録の `docs/specs/` は含めない。フェンスの開閉は CommonMark の規則（同じマーカー・同数以上・インデント3以下）で判定する — 単純なトグルだとコード例の中のフェンス行で状態がずれ、コードブロックを段落として結合してしまう
- **外部スキルの取り込み**: 逐語コピーせず日本語で再構成し、本文末尾に `## 出典`（原典 URL・ライセンス・再構成時点）を置く
- **description は短く**: 一覧として毎セッション全スキル分がロードされるため、「何をするか + いつ使うか」を 1〜2 文（目安 200 字以内）で書く。Codex は実測で約 328 字で切り詰めるため、長いトリガー列挙は末尾から失われる。領分・手順の詳細は本文か補助ファイルへ置く（progressive disclosure）
- **スキル退避**: 使用頻度が低いスキルは `git mv shared/skills/<name> shared/skills-archive/<name>` でデプロイ対象から外す（deploy.sh の変更は不要。Claude/Cursor はディレクトリ symlink が即追随し、Codex と `~/.agents/skills` の残骸リンクは次回 deploy の `prune_stale_link` が除去する）。復帰は逆向きに `git mv` して `./scripts/deploy.sh`。退避時は残存スキルからの参照切れを grep で確認すること

`shared/instructions.md` に足してよいのは作業種別を問わず常に効く汎用ルールだけ（グローバル設定として毎セッション全文ロードされる）。特定作業の知識はスキル本文へ、特定スキルからしか参照しない長大な参照表はそのスキルの補助ファイルとして `shared/skills/<skill>/` に置くこと（例: `pr-review/REVIEW-BADGES.md`）。

### gh skill との関係

- 探索: `gh skill search` / `preview` は可
- **禁止**: `gh skill install --scope user`（実体コピーで aimod の symlink を壊す）
- 取り込み: 外部スキルは `shared/skills/` にコピーして aimod 正本化し、競合時は新しい方を採用してから `./scripts/deploy.sh`

## レビュー用エージェント

`pr-review` スキル（PRレビュー）では固定2体 + 差分に応じたスペシャリスト 0〜3 体を並列起動する。すべてのエージェントが統一された JSON 出力（`findings[]` + `severity` + `mode`）を返す。

### PRレビュー構成（pr-review）

固定:

| エージェント | 観点 |
|---|---|
| `meta-reviewer` | 方向性（コード本文は見ない） |
| `fatal-reviewer` | 致命のみ（`severity: fatal`）。これだけが CHANGES_REQUESTED |

追加: メインが差分に応じて既存スペシャリストを 0〜3 体選ぶ（`qa` / `safety-skeptic` 等）。

固定2体は見るスコープが排他的に設計されている。各エージェントは入力プロンプトから動作モード（`pr_review` / `self_review`）を自動判定する。出力 JSON の `mode` フィールドで実モードを追跡できる。

`self_review` に専用スキルは無い。セルフレビューは `meta-reviewer` / `fatal-reviewer` を Task ツールから直接起動し、プロンプトに `branch` / `plan` / 「セルフレビュー」を含めて自動判定させる。

## スペシャリスト（認知レンズ）エージェント

`consult-specialists` スキル経由で呼ぶ、**専門性とスタンスを持つ 12 体** のサブエージェント。`pr-review` では差分に応じて 0〜3 体が動的追加メンバーとしても選ばれる。各エージェントは助言だけでなく専門領域の作業も実行する。最終判断はメインエージェント。

### Core Engineering

| エージェント | 専門性 | 何を疑う／重視するか |
|---|---|---|
| `architect` | システム/境界/抽象化/データモデル/API | 長期的な構造整合性 |
| `solver` | 問題解決/突破/プロト/代替案 | まず動く解 / 制約から逆算 |
| `tech-lead` | 実装品質/PR 設計/レビュー/プロセス | チームで保守できるか |
| `qa` | テスト/AC/エッジケース/影響範囲 | 仕様は曖昧、実装は壊れる |

### Product Quality

| エージェント | 専門性 | 何を疑う／重視するか |
|---|---|---|
| `taste` | 体験/情報設計/コピー/一貫性 | 気持ちよさ、わかりやすさ、削ぎ落とし |
| `friction-maximalist` | UX/オンボーディング/認知負荷 | ユーザーは読まない・迷う・離脱する |
| `business-realist` | 事業価値/ROI/優先順位/コスト | いま作る価値があるか / 機会費用 |
| `data-realist` | 計測/ログ/KPI/分析 | 測れない成功を疑う |

### Risk / Sharpness / Optional

| エージェント | 専門性 | 何を疑う／重視するか |
|---|---|---|
| `failure-pessimist` | SRE/監視/復旧/運用 | 正常系より異常系 |
| `safety-skeptic` | セキュリティ/権限/漏洩/ポリシー | 悪用される前提 |
| `contrarian` | 差別化/戦略/尖り/反対意見 | 無難な案を疑う |
| `debt-auditor` | 負債/移行/廃止/所有権 | 撤去条件付きで入れる |

### 運用原則

- **全員を常に呼ばない**: 1〜3 体に絞る。観点が重複するエージェントは代表だけ呼ぶ
- **観点が独立なら並列、依存するなら逐次**: 例）architect + qa + safety-skeptic は並列／solver → tech-lead は逐次
- **助言モード／作業モード**: プロンプトで明示する。作業も任せられる（テスト追加、撤去計画起草、コピー書き換え等）
- **メインエージェントが統合・判断する**: 採用・棄却・保留を分け、衝突は目的／制約／リスク許容度に照らして決める
- **PR 専用フローは既存スキル優先**: PR レビューは `pr-review`。本枠組みはその中で「不足する視点を補う」位置付け

詳細は `shared/skills/consult-specialists/SKILL.md` を参照。

## 注意事項

- `shared/instructions.md` はグローバル設定（`~/.claude/CLAUDE.md` / `~/.codex/AGENTS.md` / `~/.config/opencode/AGENTS.md`）としてデプロイされるため、変更の影響範囲が広い
- `shared/` 配下の変更は Claude Code・Cursor・Codex・opencode のすべてに影響する（agents は Claude / Cursor / opencode のみ）
