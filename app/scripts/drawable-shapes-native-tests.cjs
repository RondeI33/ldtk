'use strict';
const assert=require('node:assert/strict'),path=require('node:path'),fs=require('node:fs');

module.exports=async function({win,ev,call,delay,pass,frame,until,tmp,output}){
 win.setSize(1600,1000);win.show();win.focus();win.webContents.focus();
 const state=()=>call('state');
 const C='__ldtk.classes',S=C+'["data.DrawableShape"]',F='shapeFixture',ED=F+'.editor()';
 const processFrame=()=>win.webContents.executeJavaScript(`new Promise((resolve,reject)=>{
  const timer=setTimeout(()=>reject(Error('Editor frame did not finish')),10000),P=__ldtk.classes['dn.Process'];
  P.callAtTheBeginningOfNextFrame(()=>P.callAtTheEndOfCurrentFrame(()=>{clearTimeout(timer);resolve(true)}));
 })`,true);
 await ev(`(()=>{window.shapeMouse={sequence:0};document.addEventListener('mousemove',e=>{shapeMouse={sequence:shapeMouse.sequence+1,x:e.clientX,y:e.clientY}},true);return true})()`);
 const nativeMove=async p=>{
  const seq=await ev('shapeMouse.sequence');win.webContents.sendInputEvent({type:'mouseMove',...p});
  await until(`shapeMouse.sequence>${seq}&&shapeMouse.x===${p.x}&&shapeMouse.y===${p.y}`,'native mouse delivery');await processFrame();
 };
 const move=async(x,y)=>{
  const p=await call('screen',x,y);
  assert.equal(await ev(`document.elementFromPoint(${p.x},${p.y})?.id`),'webgl','Map point is covered by UI');
  await nativeMove({x:p.x+1,y:p.y});await nativeMove(p);return p;
 };
 const release=async(p,button='left')=>{
  win.webContents.sendInputEvent({type:'mouseUp',...p,button,clickCount:1});await processFrame();await processFrame();
 };
 const drag=async(points,button='left')=>{
  let p=await move(...points[0]);win.webContents.sendInputEvent({type:'mouseDown',...p,button,clickCount:1});
  await processFrame();
  for(const xy of points.slice(1))p=await move(...xy);
  await release(p,button);return p;
 };
 const key=async keyCode=>{
  win.webContents.sendInputEvent({type:'keyDown',keyCode});win.webContents.sendInputEvent({type:'keyUp',keyCode});await processFrame();await processFrame();
 };
 const clickSelector=async selector=>{
  let p=null;
  for(let i=0;i<100&&!p;i++){
   p=await ev(`(()=>{const el=document.querySelector(${JSON.stringify(selector)});if(!el)return null;el.scrollIntoView({block:'nearest'});const r=el.getBoundingClientRect();return r.width>0&&r.height>0?{x:Math.round(r.left+r.width/2),y:Math.round(r.top+r.height/2)}:null})()`);
   if(!p)await delay(30);
  }
  assert(p,'Missing clickable control '+selector);
  await nativeMove({x:p.x+1,y:p.y});await nativeMove(p);
  win.webContents.sendInputEvent({type:'mouseDown',...p,button:'left',clickCount:1});await processFrame();await release(p);
 };
 let sequence=0;
 const setup=async(options={})=>{
  await call('setup',path.join(tmp,'native-'+(++sequence)+'.ldtk'),options);await processFrame();await processFrame();
  await ev(`${C}['ui.Modal'].closeAll()`);await processFrame();
 };
 const activate=async(brush='Paint',index=null,preset='Rectangle')=>{
  await ev(`(()=>{const e=${ED},ei=${index==null?'null':F+'.entity('+index+')'};${C}['ui.DrawableShapeEditor'].activate(e.project.defs.getEntityDef(shapeFixture.defs.hazard),ei,${JSON.stringify(brush)},${JSON.stringify(preset)});return true})()`);
  await processFrame();assert.equal((await state()).special,'DrawableShapeTool');
 };
 const shapeEntities=s=>s.entities.filter(e=>e.shape);
 const cellsWorld=e=>e.shape.cells.reduce((a,_,i,c)=>i%2?a:(a.push([e.left+c[i]*e.shape.grid,e.top+c[i+1]*e.shape.grid]),a),[]);

 await setup({empty:true});
 await ev(`(()=>{const input=document.querySelector('.shapePlacementMode');input.value='Custom';input.dispatchEvent(new Event('change',{bubbles:true}));return true})()`);await processFrame();
 let before=await state();
 await drag([[72,72],[72,104],[104,104]]);
 let after=await state(),owner=shapeEntities(after)[0];
 assert.equal(shapeEntities(after).length,1);assert.deepEqual(owner.shape.cells,[0,0,0,1,0,2,1,2,2,2]);assert.equal(after.history,before.history+1);
 assert.equal(await ev(`document.querySelectorAll('.entityInstanceEditor [defuid="'+shapeFixture.fields.ShapeCells+'"] input').length`),0);
 await pass('Native palette and brush draw an L as one entity, one native array and one undo operation');
 const iid=owner.iid,oldWorld=cellsWorld(owner);before=after;
 await drag([[56,72],[56,56],[72,56]]);after=await state();owner=shapeEntities(after)[0];
 assert.equal(owner.iid,iid);assert.equal(owner.left,48);assert.equal(owner.top,48);assert.equal(after.history,before.history+1);
 for(const cell of oldWorld)assert(cellsWorld(owner).some(c=>c[0]===cell[0]&&c[1]===cell[1]));
 await pass('Native paint-left/up updates pivot-aware bounds without moving existing world cells');
 const extended=after.entities;
 assert.equal(await call('undo'),true);await processFrame();await processFrame();assert.deepEqual((await state()).entities,before.entities);
 assert.equal(await call('redo'),true);await processFrame();await processFrame();assert.deepEqual((await state()).entities,extended);
 await pass('One Undo/Redo restores a complete shape stroke, bounds, native fields and original IID');

 await setup();await activate('Erase',0);before=await state();
 await drag([[72,88]]);after=await state();assert.deepEqual(after.entities,before.entities);assert.equal(after.history,before.history);
 assert.match(await ev(`${ED}.specialTool.candidateError`),/connect|edge|island/i);
 await pass('Erasing a one-cell bridge is rejected atomically with an invalid-candidate preview');
 await activate('Paint',0);before=await state();await drag([[120,120]]);after=await state();
 assert.deepEqual(after.entities,before.entities);assert.equal(after.history,before.history);
 await pass('A diagonal-only addition is rejected instead of creating an island or an invented bridge');
 let p=await move(56,72);win.webContents.sendInputEvent({type:'mouseDown',...p,button:'left',clickCount:1});await processFrame();p=await move(56,56);
 assert.deepEqual((await state()).entities,before.entities,'Candidate must not mutate native fields before release');
 await key('Escape');await release(p);assert.deepEqual((await state()).entities,before.entities);
 assert.equal(await ev(`Object.keys(${C}['display.EntityRender'].suppressedShapes.h).length`),0);
 await pass('Escape cancels a held brush stroke and restores the source preview without a history entry');

 await setup({empty:true});await activate();before=await state();await drag([[72,72],[200,200]]);after=await state();owner=shapeEntities(after)[0];
 assert.equal(owner.shape.cells.length/2,17);assert.equal(await ev(`${C}['DrawableShapeGeometry'].validate(${JSON.stringify(owner.shape.cells)},false)`),null);assert.equal(after.history,before.history+1);
 await pass('Fast native brush movement interpolates every shared-edge step without leaving gaps');
 await setup({empty:true});await activate();await drag([[72,72]]);before=await state();owner=shapeEntities(before)[0];
 await drag([[72,72]],'right');after=await state();assert.equal(after.entities.length,0);assert.equal(after.history,before.history+1);
 assert.equal(await call('undo'),true);await processFrame();await processFrame();assert.equal(shapeEntities(await state())[0].iid,owner.iid);
 await pass('Erasing the last cell deletes its owner through a single undoable native transaction');

 await setup({empty:true});await activate('Preset',null,'Ring');await drag([[72,72],[136,136]]);after=await state();owner=shapeEntities(after)[0];
 assert.equal(owner.shape.preset,'Ring');assert.equal(owner.shape.cells.length/2,16);assert.equal(owner.fields.VisualProfile,'Spikes');
 assert.equal(await ev(`${C}['DrawableShapeGeometry'].holeCount(${JSON.stringify(owner.shape.cells)})`),1);
 assert.equal(await ev(`${ED}.get_curLayerInstance().entityInstances[0].isOver(104,104)`),false);
 await pass('Native Ring preset placement retains its empty centre and commits the spike preview profile');
 await activate('Preset',null,'UShape');before=await state();await drag([[216,72],[232,88]]);assert.deepEqual((await state()).entities,before.entities);
 await pass('A U preset below its displayed minimum size is rejected without a filled-rectangle fallback');

 // Adjacent objects must be separate; preset-placement erase must never place another owner.
 await setup({empty:true});await activate('Rectangle');await drag([[72,72],[88,88]]);await drag([[104,72],[120,88]]);
 after=await state();assert.equal(after.entities.length,2);assert.notEqual(after.entities[0].iid,after.entities[1].iid);
 before=after;await drag([[120,88]],'right');after=await state();assert.equal(after.entities.length,2);assert.equal(after.entities[1].shape.mode,'Custom');
 assert.equal(after.entities[0].iid,before.entities[0].iid);assert.equal(after.entities[1].shape.cells.length/2,3);
 await pass('Adjacent shapes keep separate IIDs, and native erase in Rectangle mode edits cells rather than placing an owner');

 await setup();await call('select',0);await processFrame();before=await state();
 await drag([[104,88]]);after=await state();assert.deepEqual(after.selected,[before.ids[4]]);
 await pass('Clicking the empty bounds of a selected concave shape reaches the ordinary entity underneath');

 // Exercise full renderer integration, including every preset at tall/wide dimensions.
 const renderChecks=await ev(`(()=>{const p=${ED}.project,li=${ED}.get_curLayerInstance(),ed=p.defs.getEntityDef(shapeFixture.defs.hazard),S=${S},G=${C}['DrawableShapeGeometry'],R=${C}['display.EntityRender'];let count=0;
 for(const preset of ['Rectangle','Strip','LCorner','UShape','Staircase','Diamond','Ring'])for(const [w,h] of [[11,5],[5,11]]){
  const ei=new ${C}['data.inst.EntityInstance'](p,li,ed.uid,'render-'+count);ei.tidy(p,li);const error=S.applyPreset(ei,preset,w,h,1,0);if(error)throw Error(error);
  S.set(ei,'VisualProfile','Spikes');S.set(ei,'ShapeFacing',preset==='Strip'?'Right':'All');const core=R.renderCore(ei),stats=core.g.drawableShapeStats;
  if(stats.cellCount!==S.read(ei).cells.length/2)throw Error('Renderer cell count disagrees');
  if(preset==='Strip'&&stats.spikeFaces.some(f=>f.face!=='Right'))throw Error('Spikes rendered on safe side');
  S.set(ei,'VisualProfile','EnergyPool');const pool=R.renderCore(ei),ps=pool.g.drawableShapeStats;
  if(ps.spikeFaces.length!==0||ps.surfaceSpans.some(span=>span.width<=0))throw Error('Pool uses invalid surfaces');
  core.wrapper.removeChildren();pool.wrapper.removeChildren();count++;
 }return count})()`);
 assert.equal(renderChecks,14);await pass('All seven presets render at wide and tall sizes with exposed spike faces and horizontal pool surfaces');

 // Saved configuration uses the existing template implementation and native canvas dispatcher.
 await setup();await call('select',0);await ev(`(()=>{${S}.set(${F}.entity(0),'Damage',91);${S}.set(${F}.entity(0),'Color','#22BBCC');window.nativeShapeTemplate=${ED}.selectionTool.group.toSelectionTemplate('Hazard configuration');${ED}.setSpecialTool(new ${C}['tool.SelectionTemplateTool'](nativeShapeTemplate));return true})()`);await processFrame();
 before=await state();await move(264,72);
 assert.equal(await ev(`${ED}.specialTool.debugGhostStats().appliesSettings`),true);
 await drag([[264,72]]);after=await state();
 assert.equal(after.entities.length,before.entities.length);assert.equal(after.entities[1].iid,before.entities[1].iid);assert.deepEqual(after.entities[1].shape.cells,before.entities[1].shape.cells);assert.equal(after.entities[1].fields.Damage,91);assert.equal(after.entities[1].fields.Color,'#22BBCC');assert.equal(after.history,before.history+1);
 await pass('Saved-template hover previews Apply settings; native drop/click preserves the target mask, IID and single ownership');
 await ev(`${ED}.setSpecialTool(new ${C}['tool.SelectionTemplateTool'](nativeShapeTemplate))`);await processFrame();before=await state();await drag([[456,328]]);after=await state();
 assert.equal(after.entities.length,before.entities.length+1);const placed=after.entities.find(e=>!before.entities.some(old=>old.iid===e.iid));assert.deepEqual(placed.shape.cells,before.entities[0].shape.cells);assert.equal(placed.fields.Damage,91);
 await pass('The same saved configuration places a fresh shape with a new IID when dropped on empty space');

 // The ordinary native Color field opens the extended dialog and commits exactly once.
 await setup();await call('select',0);await processFrame();before=await state();
 await clickSelector('.entityInstanceEditor .colorWrapper');
 await until('!!document.querySelector(".hueWheelPicker .hueWheel")','hue wheel dialog');
 assert.equal(await ev('document.querySelectorAll(".hueWheelPicker .svSquare").length'),1);
 const picker=()=>ev(`(()=>{const cp=${C}['ui.Modal'].getFirst(${C}['ui.modal.dialog.ColorPicker']);return {h:cp.picker.hue,s:cp.picker.saturation,v:cp.picker.value,hex:cp.picker.getHexString(),input:cp.jContent.find('.input input').val(),r:cp.jContent.find('.rgb .red').val(),g:cp.jContent.find('.rgb .green').val(),b:cp.jContent.find('.rgb .blue').val()}})()`);
 const clickFraction=async(selector,x,y)=>{
  const q=await ev(`(()=>{const r=document.querySelector(${JSON.stringify(selector)}).getBoundingClientRect();return {x:Math.round(r.left+r.width*${x}),y:Math.round(r.top+r.height*${y})}})()`);
  await nativeMove({x:q.x+1,y:q.y});await nativeMove(q);win.webContents.sendInputEvent({type:'mouseDown',...q,button:'left',clickCount:1});await processFrame();await release(q);
 };
 await clickFraction('.hueWheel',0.06,0.5);await clickFraction('.svSquare',0.75,0.25);
 let color=await picker();assert(Math.abs(color.h-180)<4);assert(Math.abs(color.s-0.75)<0.03);assert(Math.abs(color.v-0.75)<0.03);
 assert.equal(color.input.toUpperCase(),color.hex.slice(1));assert.equal(Number(color.r),parseInt(color.hex.slice(1,3),16));assert.equal(Number(color.g),parseInt(color.hex.slice(3,5),16));assert.equal(Number(color.b),parseInt(color.hex.slice(5),16));
 after=await state();assert.equal(after.entities[0].fields.Color,before.entities[0].fields.Color);assert.equal(after.history,before.history);
 const preview=await ev(`${C}['display.EntityRender'].previewColors.h[${JSON.stringify(before.ids[0])}]`);assert.equal(preview,parseInt(color.hex.slice(1),16));
 await pass('Native hue-wheel and SV-square input synchronize hex/RGB and live tint without committing fields or undo steps');
 await ev(`(()=>{const cp=${C}['ui.Modal'].getFirst(${C}['ui.modal.dialog.ColorPicker']);cp.jContent.find('.input input').val('336699').trigger('keyup');return true})()`);color=await picker();assert.equal(color.hex,'#336699');assert.equal(Number(color.r),51);assert.equal(Number(color.g),102);assert.equal(Number(color.b),153);
 await ev(`(()=>{const cp=${C}['ui.Modal'].getFirst(${C}['ui.modal.dialog.ColorPicker']);cp.jContent.find('.rgb .red').val('128').trigger('input');return true})()`);color=await picker();assert.equal(color.hex,'#806699');
 fs.writeFileSync(path.join(output,'color-wheel.png'),(await win.webContents.capturePage()).toPNG());
 await key('Escape');await until('!document.querySelector(".hueWheelPicker")','native Escape confirmation');after=await state();assert.equal(after.entities[0].fields.Color,'#806699');assert.equal(after.history,before.history+1);assert.equal(after.entities[1].fields.Color,before.entities[1].fields.Color);
 assert.equal(await ev(`Object.keys(${C}['display.EntityRender'].previewColors.h).length`),0);
 await pass('Hex and RGB edits stay synchronized; Escape retains native confirmation semantics and changes only one instance in one undo step');
 assert.equal(await call('undo'),true);await processFrame();await processFrame();assert.equal((await state()).entities[0].fields.Color,before.entities[0].fields.Color);
 assert.equal(await call('redo'),true);await processFrame();await processFrame();await call('reload');await processFrame();assert.equal((await state()).entities[0].fields.Color,'#806699');
 await pass('Native color undo/redo and save/reopen retain standard #RRGGBB per-instance serialization');
 await ev(`${C}['ui.EntityInstanceEditor'].closeExisting()`);await frame();
 fs.writeFileSync(path.join(output,'drawable-shapes-canvas.png'),(await win.webContents.capturePage()).toPNG());
};
