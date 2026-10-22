'use strict';
const {app}=require('electron');
const fs=require('node:fs'),os=require('node:os'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),tmp=fs.mkdtempSync(path.join(os.tmpdir(),'smartive-multi-'));
const output=path.join(root,'test-results/entity-multi');fs.mkdirSync(output,{recursive:true});
process.chdir(root);app.setPath('userData',tmp);app.setAppPath(root);
process.env.LDTK_SMARTIVE_CONTROL_DIR=path.join(tmp,'control');
app.commandLine.appendSwitch('no-sandbox');
if(process.platform==='linux'){app.commandLine.appendSwitch('use-gl','angle');app.commandLine.appendSwitch('use-angle','swiftshader');}
const passed=[],delay=ms=>new Promise(r=>setTimeout(r,ms));
const timer=setTimeout(()=>{console.error('Multi-entity test timeout');app.exit(1)},process.platform==='darwin'?240000:120000);
let running=false;
app.on('browser-window-created',(_,win)=>{
 win.webContents.on('console-message',(_,level,msg)=>{if(level>=2)console.log('[renderer]',msg)});
 win.webContents.on('did-finish-load',()=>{
  if(!win.webContents.getURL().endsWith('/assets/app.html')||running)return;
  running=true;run(win).catch(async err=>{
   console.error(err.stack||err);
   fs.writeFileSync(path.join(output,'results.json'),JSON.stringify({status:'failed',passed,error:String(err.stack||err)},null,2));
   try{fs.writeFileSync(path.join(output,'failure.png'),(await win.webContents.capturePage()).toPNG());}catch(_){}
   clearTimeout(timer);app.exit(1);
  });
 });
});
async function run(win){
 const ev=async code=>{
  const r=await win.webContents.executeJavaScript(`(()=>{try{return {ok:true,v:(${code})}}catch(e){return {ok:false,error:String(e&&e.stack||e)}}})()`,true);
  if(!r||!r.ok)throw Error(code+'\n'+String(r&&r.error));return r.v;
 };
 const until=async(code,msg)=>{for(let i=0;i<250;i++){if(await ev(`!!(${code})`))return;await delay(40)}throw Error(msg)};
 const pass=m=>{passed.push(m);console.log('PASS: '+m)};
 await until('globalThis.__ldtk && __ldtk.App.ME && document.querySelector("#page")','No app');
 await delay(750);win.setSize(1600,1000);win.show();win.focus();win.webContents.setBackgroundThrottling(false);
 await win.webContents.executeJavaScript(fs.readFileSync(path.join(__dirname,'entity-multi-fixture.js'),'utf8'),true);
 const setup=async()=>{
  console.log('SETUP fixture');
  const data=await ev(`multiFixture.setup(${JSON.stringify(path.join(tmp,'test.ldtk'))})`);await delay(450);await ev('multiFixture.editor()&&true');await ev('__ldtk.classes["ui.Modal"].closeAll()');await delay(200);return data;
 };
 const select=()=>ev('multiFixture.select()');
 const value=(name,idx=0)=>`#multi_field_${fields[name]}_${idx}`;
 const setUI=async(name,v,idx=0)=>ev(`(()=>{const el=document.querySelector(${JSON.stringify(value(name,idx))});if(!el)throw Error('Missing ${name}');el.value=${JSON.stringify(v)};el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}));return true})()`);
 const values=name=>ev(`multiFixture.values(${JSON.stringify(name)})`);
 const state=()=>ev('multiFixture.state()');
 const good=async()=>assert.equal(await ev('__ldtk.App.ME.curPageProcess.__class__.__name__'),'page.Editor');
 console.log('BOOT ready');
 let {fields}=await setup();
 console.log('FIXTURE ready');
 require('electron').Menu.setApplicationMenu(null);win.webContents.focus();
 const a=await ev('multiFixture.point(40,40)'),b=await ev('multiFixture.point(160,90)');
 await ev('multiFixture.editor().selectionTool.clear()');
 const beforeSelect=await state();
 win.webContents.sendInputEvent({type:'keyDown',keyCode:'Alt'});
 win.webContents.sendInputEvent({type:'keyDown',keyCode:'Shift'});
 await until('multiFixture.keys().alt && multiFixture.keys().shift','Modifiers not delivered');
 win.webContents.sendInputEvent({type:'mouseMove',x:a.x,y:a.y,modifiers:['alt','shift']});await delay(60);
 win.webContents.sendInputEvent({type:'mouseDown',x:a.x,y:a.y,button:'left',clickCount:1,modifiers:['alt','shift']});
 await until('multiFixture.editor().selectionTool.isRunning()','Selection did not start on mouse-down');
 win.webContents.sendInputEvent({type:'mouseMove',x:b.x,y:b.y,modifiers:['alt','shift']});await delay(150);
 win.webContents.sendInputEvent({type:'mouseUp',x:b.x,y:b.y,button:'left',clickCount:1,modifiers:['alt','shift']});
 await until('!multiFixture.editor().selectionTool.isRunning()','Selection did not stop on mouse-up');
 win.webContents.sendInputEvent({type:'keyUp',keyCode:'Shift'});win.webContents.sendInputEvent({type:'keyUp',keyCode:'Alt'});
 await until('document.querySelector(".multiEntityInstanceEditor") && !multiFixture.editor().selectionTool.isRunning()','Rectangle did not open multi-inspector');
 assert.equal((await state()).data,beforeSelect.data);
 assert.equal((await state()).history,beforeSelect.history);
 assert((await ev('document.querySelector(".multiEntityInstanceEditor header .id").textContent')).includes('2 selected'));
 pass('Actual Shift+Option/Alt rectangle opens the contextual inspector across entity layers without changing data');

 assert.equal(await ev(`document.querySelector(${JSON.stringify(value('Amount'))}).placeholder`),'—');
 assert.equal(await ev(`document.querySelector(${JSON.stringify(value('Label'))}).value`),'unchanged');
 assert.equal(await ev(`document.querySelector(${JSON.stringify(value('Active'))}).indeterminate`),true);
 assert.equal(await ev(`document.querySelector(${JSON.stringify(value('Mode'))}).selectedOptions[0].textContent`),'—');
 assert.equal(await ev(`document.querySelector('[data-multi-field="${fields.Steps}"] .multiSize').placeholder`),'—');
 assert.equal(await ev(`document.querySelector(${JSON.stringify(value('Steps',2))})===null`),true);
 let before=await state();
 await ev(`(()=>{const x=document.querySelector(${JSON.stringify(value('Amount'))});x.focus();x.blur();x.dispatchEvent(new Event('change',{bubbles:true}));return true})()`);
 assert.equal((await state()).data,before.data);assert.equal((await state()).history,before.history);
 await delay(200);
 console.log('PANEL layout',await ev('(()=>{const p=document.querySelector(".multiEntityInstanceEditor"),r=p.getBoundingClientRect(),s=getComputedStyle(p);return {left:r.left,top:r.top,width:r.width,height:r.height,display:s.display,visibility:s.visibility,opacity:s.opacity}})()'));
 fs.writeFileSync(path.join(output,'mixed-values.png'),(await win.webContents.capturePage()).toPNG());
 pass('Mixed numbers, bools, enums, nullable zero and array lengths show a dash; focus/blur is read-only');

 before=await state();
 await setUI('Amount','3');
 let after=await state();
 assert.deepEqual(await values('Amount'),[3,3,3]);assert.equal(after.history,before.history+1);
 for(let i=0;i<3;i++) {
  const strip=e=>({...e,fieldInstances:e.fieldInstances.filter(f=>f.defUid!==fields.Amount)});
  assert.deepEqual(strip(after.entities[i]),strip(before.entities[i]));
 }
 assert(await ev('multiFixture.undo()'));await delay(160);assert.equal((await state()).data,before.data);
 assert(await ev('multiFixture.redo()'));await delay(160);assert.deepEqual(await values('Amount'),[3,3,3]);
 await select();const noOp=await state();await setUI('Amount','3');assert.equal((await state()).history,noOp.history);
 pass('Mixed-to-first-value edit affects only the chosen field; one Undo/Redo restores all selected layers');

 before=await state();await setUI('Amount','abc');assert.equal((await state()).data,before.data);
 await setUI('Amount','101');assert.equal((await state()).data,before.data);assert.equal((await state()).history,before.history);
 assert((await ev('document.querySelector(".multiEditError").textContent')).length>0);
 await setUI('Rate','4.125');assert.deepEqual(await values('Rate'),[4.125,4.125,1.5]);
 await setUI('Label','batch');assert.deepEqual(await values('Label'),['batch','batch','unchanged']);
 await setUI('Text','line one\nline two');
 assert.deepEqual((await values('Text')).slice(0,2),['line one\\nline two','line one\\nline two']);
 await setUI('Color','#123abc');assert.deepEqual((await values('Color')).slice(0,2),['#123ABC','#123ABC']);
 await setUI('Mode','C');assert.deepEqual(await values('Mode'),['C','C','A']);
 await setUI('Anchor','12,13');assert.deepEqual((await values('Anchor')).slice(0,2),[{cx:12,cy:13},{cx:12,cy:13}]);
 await ev(`document.querySelector(${JSON.stringify(value('Active'))}).click()`);
 assert.deepEqual((await values('Active')).slice(0,2),[true,true]);
 await ev(`document.querySelector(${JSON.stringify(value('Active'))}).click()`);
 assert.deepEqual((await values('Active')).slice(0,2),[false,false]);
 pass('Scalar number, text, color, enum, point and tri-state bool edits work; invalid input is atomic');

 await setUI('Steps','42',1);assert.deepEqual(await values('Steps'),[[1,42],[11,42,13],[21,22]]);
 await ev(`(()=>{const x=document.querySelector('[data-multi-field="${fields.Steps}"] .multiSize');x.value='4';x.dispatchEvent(new Event('change',{bubbles:true}));return true})()`);
 assert.deepEqual(await values('Steps'),[[1,42,0,0],[11,42,13,0],[21,22]]);
 before=await state();
 await ev(`(()=>{const x=document.querySelector('[data-multi-field="${fields.Steps}"] .multiSize');x.value='9';x.dispatchEvent(new Event('change',{bubbles:true}));return true})()`);
 assert.equal((await state()).data,before.data);assert.equal((await state()).history,before.history);
 pass('Array per-index edits preserve other differences; explicit resize retains individual values and obeys bounds');

 await ev(`document.querySelector('[data-multi-field="${fields.Nullable}"] .multiReset').click()`);
 assert.deepEqual((await values('Nullable')).slice(0,2),[null,null]);
 await setUI('Nullable','0');assert.deepEqual((await values('Nullable')).slice(0,2),[0,0]);
 before=await state();
 await ev(`(()=>{const x=document.querySelector(${JSON.stringify(value('Label'))});x.value='cancelled';x.dispatchEvent(new Event('input',{bubbles:true}));x.dispatchEvent(new KeyboardEvent('keydown',{bubbles:true,key:'Escape',keyCode:27}));return true})()`);
 assert.equal((await state()).data,before.data);
 pass('Reset/default, null versus zero, and Escape cancellation never apply a mixed placeholder as data');

 const target=await ev('multiFixture.ids[2]');
 await setUI('Link',target);let refs=await values('Link');assert(refs.slice(0,2).every(r=>r.entityIid===target));
 const reverse=await ev('__ldtk.Editor.ME.project.getEntityInstancesReferingTo(multiFixture.entity(2)).map(e=>e.iid).sort()');
 assert.deepEqual(reverse,(await ev('multiFixture.ids.slice(0,2)')).sort());
 assert.equal((await values('Link'))[2].entityIid,await ev('multiFixture.ids[0]'),'Unselected inbound reference was lost');
 before=await state();
 let blocked=await ev(`(()=>{try{multiFixture.edit('Link',multiFixture.ids[0]);return false}catch(e){return true}})()`);
 assert.equal(blocked,true);assert.equal((await state()).data,before.data);
 pass('Bulk references obey per-entity restrictions and preserve identity, unselected and reverse references');

 const persisted=(await state()).entities;
 await ev('multiFixture.reload()');await delay(200);await ev('multiFixture.editor()&&true');
 assert.deepEqual((await state()).entities,persisted);
 pass('Save/reload preserves the batch edits in the unchanged LDtk JSON format');

 ({fields}=await setup());await select();await ev('multiFixture.filters()');
 assert.equal(await ev(`document.querySelector('[data-multi-field="${fields.Label}"]')===null`),true);
 assert.deepEqual(await ev(`Array.from(document.querySelector(${JSON.stringify(value('Mode'))}).options).filter(o=>!o.disabled).map(o=>o.value)`),['C']);
 before=await state();blocked=await ev(`(()=>{try{multiFixture.edit('Mode','A');return false}catch(e){return true}})()`);
 assert(blocked);assert.equal((await state()).data,before.data);
 await setUI('Mode','C');assert.deepEqual((await values('Mode')).slice(0,2),['C','C']);
 pass('Conditional fields and enum choices use the intersection allowed by every selected entity');

 ({fields}=await setup());await select();await ev('multiFixture.stampFixture()');
 before=await state();
 await ev(`(()=>{const x=document.querySelector(${JSON.stringify(value('Active'))});if(!x.checked)x.click();return true})()`);
 assert.deepEqual(await ev('multiFixture.stampValues()'),[[1],[1]]);
 assert(await ev('multiFixture.undo()'));await delay(160);
 assert.deepEqual(await ev('multiFixture.stampValues()'),[[],[]]);
 assert.deepEqual((await values('Active')).slice(0,2),[false,false]);
 pass('Conditional tile stamps on both selected entities join the same Undo transaction');

 await ev('multiFixture.select([0,3])');assert.equal((await state()).panel,false);
 await ev('multiFixture.select([0])');
 assert.equal(await ev('!!document.querySelector(".entityInstanceEditor:not(.multiEntityInstanceEditor)")'),true);
 await select();await ev('multiFixture.editor().selectionTool.onKeyPress(46)');await delay(160);
 assert.equal((await state()).panel,false);await good();
 ({fields}=await setup());await select();
 await ev('multiFixture.editor().selectLevel(multiFixture.editor().project.getLevelAnywhere(multiFixture.second))');
 assert.equal(await ev('!!document.querySelector(".multiEntityInstanceEditor")'),false);
 await good();
 pass('Mixed types, single-selection fallback, Delete and level switching clean up the inspector safely');

 fs.writeFileSync(path.join(output,'results.json'),JSON.stringify({status:'passed',passed,platform:process.platform,electron:process.versions.electron},null,2));
 console.log('SUCCESS: '+passed.length+' multi-entity scenarios passed');
 clearTimeout(timer);app.exit(0);
}
require('../assets/main.js');
