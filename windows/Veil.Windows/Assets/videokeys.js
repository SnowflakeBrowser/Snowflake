(() => {
  try {
    if (location.protocol === 'veil:' || location.protocol === 'data:' || window.__veilVideoKeys) return;
    window.__veilVideoKeys = true;
    let box = null, timer = 0;
    const toast = (text) => {
      try {
        if (!box) {
          box = document.createElement('div');
          box.style.cssText = 'position:fixed;top:18px;left:50%;transform:translateX(-50%);z-index:2147483647;padding:7px 14px;border-radius:10px;background:rgba(0,0,0,.78);color:#fff;font:600 14px -apple-system,system-ui,sans-serif;pointer-events:none;transition:opacity .2s;opacity:0';
          (document.body || document.documentElement).appendChild(box);
        }
        box.textContent = text;
        box.style.opacity = '1';
        clearTimeout(timer);
        timer = setTimeout(() => { box.style.opacity = '0'; }, 1100);
      } catch (e) {}
    };
    const pick = () => {
      const vs = Array.from(document.querySelectorAll('video'));
      const playing = vs.find(v => !v.paused && !v.ended);
      if (playing) return playing;
      vs.sort((a, b) => (b.videoWidth * b.videoHeight) - (a.videoWidth * a.videoHeight));
      return vs[0];
    };
    const pip = async (v) => {
      try {
        if (document.pictureInPictureElement) { await document.exitPictureInPicture(); }
        else if (v.requestPictureInPicture) { await v.requestPictureInPicture(); }
        else if (v.webkitSetPresentationMode) {
          v.webkitSetPresentationMode(v.webkitPresentationMode === 'picture-in-picture' ? 'inline' : 'picture-in-picture');
        }
      } catch (err) { toast('Picture in Picture is not available here'); }
    };
    const speed = (v, rate) => {
      v.playbackRate = Math.max(0.25, Math.min(4, Math.round(rate * 100) / 100));
      toast(v.playbackRate + '\u00d7');
    };
    window.addEventListener('keydown', (e) => {
      if (!e.altKey || e.metaKey || e.ctrlKey) return;
      const t = e.target;
      if (t && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName))) return;
      const v = pick();
      if (!v) return;
      if (e.code === 'BracketRight') speed(v, v.playbackRate + 0.25);
      else if (e.code === 'BracketLeft') speed(v, v.playbackRate - 0.25);
      else if (e.code === 'Backslash') speed(v, 1);
      else if (e.code === 'KeyP') pip(v);
      else return;
      e.preventDefault();
      e.stopPropagation();
    }, true);
  } catch (e) {}
})();