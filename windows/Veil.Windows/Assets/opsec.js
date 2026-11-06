(() => {
  try {
    if (location.protocol === 'veil:') return;
    const C = __CONFIG__;
    const put = (obj, name, value) => { try { Object.defineProperty(obj, name, { value: value, configurable: true, writable: true }); } catch (e) {} };
    const getter = (obj, name, fn) => { try { Object.defineProperty(obj, name, { get: fn, configurable: true }); } catch (e) {} };
    if (C.webrtc) {
      ['RTCPeerConnection', 'webkitRTCPeerConnection', 'RTCSessionDescription', 'RTCIceCandidate', 'RTCDataChannel']
        .forEach(n => put(window, n, undefined));
    }
    if (C.beacons) {
      put(Navigator.prototype, 'sendBeacon', function () { return true; });
      const strip = () => document.querySelectorAll('a[ping],area[ping]').forEach(a => a.removeAttribute('ping'));
      document.addEventListener('DOMContentLoaded', strip);
      document.addEventListener('mouseover', strip, true);
    }
    if (C.hardware) {
      getter(Navigator.prototype, 'hardwareConcurrency', () => 4);
      getter(Navigator.prototype, 'deviceMemory', () => 8);
      put(Navigator.prototype, 'getBattery', undefined);
    }
    if (C.referrer) {
      const add = () => {
        const m = document.createElement('meta');
        m.name = 'referrer'; m.content = 'same-origin';
        (document.head || document.documentElement).appendChild(m);
      };
      if (document.documentElement) add();
      else new MutationObserver((_, o) => { if (document.documentElement) { o.disconnect(); add(); } }).observe(document, { childList: true });
    }
  } catch (e) {}
})();