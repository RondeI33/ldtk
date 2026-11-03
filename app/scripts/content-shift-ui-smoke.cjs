'use strict';
const {app}=require('electron');
const fs=require('node:fs'),os=require('node:os'),path=require('node:path'),assert=require('node:assert/strict'),http=require('node:http');
const root=path.resolve(__dirname,'..'),tmp=fs.mkdtempSync(path.join(os.tmpdir(),'smartive-content-shift-'));
const output=path.join(root,'test-results/content-shift');fs.mkdirSync(output,{recursive:true});
process.chdir(root);app.setPath('userData',tmp);
if(app.setAppPath)app.setAppPath(root);else app.getAppPath=()=>root;
process.env.LDTK_SMARTIVE_CONTROL_DIR=path.join(tmp,'control');
app.commandLine.appendSwitch('no-sandbox');
if(process.platform==='linux'){
 app.commandLine.appendSwitch('use-gl','angle');
 app.commandLine.appendSwitch('use-angle','swiftshader');
}
let running=false;const passed=[];const delay=ms=>new Promise(r=>setTimeout(r,ms));
const timer=setTimeout(()=>{console.error('FAIL: content shift smoke timed out');app.exit(1);},process.platform==='darwin'?180000:120000);
app.on('browser-window-created',(_,win)=>{
 win.webContents.on('did-finish-load',()=>{
  if(!win.webContents.getURL().endsWith('/assets/app.html')||running)return;
  running=true;
  test(win).catch(async err=>{
   console.error(err.stack||err);
   try{fs.writeFileSync(path.join(output,'failure.png'),(await win.webContents.capturePage()).toPNG());}catch(_){}
   fs.writeFileSync(path.join(output,'results.json'),JSON.stringify({status:'failed',passed,error:String(err.stack||err)},null,2));
   clearTimeout(timer);app.exit(1);
  });
 });
});
async function test(win){
 const ev=async code=>{
  const r=await win.webContents.executeJavaScript('(()=>{try{return {ok:true,value:('+code+')};}catch(e){return {ok:false,error:String(e&&e.stack||e)};}})()',true);
  if(!r||!r.ok)throw Error('Renderer expression failed: '+code+'\n'+String(r&&r.error));
  return r.value;
 };
 const poll=async (f,message)=>{
  for(let i=0;i<250;i++){const result=await f();if(result)return result;await delay(40);}
  throw Error(message);
 };
 const pass=message=>{passed.push(message);console.log('PASS:',message);};
 await poll(()=>ev('!!(globalThis.__ldtk && __ldtk.App.ME && document.querySelector("#page"))'),'Editor bootstrap unavailable');
 await delay(700);
 win.setSize(1400,900);win.show();win.focus();win.webContents.setBackgroundThrottling(false);
 await win.webContents.executeJavaScript(fs.readFileSync(path.join(__dirname,'content-shift-fixture.js'),'utf8'),true);
 const setup=async (id,external=false)=>{
  await ev('contentShiftFixture.setup('+JSON.stringify(path.join(tmp,id+'.ldtk'))+','+external+')');
  await delay(120);
 };
 const state=()=>ev('contentShiftFixture.state()');
 const resize=(left,top,w,h)=>ev('contentShiftFixture.resize('+[left,top,w,h].join(',')+')');
 const save=()=>ev('contentShiftFixture.save()');
 function expected(s,worldX,worldY,w,h,sx,sy,ax,ay,ex,ey){
  assert.deepEqual([s.worldX,s.worldY,s.width,s.height],[worldX,worldY,w,h]);
  assert.deepEqual(s.shift,[sx,sy]);
  assert.deepEqual(s.anchor,[ax,ay]);
  assert.deepEqual(s.entityWorld,[ex,ey]);
 }
 function noShiftInLdtk(saved){
  assert(!saved.project.includes('contentShift'),'LDtk project JSON leaked contentShift');
  for(const level of saved.externalFiles)assert(!level.includes('contentShift'),'External level leaked contentShift');
 }
 await setup('control-reload');
 await resize(-64,0,576,256);await save();
 // Start control test with a freshly opened editor; earlier fixture pages
 // may leave deferred UI tasks that obscure reload completion.
 await ev('contentShiftFixture.reopen()');await delay(180);
 // Do not bypass the actual control server: call POST /reload with its token.
 const ctrl=await poll(()=>{
  const dir=path.join(tmp,'control');
  if(!fs.existsSync(dir))return null;
  const f=fs.readdirSync(dir).find(name=>name.endsWith('.json'));
  return f?JSON.parse(fs.readFileSync(path.join(dir,f),'utf8')):null;
 },'Control endpoint did not start');
 async function request(route,method='GET'){
  return new Promise((resolve,reject)=>{
   const req=http.request({hostname:'127.0.0.1',port:ctrl.port,method,path:route,headers:{'X-LDtk-Token':ctrl.token,'Content-Type':'application/json'}},res=>{
    let body='';res.on('data',chunk=>body+=chunk);res.on('end',()=>{try{resolve({status:res.statusCode,body:JSON.parse(body)});}catch(err){reject(err);}});
   });
   req.on('error',reject);if(method==='POST')req.write('{}');req.end();
  });
 }
 const status=await request('/status');assert.equal(status.status,200);
 const response=await request('/reload','POST');
 assert.equal(response.status,200,JSON.stringify(response.body));
 assert.equal(response.body.reloaded,true,JSON.stringify(response.body));
 await delay(180);
 expected(await state(),936,500,576,256,-64,0,1000,500,1100,600);
 pass('12. Real authenticated POST /reload restores the sidecar shift');
 await setup('move');
 expected(await ev('contentShiftFixture.move(200,0)'),1200,500,512,256,0,0,1200,500,1300,600);
 pass('1. World drag moves anchor without creating a content shift');
 await setup('left');
 const baseline=(await save()).sidecar;
 const iid=(await state()).iid;
 expected(await resize(-64,0,576,256),936,500,576,256,-64,0,1000,500,1100,600);
 let saved=await save();noShiftInLdtk(saved);
 let side=JSON.parse(saved.sidecar);
 assert.deepEqual(Object.keys(side.levels),[iid]);
 assert.deepEqual(side.levels[iid],{contentShift:{x:-64,y:0}});
 console.log('SIDECAR CASE 2:',JSON.stringify({levels:side.levels},null,2));
 // Saving unchanged content must not rewrite or change the bytes on disk.
 const afterSave=saved.sidecar;assert.equal((await save()).sidecar,afterSave);
 pass('2. Left-edge expansion writes exactly the nonzero contentShift and preserves the entity world position');
 await setup('top');
 const prior=(await save()).sidecar;
 expected(await resize(0,32,512,224),1000,532,512,224,0,32,1000,500,1100,600);
 pass('3. Top-edge contraction preserves world entity and anchor');
 let undo=await ev('contentShiftFixture.undo()');
 assert(undo.done);expected(undo.state,1000,500,512,256,0,0,1000,500,1100,600);
 saved=await save();
 assert(!Object.hasOwn(JSON.parse(saved.sidecar),'levels'));
 assert.equal(saved.sidecar,prior,'Sidecar after undo was not byte-identical');
 pass('4. Resize undo restores content and sidecar bytes');
 let redo=await ev('contentShiftFixture.redo()');
 assert(redo.done);expected(redo.state,1000,532,512,224,0,32,1000,500,1100,600);
 pass('5. Redo restores content and shift');
 await setup('right-bottom');
 expected(await resize(0,0,640,320),1000,500,640,320,0,0,1000,500,1100,600);
 pass('6. Right/bottom expansion leaves shift zero');
 await setup('level-settings');
 expected(await ev('contentShiftFixture.settingsResize(768,384)'),1000,500,768,384,0,0,1000,500,1100,600);
 pass('7. Settings width/height does not create a content shift');
 await setup('sub-cell');
 expected(await resize(-8,0,520,256),992,500,520,256,-8,0,1000,500,1100,600);
 pass('8. Non-grid-aligned -8 px is accumulated exactly');
 await setup('move-after-left');
 await resize(-64,0,576,256);
 expected(await ev('contentShiftFixture.move(100,0)'),1036,500,576,256,-64,0,1100,500,1200,600);
 pass('9. Moving a previously resized level preserves the shift');
 await setup('duplicate');
 await resize(-64,0,576,256);
 const source=await state();
 const duplicate=await ev('contentShiftFixture.duplicate()');
 assert.notEqual(duplicate.iid,source.iid);
 assert.deepEqual(duplicate.shift,[-64,0]);
 assert.deepEqual(duplicate.anchor,[duplicate.worldX+64,duplicate.worldY]);
 saved=await save();side=JSON.parse(saved.sidecar);
 assert.deepEqual(Object.keys(side.levels).sort(),[source.iid,duplicate.iid].sort());
 assert.deepEqual(Object.keys(side.levels),Object.keys(side.levels).sort(),'Level IIDs are unsorted');
 pass('10. Duplicate copies shift and writes deterministic IID ordering');
 await setup('reopen');
 await resize(-64,0,576,256);await save();
 expected(await ev('contentShiftFixture.reopen()'),936,500,576,256,-64,0,1000,500,1100,600);
 pass('11. Save-close-reopen loads the shift from sidecar');
 await setup('external-level',true);
 await resize(-64,0,576,256);saved=await save();noShiftInLdtk(saved);
 assert(saved.externalFiles.length>0);
 await ev('contentShiftFixture.beginLoader()');
 await poll(()=>ev('!!(contentShiftFixture.loadedProject||contentShiftFixture.loadError)'),'External project loader did not finish');
 assert.equal(await ev('contentShiftFixture.loadError'),null,'External-level loader failed');
 const loaded=await ev('contentShiftFixture.loadedState()');
 assert.deepEqual(loaded.shift,[-64,0]);assert.deepEqual(loaded.anchor,[1000,500]);
 assert.deepEqual(loaded.entityWorld,[1100,600]);
 pass('External .ldtkl loader restores shift after replacing level headers');
 await setup('delete');
 await resize(-64,0,576,256);
 await ev('contentShiftFixture.delete()');
 saved=await save();assert(!Object.hasOwn(JSON.parse(saved.sidecar),'levels'));
 pass('Deleting the shifted level removes its sidecar entry on the next save');
 fs.writeFileSync(path.join(output,'results.json'),JSON.stringify({status:'passed',passed,platform:process.platform,electron:process.versions.electron},null,2));
 console.log('SUCCESS: '+passed.length+' contentShift regressions passed');
 clearTimeout(timer);app.exit(0);
}
require('../assets/main.js');
