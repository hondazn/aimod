// E2E証跡動画のシナリオ雛形。このファイルを複製して1シナリオ1本で書く。
// 実行前に使い捨てDBをシードし直すこと（入力が追記型のため）。
// 録画ディレクトリは実行ごとに空にすること（古い webm の混入防止）。
import { chromium } from "playwright-core";
// flash は下の TODO 使用例のために残す（複製直後は未使用になる）。
// eslint-disable-next-line no-unused-vars
import { hold, breath, smoothScrollBy, flash } from "./helpers.mjs";

const BASE = "http://localhost:3101";

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({
  viewport: { width: 1280, height: 720 },
  recordVideo: {
    dir: "/tmp/<task>/video", // TODO: 実行ごとに空のディレクトリを指定する
    size: { width: 1280, height: 720 },
  },
});
const page = await context.newPage();
// 疑似カーソル（赤矢印＋クリック波紋）。headless には実カーソルが写らない。
await page.addInitScript({ path: "./cursor.js" });

// TODO: goto は初回だけ。以後の画面遷移はすべてクリックで辿る。
await page.goto(`${BASE}/login`, { waitUntil: "networkidle" });
await hold(1500);

// TODO: 受け入れ基準の操作を書く。検証箇所では flash() で示す。
// await flash(page.locator("..."));

console.log("final url:", page.url());
await context.close(); // ← 録画ファイルの確定はここ
await browser.close();
console.log("done");
