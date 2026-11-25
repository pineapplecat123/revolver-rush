#!/usr/bin/env node
'use strict';
// No browser/network needed. Pure layout tests + app event wiring in a tiny DOM double.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const OV = require('../companion/bullet-editor/overview.js');
const dir = path.join(__dirname, '../companion/bullet-editor');
const rows = [
  {id:'old', name:'老火焰', type:'开始', school:'火', damage:'0', rarity:'普通', effect:'枪口火焰\n消耗枪口火焰', game_description:'专用游戏内描述  \n', notes:'仅设计师可见', in_game:true, created_at:'2026-11-20T00:00:00Z', updated_at:'2026-11-21T00:00:00Z'},
  {id:'new', name:'新冰弹', type:'中间', school:'冰', damage:'23', rarity:'普通', effect:'火焰层数', game_description:'伤害', in_game:false, created_at:'2026-11-22T00:00:00Z', updated_at:'2026-11-24T00:00:00Z'},
  {id:'blank', name:'未分类', type:'', school:'', rarity:'稀有', created_at:'2026-11-23T00:00:00Z'}
];
const original = JSON.stringify(rows);
const currentRows = JSON.parse(fs.readFileSync(path.join(dir, 'data.json'), 'utf8')).bullets;
assert.deepEqual(OV.defaultView({sort:'name',dir:'asc'}), {sort:'updated',dir:'desc',overviewDefaults:1});
assert.equal(OV.defaultView({sort:'name',dir:'asc',overviewDefaults:1}).sort, 'name');
assert(OV.updatedStamp(rows[2]) > OV.updatedStamp(rows[0]));
assert.equal(OV.displayValue({}, 'updated_at'), '—');
assert.match(OV.displayValue(rows[0], 'updated_at'), /8:00:00.*北京时间/);
assert.equal(OV.matches(rows[0], {q:'专用游戏内'}, 'all'), true);
assert.equal(OV.matches(rows[0], {q:'火焰',type:'中间'}, 'all'), false);
assert.deepEqual({...OV.counts(rows,'school',{school:'火'},'all')}, {'火':1,'冰':1,'':1});
assert.deepEqual({...OV.counts(rows,'school',{school:'火',type:'中间'},'out')}, {'火':0,'冰':1,'':0});
assert.deepEqual({...OV.counts(rows,'type',{school:'火',type:'中间'},'all')}, {'开始':1,'中间':0,'':0});
assert.deepEqual({...OV.counts([{school:'__proto__'}],'school',{},'all')}, {['__proto__']:1});

const measure = {font:'', measureText(s) { return {width: Array.from(s).length * 22}; }};
assert.deepEqual(OV.wrap(measure, '中文🙂测\n\n试', 44), ['中文','🙂测','','试']);
const plan = OV.layout(measure, rows, OV.fields.map(f=>f[0]));
assert.equal(plan.width, 1000);
const boxes = plan.commands.filter(c=>c.box);
assert.equal(boxes.length, rows.length);
boxes.forEach((b, i)=>{
  if (i) assert(b.y >= boxes[i-1].y + boxes[i-1].height);
  assert(b.y+b.height < plan.height);
  plan.commands.filter(c=>!c.box && c.y>=b.y && c.y<b.y+b.height).forEach(c=>{
    assert(c.y+c.size <= b.y+b.height);
    assert(measure.measureText(c.text).width <= 896);
  });
});
assert(plan.commands.some(c=>c.style==='italic' && c.text.includes('效果说明')));
assert(plan.commands.some(c=>c.text.includes('专用游戏内描述')));
assert(OV.layout(measure, currentRows, OV.fields.map(f=>f[0])).height <= 16000, 'full current dataset fits conservative mobile canvas budget');
const namesOnly = OV.layout(measure, rows, []);
assert.equal(namesOnly.commands.filter(c=>!c.box).length, 3);
assert(OV.layout(measure, [{name:'大段', effect:'中文'.repeat(3000)+'\n结束'}], ['effect']).height > 3000);

