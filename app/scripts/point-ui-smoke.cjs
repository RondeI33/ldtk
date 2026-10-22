'use strict';
const {app,Menu}=require('electron');
const fs=require('node:fs'),os=require('node:os'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),tmp=fs.mkdtempSync(path.join(os.tmpdir(),'smartive-points-'));
const output=path.join(root,'test-results/points');fs.mkdirSync(output,{recursive:true});
process.chdir(root);app.setPath('userData',tmp);app.setAppPath(root);
process.env.LDTK_SMARTIVE_CONTROL_DIR=path.join(tmp,'control');
app.commandLine.appendSwitch('no-sandbox');
if(process.platform==='linux'){app.commandLine.appendSwitch('use-gl','angle');app.commandLine.appendSwitch('use-angle','swiftshader');}
const passed=[],delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const timer=setTimeout(()=>{console.error('FAIL: point regression timed out');app.exit(1);},process.platform==='darwin'?360000:180000);
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
 await win.webContents.executeJavaScript(fs.readFileSync(path.join(__dirname,'point-fixture.js'),'utf8'),true);
 await ev(`(()=>{window.pointMouseDelivery={sequence:0,x:null,y:null};document.addEventListener('mousemove',event=>{
  pointMouseDelivery={sequence:pointMouseDelivery.sequence+1,x:event.clientX,y:event.clientY};
 },true);return true})()`);
 const call=(name,...args)=>ev(`pointFixture.${name}(${args.map(arg=>JSON.stringify(arg)).join(',')})`);
 const state=()=>call('state');
 const frame=()=>win.webContents.executeJavaScript(`new Promise((resolve,reject)=>{
  const timer=setTimeout(()=>reject(Error('Editor frame did not complete')),8000),P=__ldtk.classes['dn.Process'];
  P.callAtTheBeginningOfNextFrame(()=>P.callAtTheEndOfCurrentFrame(()=>{clearTimeout(timer);resolve(true)}));
 })`,true);
 const nativeMove=async p=>{
  const sequence=await ev('pointMouseDelivery.sequence');
  win.webContents.sendInputEvent({type:'mouseMove',...p});
  await until(`pointMouseDelivery.sequence>${sequence} && pointMouseDelivery.x===${p.x} && pointMouseDelivery.y===${p.y}`,
   'Native mouse movement was not delivered');
  // Chromium delivers DOM input asynchronously, then Heaps consumes its event
  // queue during an editor frame. Receiving DOM input alone is not a hover update.
  await frame();
 };
 let fields,ids,setupCount=0;
 const setup=async options=>{
  ({fields,ids}=await call('setup',path.join(tmp,`points-${++setupCount}.ldtk`),options||{}));
  await delay(400);await ev('pointFixture.editor()&&true');await ev('__ldtk.classes["ui.Modal"].closeAll()');await delay(100);
 };
 const pass=async message=>{
  assert.equal(await ev('__ldtk.App.ME.curPageProcess.__class__.__name__'),'page.Editor','Application entered a crash page');
  assert.equal((await state()).sentinel,1,'An unrelated layer changed');passed.push(message);console.log('PASS: '+message);
 };
 const move=async(x,y)=>{
  const p=await call('screen',x,y);
  assert.equal(await ev(`document.elementFromPoint(${p.x},${p.y})?.id`),'webgl','Map target is covered by UI');
  // Enter the canvas, then deliver a distinct in-canvas movement. Await each
  // event and its frame instead of caching a cursor before CI has processed it.
  await nativeMove({x:p.x+1,y:p.y});
  await nativeMove(p);
  if(await ev('pointFixture.state().picker')){
   try{
    await until(`(()=>{const t=pointFixture.editor().specialTool;return t&&t.lastMouse&&t.lastMouse.pageX===${p.x}&&t.lastMouse.pageY===${p.y}})()`,
     'Point picker did not receive the native target movement');
   }catch(error){throw Error(error.message+'; '+JSON.stringify({target:p,editor:await call('debug')}));}
  }
  if(process.env.LDTK_POINT_DIAGNOSTICS)console.log('POINT MOVE settled',await call('debug'));
  return p;
 };
 const clickAt=async(p,button='left')=>{
  win.webContents.sendInputEvent({type:'mouseMove',...p});await delay(40);
  win.webContents.sendInputEvent({type:'mouseDown',...p,button,clickCount:1});await delay(60);
  win.webContents.sendInputEvent({type:'mouseUp',...p,button,clickCount:1});await delay(140);
 };
 const clickSelector=async selector=>{
  const p=await until(`(()=>{const el=document.querySelector(${JSON.stringify(selector)});if(!el)return null;el.scrollIntoView({block:'nearest'});const r=el.getBoundingClientRect(),x=Math.round(r.left+r.width/2),y=Math.round(r.top+r.height/2);return r.width>0&&r.height>0&&el.contains(document.elementFromPoint(x,y))?{x,y}:null})()`,
   'Inspector control did not become visible and clickable: '+selector);
  await clickAt(p);
 };
 const begin=async(name,array=false)=>{
  await call('select',0);await delay(120);
  await clickSelector(array?`.entityInstanceEditor [defuid="${fields[name]}"] button.add`:`.entityInstanceEditor #field_${name}_${fields[name]}`);
  await until('pointFixture.state().picker','Inspector button did not activate PickPoint');
 };
 const choose=async(x,y,{keepPicking=false,release=null}={})=>{
  const p=await move(x,y),before=await state();
  assert.equal(before.linkPreview,true,'Point preview was replaced by entity/selection/resize hover; '+JSON.stringify(await call('debug')));
  win.webContents.sendInputEvent({type:'mouseDown',...p,button:'left',clickCount:1});
  await until('(()=>{const s=pointFixture.state();return s.pickerRunning||!s.picker||s.selectionRunning||s.resizing})()',
   'Native point mouse-down was not processed');
  const held=await state();
  if(process.env.LDTK_POINT_DIAGNOSTICS)console.log('POINT HELD',JSON.stringify({before,held,debug:await call('debug')}));
  assert.equal(held.pickerRunning,true,'Canvas mouse-down did not reach the active point picker');
  assert.equal(held.selectionRunning,false,'Point picking started a selection drag');assert.equal(held.resizing,false,'Point picking started an entity resize');
  const end=release?await move(release.x,release.y):p;
  win.webContents.sendInputEvent({type:'mouseUp',...end,button:'left',clickCount:1});
  await until('!pointFixture.state().pickerRunning','Native point mouse-up was not processed');await delay(100);
  const after=await state();assert.equal(after.picker,keepPicking);assert.equal(after.selectionRunning,false);assert.equal(after.resizing,false);
  return after;
 };
 const changedPoint=(before,after,name,value)=>{
  const expected=JSON.parse(JSON.stringify(before.entities));expected[0].fields[name]=value;
  if(process.env.LDTK_POINT_DIAGNOSTICS)console.log('POINT CHANGE',JSON.stringify({name,expected,actual:after.entities,history:[before.history,after.history]}));
  assert.deepEqual(after.entities,expected,'Point editing changed another field, entity, reference or geometry');
  assert.equal(after.history,before.history+1,'Point change must be one undoable operation');
  assert.deepEqual(after.selected,before.selected,'Point edit changed the selected entity');
  assert.equal(after.inspector,ids[0]);assert.equal(after.activeLayer,before.activeLayer);
 };
 const escape=async()=>{
  win.webContents.sendInputEvent({type:'keyDown',keyCode:'Escape'});win.webContents.sendInputEvent({type:'keyUp',keyCode:'Escape'});
  await until('!pointFixture.state().picker','Escape did not cancel point picking');
 };

 await setup();
 await begin('ToPoint');let before=await state();let after=await choose(104,104);
 changedPoint(before,after,'ToPoint',{cx:6,cy:6});
 await pass('Native inspector and canvas clicks set a null point inside its own selected VeinCable without deselecting it');
 assert.equal(await call('undo'),true);
 // LayerInstancesRestoredFromHistory is emitted at the end of a frame.
 // Do not race Undo/Redo with the next operation: wait for an actual editor frame.
 await frame();await frame();
 await until('pointFixture.state().entities[0].fields.ToPoint===null',
  'Undo did not restore the previous ToPoint value');
 assert.deepEqual((await state()).entities,before.entities);
 assert.equal(await call('redo'),true);
 await frame();await frame();
 await until('pointFixture.state().entities[0].fields.ToPoint?.cx===6 && pointFixture.state().entities[0].fields.ToPoint?.cy===6',
  'Redo did not restore the edited ToPoint value');
 assert.deepEqual((await state()).entities,after.entities);
 await pass('One Undo/Redo restores the entire point edit while preserving entities, references and unrelated layers');

 await begin('FromPoint');before=await state();after=await choose(264,104);
 changedPoint(before,after,'FromPoint',{cx:16,cy:6});
 await pass('Editing an existing point inside another entity keeps the cable inspector and selection');
 await begin('ToPoint');before=await state();after=await choose(264,104);
 changedPoint(before,after,'ToPoint',{cx:16,cy:6});
 await pass('An existing point handle and its underlying entity cannot steal another field\'s point placement');
 await begin('ToPoint');before=await state();after=await choose(424,104);
 changedPoint(before,after,'ToPoint',{cx:26,cy:6});
 await pass('Point placement over an entity in another layer preserves the active layer and source entity');

 await begin('ToPoint');before=await state();await move(-8,232);await clickAt(await call('screen',-8,232));after=await state();
 assert.equal(after.picker,true);assert.deepEqual(after.entities,before.entities);assert.equal(after.history,before.history);
 await escape();
 await pass('An out-of-bounds click leaves the point, data and history unchanged and allows cancellation');
 await begin('ToPoint');before=await state();await clickAt(await move(264,104),'right');after=await state();
 assert.equal(after.picker,false);assert.deepEqual(after.entities,before.entities);assert.equal(after.history,before.history);
 await begin('ToPoint');before=await state();await move(264,104);await escape();after=await state();
 assert.deepEqual(after.entities,before.entities);assert.equal(after.history,before.history);
 await pass('Right-click and Escape cancel point picking over entities without moving them or modifying data');

 await begin('Path',true);before=await state();
 for(const [x,y] of [[104,104],[264,104],[424,104]])await choose(x,y,{keepPicking:true});
 after=await state();
 const expected=JSON.parse(JSON.stringify(before.entities));expected[0].fields.Path=[{cx:6,cy:6},{cx:16,cy:6},{cx:26,cy:6}];
 assert.deepEqual(after.entities,expected);assert.equal(after.history,before.history+3);assert.deepEqual(after.selected,before.selected);
 before=after;await choose(104,104,{keepPicking:true});after=await state();
 assert.deepEqual(after.entities,before.entities);assert.equal(after.history,before.history);
 await escape();
 await pass('Array point editing continues across own/other/layered entities and rejects duplicate cells without extra history');

 const persisted=(await state()).entities;await call('reload');await delay(250);await ev('pointFixture.editor()&&true');
 assert.deepEqual((await state()).entities,persisted);
 await pass('Scalar and array point edits survive actual project JSON save/reload with entity references intact');

 await call('select',0);await delay(120);
 await clickSelector(`.entityInstanceEditor [defuid="${fields.To}"] button.pickRef`);
 await until('pointFixture.state().valuePicker','Entity-reference picker did not open');
 const refTarget=await move(440,120);
 // Prove that the real picker accepts the hovered entity before dispatching
 // native mouse input. This distinguishes a hit-test bug from a delayed event.
 const hoveredRef=await ev('(()=>{const p=__ldtk.classes["ui.ValuePicker"].ME;return p&&p.pickAt(pointFixture.editor().getMouse())?.iid||null})()');
 assert.equal(hoveredRef,ids[2],'Reference picker is not targeting the visible cross-layer entity');
 before=await state();
 win.webContents.sendInputEvent({type:'mouseDown',...refTarget,button:'left',clickCount:1});
 await until('!pointFixture.state().valuePicker','Reference picker did not accept native mouse-down');
 win.webContents.sendInputEvent({type:'mouseUp',...refTarget,button:'left',clickCount:1});
 await until('pointFixture.state().entities[0].fields.To===pointFixture.ids[2]',
  'Reference picker closed but did not store the target entity');
 await frame();after=await state();
 const refExpected=JSON.parse(JSON.stringify(before.entities));refExpected[0].fields.To=ids[2];
 assert.deepEqual(after.entities,refExpected);assert.equal(after.valuePicker,false);assert.equal(after.activeLayer,before.activeLayer);
 await pass('The entity-reference picker still receives its native entity click and preserves the source layer');

 await begin('ToPoint');await escape();before=await state();
 await clickAt(await move(280,120));after=await state();
 assert.equal(after.inspector,ids[1]);assert.deepEqual(after.entities,before.entities);
 const start=await move(280,120),end=await call('screen',312,152);
 win.webContents.sendInputEvent({type:'mouseDown',...start,button:'left',clickCount:1});
 await until('pointFixture.state().selectionRunning','Native selection drag did not start');
 win.webContents.sendInputEvent({type:'mouseMove',...end});
 await until('pointFixture.editor().selectionTool.moveStarted','Native selection drag did not move');
 win.webContents.sendInputEvent({type:'mouseUp',...end,button:'left',clickCount:1});
 await until('!pointFixture.state().selectionRunning','Native selection drag did not finish');await delay(100);
 after=await state();assert.equal(after.entities[1].x,before.entities[1].x+32);assert.equal(after.entities[1].y,before.entities[1].y+32);
 assert.deepEqual(after.entities[0],before.entities[0]);assert.deepEqual(after.entities[2],before.entities[2]);
 await pass('After cancelling the picker, native entity selection and drag still work normally');

 await setup({resizable:true});await begin('ToPoint');before=await state();const handle=await call('handle');
 await move(handle.x,handle.y);
 fs.writeFileSync(path.join(output,'point-preview.png'),(await win.webContents.capturePage()).toPNG());
 const release={x:handle.x+32,y:handle.y+32};after=await choose(handle.x,handle.y,{release});
 changedPoint(before,after,'ToPoint',{cx:Math.floor(release.x/16),cy:Math.floor(release.y/16)});
 await pass('Point preview and press/drag/release over an active resize handle set the point without resizing or moving the entity');


 // Ctrl+Shift + mouse, NOT Ctrl+Shift+W, is an Entities-layer erase
 // rectangle. It must bypass the regular entity/selection/resize hit tests.
 const eraseState=()=>call('eraseState');
 const erasePass=async message=>{
  assert.equal(await ev('__ldtk.App.ME.curPageProcess.__class__.__name__'),'page.Editor','Application entered a crash page');
  assert.equal((await eraseState()).sentinel,1,'An unrelated layer changed during entity erase');
  passed.push(message);console.log('PASS: '+message);
 };
 const modifierDown=async()=>{
  win.webContents.sendInputEvent({type:'keyDown',keyCode:'Control'});
  win.webContents.sendInputEvent({type:'keyDown',keyCode:'Shift'});
  await delay(80);
 };
 const modifierUp=async()=>{
  win.webContents.sendInputEvent({type:'keyUp',keyCode:'Shift'});
  win.webContents.sendInputEvent({type:'keyUp',keyCode:'Control'});
  await delay(80);
 };
 const eraseGesture=async(from,to=null,button='left')=>{
  const start=await move(from[0],from[1]);
  await modifierDown();
  // Re-hover while modifiers are held, so the real editor receives the same
  // sequence as a human before the mouse press.
  await nativeMove({x:start.x+1,y:start.y});await nativeMove(start);
  win.webContents.sendInputEvent({type:'mouseDown',...start,button,clickCount:1,modifiers:['control','shift']});
  await until('pointFixture.editor().get_curTool().isRunning()','Ctrl+Shift press was stolen by selection or resize');
  assert.equal((await state()).selectionRunning,false,'Ctrl+Shift activated SelectionTool');
  if(to){
   const end=await call('screen',to[0],to[1]);
   await nativeMove(end);
   win.webContents.sendInputEvent({type:'mouseUp',...end,button,clickCount:1,modifiers:['control','shift']});
  }else{
   win.webContents.sendInputEvent({type:'mouseUp',...start,button,clickCount:1,modifiers:['control','shift']});
  }
  await until('!pointFixture.editor().get_curTool().isRunning()','Entity erase gesture did not finish');
  await modifierUp();await delay(120);
 };
 const eraseCompare=(actual,expected)=>{
  assert.deepEqual(actual.source,expected.source,'Active-layer entities differ');
  assert.deepEqual(actual.other,expected.other,'An entity on another layer changed');
  assert.equal(actual.sentinel,expected.sentinel,'An unrelated IntGrid layer changed');
  assert.equal(actual.activeLayer,expected.activeLayer,'Active layer changed');
 };
 await setup();
 await call('select',0);await delay(120);
 let eraseBefore=await eraseState();
 // Two entities share the same screen position, but only the active layer
 // may be altered by the shortcut.
 await ev(`(()=>{const f=pointFixture,other=f.entity(2);other.x=264;other.y=104;f.editor().levelRender.invalidateLayer(other._li);
  // This fixture-only move must be a committed history baseline. Otherwise
  // Undo of the next deletion legitimately restores the previous position.
  const editor=f.editor();editor.levelTimelines.h[editor.curLevelId].saveLayerState(other._li);
  return true})()`);
 eraseBefore=await eraseState();
 await eraseGesture([480,240],[544,288]);
 let erased=await eraseState();
 eraseCompare(erased,eraseBefore);assert.equal(erased.history,eraseBefore.history);
 await erasePass('Ctrl+Shift dragging an empty rectangle keeps every layer and history unchanged');
 await eraseGesture([104,104],[280,136]);
 erased=await eraseState();
 assert.deepEqual(erased.source,[],'Rectangle did not remove both covered active-layer entities');
 assert.deepEqual(erased.other,eraseBefore.other,'Rectangle removed an entity from another layer');
 assert.equal(erased.history,eraseBefore.history+1,'Rectangle erase must be one undo transaction');
 assert.equal(await call('undo'),true);await frame();await frame();
 eraseCompare(await eraseState(),eraseBefore);
 assert.equal(await call('redo'),true);await frame();await frame();
 assert.deepEqual((await eraseState()).source,[]);
 assert.deepEqual((await eraseState()).other,eraseBefore.other);
 await erasePass('Ctrl+Shift rectangle erases active Entities only and Undo/Redo restores all at once');

 await setup();await call('select',1);await delay(120);
 eraseBefore=await eraseState();
 await eraseGesture([264,104]);
 erased=await eraseState();
 assert.equal(erased.source.length,1,'Single Ctrl+Shift click did not delete the clicked entity');
 assert.equal(erased.source[0].iid,eraseBefore.source[0].iid,'Single erase removed the wrong entity');
 assert.deepEqual(erased.other,eraseBefore.other,'Single erase changed another entity layer');
 assert.equal(erased.history,eraseBefore.history+1,'Single-click erase must be undoable');
 assert.equal(await call('undo'),true);await frame();await frame();
 eraseCompare(await eraseState(),eraseBefore);
 await erasePass('Ctrl+Shift clicking a selected entity erases it without selection interception');

 // A foreground entity on another visible Entities layer must never be erased,
 // including when the user Ctrl+Shift-clicks at its exact same coordinates.
 await setup();await call('select',1);await delay(120);
 await ev(`(()=>{const f=pointFixture,e=f.editor(),other=f.entity(2);
  other.x=264;other.y=104;
  e.levelRender.invalidateLayer(other._li);
  e.levelTimelines.h[e.curLevelId].saveLayerState(other._li);
  return true})()`);
 eraseBefore=await eraseState();
 await eraseGesture([264,104]);
 erased=await eraseState();
 assert.equal(erased.source.length,1,'Overlapping Ctrl+Shift click failed to remove the active-layer target');
 assert.equal(erased.source[0].iid,eraseBefore.source[0].iid,'Overlapping click erased the wrong source entity');
 assert.deepEqual(erased.other,eraseBefore.other,'Overlapping click removed an entity from another layer');
 assert.equal(erased.history,eraseBefore.history+1,'Overlapping erase did not create a history checkpoint');
 assert.equal(await call('undo'),true);await frame();await frame();
 eraseCompare(await eraseState(),eraseBefore);
 await erasePass('Ctrl+Shift single-click removes only active-layer entities even when two layers overlap');

 if(process.platform==='darwin'){
  // macOS may translate a physical Control+left-click to a secondary click.
  await setup();await call('select',1);await delay(120);
  eraseBefore=await eraseState();
  await eraseGesture([264,104],null,'right');
  erased=await eraseState();
  assert.equal(erased.source.length,1,'macOS control-click was intercepted');
  assert.equal(erased.history,eraseBefore.history+1,'macOS control-click must be undoable');
  assert.equal(await call('undo'),true);await delay(160);
  eraseCompare(await eraseState(),eraseBefore);
  await erasePass('macOS Control+Shift secondary-click erases the active-layer entity only');
 }

 await setup();await call('select',0);await delay(120);
 eraseBefore=await eraseState();
 await clickAt(await move(104,104));
 eraseCompare(await eraseState(),eraseBefore);
 assert.equal((await eraseState()).history,eraseBefore.history);
 await erasePass('An ordinary entity click without Ctrl+Shift remains non-destructive');

 fs.writeFileSync(path.join(output,'results.json'),JSON.stringify({status:'passed',passed,platform:process.platform,electron:process.versions.electron},null,2));
 fs.writeFileSync(path.join(output,'success.png'),(await win.webContents.capturePage()).toPNG());
 console.log('SUCCESS: '+passed.length+' point-picking scenarios passed');clearTimeout(timer);app.exit(0);
}
require('../assets/main.js');
