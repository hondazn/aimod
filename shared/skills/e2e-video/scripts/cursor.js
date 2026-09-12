// E2E録画用の疑似カーソル。実カーソルはheadlessに写らないため、
// マウス追従の矢印＋クリック時の波紋をDOMに描いて録画に残す。
(() => {
  if (window.__e2eCursor === true) return;
  window.__e2eCursor = true;
  const cursor = document.createElement("div");
  cursor.style.cssText =
    "position:fixed;left:0;top:0;z-index:2147483647;pointer-events:none;" +
    "width:24px;height:24px;will-change:transform;";
  cursor.innerHTML =
    '<svg width="24" height="24" viewBox="0 0 24 24">' +
    '<path d="M6 2 L6 18.5 L10.8 14.6 L13.4 20.4 L16.2 19.1 L13.6 13.4 L18.4 13.4 Z" ' +
    'fill="#e11d48" stroke="white" stroke-width="1.6"/></svg>';
  const mount = () => {
    if (document.documentElement !== null && !cursor.isConnected) {
      document.documentElement.appendChild(cursor);
    }
  };
  const place = (x, y) => {
    mount();
    cursor.style.transform = `translate(${x - 3}px,${y - 2}px)`;
  };
  const ripple = (x, y) => {
    const ring = document.createElement("div");
    ring.style.cssText =
      `position:fixed;z-index:2147483647;pointer-events:none;` +
      `left:${x - 16}px;top:${y - 16}px;width:32px;height:32px;` +
      `border:3px solid #e11d48;border-radius:50%;opacity:1;` +
      `transition:transform .45s ease-out,opacity .45s ease-out;`;
    document.documentElement.appendChild(ring);
    requestAnimationFrame(() => {
      ring.style.transform = "scale(1.9)";
      ring.style.opacity = "0";
    });
    setTimeout(() => ring.remove(), 500);
  };
  window.addEventListener(
    "mousemove",
    (e) => place(e.clientX, e.clientY),
    true
  );
  window.addEventListener(
    "mousedown",
    (e) => {
      place(e.clientX, e.clientY);
      ripple(e.clientX, e.clientY);
    },
    true
  );
  mount();
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", mount);
  }
})();
