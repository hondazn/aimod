// E2E証跡動画のための汎用ヘルパー。使い方は scenario-template.mjs を見る。
export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// 目視用の間。画面切り替わり直後の把握用（長め）と操作間の呼吸（短め）。
export const hold = (ms = 2200) => sleep(ms);
export const breath = () => sleep(700);

// イージング付きの滑らかなスクロール。刻みホイールや scrollIntoView
// （瞬間移動）では録画がカクつく・テレポートに見えるため。
export async function smoothScrollBy(page, dy, duration = 1400) {
  await page.evaluate(
    ([dy, duration]) =>
      new Promise((resolve) => {
        const startY = window.scrollY;
        const t0 = performance.now();
        const step = (t) => {
          const k = Math.min((t - t0) / duration, 1);
          const eased = k < 0.5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2;
          window.scrollTo(0, startY + dy * eased);
          if (k < 1) requestAnimationFrame(step);
          else resolve();
        };
        requestAnimationFrame(step);
      }),
    [dy, duration]
  );
}

const FLASH_CSS = [
  "@keyframes e2e-flash {",
  "  0%, 100% { box-shadow: 0 0 0 0 rgba(225,29,72,0); background-color: transparent; }",
  "  30%, 70% { box-shadow: 0 0 0 3px #e11d48; background-color: #fff1f2; }",
  "}",
  ".e2e-flash { animation: e2e-flash 1.1s ease-in-out 2; border-radius: 6px; }",
].join("\n");

// 検証箇所のフラッシュ表示（赤枠＋ピンク背景で2回点滅）。
// リロードで <style> が消えるため都度注入する。
export async function flash(locator, holdsMs = 2400) {
  await locator.evaluate(
    (e, args) => {
      if (document.getElementById("e2e-flash-style") === null) {
        const style = document.createElement("style");
        style.id = "e2e-flash-style";
        style.textContent = args.css;
        document.head.appendChild(style);
      }
      e.classList.add("e2e-flash");
      setTimeout(() => e.classList.remove("e2e-flash"), args.holdsMs);
    },
    { css: FLASH_CSS, holdsMs }
  );
  await sleep(holdsMs);
}

const CAPTION_CSS = [
  "position:fixed",
  "left:24px",
  "right:24px",
  "bottom:24px",
  "z-index:2147483646",
  "background:rgba(15,23,42,.94)",
  "color:#fff",
  "padding:14px 18px",
  "border-radius:10px",
  "font:15px/1.6 system-ui,sans-serif",
  "box-shadow:0 8px 28px rgba(0,0,0,.35)",
  "border-left:5px solid #e11d48",
].join(";");

// 画面下部に解説パネルを出す。動画だけを見た人に「いま何を確かめているか」を
// 伝えるためのもので、これが無いと操作は写っても意図が伝わらない。
// 検証箇所を隠さないよう下端に固定し、次の操作の前に clearCaption で消す。
export async function caption(page, title, body, holdMs = 2600) {
  await page.evaluate(
    (args) => {
      document.getElementById("e2e-caption")?.remove();
      const el = document.createElement("div");
      el.id = "e2e-caption";
      el.style.cssText = args.css;
      const h = document.createElement("div");
      h.style.cssText = "font-weight:700;margin-bottom:4px";
      h.textContent = args.title;
      const p = document.createElement("div");
      p.textContent = args.body;
      el.append(h, p);
      document.body.appendChild(el);
    },
    { css: CAPTION_CSS, title, body }
  );
  await sleep(holdMs);
}

export async function clearCaption(page) {
  await page.evaluate(() => document.getElementById("e2e-caption")?.remove());
}
