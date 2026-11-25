/* Local-only overview/export helpers. No network, storage or data writes. */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.BulletOverview = factory();
})(typeof window !== 'undefined' ? window : this, function () {
  'use strict';
  var fields = [
    ['type', '类型'], ['school', '流派'], ['damage', '基础伤害'], ['rarity', '稀有度'],
    ['in_game', '入库状态'], ['effect', '效果说明'], ['game_description', '游戏内描述'],
    ['notes', '备注'], ['muzzle_color', '枪口火焰颜色'], ['bullet_color', '子弹颜色'],
    ['updated_at', '更新时间'], ['created_at', '创建时间']
  ];
  var fontFamily = '\"PingFang SC\",\"Microsoft YaHei\",\"Noto Sans CJK SC\",\"Noto Sans SC\",sans-serif';
  function text(v) { return String(v == null ? '' : v); }
  function norm(v) { return text(v).trim().toLowerCase(); }
  function matches(b, view, status, omit) {
    if (status === 'in' && !b.in_game || status === 'out' && b.in_game) return false;
    if (['type', 'school', 'rarity'].some(function (key) {
      return key !== omit && view[key] && text(b[key]).trim() !== view[key];
    })) return false;
    var q = norm(view.q);
    return !q || ['name', 'type', 'school', 'effect', 'game_description', 'notes'].some(function (key) {
      return norm(b[key]).indexOf(q) !== -1;
    });
  }
  // Disjunctive facets: each count respects every active filter except itself.
  function counts(rows, key, view, status) {
    var result = Object.create(null);
    rows.forEach(function (b) { result[text(b[key]).trim()] = 0; });
    rows.forEach(function (b) {
      if (matches(b, view, status, key)) result[text(b[key]).trim()]++;
    });
    return result;
  }
  function defaultView(saved) {
    var v = Object.assign({}, saved || {});
    // One-time migration: old saved sorting must not mask the new default.
    if (v.overviewDefaults !== 1) { v.sort = 'updated'; v.dir = 'desc'; v.overviewDefaults = 1; }
    return v;
  }
  function updatedStamp(b) { return Date.parse(b.updated_at) || Date.parse(b.created_at) || 0; }
  function displayValue(b, key) {
    if (key === 'in_game') return b.in_game ? '已入库' : '未入库';
    if (key === 'updated_at' || key === 'created_at') {
      if (key === 'updated_at' ? !updatedStamp(b) : !b[key]) return '—';
      var d = new Date(key === 'updated_at' ? updatedStamp(b) : b[key]);
      if (!isFinite(d.getTime())) return '—';
      return d.toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai', hour12: false }) + '（北京时间）';
    }
    return text(b[key]) || '—';
  }
  function graphemes(s) {
    if (typeof Intl !== 'undefined' && Intl.Segmenter) return Array.from(new Intl.Segmenter('zh', { granularity: 'grapheme' }).segment(s), function (v) { return v.segment; });
    return Array.from(s);
  }
  // Measure exactly what will be painted, preserving explicit newlines and blank lines.
  function wrap(ctx, value, width) {
    var lines = [];
    text(value).replace(/\r\n?/g, '\n').split('\n').forEach(function (paragraph) {
      var line = '';
      graphemes(paragraph).forEach(function (ch) {
        if (line && ctx.measureText(line + ch).width > width) { lines.push(line); line = ''; }
        line += ch;
      });
      lines.push(line);
    });
    return lines;
  }
  function font(size, style) { return (style || 'normal') + ' ' + size + 'px ' + fontFamily; }
  function layout(ctx, rows, selectedFields) {
    var width = 1000, pad = 36, y = 104, commands = [];
    rows.forEach(function (b, index) {
      var top = y, lines = [];
      function add(value, size, style, color) {
        ctx.font = font(size, style);
        wrap(ctx, value, width - pad * 2 - 32).forEach(function (line) {
          lines.push({ text: line, size: size, style: style, color: color });
        });
      }
      add((index + 1) + '. ' + (text(b.name) || '未命名'), 27, 'bold', '#ffcb7a');
      fields.forEach(function (field) {
        if (selectedFields.indexOf(field[0]) !== -1) add(field[1] + '：' + displayValue(b, field[0]), 22, field[0] === 'game_description' ? 'italic' : 'normal', '#eef0f6');
      });
      y += 16;
      lines.forEach(function (line) { line.x = pad + 16; line.y = y; commands.push(line); y += line.size + 12; });
      y += 12;
      commands.push({ box: true, x: pad, y: top, width: width - pad * 2, height: y - top });
      y += 20;
    });
    return { width: width, height: Math.ceil(y + 20), commands: commands };
  }
  async function png(rows, selectedFields, document) {
    if (!rows.length) throw new Error('请至少选择一颗子弹。');
    // Same native Chinese fonts as the editor; wait for any document fonts before measuring.
    if (document.fonts && document.fonts.ready) await document.fonts.ready;
    var canvas = document.createElement('canvas'), ctx = canvas.getContext('2d');
    if (!ctx) throw new Error('浏览器不支持图片绘制，请更换浏览器。');
    var plan = layout(ctx, rows, selectedFields);
    // Conservative mobile canvas limit (16 MP / 16384px). Never crop or silently omit rows.
    if (plan.height > 16000) throw new Error('长图超过手机安全尺寸，请减少子弹或字段后再导出（不会截断内容）。');
    canvas.width = plan.width; canvas.height = plan.height;
    ctx.fillStyle = '#14161d'; ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.textBaseline = 'top'; ctx.font = font(30, 'bold'); ctx.fillStyle = '#ffcb7a';
    ctx.fillText('子弹数据 · ' + rows.length + ' 颗', 36, 28);
    // Paint backgrounds first, then text: no overlap with adjacent rows, no clipping.
    plan.commands.filter(function (c) { return c.box; }).forEach(function (c) {
      ctx.fillStyle = '#262a36'; ctx.fillRect(c.x, c.y, c.width, c.height);
    });
    plan.commands.filter(function (c) { return !c.box; }).forEach(function (c) {
      ctx.font = font(c.size, c.style); ctx.fillStyle = c.color; ctx.fillText(c.text, c.x, c.y);
    });
    try {
      return await new Promise(function (resolve, reject) {
        canvas.toBlob(function (blob) {
          // Canvas allocation/encoding failures are explicit, not empty downloads.
          if (blob && blob.size) resolve(blob);
          else reject(new Error('图片生成失败，请减少内容或更换浏览器后再试。'));
        }, 'image/png');
      });
    } finally { canvas.width = 1; canvas.height = 1; }
  }
  return { fields: fields, matches: matches, counts: counts, defaultView: defaultView,
    updatedStamp: updatedStamp, displayValue: displayValue, wrap: wrap, layout: layout, png: png };
});
