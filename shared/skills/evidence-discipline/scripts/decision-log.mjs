#!/usr/bin/env node
// 決定ログ（TSV）に1行追記する。
//
//   node decision-log.mjs <file> <phase> <decision> <why> <evidence> <result>
//
// ヘッダが無ければ書き、時刻を付けて TSV の1行を足す。セル内のタブと改行は空白へ潰し、
// 先頭が = + - @ のセルは表計算の数式注入を避けて ' を前置する。依存は無い。
import { appendFileSync, existsSync, readFileSync } from "node:fs";

const HEADER = "ts\tphase\tdecision\twhy\tevidence\tresult\n";
const args = process.argv.slice(2);

if (args.length !== 6) {
  process.stderr.write(
    "usage: decision-log.mjs <file> <phase> <decision> <why> <evidence> <result>\n"
  );
  process.exit(2);
}

const [file, phase, decision, why, evidence, result] = args;

function cell(value) {
  const cleaned = String(value).replace(/[\t\r\n]+/g, " ").trim();
  return /^[=+\-@]/.test(cleaned) ? `'${cleaned}` : cleaned;
}

const row = [new Date().toISOString(), phase, decision, why, evidence, result]
  .map(cell)
  .join("\t");

const needsHeader = !existsSync(file) || readFileSync(file, "utf8").length === 0;
appendFileSync(file, (needsHeader ? HEADER : "") + row + "\n");
process.stdout.write(row + "\n");
