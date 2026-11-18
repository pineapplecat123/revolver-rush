/* Type-based bullet color helpers for the editor.
 * Random colors are assigned only on new type selection / actual type change.
 * Display fallbacks are deterministic and must not be used to recolor saved rows.
 */
(function (root) {
  'use strict';

  var FALLBACK = '#EAEAEF';
  var DISPLAY_FALLBACK = { '开始': '#52C76B', '中间': '#F2CC38', '结束': '#DB3D38' };

  // Inclusive HSL windows. Lightness is mid for 开始, high for 中间 (light),
  // low for 结束 (deep red). Hue is degrees.
  var RANGES = {
    '开始': { h0: 120, h1: 180, s0: 0.65, s1: 0.90, l0: 0.40, l1: 0.55 },
    '中间': { h0: 32, h1: 55, s0: 0.80, s1: 1.00, l0: 0.62, l1: 0.80 },
    '结束': { h0: 0, h1: 18, s0: 0.80, s1: 1.00, l0: 0.28, l1: 0.48 }
  };

  function clamp01(n) {
    return Math.max(0, Math.min(1, n));
  }

  function hslToHex(h, s, l) {
    h = ((h % 360) + 360) % 360;
    s = clamp01(s);
    l = clamp01(l);
    var c = (1 - Math.abs(2 * l - 1)) * s;
    var x = c * (1 - Math.abs((h / 60) % 2 - 1));
    var m = l - c / 2;
    var r = 0, g = 0, b = 0;
    if (h < 60) { r = c; g = x; b = 0; }
    else if (h < 120) { r = x; g = c; b = 0; }
    else if (h < 180) { r = 0; g = c; b = x; }
    else if (h < 240) { r = 0; g = x; b = c; }
    else if (h < 300) { r = x; g = 0; b = c; }
    else { r = c; g = 0; b = x; }
    function hex(v) {
      var n = Math.round((v + m) * 255);
      if (n < 0) n = 0;
      if (n > 255) n = 255;
      return ('0' + n.toString(16)).slice(-2);
    }
    return ('#' + hex(r) + hex(g) + hex(b)).toUpperCase();
  }

  function hexToHsl(hex) {
    var s = String(hex || '').trim();
    if (s.charAt(0) === '#') s = s.slice(1);
    if (!/^[0-9A-Fa-f]{6}$/.test(s)) return null;
    var r = parseInt(s.slice(0, 2), 16) / 255;
    var g = parseInt(s.slice(2, 4), 16) / 255;
    var b = parseInt(s.slice(4, 6), 16) / 255;
    var max = Math.max(r, g, b), min = Math.min(r, g, b);
    var l = (max + min) / 2;
    var d = max - min;
    var h = 0, sat = 0;
    if (d !== 0) {
      sat = d / (1 - Math.abs(2 * l - 1));
      if (max === r) h = ((g - b) / d) % 6;
      else if (max === g) h = (b - r) / d + 2;
      else h = (r - g) / d + 4;
      h *= 60;
      if (h < 0) h += 360;
    }
    return { h: h, s: sat, l: l };
  }

  function rangeFor(type) {
    return RANGES[String(type || '').trim()] || null;
  }

  function randomBulletColor(type, rng) {
    var r = rangeFor(type);
    if (!r) return FALLBACK;
    var rnd = rng || Math.random;
    function unit() {
      var v = typeof rnd === 'function' ? rnd() : Math.random();
      if (typeof v !== 'number' || v < 0 || v >= 1) v = Math.random();
      return v;
    }
    var h = r.h0 + unit() * (r.h1 - r.h0);
    var s = r.s0 + unit() * (r.s1 - r.s0);
    var l = r.l0 + unit() * (r.l1 - r.l0);
    return hslToHex(h, s, l);
  }

  function isInTypeRange(hex, type, slack) {
    var r = rangeFor(type);
    var hsl = hexToHsl(hex);
    if (!r || !hsl) return false;
    var eps = slack == null ? 0.03 : slack;
    if (hsl.s < r.s0 - eps || hsl.s > r.s1 + eps) return false;
    if (hsl.l < r.l0 - eps || hsl.l > r.l1 + eps) return false;
    var h = hsl.h;
    return h + 0.8 >= r.h0 && h - 0.8 <= r.h1;
  }

  function displayFallbackColor(type) {
    var t = String(type || '').trim();
    return DISPLAY_FALLBACK[t] || FALLBACK;
  }

  function normalizeType(type) {
    return String(type || '').trim();
  }

  // If the type actually changed to a known slot type, assign a new random
  // bullet color. Otherwise keep the current persisted value.
  function bulletColorAfterTypeChange(prevType, nextType, currentColor, rng) {
    var prev = normalizeType(prevType);
    var next = normalizeType(nextType);
    if (prev === next) return currentColor || displayFallbackColor(next);
    if (RANGES[next]) return randomBulletColor(next, rng);
    return currentColor || FALLBACK;
  }

  function syncMuzzleFromBullet(bulletHex, fallback) {
    var s = String(bulletHex || '').trim();
    if (s.charAt(0) !== '#') s = '#' + s;
    if (!/^#[0-9A-Fa-f]{6}$/.test(s)) return fallback || FALLBACK;
    return s.toUpperCase();
  }

  var api = {
    FALLBACK: FALLBACK,
    DISPLAY_FALLBACK: DISPLAY_FALLBACK,
    RANGES: RANGES,
    hslToHex: hslToHex,
    hexToHsl: hexToHsl,
    randomBulletColor: randomBulletColor,
    isInTypeRange: isInTypeRange,
    displayFallbackColor: displayFallbackColor,
    bulletColorAfterTypeChange: bulletColorAfterTypeChange,
    syncMuzzleFromBullet: syncMuzzleFromBullet
  };

  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.BulletColors = api;
})(typeof window !== 'undefined' ? window : globalThis);
