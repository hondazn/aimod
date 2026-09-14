#!/usr/bin/env node
// ワークスペースに紐づく過去セッションの transcript を mtime 降順で列挙する。
//
//   原典: https://github.com/shiwenbin1617/pstack の skills/recall/scripts/find-transcripts.mjs
//         MIT License, Copyright (c) 2026 Lauren Tan
//   aimod 向けに書き直した。Node 標準ライブラリのみを使う。
//
//   node find-transcripts.mjs --host claude --host codex --workspace <path> [--limit <n>] [--home <dir>]
//
// 各 JSONL の先頭 128KB だけを読み、cwd メタデータ（value.cwd または value.payload.cwd）が
// --workspace と完全一致するものを選ぶ。メッセージ本文は読まない。出力は1行1パス。
import { open, readdir, realpath, stat } from "node:fs/promises";
import { realpathSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve, win32 } from "node:path";
import { fileURLToPath } from "node:url";

const METADATA_BYTES = 128 * 1024;
const HOST_ROOTS = {
  claude: [".claude", "projects"],
  codex: [".codex", "sessions"],
};
const USAGE =
  "usage: node find-transcripts.mjs --host <claude|codex> [--host ...] --workspace <path> [--limit <n>] [--home <dir>]";

// symlink 越しの同一ディレクトリを同じものとして扱う。解決できなければ与えられたパスで比較する。
function normalize(path) {
  if (process.platform === "win32" || /^[A-Za-z]:[\\/]/.test(path) || path.startsWith("\\\\")) {
    return win32.resolve(path).replaceAll("/", "\\").toLowerCase();
  }
  return resolve(path);
}

async function canonical(path) {
  try {
    return normalize(await realpath(path));
  } catch {
    return normalize(path);
  }
}

function metadataCwd(record) {
  if (typeof record !== "object" || record === null) return null;
  if (typeof record.cwd === "string") return record.cwd;
  const payload = record.payload;
  if (typeof payload === "object" && payload !== null && typeof payload.cwd === "string") {
    return payload.cwd;
  }
  return null;
}

// 先頭 128KB の範囲で cwd を持つ最初の行を探す。末尾で切れた行は JSON にならず読み飛ばされる。
async function readCwd(path) {
  const handle = await open(path, "r");
  try {
    const buffer = Buffer.alloc(METADATA_BYTES);
    const { bytesRead } = await handle.read(buffer, 0, buffer.length, 0);
    for (const line of buffer.subarray(0, bytesRead).toString("utf8").split(/\r?\n/)) {
      if (!line.trim()) continue;
      try {
        const cwd = metadataCwd(JSON.parse(line));
        if (cwd !== null) return cwd;
      } catch {
        // 途中で切れた行や JSON でない行は次の行へ進む。
      }
    }
    return null;
  } finally {
    await handle.close();
  }
}

async function collectJsonl(root) {
  const found = [];
  const pending = [root];
  while (pending.length > 0) {
    const directory = pending.pop();
    let entries;
    try {
      entries = await readdir(directory, { withFileTypes: true });
    } catch {
      console.error(`note: 置き場が無い: ${directory}`);
      continue;
    }
    for (const entry of entries) {
      const path = join(directory, entry.name);
      if (entry.isDirectory()) pending.push(path);
      else if (entry.isFile() && entry.name.endsWith(".jsonl")) found.push(path);
    }
  }
  return found;
}

export async function findTranscripts({ hosts, workspace, home, limit }) {
  const expected = await canonical(workspace);
  const matches = [];
  for (const host of hosts) {
    for (const path of await collectJsonl(join(home, ...HOST_ROOTS[host]))) {
      let cwd;
      let info;
      try {
        [cwd, info] = await Promise.all([readCwd(path), stat(path)]);
      } catch {
        continue;
      }
      if (cwd === null || (await canonical(cwd)) !== expected) continue;
      matches.push({ path, modifiedAtMs: info.mtimeMs });
    }
  }
  matches.sort((left, right) => right.modifiedAtMs - left.modifiedAtMs || left.path.localeCompare(right.path));
  return (limit === undefined ? matches : matches.slice(0, limit)).map((match) => match.path);
}

function parseArgs(argv) {
  const options = { hosts: [], workspace: null, home: homedir(), limit: undefined, help: false };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--host") options.hosts.push(argv[++index] ?? "");
    else if (argument === "--workspace") options.workspace = argv[++index] ?? "";
    else if (argument === "--limit") options.limit = Number(argv[++index]);
    else if (argument === "--home") options.home = argv[++index] ?? "";
    else if (argument === "--help" || argument === "-h") options.help = true;
    else throw new Error(`unknown argument: ${argument}`);
  }
  return options;
}

export async function main(argv) {
  try {
    const { hosts, workspace, home, limit, help } = parseArgs(argv);
    if (help) {
      console.log(USAGE);
      return 0;
    }
    if (hosts.length === 0 || !workspace) throw new Error(USAGE);
    for (const host of hosts) {
      if (!(host in HOST_ROOTS)) throw new Error(`unknown host: ${host}（claude か codex を指定する）`);
    }
    if (limit !== undefined && (!Number.isSafeInteger(limit) || limit < 1)) {
      throw new Error("--limit は 1 以上の整数");
    }
    const paths = await findTranscripts({ hosts: [...new Set(hosts)], workspace, home, limit });
    if (paths.length > 0) process.stdout.write(`${paths.join("\n")}\n`);
    return 0;
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    return 1;
  }
}

if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url))) {
  process.exitCode = await main(process.argv.slice(2));
}
