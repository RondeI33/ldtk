'use strict';

const assert=require('node:assert/strict'),path=require('node:path');

module.exports=async function({win,ev,call,pass,until,tmp}){
 const C='__ldtk.classes',E='__ldtk.enums',ED='shapeFixture.editor()',S=C+'["data.DrawableShape"]';
 const state=()=>call('state');
 const processFrame=()=>win.webContents.executeJavaScript(`new Promise((resolve,reject)=>{
  const timer=setTimeout(()=>reject(Error('Clipboard editor frame did not finish')),10000),P=__ldtk.classes['dn.Process'];
  P.callAtTheBeginningOfNextFrame(()=>P.callAtTheEndOfCurrentFrame(()=>{clearTimeout(timer);resolve(true)}));
 })`,true);
 win.show();win.focus();win.webContents.focus();
 await ev(`(()=>{window.shapeClipboardMouse={sequence:0};document.addEventListener('mousemove',e=>{shapeClipboardMouse={sequence:shapeClipboardMouse.sequence+1,x:e.clientX,y:e.clientY}},true);return true})()`);
 const nativeMove=async p=>{
  const seq=await ev('shapeClipboardMouse.sequence');win.webContents.sendInputEvent({type:'mouseMove',...p});
  await until(`shapeClipboardMouse.sequence>${seq}&&shapeClipboardMouse.x===${p.x}&&shapeClipboardMouse.y===${p.y}`,'clipboard mouse delivery');await processFrame();
 };
 const move=async(x,y)=>{
  const p=await call('screen',x,y);assert.equal(await ev(`document.elementFromPoint(${p.x},${p.y})?.id`),'webgl','Clipboard map point is covered by UI');
  await nativeMove({x:p.x+1,y:p.y});await nativeMove(p);return p;
 };
 const shortcut=async keyCode=>{
  const key=process.platform==='darwin'?'Meta':'Control',modifiers=[process.platform==='darwin'?'meta':'control'];
  win.webContents.sendInputEvent({type:'keyDown',keyCode:key});await processFrame();
  win.webContents.sendInputEvent({type:'keyDown',keyCode,modifiers});await processFrame();
  win.webContents.sendInputEvent({type:'keyUp',keyCode,modifiers});win.webContents.sendInputEvent({type:'keyUp',keyCode:key});
  await processFrame();await processFrame();
 };
 const drop=async p=>{
  win.webContents.sendInputEvent({type:'mouseDown',...p,button:'left',clickCount:1});await processFrame();
  win.webContents.sendInputEvent({type:'mouseUp',...p,button:'left',clickCount:1});await processFrame();await processFrame();
 };
 const setup=async name=>{
  await call('setup',path.join(tmp,'clipboard-'+name+'.ldtk'));await processFrame();await processFrame();
  await ev(`${C}['ui.Modal'].closeAll()`);await processFrame();
 };
 const blur=()=>ev('(()=>{document.activeElement?.blur();return true})()');
 const copied=()=>ev(`__ldtk.App.ME.clipboard.getParsedJson()`);

 await setup('single');
 await ev(`(()=>{const ei=shapeFixture.entity(0);${C}['ui.DrawableShapeEditor'].commit(ei,()=>{${S}.set(ei,'Damage',91);${S}.set(ei,'Color','#4477AA');return null});return true})()`);
 await call('select',0);await processFrame();await blur();let point=await move(264,72);
 let before=await state();await shortcut('C');
 await until(`__ldtk.App.ME.clipboard.is(${E}['ClipboardType'].CSelection)`,'native scene clipboard');
 const payload=await copied();assert.equal(payload.format,1);assert.equal(payload.projectIid,await ev(`${ED}.project.iid`));
 const fields=Object.fromEntries(payload.selection.entities[0].json.fieldInstances.map(f=>[f.__identifier,f.__value]));
 assert.deepEqual(fields.ShapeCells,before.entities[0].shape.cells);assert.equal(fields.Color,'#4477AA');assert.equal(fields.Damage,91);
 assert.deepEqual((await state()).entities,before.entities);assert.equal((await state()).history,before.history);
 await shortcut('V');await until(`${ED}.specialTool?.getShortName()==='SelectionTemplateTool'`,'native clipboard placement tool');
 point=await move(264,72);assert.equal(await ev(`${ED}.specialTool.debugGhostStats().appliesSettings`),false);
 await drop(point);let after=await state(),placed=after.entities.find(e=>!before.entities.some(old=>old.iid===e.iid));
 assert(placed,'Native paste did not allocate a copied owner');assert.equal(after.entities.length,before.entities.length+1);
 assert.deepEqual(placed.shape,before.entities[0].shape);assert.deepEqual(placed.fields,before.entities[0].fields);
 assert.deepEqual(after.entities.filter(e=>e.iid!==placed.iid),before.entities);assert.equal(after.history,before.history+1);
 const pasted=after.entities;assert.equal(await call('undo'),true);await processFrame();await processFrame();assert.deepEqual((await state()).entities,before.entities);
 assert.equal(await call('redo'),true);await processFrame();await processFrame();assert.deepEqual((await state()).entities,pasted);
 await pass('Native Ctrl/Cmd+C/V copies complete fields and masks, allocates a fresh IID over an existing shape, and records one undoable placement');

 // Scene shortcuts must not intercept ordinary text editing in the inspector.
 await ev(`(()=>{${ED}.clearSpecialTool();const input=document.createElement('input');input.id='shapeClipboardTextInput';input.value='Text editing';document.body.appendChild(input);input.focus();return true})()`);
 before=await state();assert.equal(await ev(`${ED}.canUseSelectionClipboard()`),false);await shortcut('V');
 assert.equal((await state()).special,null);assert.deepEqual((await state()).entities,before.entities);assert.equal((await state()).history,before.history);
 await ev('(()=>{document.querySelector("#shapeClipboardTextInput").remove();return true})()');
 await pass('Scene clipboard shortcuts leave focused text controls and level history under native text-editing ownership');
 await ev(`(()=>{const value=JSON.parse(JSON.stringify(__ldtk.App.ME.clipboard.getParsedJson()));value.projectIid='different-project';__ldtk.App.ME.clipboard.copyData(${E}['ClipboardType'].CSelection,value);return true})()`);
 await blur();await move(200,240);before=await state();await shortcut('V');
 assert.equal((await state()).special,null);assert.deepEqual((await state()).entities,before.entities);assert.equal((await state()).history,before.history);
 await pass('Clipboard content from a different project is rejected without creating owners or changing the level timeline');

 await setup('cross-level');
 await ev(`(()=>{const a=shapeFixture.entity(0),b=shapeFixture.entity(1);${C}['ui.DrawableShapeEditor'].commit(a,()=>{${S}.field(a,'Link',true).setEntityRefTo(0,a,b);${S}.field(a,'Anchor',true).parseValue(0,'13,11');return null});
  ${ED}.selectionTool.select([${E}.GenericLevelElement.Entity(a._li,a),${E}.GenericLevelElement.Entity(b._li,b)]);return true})()`);
 await processFrame();await blur();await move(200,240);before=await state();await shortcut('C');
 assert.equal((await copied()).selection.entities.length,2);
 const sourceHistory=await ev(`${ED}.levelTimelines.h[shapeFixture.levels[0]].curStateIdx`);
 await ev(`(()=>{const e=${ED};e.selectLevel(shapeFixture.level(1));e.selectLayerInstance(shapeFixture.level(1).getLayerInstance(shapeFixture.layers[0]));e.camera.fit(true);return true})()`);
 await processFrame();await processFrame();await blur();await move(72,264);await shortcut('V');
 await until(`${ED}.specialTool?.getShortName()==='SelectionTemplateTool'`,'cross-level paste placement');
 point=await move(72,264);await drop(point);after=await state();
 const copies=after.entities.filter(e=>!before.entities.some(old=>old.iid===e.iid));assert.equal(copies.length,2);
 const aCopy=copies.find(e=>e.shape.preset==='Custom'),ringCopy=copies.find(e=>e.shape.preset==='Ring');assert(aCopy&&ringCopy);
 assert.deepEqual(aCopy.shape,before.entities[0].shape);assert.deepEqual(ringCopy.shape,before.entities[1].shape);
 assert.equal(aCopy.level,await ev('shapeFixture.levels[1]'));assert.equal(ringCopy.level,aCopy.level);
 assert.equal(aCopy.fields.Link.entityIid,ringCopy.iid);assert.equal(aCopy.fields.Color,before.entities[0].fields.Color);
 assert.equal(await ev(`(()=>{const a=shapeFixture.entity(${JSON.stringify(aCopy.iid)}),b=shapeFixture.entity(${JSON.stringify(ringCopy.iid)});return ${ED}.project.getEntityInstancesReferingTo(b).includes(a)})()`),true);
 const source=before.entities[0],sourceAnchor=source.fields.Anchor,copyAnchor=aCopy.fields.Anchor;
 assert.equal(copyAnchor.cx-sourceAnchor.cx,Math.round((aCopy.left-source.left)/16));assert.equal(copyAnchor.cy-sourceAnchor.cy,Math.round((aCopy.top-source.top)/16));
 assert.deepEqual(after.entities.filter(e=>!copies.some(copy=>copy.iid===e.iid)),before.entities);
 assert.equal(await ev(`${ED}.levelTimelines.h[shapeFixture.levels[0]].curStateIdx`),sourceHistory);
 assert.equal(after.history,1);assert.equal(await call('undo'),true);await processFrame();await processFrame();assert.deepEqual((await state()).entities,before.entities);
 await pass('Cross-level clipboard paste remaps copied entity references, moves point anchors with geometry, preserves source IIDs and has an independent destination undo');
};
