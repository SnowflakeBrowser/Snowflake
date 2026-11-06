(() => {
  try {
    if (location.protocol === 'veil:' || window.__veilFun) return;
    window.__veilFun = true;
    const C = __CONFIG__;
    const go = () => {
      const R = document.documentElement;
      let css = '';
      const FILTERS = { grayscale: 'grayscale(1)', sepia: 'sepia(.85)', contrast: 'contrast(1.25) saturate(1.2)',
                        vivid: 'saturate(1.7)', cool: 'hue-rotate(160deg)' };
      if (C.pageFilter === 'dark') {
        css += 'html{filter:invert(1) hue-rotate(180deg)!important;background:#fff}' +
               'img,video,canvas,picture,iframe{filter:invert(1) hue-rotate(180deg)!important}';
      } else if (FILTERS[C.pageFilter]) {
        css += 'html{filter:' + FILTERS[C.pageFilter] + '!important}';
      }
      const FONTS = {
        comic: '"Comic Sans MS","Comic Neue",cursive',
        rounded: 'ui-rounded,"SF Pro Rounded","Arial Rounded MT Bold",sans-serif',
        serif: 'Georgia,"Times New Roman",serif',
        mono: 'ui-monospace,Menlo,monospace',
        hand: '"Bradley Hand","Noteworthy","Marker Felt",cursive'
      };
      if (FONTS[C.pageFont]) {
        css += '*:not(i):not(code):not(pre):not(kbd):not(samp):not([class*=icon]):not([class*=Icon]):not([class*=fa]):not([class*=material]):not([class*=glyph]){font-family:' + FONTS[C.pageFont] + '!important}';
      }
      const SEL = { pink: '#ff9ecb', lime: '#c6f26b', yellow: '#ffe566', sky: '#8fd3ff', violet: '#c4b0ff' };
      if (SEL[C.selectionColor]) css += '::selection{background:' + SEL[C.selectionColor] + '!important;color:#111!important}';
      if (C.linkStyle === 'wavy') css += 'a{text-decoration:underline wavy!important;text-underline-offset:3px!important}';
      if (C.linkStyle === 'highlight') css += 'a{background:linear-gradient(transparent 60%,rgba(255,235,59,.55) 0)!important;text-decoration:none!important}';
      if (C.linkStyle === 'plain') css += 'a{text-decoration:none!important}';
      if (C.linkStyle === 'underline') css += 'a{text-decoration:underline!important}';
      if (C.smoothScroll) css += 'html{scroll-behavior:smooth!important}';
      if (C.hideScrollbars) css += '::-webkit-scrollbar{display:none!important}html{scrollbar-width:none!important}';
      if (C.roundImages) css += 'img,video{border-radius:14px!important}';
      if (C.blurImages) css += 'img,video{filter:blur(12px)!important;transition:filter .25s}img:hover,video:hover{filter:none!important}';
      if (C.reduceMotion) css += '*,*::before,*::after{animation-duration:.001s!important;animation-iteration-count:1!important;transition-duration:.001s!important}';
      if (C.forceSelect) css += '*{-webkit-user-select:text!important;user-select:text!important}';
      if (C.readableText) css += 'p,li,dd{line-height:1.7!important}p{max-width:75ch}';
      if (C.grayImages) css += 'img,video{filter:grayscale(1)!important}';
      if (css) {
        const st = document.createElement('style');
        st.textContent = css;
        st.setAttribute('data-veil-fun', '1');
        (document.head || R).appendChild(st);
      }
      const overlay = (bg, blend) => {
        const d = document.createElement('div');
        d.style.cssText = 'position:fixed;left:0;top:0;right:0;bottom:0;pointer-events:none;z-index:2147483647;background:' + bg + (blend ? ';mix-blend-mode:' + blend : '');
        d.setAttribute('data-veil-fun', '1');
        R.appendChild(d);
      };
      if (C.dimPages > 0) overlay('rgba(0,0,0,' + (C.dimPages / 100) + ')');

    };
    if (document.documentElement) go();
    else new MutationObserver((_, o) => { if (document.documentElement) { o.disconnect(); go(); } }).observe(document, { childList: true });
  } catch (e) {}
})();