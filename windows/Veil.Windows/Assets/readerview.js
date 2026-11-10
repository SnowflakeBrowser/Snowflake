(() => {
  const toast = (text) => {
    try {
      const b = document.createElement('div');
      b.style.cssText = 'position:fixed;top:18px;left:50%;transform:translateX(-50%);z-index:2147483647;padding:7px 14px;border-radius:10px;background:rgba(0,0,0,.78);color:#fff;font:600 14px -apple-system,system-ui,sans-serif;pointer-events:none';
      b.textContent = text;
      (document.body || document.documentElement).appendChild(b);
      setTimeout(() => b.remove(), 1800);
    } catch (e) {}
  };
  const root = document.documentElement;
  if (root.hasAttribute('data-veil-reader')) {
    root.removeAttribute('data-veil-reader');
    const old = document.getElementById('veil-reader-style');
    if (old) old.remove();
    document.querySelectorAll('[data-veil-reader-main]').forEach(e => e.removeAttribute('data-veil-reader-main'));
    return;
  }
  const textLen = (el) => (el ? el.innerText.trim().length : 0);
  let main = document.querySelector('article') || document.querySelector('main') || document.querySelector('[role="main"]');
  if (!main || textLen(main) < 400) {
    const score = new Map();
    document.querySelectorAll('p').forEach(p => {
      const n = p.innerText.trim().length;
      if (n < 60 || !p.parentElement) return;
      score.set(p.parentElement, (score.get(p.parentElement) || 0) + n);
    });
    let best = null, bestScore = 0;
    score.forEach((v, k) => { if (v > bestScore) { best = k; bestScore = v; } });
    if (best && bestScore >= 300) main = best;
  }
  if (!main || textLen(main) < 200) { toast('Reader view is not available on this page'); return; }
  main.setAttribute('data-veil-reader-main', '');
  const css = [
    'html[data-veil-reader] { background: #fbfbfa !important; }',
    'html[data-veil-reader] body *:not([data-veil-reader-main]):not([data-veil-reader-main] *):not(:has([data-veil-reader-main])) { display: none !important; }',
    'html[data-veil-reader] body { background: transparent !important; margin: 0 !important; padding: 0 !important; }',
    'html[data-veil-reader] [data-veil-reader-main] { display: block !important; position: static !important; float: none !important; width: auto !important; max-width: 700px !important; margin: 56px auto !important; padding: 0 24px !important; color: #1d1d1f !important; background: transparent !important; font: 19px/1.65 Georgia, "Iowan Old Style", serif !important; }',
    'html[data-veil-reader] [data-veil-reader-main] :is(nav, aside, footer, form, button, iframe, [class*="advert"], [id*="advert"], [class*="newsletter"], [class*="share"]) { display: none !important; }',
    'html[data-veil-reader] [data-veil-reader-main] img, html[data-veil-reader] [data-veil-reader-main] video { max-width: 100% !important; height: auto !important; }',
    'html[data-veil-reader] [data-veil-reader-main] a { color: inherit !important; }',
    '@media (prefers-color-scheme: dark) { html[data-veil-reader] { background: #121214 !important; } html[data-veil-reader] [data-veil-reader-main] { color: #e8e8ea !important; } }'
  ].join('\n');
  const st = document.createElement('style');
  st.id = 'veil-reader-style';
  st.textContent = css;
  document.documentElement.appendChild(st);
  root.setAttribute('data-veil-reader', '');
  window.scrollTo(0, 0);
})();