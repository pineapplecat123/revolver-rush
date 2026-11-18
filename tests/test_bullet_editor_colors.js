#!/usr/bin/env node
'use strict';
const assert = require('assert');
const colors = require('../companion/bullet-editor/bullet_colors.js');

function seqRng(values) {
  let i = 0;
  return function () {
    const v = values[i % values.length];
    i += 1;
    return v;
  };
}

let passed = 0;
function ok(cond, msg) {
  assert(cond, msg);
  passed += 1;
}

['开始', '中间', '结束'].forEach((type) => {
  const seen = new Set();
  for (let i = 0; i < 80; i++) {
    const hex = colors.randomBulletColor(type);
    ok(/^#[0-9A-F]{6}$/.test(hex), type + ' hex ' + hex);
    ok(colors.isInTypeRange(hex, type), type + ' range ' + hex + ' hsl=' + JSON.stringify(colors.hexToHsl(hex)));
    seen.add(hex);
  }
  ok(seen.size >= 20, type + ' should vary, got ' + seen.size);
  ok(!colors.isInTypeRange(colors.randomBulletColor(type), type === '开始' ? '结束' : '开始'), type + ' should not land in a foreign window (occasional edge allowed below)');
});

// fixed midpoints must sit in their own window
ok(colors.isInTypeRange(colors.hslToHex(150, 0.8, 0.47), '开始'), 'cyan-green midpoint');
ok(colors.isInTypeRange(colors.hslToHex(44, 0.95, 0.70), '中间'), 'light yellow-orange midpoint');
ok(colors.isInTypeRange(colors.hslToHex(8, 0.95, 0.36), '结束'), 'deep red midpoint');
ok(!colors.isInTypeRange(colors.hslToHex(44, 0.95, 0.70), '开始'));
ok(!colors.isInTypeRange(colors.hslToHex(150, 0.8, 0.47), '中间'));
ok(!colors.isInTypeRange('#222222', '结束'), 'near-black is not deep red in range');

// Deterministic rng still stays in range and is stable for the same stream
const a = colors.randomBulletColor('开始', seqRng([0.1, 0.2, 0.3]));
const b = colors.randomBulletColor('开始', seqRng([0.1, 0.2, 0.3]));
ok(a === b, 'same rng stream is stable, got ' + a + ' vs ' + b);
ok(colors.isInTypeRange(a, '开始'));

// Persist: no type change keeps the current color, even if it is manual
const manual = '#12AB89';
ok(colors.bulletColorAfterTypeChange('开始', '开始', manual) === manual, 'viewing / same type must not reroll');
ok(colors.bulletColorAfterTypeChange('开始', '开始', manual, () => { throw new Error('must not rng'); }) === manual);

// Actual type change assigns a new in-range color
const changed = colors.bulletColorAfterTypeChange('开始', '结束', manual, seqRng([0.2, 0.2, 0.2]));
ok(changed !== manual, 'type change should assign a new color');
ok(colors.isInTypeRange(changed, '结束'), 'new color in 结束 range: ' + changed);

// New entry first type selection (from empty)
const first = colors.bulletColorAfterTypeChange('', '中间', '', seqRng([0.5, 0.5, 0.5]));
ok(colors.isInTypeRange(first, '中间'), 'first type pick: ' + first);

// Display fallback is deterministic, not random
ok(colors.displayFallbackColor('开始') === colors.DISPLAY_FALLBACK['开始']);
ok(colors.displayFallbackColor('开始') === colors.displayFallbackColor('开始'));

// Sync copies bullet into status/muzzle once, no live link
ok(colors.syncMuzzleFromBullet('#aBcdEf') === '#ABCDEF');
ok(colors.syncMuzzleFromBullet('112233') === '#112233');
ok(colors.syncMuzzleFromBullet('nope', '#52C76B') === '#52C76B');

console.log('ok', passed, 'asserts');
