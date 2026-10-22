'use strict';
const {app}=require('electron');
const fs=require('node:fs'),os=require('node:os'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),tmp=fs.mkdtempSync(path.join(os.tmpdir(),'smartive-entity-chain-'));
const output=path.join(root,'test-results/entity-chain');fs.mkdirSync(output,{recursive:true});
process.chdir(root);app.setPath('userData',tmp);if(app.setAppPath)app.setAppPath(root);else app.getAppPath=()=>root;
process.env.LDTK_SMARTIVE_CONTROL_DIR=path.join(tmp,'control');
app.commandLine.appendSwitch('no-sandbox');
if(process.platform==='linux'){
 app.commandLine.appendSwitch('use-gl','angle');app.commandLine.appendSwitch('use-angle','swiftshader');
}
const timer=setTimeout(()=>{console.error('FAIL: entity chain regression timed out');app.exit(1);},process.platform==='darwin'?240000:120000);
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
  if(i===199)throw Error('Editor bootstrap unavailable');await delay(40);
 }
 await delay(800);win.setSize(1400,900);win.show();win.focus();win.webContents.setBackgroundThrottling(false);
 await win.webContents.executeJavaScript(fs.readFileSync(path.join(__dirname,'entity-chain-fixture.js'),'utf8'),true);
 const call=(name,...args)=>ev(`entityChainFixture.${name}(${args.map(arg=>JSON.stringify(arg)).join(',')})`);
 let setupCount=0;
 const setup=async options=>{
  await call('setup',path.join(tmp,`chain-${++setupCount}.ldtk`),options||{});await delay(160);
  await ev('entityChainFixture.editor() && true');return call('state');
 };
 const entities=state=>state.levels.flatMap(level=>level.entities);
 const entity=(state,i)=>entities(state).find(ei=>ei.iid===state.ids[i]);
 const history=state=>state.timelines[state.active];
 const pass=async message=>{
  assert.equal(await ev('__ldtk.App.ME.curPageProcess.__class__.__name__'),'page.Editor','Application entered a crash page');
  const state=await call('state');assert(state.levels.every(level=>level.sentinel===1),'An unrelated layer changed');
  passed.push(message);console.log('PASS: '+message);
 };
 const undoRedo=async (before,after)=>{
  assert.equal(await call('undo'),true);await delay(100);assert.deepEqual((await call('state')).levels,before.levels);
  assert.equal(await call('redo'),true);await delay(100);assert.deepEqual((await call('state')).levels,after.levels);
 };

 await setup();await call('place',64,64);await call('place',192,64);let after=await call('place',320,64);
 assert.equal(entity(after,0).refs.To,after.ids[1]);assert.equal(entity(after,1).refs.From,after.ids[0]);
 assert.equal(entity(after,1).refs.To,after.ids[2]);assert.equal(entity(after,2).refs.From,after.ids[1]);
 assert.equal(entity(after,0).refs.From,null);assert.equal(entity(after,2).refs.To,null);
 assert(after.events.includes(after.ids[1])&&after.events.includes(after.ids[2]),'Both changed entities must emit EntityInstanceChanged');
 const fullyLinked=after;
 assert.equal(await call('undo'),true);await delay(100);let undone=await call('state');
 assert.equal(entity(undone,1).refs.To,null);
 if(entity(undone,2))assert.equal(entity(undone,2).refs.From,null);
 assert.equal(entity(undone,0).refs.To,after.ids[1]);assert.equal(entity(undone,1).refs.From,after.ids[0]);
 assert.equal(await call('redo'),true);await delay(100);assert.deepEqual((await call('state')).levels,fullyLinked.levels);
 await pass('Three actual VeinCable placements build To/From links; one Undo/Redo restores both sides and emits both entity events');

 const written=await call('save');
 assert.deepEqual(written.entities['3873'].autoChainBackRefs,[{chainField:'To',backField:'From'}]);
 assert.equal(written.entities['3873'].appearanceOverrides[0].color,'#a1b2c3');
 assert.equal(written.entities['3873'].appearanceOverrides[0].whenFieldIdentifier,'AppearanceEnabled');
 assert(!await ev('JSON.stringify(entityChainFixture.editor().project.toJson()).includes("autoChainBackRefs")'));
 const savedLevels=(await call('state')).levels;await call('reload');await delay(180);
 assert.deepEqual((await call('state')).levels,savedLevels);
 await call('place',448,64);after=await call('place',64,160);
 assert.equal(entity(after,3).refs.To,after.ids[4]);assert.equal(entity(after,4).refs.From,after.ids[3]);
 await pass('Sidecar and project save/reload preserve the mapping, existing appearance overrides and links without changing stock JSON');

 await setup({seeds:[{},{}]});let before=await call('state');after=await call('click',1,0);
 assert.equal(entity(after,0).refs.To,after.ids[1]);assert.equal(entity(after,1).refs.From,after.ids[0]);
 assert.equal(history(after),history(before)+1);await undoRedo(before,after);
 await pass('Clicking an existing entity stores the forward/back pair in one undoable history state');

 await setup({seeds:[{},{layer:1}]});before=await call('state');after=await call('click',1,0);
 assert.equal(entity(after,0).refs.To,after.ids[1]);assert.equal(entity(after,1).refs.From,after.ids[0]);
 assert.equal(history(after),history(before)+1);await undoRedo(before,after);
 await pass('Existing targets on a different entity layer are restored together with the source by one Undo/Redo');

 await setup({config:null});await call('place',64,64);after=await call('place',192,64);
 assert.equal(entity(after,0).refs.To,after.ids[1]);assert.equal(entity(after,1).refs.From,null);
 await setup({config:null});await call('place',64,64,'patrol');await call('place',192,64,'patrol');after=await call('place',320,64,'patrol');
 assert.equal(entity(after,0).refs.Next,after.ids[1]);assert.equal(entity(after,1).refs.Next,after.ids[2]);
 await pass('Unconfigured VeinCable fields and PatrolPoint.Next retain their original one-way auto-chain behavior');

 await setup({seeds:[{},{},{}]});await call('seedRef',1,'From',2);before=await call('checkpoint');
 let logs=await call('logs');after=await call('click',1,0);
 assert.equal(entity(after,0).refs.To,after.ids[1]);assert.equal(entity(after,1).refs.From,after.ids[2]);
 assert((await call('logs')).slice(logs.length).some(message=>/From|back/i.test(message)),'Occupied reverse reference must be logged');
 await undoRedo(before,after);
 await pass('An occupied scalar back reference is preserved and logged while the forward reference remains undoable');

 await setup({seeds:[{},{}]});await call('seedRef',1,'From',0);before=await call('checkpoint');after=await call('click',1,0);
 assert.equal(entity(after,1).refs.From,after.ids[0]);assert.equal(entity(after,0).refs.To,after.ids[1]);await undoRedo(before,after);
 await pass('An existing back reference to the same source remains intact');

 for(const options of [{backType:'missing'},{backType:'int'},{reject:true}]){
  await setup({...options,seeds:[{},{}]});before=await call('state');after=await call('click',1,0);
  assert.equal(entity(after,0).refs.To,after.ids[1]);
  assert.deepEqual(entity(after,1).refs,entity(before,1).refs);
  await undoRedo(before,after);
 }
 await pass('Missing, non-EntityRef and disallowed reverse fields skip only the back link');

 await setup({array:true,seeds:[{},{},{}]});await call('seedRef',1,'From',2);before=await call('checkpoint');after=await call('click',1,0);
 assert.deepEqual(entity(after,1).refs.From,[after.ids[2],after.ids[0]]);await undoRedo(before,after);
 after=await call('click',1,0);assert.deepEqual(entity(after,1).refs.From,[after.ids[2],after.ids[0]]);
 await pass('Array back references append after existing values, avoid duplicates and undo/redo without deleting earlier references');

 await setup({array:true,max:1,seeds:[{},{},{}]});await call('seedRef',1,'From',2);before=await call('checkpoint');logs=await call('logs');after=await call('click',1,0);
 assert.equal(entity(after,0).refs.To,after.ids[1]);assert.deepEqual(entity(after,1).refs.From,[after.ids[2]]);
 assert((await call('logs')).slice(logs.length).some(message=>/From|back/i.test(message)));await undoRedo(before,after);
 await pass('A full bounded back-reference array is preserved and logged');

 await setup({chainArray:true,seeds:[{},{},{}]});await call('click',1,0);after=await call('click',2,0);
 assert.deepEqual(entity(after,0).refs.To,[after.ids[1],after.ids[2]]);
 assert.equal(entity(after,1).refs.From,after.ids[0]);assert.equal(entity(after,2).refs.From,after.ids[0]);
 await pass('Array forward fields continue appending and initialize the selected target back reference');

 await setup({seeds:[{},{},{}]});await call('click',1,0);await call('click',0,1);after=await call('click',2,1);
 assert.equal(entity(after,1).refs.To,after.ids[2]);assert.equal(entity(after,1).refs.From,after.ids[0]);
 assert((await call('referrers',0)).includes(after.ids[1]),'Remaining From reference must stay in the reverse-reference cache');
 await pass('Retargeting To preserves another From reference to the old target in the project reference cache');

 await setup({seeds:[{},{level:1}]});await call('activate',1);before=await call('state');after=await call('click',1,0);
 assert.equal(entity(after,0).refs.To,after.ids[1]);assert.equal(entity(after,1).refs.From,after.ids[0]);
 assert.deepEqual(after.timelines,before.timelines);assert(after.events.includes(after.ids[0])&&after.events.includes(after.ids[1]));
 const crossState=after.levels;await call('save');await call('reload');await delay(180);assert.deepEqual((await call('state')).levels,crossState);
 await pass('Cross-level links update both entities and survive save/reload without adding cross-level history');

 await setup({localBack:true,seeds:[{},{level:1}]});await call('activate',1);before=await call('state');after=await call('click',1,0);
 assert.equal(entity(after,0).refs.To,after.ids[1]);assert.equal(entity(after,1).refs.From,null);assert.deepEqual(after.timelines,before.timelines);
 await pass('Back-field level restrictions use the real source level and reject forbidden cross-level back links');

 await setup({seeds:[{},{def:'other'}]});before=await call('state');after=await call('click',1,0);
 assert.deepEqual(after.levels,before.levels);assert.deepEqual(after.timelines,before.timelines);assert.deepEqual(after.events,[]);
 await pass('A rejected forward link never creates a reverse reference or a history entry');

 await setup({symmetricBack:true,seeds:[{},{},{}]});await call('seedRef',0,'From',2);before=await call('checkpoint');logs=await call('logs');after=await call('click',1,0);
 assert.equal(entity(after,0).refs.To,after.ids[1]);assert.equal(entity(after,0).refs.From,after.ids[2]);
 assert.equal(entity(after,2).refs.From,after.ids[0]);assert.equal(entity(after,1).refs.From,null);
 assert((await call('logs')).slice(logs.length).some(message=>/From|back/i.test(message)));await undoRedo(before,after);
 await pass('Symmetric reverse fields do not overwrite an occupied counterpart or damage its third-entity link');

 await setup({config:[null,{},'invalid',{chainField:7,backField:'From'},{chainField:'To',backField:'From'}],seeds:[{},{}]});after=await call('click',1,0);
 assert.equal(entity(after,1).refs.From,after.ids[0]);
 await call('reloadConfig',{format:1,entities:{'3873':{identifier:'VeinCable',appearanceOverrides:[]}}});assert.deepEqual(await call('runtimeConfig'),[]);
 await call('reloadConfig',{format:1,entities:{'3873':{autoChainBackRefs:[{chainField:'To',backField:'From'}]}}});
 assert.equal((await call('runtimeConfig')).length,1);
 await call('reloadConfig',null);assert.deepEqual(await call('runtimeConfig'),[]);
 await pass('Malformed rules are ignored safely and removing the rule or sidecar clears stale runtime configuration');

 fs.writeFileSync(path.join(output,'results.json'),JSON.stringify({status:'passed',passed,platform:process.platform,electron:process.versions.electron},null,2));
 fs.writeFileSync(path.join(output,'success.png'),(await win.webContents.capturePage()).toPNG());
 console.log('SUCCESS: '+passed.length+' entity-chain scenarios passed');clearTimeout(timer);app.exit(0);
}
require('../assets/main.js');
