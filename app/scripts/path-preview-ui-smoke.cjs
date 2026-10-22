'use strict';
const {app,Menu}=require('electron');
const fs=require('node:fs'),os=require('node:os'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),tmp=fs.mkdtempSync(path.join(os.tmpdir(),'smartive-path-preview-'));
const output=path.join(root,'test-results/path-preview');fs.mkdirSync(output,{recursive:true});
process.chdir(root);app.setPath('userData',tmp);app.setAppPath(root);
process.env.LDTK_SMARTIVE_CONTROL_DIR=path.join(tmp,'control');
app.commandLine.appendSwitch('no-sandbox');
if(process.platform==='linux'){app.commandLine.appendSwitch('use-gl','angle');app.commandLine.appendSwitch('use-angle','swiftshader');}
const passed=[],delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const timer=setTimeout(()=>{console.error('FAIL: path preview regression timed out');app.exit(1);},180000);
let running=false;
app.on('browser-window-created',(_,win)=>{
 win.webContents.on('did-finish-load',()=>{
  if(!win.webContents.getURL().endsWith('/assets/app.html')||running)return;
  running=true;run(win).catch(async error=>{
   console.error(error.stack||error);
   fs.writeFileSync(path.join(output,'results.json'),JSON.stringify({status:'failed',passed,error:String(error.stack||error)},null,2));
   try{fs.writeFileSync(path.join(output,'failure.png'),(await win.webContents.capturePage()).toPNG());}catch(_){}
   clearTimeout(timer);app.exit(1);
  });
 });
});
async function run(win){
 const ev=async code=>{
  const r=await win.webContents.executeJavaScript(`(()=>{try{return {ok:true,value:(${code})}}catch(e){return {ok:false,error:String(e&&e.stack||e)}}})()`,true);
  if(!r||!r.ok)throw Error(code+'\n'+String(r&&r.error));return r.value;
 };
 const until=async(code,message)=>{for(let i=0;i<200;i++){const value=await ev(code);if(value)return value;await delay(40)}throw Error(message);};
 await until('!!(globalThis.__ldtk && __ldtk.App.ME && document.querySelector("#page"))','Editor bootstrap unavailable');
 await delay(750);win.setSize(1600,1000);win.show();win.focus();win.webContents.focus();win.webContents.setBackgroundThrottling(false);Menu.setApplicationMenu(null);
 await win.webContents.executeJavaScript(fs.readFileSync(path.join(__dirname,'path-preview-fixture.js'),'utf8'),true);
 await ev(`(()=>{window.pathMouseDelivery={sequence:0,x:null,y:null};document.addEventListener('mousemove',event=>{
  pathMouseDelivery={sequence:pathMouseDelivery.sequence+1,x:event.clientX,y:event.clientY};
 },true);return true})()`);
 const call=(name,...args)=>ev(`pathPreviewFixture.${name}(${args.map(arg=>JSON.stringify(arg)).join(',')})`);
 const state=()=>call('stats');
 const frame=()=>win.webContents.executeJavaScript(`new Promise((resolve,reject)=>{
  const timer=setTimeout(()=>reject(Error('Editor frame did not complete')),8000),P=__ldtk.classes['dn.Process'];
  P.callAtTheBeginningOfNextFrame(()=>P.callAtTheEndOfCurrentFrame(()=>{clearTimeout(timer);resolve(true)}));
 })`,true);
 const settled=async()=>{await frame();await frame();return state();};
 const edit=async values=>{await call('edit',values);await settled();return (await state()).preview;};
 const pass=async message=>{
  assert.equal(await ev('__ldtk.App.ME.curPageProcess.__class__.__name__'),'page.Editor','Application entered a crash page');
  assert.equal((await state()).sentinel,1,'An unrelated layer changed');passed.push(message);console.log('PASS: '+message);
 };
 const screenshot=async name=>{await settled();fs.writeFileSync(path.join(output,name+'.png'),(await win.webContents.capturePage()).toPNG());};
 const nativeMove=async p=>{
  const sequence=await ev('pathMouseDelivery.sequence');win.webContents.sendInputEvent({type:'mouseMove',...p});
  await until(`pathMouseDelivery.sequence>${sequence} && pathMouseDelivery.x===${p.x} && pathMouseDelivery.y===${p.y}`,'Native mouse movement was not delivered');await frame();
 };
 const move=async(x,y)=>{
  const p=await call('screen',x,y);
  assert.equal(await ev(`document.elementFromPoint(${p.x},${p.y})?.id`),'webgl','Map target is covered by UI');
  await nativeMove({x:p.x+1,y:p.y});await nativeMove(p);return p;
 };
 const click=async p=>{
  await nativeMove(p);win.webContents.sendInputEvent({type:'mouseDown',...p,button:'left',clickCount:1});await frame();
  win.webContents.sendInputEvent({type:'mouseUp',...p,button:'left',clickCount:1});await settled();
 };
 const clickSelector=async selector=>{
  const p=await until(`(()=>{const el=document.querySelector(${JSON.stringify(selector)});if(!el)return null;el.scrollIntoView({block:'nearest'});const r=el.getBoundingClientRect(),x=Math.round(r.left+r.width/2),y=Math.round(r.top+r.height/2);return r.width>0&&r.height>0&&el.contains(document.elementFromPoint(x,y))?{x,y}:null})()`,'Inspector control unavailable: '+selector);
  await click(p);
 };
 const escape=async()=>{win.webContents.sendInputEvent({type:'keyDown',keyCode:'Escape'});win.webContents.sendInputEvent({type:'keyUp',keyCode:'Escape'});await settled();};
 const base={Path:[[16,6],[16,10],[6,10]],Mode:'Loop',BlockCount:4,BlockWidth:3,BlockHeight:1,Gap:2,EvenSpacing:false,StartOffset:0};
 const setup=await call('setup',path.join(tmp,'cargo-preview.ldtk'));
 await delay(400);await ev('__ldtk.classes["ui.Modal"].closeAll()');await settled();
 let s=await state(),p=s.preview;
 assert.equal(p.blocks,4);assert.equal(p.geometry.length,28);assert.equal(p.cue,'loop');assert.deepEqual(p.gapValues,[2,2,2,10]);
 assert.equal(s.stockGraphics,true);assert.equal(s.underFields,true);assert.equal(p.visible,true);assert.equal(p.color,0xe8a33d);
 await pass('Initial CargoLine draws four indexed blocks, correct gap labels and Loop closure beneath stock path/handles');await screenshot('loop');

 p=await edit({BlockCount:5,BlockWidth:2,BlockHeight:2,Gap:1});
 assert.equal(p.blocks,5);assert.equal(p.geometry.width,2);assert.equal(p.geometry.height,2);assert.equal(p.geometry.pitch,3);
 await pass('Count, width, height and Gap changes redraw through actual entity-field events');
 p=await edit({...base,BlockCount:7,EvenSpacing:true});
 assert.equal(p.blocks,7);assert.equal(p.geometry.pitch,4);assert.deepEqual(p.gapValues,[1,1,1,1,1,1,1]);
 await pass('EvenSpacing uses path length divided by block count and draws every Loop gap');
 p=await edit({...base,BlockCount:2,StartOffset:-3});
 assert.deepEqual(p.geometry.blocks.map(b=>b.distance),[25,2]);assert.deepEqual(p.gapValues,[20,2]);
 await pass('Negative start offsets wrap correctly and seam dimensions follow spatial block order');
 p=await edit({Path:[[26,6]],Mode:'Teleport',BlockCount:3,BlockWidth:2,BlockHeight:1,Gap:3,EvenSpacing:false,StartOffset:13});
 assert.equal(p.cue,'teleport');assert.equal(p.geometry.length,20);assert.equal(p.geometry.seamGap,8);assert.deepEqual(p.geometry.blocks.map(b=>b.distance),[13,18,3]);assert.deepEqual(p.gapValues,[8,3]);
 assert.ok(p.labels.includes('seam 8'));await pass('Teleport shows its return cue, seam value and offset-aware gap dimensions');await screenshot('teleport');
 p=await edit({Path:[[14,6]],BlockCount:4,BlockWidth:3,Gap:0,StartOffset:0});
 assert.equal(p.geometry.seamGap,-4);assert.equal(p.geometry.overlap,true);assert.equal(p.color,0xff3030);assert.match(p.warning,/seam -4/);assert.deepEqual(p.gapValues,[-2,-1,0]);
 await pass('Seam-overlap vector E turns all blocks red and reports the negative seam');await screenshot('overlap');
 p=await edit({Path:[[6,18]],Mode:'PingPong',BlockCount:3,BlockWidth:3,BlockHeight:2,Gap:1,StartOffset:0});
 assert.equal(p.geometry.extent,2);assert.equal(p.geometry.range,6);assert.equal(p.geometry.pitch,3);assert.equal(p.ghosts,3);assert.equal(p.cue,'pingpong');
 await pass('Vertical PingPong uses height for extent and draws the entire far-end ghost train');await screenshot('pingpong');
 p=await edit({Path:[[12,6]],Mode:'PingPong',BlockCount:3,BlockWidth:3,BlockHeight:1,Gap:1});
 assert.equal(p.geometry.range,-2);assert.equal(p.ghosts,0);assert.equal(p.geometry.isStatic,true);assert.match(p.warning,/does not fit/);
 await pass('A PingPong train that does not fit displays its warning and no misleading moving ghost');
 p=await edit({Path:[],BlockCount:1});assert.equal(p.blocks,1);assert.equal(p.gaps,0);assert.equal(p.geometry.length,0);assert.equal(p.geometry.isStatic,true);
 await pass('Empty paths and one-block lines stay well-defined and omit gap dimensions');

 await edit(base);await call('visibility',false);s=await settled();assert.equal(s.preview.visible,false);
 await call('visibility',true);s=await settled();assert.equal(s.preview.visible,true);
 await pass('Hiding and restoring the entity layer hides and restores the whole preview');
 const beforeMove=(await state()).preview.geometry.vertices;await call('moveEntity',16,0);p=(await settled()).preview;
 assert.equal(p.geometry.vertices[0].x,beforeMove[0].x+1);assert.deepEqual(p.geometry.vertices[1],beforeMove[1]);
 await call('moveEntity',-16,0);await settled();await pass('Moving the entity redraws V0 without moving unselected path points');

 const rt=await call('roundtrip');assert.equal(rt.before,rt.withPreview);assert.equal(rt.withPreview,rt.withoutPreview);
 const key=String(setup.entityDef);assert.deepEqual(rt.rawAfter.gameMetadata,rt.rawBefore.gameMetadata);assert.deepEqual(rt.rawAfter.entities[key].pathPreview,rt.rawBefore.entities[key].pathPreview);
 assert.deepEqual(rt.rawAfter.entities[key].gameOnly,rt.rawBefore.entities[key].gameOnly);assert.deepEqual(rt.rawAfter.entities[key].fields[setup.fields.Path].foreignField,{keep:true});
 assert.deepEqual(rt.rawAfter.entities['87654321'],rt.rawBefore.entities['87654321']);
 assert.equal(JSON.parse(rt.before).jsonVersion,'1.5.3');
 await pass('Repeated saves preserve exact pathPreview and unknown sidecar metadata while project JSON stays byte-identical');
 const defaults=await call('missingDefaults');assert.deepEqual(defaults.after,defaults.before);assert.equal(defaults.count,4);
 await pass('Preview reads field defaults without inserting missing serialized FieldInstances');
 await call('config',{startOffset:{fieldUid:setup.fields.Speed,fieldIdentifier:'StartOffset'}});p=(await settled()).preview;
 assert.equal(p.geometry.blocks[0].distance,2);
 await call('config',{startOffset:{fieldUid:999999,fieldIdentifier:'StartOffset'}});p=(await settled()).preview;assert.equal(p.geometry.blocks[0].distance,0);
 await call('config',{startOffset:{fieldUid:setup.fields.StartOffset,fieldIdentifier:'StartOffset'}});await settled();
 await pass('Existing field UID wins a conflicting identifier; missing UIDs fall back to identifiers');
 await call('config',{mode:{fieldUid:setup.fields.Mode,fieldIdentifier:'Mode',loopValue:'Circuit',teleportValue:'Warp',pingPongValue:'Bounce'}});
 p=await edit({Mode:'Warp'});assert.equal(p.cue,'teleport');p=await edit({Mode:'Bounce'});assert.ok(['pingpong','does not fit'].includes(p.cue));
 await call('config',{mode:{fieldUid:setup.fields.Mode,fieldIdentifier:'Mode',loopValue:'Loop',teleportValue:'Teleport',pingPongValue:'PingPong'}});await edit(base);
 await ev('(()=>{const f=pathPreviewFixture;f.entity().get_def().set_identifier("GenericMovingBlocks");f.editor().ge.emit(__ldtk.enums.GlobalEvent.EntityDefChanged);return true})()');
 p=(await settled()).preview;assert.equal(p.blocks,4);await pass('Custom mode values and a renamed entity use the same generic sidecar-driven preview');
 const remapped=await call('remapSidecar');await settled();assert.ok(remapped.entities[key]);assert.equal(remapped.entities['900001'],undefined);
 assert.ok(remapped.entities[key].fields[setup.fields.Path]);assert.equal(remapped.entities[key].fields['900002'],undefined);assert.equal((await state()).preview.blocks,4);
 await pass('Entity/field key remapping retains unknown data and removes stale old UID entries');

 // Native input must hit the existing point handle while the preview is visible.
 await call('select','points',[1]);await settled();const nativeBefore=await state();
 const start=await move(264,168),end=await call('screen',296,184);
 win.webContents.sendInputEvent({type:'mouseDown',...start,button:'left',clickCount:1});
 await until('pathPreviewFixture.stats().selectionRunning','Native point drag did not start');await nativeMove(end);
 await until('pathPreviewFixture.stats().moveStarted','Native point drag did not create a ghost');s=await settled();
 assert.deepEqual(s.values,nativeBefore.values,'Native drag mutated the model before drop');assert.equal(s.suppressed,true);
 assert.equal(s.ghostPreviews.length,1);assert.equal(s.ghostPreviews[0].blocks,4);
 assert.deepEqual(s.ghostPreviews[0].geometry.vertices[2],{x:18.5,y:11.5});await screenshot('point-drag');
 win.webContents.sendInputEvent({type:'mouseUp',...end,button:'left',clickCount:1});
 await until('!pathPreviewFixture.stats().selectionRunning','Native point drop did not finish');s=await settled();
 const expected=JSON.parse(JSON.stringify(nativeBefore.values));expected.fields.Path[1]={cx:18,cy:11};assert.deepEqual(s.values,expected);assert.equal(s.suppressed,false);assert.equal(s.ghostPreviews.length,0);
 await pass('Native point drag previews blocks continuously, keeps handles interactive, and commits only the moved point');
 assert.equal(await call('undo'),true);await settled();assert.deepEqual((await state()).values,nativeBefore.values);
 assert.equal(await call('redo'),true);await settled();assert.deepEqual((await state()).values,expected);
 await pass('One Undo/Redo restores both point geometry and the live preview after native dragging');

 await edit(base);let before=(await state()).values;
 await call('beginGroup','points',[0],16,16,false);s=await settled();assert.deepEqual(s.values,before);assert.equal(s.suppressed,true);
 await call('endGroup','cancel');s=await settled();assert.deepEqual(s.values,before);assert.equal(s.suppressed,false);assert.equal(s.ghostPreviews.length,0);
 await call('beginGroup','points',[0],16,0,false);await call('endGroup','clear');s=await settled();assert.deepEqual(s.values,before);assert.equal(s.suppressed,false);
 const disposed=await call('disposeGroup');assert.equal(disposed.suppressed,true);assert.equal(disposed.after,false);
 await pass('Cancelling, clearing or disposing a point drag restores the preview and leaves the path unchanged');
 await call('beginGroup','points',[0,1],16,0,true);s=await settled();assert.deepEqual(s.values,before);assert.equal(s.suppressed,true);
 assert.equal(s.ghostPreviews[0].geometry.vertices.length,7);await call('endGroup','commit');s=await settled();
 assert.deepEqual(s.values.fields.Path,[{cx:17,cy:6},{cx:16,cy:6},{cx:17,cy:10},{cx:16,cy:10},{cx:6,cy:10}]);assert.equal(s.values.x,before.x);assert.equal(s.values.y,before.y);
 await pass('Copying multiple standalone path points previews and inserts copies without corrupting later indices');
 await edit(base);before=(await state()).values;
 await call('beginGroup','entity',[],16,0,true);s=await settled();assert.equal(s.suppressed,false);assert.equal(s.preview.visible,true);
 assert.equal(s.ghostPreviews[0].geometry.vertices[0].x,7.5);assert.equal(s.ghostPreviews[0].geometry.vertices[1].x,16.5);await call('endGroup','cancel');
 await call('beginGroup','both',[0,1,2],16,0,false);s=await settled();assert.equal(s.ghostPreviews[0].geometry.vertices[0].x,7.5);assert.equal(s.ghostPreviews[0].geometry.vertices[1].x,17.5);
 await call('endGroup','cancel');s=await settled();assert.deepEqual(s.values,before);assert.equal(s.suppressed,false);
 await pass('Entity-copy and combined entity/path drags preview exactly the selected elements and restore cleanly');
 await call('visibility',false);await call('beginGroup','points',[0],16,0,false);s=await settled();assert.equal(s.ghostPreviews.length,0);
 await call('endGroup','cancel');await call('visibility',true);s=await settled();assert.equal(s.suppressed,false);
 await pass('Hidden layers cannot leak path previews through a selection ghost');

 await call('select','entity');await settled();
 await clickSelector(`.entityInstanceEditor [defuid="${setup.fields.Path}"] button.add`);
 await until('pathPreviewFixture.stats().picker','Native inspector button did not activate the Path picker');
 const pathBefore=(await state()).values.fields.Path;await click(await move(360,232));
 await until(`pathPreviewFixture.values().fields.Path.length===${pathBefore.length+1}`,'Native point addition did not update the path');
 p=(await settled()).preview;assert.equal(p.blocks,4);assert.ok(p.geometry.length>28);await escape();
 await pass('Adding a Path point through the native inspector and canvas redraws blocks immediately');
 const saved=await state();await call('reload');await delay(250);await settled();s=await state();assert.deepEqual(s.values,saved.values);assert.deepEqual(s.preview.geometry,saved.preview.geometry);
 await pass('Actual JSON save/reload preserves the complete path and recreates the same editor-only preview');
 await screenshot('success');
 fs.writeFileSync(path.join(output,'results.json'),JSON.stringify({status:'passed',passed,platform:process.platform,electron:process.versions.electron},null,2));
 console.log('SUCCESS: '+passed.length+' path-preview scenarios passed');clearTimeout(timer);app.exit(0);
}
require('../assets/main.js');
