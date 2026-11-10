(() => {
  if (location.protocol === 'veil:' || location.protocol === 'data:') return;
  try {
    const bump = (data) => {
      for (let i = 0; i < data.length; i += 211) {
        if (i % 4 === 3) continue;                       // leave transparency alone
        data[i] = data[i] === 255 ? 254 : data[i] + 1;
      }
    };
    const noisy = (src) => {
      const c = document.createElement('canvas');
      c.width = src.width; c.height = src.height;
      const x = c.getContext('2d');
      x.drawImage(src, 0, 0);
      const id = origGet.call(x, 0, 0, Math.max(1, c.width), Math.max(1, c.height));
      bump(id.data);
      x.putImageData(id, 0, 0);
      return c;
    };
    const origGet = CanvasRenderingContext2D.prototype.getImageData;
    CanvasRenderingContext2D.prototype.getImageData = function (...a) {
      const d = origGet.apply(this, a);
      bump(d.data);
      return d;
    };
    const origURL = HTMLCanvasElement.prototype.toDataURL;
    HTMLCanvasElement.prototype.toDataURL = function (...a) {
      try { if (this.width && this.height) return origURL.apply(noisy(this), a); } catch (e) {}
      return origURL.apply(this, a);
    };
    Object.defineProperty(Navigator.prototype, 'hardwareConcurrency', { get: () => 4 });
  } catch (e) {}
})();