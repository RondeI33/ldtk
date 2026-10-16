'use strict';
const {app}=require('electron');
const fs=require('node:fs'),os=require('node:os'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),tmp=fs.mkdtempSync(path.join(os.tmpdir(),'smartive-entity-history-'));
const output=path.join(root,'test-results/entity-history');fs.mkdirSync(output,{recursive:true});
process.chdir(root);app.setPath('userData',tmp);if(app.setAppPath)app.setAppPath(root);else app.getAppPath=()=>root;
process.env.LDTK_SMARTIVE_CONTROL_DIR=path.join(tmp,'control');
app.commandLine.appendSwitch('no-sandbox');app.commandLine.appendSwitch('use-gl','angle');app.commandLine.appendSwitch('use-angle','swiftshader');
const timer=setTimeout(()=>{console.error('FAIL: entity history regression timed out');app.exit(1);},90000);
let running=false;const passed=[],delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
app.on('browser-window-created',(_,win)=>{
 win.webContents.on('did-finish-load',()=>{
  if(!win.webContents.getURL().endsWith('/assets/app.html')||running)return;
  running=true;run(win).catch(async error=>{
   console.error(error.stack||error);
   try{fs.writeFileSync(path.join(output,'failure.png'),(await win.webContents.capturePage()).toPNG());}catch(_){}
   fs.writeFileSync(path.join(output,'results.json'),JSON.stringify({status:'failed',passed,error:String(error.stack||error)},null,2));
   clearTimeout(timer);app.exit(1);
  });
 });
});
async function run(win){
 const ev=async code=>{
  const result=await win.webContents.executeJavaScript(`(()=>{try{return {ok:true,value:(${code})};}catch(e){return {ok:false,error:String(e&&e.stack||e)};}})()`,true);
  if(!result||!result.ok)throw Error('Renderer expression failed: '+code+'\n'+String(result&&result.error));
  return result.value;
 };
 for(let i=0;i<200;i++){
  if(await ev('!!(globalThis.__ldtk && __ldtk.App.ME && document.querySelector("#page"))'))break;
  if(i===199)throw Error('Editor bootstrap unavailable');
  await delay(40);
 }
 await delay(800);
 win.setSize(1400,900);win.show();win.focus();win.webContents.setBackgroundThrottling(false);
 await win.webContents.executeJavaScript(fs.readFileSync(path.join(__dirname,'entity-history-fixture.js'),'utf8'),true);
 const setup=async()=>{
  await ev(`entityHistoryFixture.setup(${JSON.stringify(path.join(tmp,'entities.ldtk'))})`);
  await delay(160);
  await ev('entityHistoryFixture.editor() && true');
 };
 const pass=async message=>{
  assert.equal(await ev('__ldtk.App.ME.curPageProcess.__class__.__name__'),'page.Editor','Application entered a crash page');
  passed.push(message);console.log('PASS: '+message);
 };
 await setup();
 const {a,b}=await ev('({a:entityHistoryFixture.a,b:entityHistoryFixture.b})');
 await ev('entityHistoryFixture.drag()');await ev('entityHistoryFixture.switch(entityHistoryFixture.b)');
 let before=await ev('entityHistoryFixture.state()'),after=await ev('entityHistoryFixture.click(entityHistoryFixture.b)');
 assert.equal(after.active,b);assert.deepEqual(after.levels,before.levels);
 await pass('Drag in A, switch to B and click an entity: no stale level switch or data mutation');
 for(let n=0;n<40;n++){
  const target=n%2===0?a:b;
  await ev(`entityHistoryFixture.switch(${target})`);before=await ev('entityHistoryFixture.state()');
  await ev(`entityHistoryFixture.click(${target})`);after=await ev('entityHistoryFixture.idleStop()');
  assert.equal(after.active,target);assert.deepEqual(after.timelines,before.timelines);assert.deepEqual(after.levels,before.levels);
 }
 await pass('40 alternating level selections, entity clicks and repeated stops preserve history and content');
 await ev(`entityHistoryFixture.switch(${b})`);await ev(`entityHistoryFixture.click(${b})`);await ev(`entityHistoryFixture.edit(${b},23)`);
 assert.equal(await ev('entityHistoryFixture.undo()'),true);await delay(160);
 before=await ev('entityHistoryFixture.state()');assert.equal(before.levels[1].entities[0].value,7);
 assert.deepEqual(await ev('entityHistoryFixture.emptySave()'),before);
 assert.equal(await ev('entityHistoryFixture.redo()'),true);await delay(160);
 after=await ev('entityHistoryFixture.state()');assert.equal(after.active,b);assert.equal(after.levels[1].entities[0].value,23);
 assert(after.levels.every(level=>level.sentinel===1));
 await pass('Field editor Undo/Redo, unchanged layers and empty/null history writes preserve the redo tail');
 for(let i=0;i<85;i++){
  await ev(`entityHistoryFixture.click(${b})`);await ev(`entityHistoryFixture.edit(${b},${100+i})`);
 }
 assert.equal(await ev('entityHistoryFixture.undo()'),true);await delay(160);
 assert.equal((await ev('entityHistoryFixture.state()')).levels[1].entities[0].value,183);
 assert.equal(await ev('entityHistoryFixture.redo()'),true);await delay(160);
 assert.equal((await ev('entityHistoryFixture.state()')).levels[1].entities[0].value,184);
 await pass('85 field edits cross history capacity repeatedly with correct Undo/Redo');
 assert.deepEqual(await ev('entityHistoryFixture.newHistory()'),{index:0,undo:false,full:true,layers:2,expected:2});
 await pass('Missing initial history produces a complete checkpoint without a layerJsons crash or invented undo');
 await setup();before=await ev('entityHistoryFixture.state()');after=await ev('entityHistoryFixture.cancel()');
 assert.deepEqual(after.levels,before.levels);assert.equal(after.active,a);
 await pass('Cancelled live entity move restores its source without switching levels');
 await setup();const links=await ev('entityHistoryFixture.link()');after=await ev('entityHistoryFixture.drag(entityHistoryFixture.b)');
 assert.equal(after.active,b);assert.equal(after.levels[0].entities.length,0);assert.equal(after.levels[1].entities.length,2);
 assert(after.levels[1].entities.every(entity=>entity.owner===b));
 const linkState=await ev('entityHistoryFixture.linkState()');assert.equal(linkState.find(entity=>entity.iid===links.source).ref,links.target);
 await pass('Actual cross-level drop still follows its destination and preserves identity, ownership and references');
 before=await ev('entityHistoryFixture.state()');await ev('entityHistoryFixture.reload()');await delay(160);after=await ev('entityHistoryFixture.state()');
 assert.deepEqual(after.levels,before.levels);assert.deepEqual(await ev('entityHistoryFixture.linkState()'),linkState);
 await pass('Save and reload preserve moved entities, fields, references and untouched layers');
 fs.writeFileSync(path.join(output,'results.json'),JSON.stringify({status:'passed',passed,navigationCycles:40,fieldEdits:85,platform:process.platform,electron:process.versions.electron},null,2));
 fs.writeFileSync(path.join(output,'success.png'),(await win.webContents.capturePage()).toPNG());
 console.log('SUCCESS: '+passed.length+' entity/history scenarios passed');clearTimeout(timer);app.exit(0);
}
require('../assets/main.js');
