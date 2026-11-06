(() => {
  try {
    const noisy = (src) => {
      const c = document.createElement('canvas');
      c.width = src.width; c.height = src.height;
      const x = c.getContext('2d');
      x.drawImage(src, 0, 0);
      const id = origGet.call(x, 0, 0, Math.max(1, c.width), Math.max(1, c.height));
      for (let i = 0; i < id.data.length; i += 211) id.data[i] = (id.data[i] + 1) & 255;
      x.putImageData(id, 0, 0);
      return c;
    };
    const origGet = CanvasRenderingContext2D.prototype.getImageData;
    CanvasRenderingContext2D.prototype.getImageData = function (...a) {
      const d = origGet.apply(this, a);
      for (let i = 0; i < d.data.length; i += 211) d.data[i] = (d.data[i] + 1) & 255;
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