class Element {
  constructor() { this.value=''; this.textContent=''; this.children=[]; this.listeners={}; this.disabled=false;
    this.classList={add(){},remove(){},toggle(){}}; }
  set innerHTML(html) {
    this.html=html;
    this.inputs=Array.from(html.matchAll(/<input[^>]+>/g), m=>({
      value: (m[0].match(/value="([^"]*)"/)||[])[1]||'', checked:/\bchecked\b/.test(m[0])
    }));
  }
  get innerHTML() { return this.html||''; }
  setAttribute(name, value) { this[name]=value; }
  addEventListener(name, fn) { (this.listeners[name] ||= []).push(fn); }
  async fire(name) { for (const fn of this.listeners[name]||[]) await fn({target:this}); }
  querySelectorAll() { return this.inputs||[]; }
  focus() {} reset() {} click() { this.clicks=(this.clicks||0)+1; }
}
function appHarness() {
  const elements = Object.create(null), storage = new Map();
  const html=fs.readFileSync(path.join(dir,'index.html'),'utf8');
  for (const m of html.matchAll(/\bid="([^"]+)"/g)) elements[m[1]]=new Element();
  const document={getElementById:id=>elements[id]||null, addEventListener(){}};
  const window={BulletOverview:{...OV},addEventListener(){}};
  let networkCalls=0;
  const sandbox={document,window,localStorage:{getItem:k=>storage.get(k),setItem:(k,v)=>storage.set(k,v)},
    setTimeout(){},clearTimeout(){},setInterval(){},console,URL:{createObjectURL(){return 'blob:test';},revokeObjectURL(){}},
    fetch(){networkCalls++; throw Error('unexpected network');}};
  // Expose closures in test memory only; production exports no debug hooks or bypass.
  const source=fs.readFileSync(path.join(dir,'app.js'),'utf8').replace(/\}\)\(\);\s*$/, `window.test={
    apply, render, fillForm, formVals, buildRec, itemHtml, selectExport, exportSelection,
    setPending(p){pending=p;}, setView(v){view=Object.assign(view,v);}, getView(){return view;}
  };})();`);
  vm.runInNewContext(source,sandbox,{filename:'app.js'});
  return {el:elements,api:window.test,overview:window.BulletOverview,storage,networkCalls:()=>networkCalls};
}
(async()=>{
  const h=appHarness();
  h.api.apply({bullets:rows,updated_at:'2026-11-25T00:00:00Z'});
  assert(h.el.list.innerHTML.indexOf('新冰弹') < h.el.list.innerHTML.indexOf('未分类'));
  assert(h.el.list.innerHTML.indexOf('未分类') < h.el.list.innerHTML.indexOf('老火焰'));
  assert.match(h.el.list.innerHTML, /class="desc effect"/);
  assert.match(h.el.list.innerHTML, /class="desc play"/);
  assert.match(h.el.filterSchool.innerHTML, /冰（1）/);
  h.api.setView({type:'中间',school:'火'}); h.api.render();
  assert.match(h.el.filterSchool.innerHTML, /火（0）/);
  assert.equal(h.el.filterSchool.value,'火');
  assert.match(h.el.filterType.innerHTML, /开始（1）/);
  h.api.fillForm(rows[0]);
  assert.equal(h.el.f_game_description.value, rows[0].game_description);
  assert.equal(h.api.formVals().game_description, rows[0].game_description);
  const built=h.api.buildRec();
  assert.equal(built.game_description,rows[0].game_description);
  assert.equal(built.notes,rows[0].notes);
  h.api.fillForm({id:'legacy',effect:'旧效果'});
  assert.equal(h.el.f_game_description.value,'旧效果');
  h.api.fillForm({});
  assert.equal(h.el.f_game_description.value,'普通的一个子弹...');
  h.el.f_school.value='新增流派'; await h.el.f_school.fire('input');
  assert.match(h.el.schoolPick.innerHTML,/新增流派/);
  assert.equal(h.el.schoolPick.value,'新增流派');
  h.el.schoolPick.value='冰'; await h.el.schoolPick.fire('change');
  assert.equal(h.api.formVals().school,'冰');
  h.api.setPending([{rec:{id:'waiting',school:'等待流派'}}]); h.api.render();
  assert.match(h.el.schoolPick.innerHTML,/等待流派/);
  assert.doesNotMatch(h.el.filterSchool.innerHTML,/等待流派/);
  h.api.setView({type:'',school:'火'});
  const storageBeforeExport = JSON.stringify([...h.storage]);
  await h.el.openExport.fire('click');
  assert.equal(h.api.exportSelection().length,1);
  assert.equal(h.api.exportSelection()[0].id,'old');
  let exported;
  h.overview.png=async (selectedRows, selectedFields)=>{exported={rows:selectedRows,fields:selectedFields};return {size:42};};
  h.el.exportFields.querySelectorAll().forEach(el=>{el.checked=el.value==='game_description';});
  await h.el.downloadExport.fire('click');
  assert.equal(exported.rows.length,1);
  assert.deepEqual(Array.from(exported.fields),['game_description']);
  assert.equal(h.el.exportDownload.href,'blob:test');
  assert.equal(h.el.exportDownload.clicks,1);
  assert.equal(h.el.downloadExport.disabled,false);
  assert.equal(JSON.stringify([...h.storage]),storageBeforeExport,'export must not modify drafts or stored data');
  h.overview.png=async ()=>{throw Error('模拟编码失败');};
  await h.el.downloadExport.fire('click');
  assert.match(h.el.exportStatus.textContent,/模拟编码失败/);
  assert.equal(h.el.downloadExport.disabled,false);
  h.api.selectExport('all'); assert.equal(h.api.exportSelection().length,3);
  assert.equal(h.api.exportSelection()[0].id,'new');
  // Polling does not mutate the export snapshot or form game description.
  h.api.apply({bullets:[...rows,{id:'later',name:'之后新增',school:'新派'}],updated_at:'2026-11-26T00:00:00Z'});
  assert.equal(h.api.exportSelection().length,3);
  h.api.selectExport('none'); assert.equal(h.api.exportSelection().length,0);
  assert.equal(h.networkCalls(),0);

  const paints=[];
  const ctx={...measure,fillRect(){},fillText(...args){paints.push(args);}};
  let canvas;
  const fakeDocument={fonts:{ready:Promise.resolve()},createElement(){
    canvas={getContext:()=>ctx,toBlob:fn=>fn({size:123,type:'image/png'})}; return canvas;
  }};
  const blob=await OV.png(rows,['effect','game_description'],fakeDocument);
  assert.equal(blob.type,'image/png');
  assert.equal(canvas.height,1); // backing memory freed after encoding
  assert(paints.some(p=>p[0].includes('专用游戏内描述')));
  await assert.rejects(OV.png([],[],fakeDocument),/至少选择/);
  await assert.rejects(OV.png([{name:'极长',effect:'长'.repeat(50000)}],['effect'],fakeDocument),/安全尺寸/);
  fakeDocument.createElement=()=>({getContext:()=>ctx,toBlob:fn=>fn(null)});
  await assert.rejects(OV.png(rows,[],fakeDocument),/图片生成失败/);
  assert.equal(JSON.stringify(rows),original);
  console.log('ok: overview defaults, facets, app controls/contracts, export selection/layout/PNG/error guards (no browser/network)');
})().catch(err=>{console.error(err);process.exitCode=1;});
