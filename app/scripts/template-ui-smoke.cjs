'use strict';
const {app,BrowserWindow}=require('electron');
const fs=require('fs'),os=require('os'),path=require('path'),assert=require('assert');
const root=path.resolve(__dirname,'..'),tmp=fs.mkdtempSync(path.join(os.tmpdir(),'smartive-templates-'));
const output=path.join(root,'test-results/templates');fs.mkdirSync(output,{recursive:true});
process.chdir(root);app.setPath('userData',tmp);if(app.setAppPath)app.setAppPath(root);else app.getAppPath=()=>root;
process.env.LDTK_SMARTIVE_CONTROL_DIR=path.join(tmp,'control');
app.commandLine.appendSwitch('no-sandbox');app.commandLine.appendSwitch('use-gl','angle');app.commandLine.appendSwitch('use-angle','swiftshader');
const timer=setTimeout(()=>{console.error('FAIL: UI smoke test timed out');app.exit(1);},60000);
let running=false,passed=[];
const delay=ms=>new Promise(r=>setTimeout(r,ms));
app.on('browser-window-created',(_,win)=>{
  win.webContents.on('did-finish-load',()=>{
    if(!win.webContents.getURL().endsWith('/assets/app.html')||running)return;
    running=true;run(win).catch(async err=>{console.error(err.stack||err);try{fs.writeFileSync(path.join(output,'failure.png'),(await win.webContents.capturePage()).toPNG());}catch(_){};clearTimeout(timer);app.exit(1);});
  });
});
async function run(win){
  const ev=code=>win.webContents.executeJavaScript(code,true);
  async function until(code,message){for(let i=0;i<200;i++){if(await ev(`!!(${code})`))return;await delay(40);}throw Error(message);}
  const pass=m=>{passed.push(m);console.log('PASS: '+m);};
  const click=selector=>ev(`(()=>{const e=document.querySelector(${JSON.stringify(selector)});if(!e)throw Error('Missing '+${JSON.stringify(selector)});e.click();})()`);
  const edit=(selector,value)=>ev(`(()=>{const e=document.querySelector(${JSON.stringify(selector)});if(!e)throw Error('Missing input '+${JSON.stringify(selector)});e.value=${JSON.stringify(value)};e.dispatchEvent(new Event('change',{bubbles:true}));e.dispatchEvent(new KeyboardEvent('keyup',{bubbles:true,key:'a'}));})()`);
  await until('(window.TemplateTestHooks=window.TemplateTestHooks || (typeof exports!=="undefined" && exports.TemplateTestHooks)) && document.querySelector("#page")','App did not expose test hooks');await delay(400);
  win.setSize(1400,900);win.show();win.focus();win.webContents.setBackgroundThrottling(false);
  const fixture=await ev(`TemplateTestHooks.setup(${JSON.stringify(path.join(tmp,'test.ldtk'))})`);await delay(450);await ev('TemplateTestHooks.dismissNotices()');await delay(250);win.webContents.focus();
  await until('document.querySelector("#selectionTemplatesTab")','Editor did not open');
  await ev('window.prompt=()=>{throw new Error("Unexpected browser prompt")};window.confirm=()=>{throw new Error("Unexpected browser confirm")};void 0;');
  assert(await ev('document.querySelector("button.editTilesets").nextElementSibling.id==="selectionTemplatesTab"'));
  assert(await ev('document.querySelector("#selectionTemplatesTab").textContent.trim()===""'));
  pass('Compact Templates icon follows Tilesets');

  await ev(`(()=>{$('#selectionTemplatesTab').trigger('mouseenter');return true;})()`);
  await until('Array.from(document.querySelectorAll(".tip .text")).some(n=>n.textContent.includes("Templates"))','Templates toolbar tooltip did not appear');
  await ev(`(()=>{$('#selectionTemplatesTab').trigger('mouseleave');return true;})()`);
  pass('Templates toolbar icon exposes the same hover tooltip behavior as native tabs');

  await click('#selectionTemplatesTab');
  await until('document.querySelector(".selectionTemplatesPanel")','Templates native panel did not open');
  await click('button.editEntities');
  await until('document.querySelector(".entityDefs") && !document.querySelector(".selectionTemplatesPanel")','Templates did not swap directly to Entities');
  await click('#selectionTemplatesTab');
  await until('document.querySelector(".selectionTemplatesPanel") && !document.querySelector(".entityDefs")','Entities did not swap directly back to Templates');
  pass('Templates swaps directly with native editor panels without manual closing');
  assert(await ev('document.querySelector(".selectionTemplatesPanel .wrapper").getBoundingClientRect().width<450'),'Templates panel should stay compact and leave the map visible');
  assert(await ev('document.querySelector("#saveSelectionTemplate").disabled'));
  await ev('TemplateTestHooks.selectAll()');
  await until('!document.querySelector("#saveSelectionTemplate").disabled','Save did not enable live');
  await ev('TemplateTestHooks.clear()');
  await until('document.querySelector("#saveSelectionTemplate").disabled','Save did not disable live');
  pass('Save state follows selection changes while the panel stays open');
  require('electron').Menu.setApplicationMenu(null);win.webContents.focus();
  const a=await ev('TemplateTestHooks.point(150,40)'),b=await ev('TemplateTestHooks.point(235,100)');
  const panelRight=await ev('document.querySelector(".selectionTemplatesPanel .wrapper").getBoundingClientRect().right');
  assert(a.x>panelRight && b.x>panelRight,'Live selection regression must exercise the visible map area beside Templates');
  win.webContents.sendInputEvent({type:'keyDown',keyCode:'Alt'});win.webContents.sendInputEvent({type:'keyDown',keyCode:'Shift'});await until('TemplateTestHooks.inputState().alt && TemplateTestHooks.inputState().shift','Modifier keys not delivered');
  win.webContents.sendInputEvent({type:'mouseMove',x:a.x,y:a.y,modifiers:['alt','shift']});await delay(120);await ev(`document.elementFromPoint(${a.x},${a.y})!==null`);
  win.webContents.sendInputEvent({type:'mouseDown',x:a.x,y:a.y,button:'left',clickCount:1,modifiers:['alt','shift']});await until('TemplateTestHooks.inputState().running','Selection drag did not begin');
  win.webContents.sendInputEvent({type:'mouseMove',x:b.x,y:b.y,modifiers:['alt','shift']});await delay(70);
  win.webContents.sendInputEvent({type:'mouseUp',x:b.x,y:b.y,button:'left',clickCount:1,modifiers:['alt','shift']});await until('!TemplateTestHooks.inputState().running','Selection drag did not finish');
  win.webContents.sendInputEvent({type:'keyUp',keyCode:'Shift'});win.webContents.sendInputEvent({type:'keyUp',keyCode:'Alt'});
  await until('!document.querySelector("#saveSelectionTemplate").disabled','Option/Alt+Shift rectangle did not enable Save');
  pass('Actual Option/Alt+Shift mouse rectangle enables Save without closing Templates');
  await ev('TemplateTestHooks.selectAll()');await delay(120);const source=await ev('TemplateTestHooks.source()');
  await click('#saveSelectionTemplate');
  await until('document.querySelector(".selectionTemplateEditor .template-name")','Native template editor did not open');
  await until('document.querySelectorAll(".te-entity").length===3','Preview did not render all entities');
  const navBefore=await ev(`(()=>{const v=document.querySelector('.te-viewport'),s=document.querySelector('.te-stage'),r=v.getBoundingClientRect();return{transform:s.style.transform,left:v.scrollLeft,top:v.scrollTop,cx:r.left+r.width/2,cy:r.top+r.height/2};})()`);
  await ev(`(()=>{const v=document.querySelector('.te-viewport'),r=v.getBoundingClientRect();v.dispatchEvent(new WheelEvent('wheel',{deltaY:-1200,clientX:r.left+r.width/2,clientY:r.top+r.height/2,bubbles:true,cancelable:true}));})()`);
  await delay(80);
  const navZoomed=await ev(`(()=>{const v=document.querySelector('.te-viewport'),s=document.querySelector('.te-stage'),r=v.getBoundingClientRect();return{transform:s.style.transform,cx:r.left+r.width/2,cy:r.top+r.height/2};})()`);
  assert.notStrictEqual(navZoomed.transform,navBefore.transform,'Mouse wheel did not zoom template preview');
  await ev(`(()=>{const v=document.querySelector('.te-viewport'),r=v.getBoundingClientRect(),x=r.left+r.width/2,y=r.top+r.height/2;v.dispatchEvent(new MouseEvent('mousedown',{button:1,clientX:x,clientY:y,bubbles:true,cancelable:true}));document.dispatchEvent(new MouseEvent('mousemove',{clientX:x-70,clientY:y-45,bubbles:true,cancelable:true}));document.dispatchEvent(new MouseEvent('mouseup',{button:1,clientX:x-70,clientY:y-45,bubbles:true,cancelable:true}));})()`);
  await delay(60);
  const navPanned=await ev(`(()=>{const v=document.querySelector('.te-viewport'),s=document.querySelector('.te-stage');return{transform:s.style.transform,panning:v.classList.contains('is-panning')};})()`);
  assert.notStrictEqual(navPanned.transform,navZoomed.transform,'Middle mouse drag did not pan template preview');
  assert.strictEqual(navPanned.panning,false,'Preview stayed in panning state after middle mouse release');
  pass('Template preview supports cursor wheel zoom and middle-mouse panning');
  await edit('.template-name','Draft cancelled');
  await click(`.te-layer[data-uid="${fixture.walls}"]`);
  await ev(`document.querySelectorAll('.te-entity')[2].click()`);await click('.te-remove-entity');
  await click('.selectionTemplateEditor .buttons .cancel');await delay(160);
  assert.strictEqual(await ev('TemplateTestHooks.templates().length'),0);assert.strictEqual(await ev('TemplateTestHooks.source()'),source);
  pass('Create and Cancel use a detached draft and do not change the map');
  await click('#saveSelectionTemplate');await until('document.querySelector(".template-name")','Create dialog did not reopen');await delay(140);
  await edit('.template-name','Generator setup');await click(`.te-layer[data-uid="${fixture.walls}"]`);
  await ev(`Array.from(document.querySelectorAll('.te-entity')).find(n=>n.dataset.key===${JSON.stringify('e:'+fixture.ids[2])}).click()`);await click('.te-remove-entity');
  await click('.te-undo');assert.strictEqual(await ev('document.querySelectorAll(".te-entity").length'),3);await click('.te-redo');assert.strictEqual(await ev('document.querySelectorAll(".te-entity").length'),2);
  await ev(`Array.from(document.querySelectorAll('.te-entity')).find(n=>n.dataset.key===${JSON.stringify('e:'+fixture.ids[0])}).click()`);
  await edit(`.te-field[data-uid="${fixture.fields.amount}"] .te-input`,'23');
  assert(await ev('document.querySelector(".te-tools").getBoundingClientRect().height<70'), 'Editor toolbar should fit on a single row');
  assert(await ev('document.querySelector(".te-field input.te-input").getBoundingClientRect().width>120'), 'Field inputs should have readable width');
  await ev('document.querySelectorAll("#notificationList .notification").forEach(n=>n.remove());void 0');
  fs.writeFileSync(path.join(output,'template-editor.png'),(await win.webContents.capturePage()).toPNG());
  await click('.selectionTemplateEditor .buttons .saveTemplate');
  await until('!document.querySelector(".selectionTemplateEditor")','Saving the new template did not close the editor');
  let saved=await ev('TemplateTestHooks.templates()[0]');assert.strictEqual(saved.name,'Generator setup');assert.strictEqual(saved.entities.length,2);assert(saved.excludedLayerUids.includes(fixture.walls));
  assert.strictEqual(saved.entities[0].json.fieldInstances.find(f=>f.defUid===fixture.fields.amount).__value,23);
  assert.strictEqual(saved.entities[1].refs.find(f=>f.fieldDefUid===fixture.fields.target).values[0],null);
  assert.strictEqual(await ev('TemplateTestHooks.source()'),source);
  const sidecar=path.join(tmp,'test.ldtk-templates.json');
  assert.strictEqual(fs.existsSync(sidecar),false,'Creating/editing a template must not write the library before project Save');
  assert.strictEqual(await ev('TemplateTestHooks.needSaving()'),true,'Template changes should mark the project dirty');
  pass('Template create/edit changes stay staged in memory until the LDtk project is saved');
  pass('Save supports layer exclusion, entity deletion, field editing, reference cleanup, and draft Undo/Redo');
  await ev("Array.from(document.querySelectorAll('.selectionTemplatesPanel button')).find(b=>b.textContent==='Rename').click()");
  await until('document.querySelector(".inputDialog input[type=text]")','Native rename dialog did not open');
  await edit('.inputDialog input[type=text]','Renamed setup');
  await ev("Array.from(document.querySelectorAll('.inputDialog .buttons button')).find(b=>b.textContent==='Validate').click()");await delay(160);
  assert.strictEqual(await ev('TemplateTestHooks.templates()[0].name'),'Renamed setup');pass('Rename uses the supported LDtk dialog, not window.prompt');
  await click('.editTemplate');await until('document.querySelector(".template-name")','Edit dialog did not open');await delay(120);
  const refKey='r:'+JSON.stringify([fixture.ids[0],fixture.fields.target,0]);
  await ev(`Array.from(document.querySelectorAll('.te-links line')).find(n=>n.dataset.key===${JSON.stringify(refKey)}).dispatchEvent(new MouseEvent('click',{bubbles:true}))`);await click('.te-remove-connection');
  await ev(`Array.from(document.querySelectorAll('.te-entity')).find(n=>n.dataset.key===${JSON.stringify('e:'+fixture.ids[0])}).click()`);
  await click(`.te-field[data-uid="${fixture.fields.amount}"] .te-reset`);
  await click(`.te-field[data-uid="${fixture.fields.targets}"] .te-value[data-index="1"] .te-remove-value`);
  await click('.selectionTemplateEditor .buttons .saveTemplate');
  await until('!document.querySelector(".selectionTemplateEditor")','Saving edited template did not close the editor');
  saved=await ev('TemplateTestHooks.templates()[0]');assert.strictEqual(saved.entities[0].refs.find(f=>f.fieldDefUid===fixture.fields.target).values[0],null);assert.strictEqual(saved.entities[0].json.fieldInstances.find(f=>f.defUid===fixture.fields.amount).realEditorValues[0],null);
  pass('Existing templates can remove a selected connection and reset a field value');
  await click('.editTemplate');await until('document.querySelector(".template-name")','Edit did not open');
  await click(`.te-layer[data-uid="${fixture.walls}"]`);await click('.selectionTemplateEditor .buttons .saveTemplate');
  await until('!document.querySelector(".selectionTemplateEditor")','Re-including layer did not close the editor');
  assert(!(await ev('TemplateTestHooks.templates()[0].excludedLayerUids')).includes(fixture.walls));
  await click('.editTemplate');await until('document.querySelector(".template-name")','Edit did not reopen');
  await click(`.te-layer[data-uid="${fixture.walls}"]`);await click('.selectionTemplateEditor .buttons .saveTemplate');
  await until('!document.querySelector(".selectionTemplateEditor")','Excluding layer did not close the editor');
  assert((await ev('TemplateTestHooks.templates()[0].excludedLayerUids')).includes(fixture.walls));
  pass('Saved templates can re-include and exclude entire layers without recreating the template');
  await until('!document.querySelector(".selectionTemplateEditor")','Editor dialog did not close');

  const occupiedBefore=await ev('TemplateTestHooks.overwriteGridState()');
  assert.strictEqual(occupiedBefore.intGrid,1);
  assert.deepStrictEqual(occupiedBefore.tiles,[{tileId:90,flips:0},{tileId:91,flips:0}]);
  assert.strictEqual(await ev('TemplateTestHooks.placeOverwriteFixture()'),true,'Template should place over occupied grid cells');
  const occupiedAfter=await ev('TemplateTestHooks.overwriteGridState()');
  assert.strictEqual(occupiedAfter.intGrid,2,'Occupied IntGrid value was not replaced');
  assert.deepStrictEqual(occupiedAfter.tiles,[{tileId:7,flips:1},{tileId:8,flips:2}],'Occupied tile stack was merged instead of replaced');
  await ev('TemplateTestHooks.undo()');
  assert.deepStrictEqual(await ev('TemplateTestHooks.overwriteGridState()'),occupiedBefore,'Undo did not restore overwritten grid contents');
  await delay(200); // allow LayerInstancesRestoredFromHistory end-of-frame cleanup to settle before activating another special tool
  pass('Template placement replaces occupied IntGrid values and entire Tiles stacks');

  const walls=await ev('TemplateTestHooks.wallState()');
  await ev('TemplateTestHooks.clear()');
  await ev("Array.from(document.querySelectorAll('.selectionTemplatesPanel button')).find(b=>b.textContent==='Place').click()");
  await until('TemplateTestHooks.inputState().placing','Place tool did not activate');
  try{
    await until('TemplateTestHooks.templateGhostStats()!=null && TemplateTestHooks.templateGhostStats().entities===2 && TemplateTestHooks.templateGhostStats().childCount>0','Placement preview did not build the real entity graphics');
  }catch(e){
    console.error('Template placement ghost stats:',await ev('TemplateTestHooks.templateGhostStats()'));
    throw e;
  }
  const ghostStats=await ev('TemplateTestHooks.templateGhostStats()');
  pass('Placement preview uses real rendered template graphics instead of size-only boxes');
  const target=await ev('TemplateTestHooks.point(272,176)');
  win.webContents.sendInputEvent({type:'mouseMove',x:target.x,y:target.y});await delay(120);await until(`document.elementFromPoint(${target.x},${target.y}).id==='webgl'`,'Map is covered by a dialog');
  fs.writeFileSync(path.join(output,'placement-real-ghost.png'),(await win.webContents.capturePage()).toPNG());
  const placed=await ev('TemplateTestHooks.commitActiveTemplateAt(272,176)');
  assert.strictEqual(placed,true,'Active SelectionTemplateTool did not commit placement');
  await until('TemplateTestHooks.entityCount()===5','Placement did not finish');
  await until('!TemplateTestHooks.inputState().placing && TemplateTestHooks.inputState().selectedCount>=2','Placed template was not handed back as a normal selection');
  assert.strictEqual(await ev('TemplateTestHooks.wallState()'),walls);
  assert.strictEqual(await ev('TemplateTestHooks.entityCount()'),5);
  const refs=await ev('TemplateTestHooks.references()');for(const e of refs.filter(e=>!fixture.ids.includes(e.id)))for(const ref of e.refs){assert(ref.resolved);assert(!fixture.ids.includes(ref.id));}
  const placedPositions=await ev('TemplateTestHooks.selectedEntityPositions()');
  assert.strictEqual(placedPositions.length,2,'Placed entities were not all selected');
  const anchor=await ev('TemplateTestHooks.selectionAnchor()');
  assert(anchor,'Placed selection has no draggable entity anchor');
  win.webContents.sendInputEvent({type:'mouseMove',x:anchor.x,y:anchor.y});await delay(80);
  win.webContents.sendInputEvent({type:'mouseDown',x:anchor.x,y:anchor.y,button:'left',clickCount:1});
  win.webContents.sendInputEvent({type:'mouseMove',x:anchor.x+44,y:anchor.y+28});await delay(80);
  win.webContents.sendInputEvent({type:'mouseUp',x:anchor.x+44,y:anchor.y+28,button:'left',clickCount:1});
  await until('JSON.stringify(TemplateTestHooks.selectedEntityPositions())!=='+JSON.stringify(JSON.stringify(placedPositions)),'Auto-selected template could not be dragged as a group');
  const movedPositions=await ev('TemplateTestHooks.selectedEntityPositions()');
  const deltas=movedPositions.map((p,i)=>({x:p.x-placedPositions[i].x,y:p.y-placedPositions[i].y}));
  assert(deltas.every(d=>d.x===deltas[0].x&&d.y===deltas[0].y),'Placed entities did not move together');
  assert(deltas[0].x!==0||deltas[0].y!==0,'Placed group drag produced no movement');
  pass('Placement exits stamp mode and auto-selects the whole template for immediate grouped movement');
  await ev('TemplateTestHooks.undo()');
  assert.strictEqual(await ev('TemplateTestHooks.entityCount()'),5,'First Undo should revert only the grouped movement, not the placement');
  await ev('TemplateTestHooks.undo()');assert.strictEqual(await ev('TemplateTestHooks.entityCount()'),3);
  await ev('TemplateTestHooks.redo()');assert.strictEqual(await ev('TemplateTestHooks.entityCount()'),5);assert.strictEqual(await ev('TemplateTestHooks.wallState()'),walls);
  pass('Placement preserves excluded walls, resolves references to new copies, and keeps movement/placement Undo separate');
  assert.strictEqual(fs.existsSync(sidecar),false,'Template library was written before explicit project Save');
  await ev('TemplateTestHooks.saveProject()');
  await until('!TemplateTestHooks.saveInProgress() && !TemplateTestHooks.needSaving()','Project Save did not finish');
  let disk=JSON.parse(fs.readFileSync(sidecar,'utf8'));
  assert.strictEqual(disk.templates.length,1);
  assert.strictEqual(disk.templates[0].name,'Renamed setup');
  pass('Normal LDtk project Save persists the staged template library');

  const persistedId=disk.templates[0].id;
  await ev(`TemplateTestHooks.deleteTemplate(${JSON.stringify(persistedId)})`);
  assert.strictEqual((await ev('TemplateTestHooks.templates()')).length,0,'Staged delete did not remove the template in memory');
  let diskAfterUnsavedDelete=JSON.parse(fs.readFileSync(sidecar,'utf8'));
  assert.strictEqual(diskAfterUnsavedDelete.templates.length,1,'Deleting without project Save changed the saved template library');
  await ev('TemplateTestHooks.reloadTemplateStage()');
  assert.strictEqual((await ev('TemplateTestHooks.templates()')).length,1,'Reloading saved template state did not restore an unsaved deletion');
  pass('Unsaved template deletion is discarded because disk changes only on project Save');

  const sourceProject=path.join(tmp,'other-project.ldtk');
  const importSetup=await ev('TemplateTestHooks.configureImportTileset()');
  const sourceJson=JSON.parse(fs.readFileSync(path.join(tmp,'test.ldtk'),'utf8'));
  sourceJson.defs.tilesets.push({uid:importSetup.tileset,identifier:'FloorTiles'});
  const diskFloor=sourceJson.defs.layers.find(ld=>ld.uid===fixture.floor);
  assert(diskFloor,'Saved fixture lost the Floor definition');
  diskFloor.tilesetDefUid=importSetup.tileset;
  const layerUidMap=new Map(),entityUidMap=new Map(),fieldUidMap=new Map(),tilesetUidMap=new Map();
  for(const [i,td] of sourceJson.defs.tilesets.entries()){const old=td.uid,next=40000+i;tilesetUidMap.set(old,next);td.uid=next;}
  for(const [i,ld] of sourceJson.defs.layers.entries()){const old=ld.uid,next=10000+i;layerUidMap.set(old,next);ld.uid=next;}
  for(const [i,ed] of sourceJson.defs.entities.entries()){
    const old=ed.uid,next=20000+i;entityUidMap.set(old,next);ed.uid=next;
    for(const [j,fd] of ed.fieldDefs.entries()){const fOld=fd.uid,fNext=30000+i*100+j;fieldUidMap.set(fOld,fNext);fd.uid=fNext;}
  }
  for(const ld of sourceJson.defs.layers){
    if(ld.tilesetDefUid!=null)ld.tilesetDefUid=tilesetUidMap.get(ld.tilesetDefUid)??ld.tilesetDefUid;
    if(ld.autoSourceLayerDefUid!=null)ld.autoSourceLayerDefUid=layerUidMap.get(ld.autoSourceLayerDefUid)??ld.autoSourceLayerDefUid;
  }
  for(const ed of sourceJson.defs.entities){
    if(ed.tilesetId!=null)ed.tilesetId=tilesetUidMap.get(ed.tilesetId)??ed.tilesetId;
    if(ed.tileRect&&ed.tileRect.tilesetUid!=null)ed.tileRect.tilesetUid=tilesetUidMap.get(ed.tileRect.tilesetUid)??ed.tileRect.tilesetUid;
    for(const fd of ed.fieldDefs){
      if(fd.tilesetUid!=null)fd.tilesetUid=tilesetUidMap.get(fd.tilesetUid)??fd.tilesetUid;
      if(fd.allowedRefsEntityUid!=null)fd.allowedRefsEntityUid=entityUidMap.get(fd.allowedRefsEntityUid)??fd.allowedRefsEntityUid;
    }
  }
  assert.notStrictEqual(layerUidMap.get(fixture.floor),fixture.floor,'Cross-project fixture must use a different layer UID');
  assert.notStrictEqual(entityUidMap.get(fixture.entityDef),fixture.entityDef,'Cross-project fixture must use a different entity UID');
  assert.notStrictEqual(tilesetUidMap.get(importSetup.tileset),importSetup.tileset,'Cross-project fixture must use a different tileset UID');
  const sourceFloor=sourceJson.defs.layers.find(ld=>ld.uid===layerUidMap.get(fixture.floor));
  assert(sourceFloor,'Source fixture lost the Floor layer');
  sourceFloor.identifier='ImportedFloorAlias';
  fs.writeFileSync(sourceProject,JSON.stringify(sourceJson,null,2));

  const baseTemplate=JSON.parse(JSON.stringify(disk.templates[0]));
  const remapTemplateToSource=input=>{
    const t=JSON.parse(JSON.stringify(input));
    t.excludedLayerUids=(t.excludedLayerUids||[]).map(uid=>layerUidMap.get(uid)??uid);
    for(const e of t.entities||[]){
      e.layerDefUid=layerUidMap.get(e.layerDefUid)??e.layerDefUid;
      e.json.defUid=entityUidMap.get(e.json.defUid)??e.json.defUid;
      for(const fi of e.json.fieldInstances||[])fi.defUid=fieldUidMap.get(fi.defUid)??fi.defUid;
      for(const ref of e.refs||[])ref.fieldDefUid=fieldUidMap.get(ref.fieldDefUid)??ref.fieldDefUid;
      for(const point of e.points||[])point.fieldDefUid=fieldUidMap.get(point.fieldDefUid)??point.fieldDefUid;
    }
    for(const c of t.cells||[])c.layerDefUid=layerUidMap.get(c.layerDefUid)??c.layerDefUid;
    return t;
  };
  const importTemplates=['src-a','src-b','src-c'].map((id,i)=>{const t=remapTemplateToSource(baseTemplate);t.id=id;t.name='Imported '+String.fromCharCode(65+i);return t;});
  importTemplates[0].cells.push({kind:'tiles',layerDefUid:layerUidMap.get(fixture.floor),gridSize:16,relX:0,relY:0,tiles:[{tileId:7,flips:0}]});
  fs.writeFileSync(sourceProject+'-templates.json',JSON.stringify({format:1,projectIid:'other-project',templates:importTemplates},null,2));
  const remapA=await ev(`TemplateTestHooks.debugImportRemap(${JSON.stringify(sourceProject)},0)`);
  assert(remapA.ok,'Imported A remap failed before picker: '+remapA.error);
  const remapC=await ev(`TemplateTestHooks.debugImportRemap(${JSON.stringify(sourceProject)},2)`);
  assert(remapC.ok,'Imported C remap failed before picker: '+remapC.error);
  await ev(`TemplateTestHooks.openImportPicker(${JSON.stringify(sourceProject)})`);
  await until('document.querySelector(".selectionTemplateImportPicker")','Selective template import picker did not open');
  assert.strictEqual(await ev('document.querySelectorAll(".selectionTemplateImportPicker input[type=checkbox]").length'),3);
  await ev(`Array.from(document.querySelectorAll('.selectionTemplateImportPicker button')).find(b=>b.textContent==='Select none').click()`);
  await ev(`(()=>{for(const id of ['src-a','src-c']){const e=document.querySelector('.selectionTemplateImportPicker input[data-template-id="'+id+'"]');e.checked=true;e.dispatchEvent(new Event('change',{bubbles:true}));}return true;})()`);
  assert(await ev(`Array.from(document.querySelectorAll('.selectionTemplateImportPicker button')).some(b=>b.textContent.includes('Import 2 selected templates'))`));
  await ev(`Array.from(document.querySelectorAll('.selectionTemplateImportPicker button')).find(b=>b.textContent.includes('Import 2 selected templates')).click()`);
  await until('!document.querySelector(".selectionTemplateImportPicker")','Selective import picker did not close');
  const stagedAfterImport=await ev('TemplateTestHooks.templates()');
  assert.strictEqual(stagedAfterImport.length,3);
  assert(stagedAfterImport.some(t=>t.name==='Imported A'));
  assert(stagedAfterImport.some(t=>t.name==='Imported C'));
  assert(!stagedAfterImport.some(t=>t.name==='Imported B'));
  assert(!stagedAfterImport.some(t=>t.id==='src-a'||t.id==='src-c'),'Imported templates did not receive fresh template IDs');

  const importedA=stagedAfterImport.find(t=>t.name==='Imported A');
  assert(importedA,'Imported A is missing');
  assert(importedA.entities.every(e=>fixture.layers.includes(e.layerDefUid)),'Imported entity layers kept source UIDs');
  assert(importedA.entities.every(e=>e.json.defUid===fixture.entityDef),'Imported entity definitions kept source UIDs');
  const destinationFieldUids=new Set(Object.values(fixture.fields));
  for(const e of importedA.entities){
    for(const fi of e.json.fieldInstances||[])assert(destinationFieldUids.has(fi.defUid),'Imported field instance kept a source UID');
    for(const ref of e.refs||[])assert(destinationFieldUids.has(ref.fieldDefUid),'Imported EntityRef kept a source field UID');
    for(const point of e.points||[])assert(destinationFieldUids.has(point.fieldDefUid),'Imported Point kept a source field UID');
  }
  const importedFloor=importedA.cells.find(c=>c.kind==='tiles');
  assert(importedFloor,'Cross-project fixture lost its tile cell');
  assert.strictEqual(importedFloor.layerDefUid,fixture.floor,'Renamed source Tiles layer was not resolved through the matching tileset');
  assert(importedA.excludedLayerUids.includes(fixture.walls),'Excluded layer UIDs were not remapped');
  const importedIndex=stagedAfterImport.findIndex(t=>t.name==='Imported A');
  const countBeforeImportedPlacement=await ev('TemplateTestHooks.entityCount()');
  assert.strictEqual(await ev(`TemplateTestHooks.place(${importedIndex},32,160)`),true,'Remapped imported template could not be placed');
  assert.strictEqual(await ev('TemplateTestHooks.entityCount()'),countBeforeImportedPlacement+importedA.entities.length,'Imported template placement did not create all remapped entities');
  pass('Cross-project import remaps entity, field, layer, excluded-layer and tileset-backed layer definitions before placement');

  assert.strictEqual(JSON.parse(fs.readFileSync(sidecar,'utf8')).templates.length,1,'Selective import wrote to disk before project Save');
  pass('Import picker clones only checked templates with fresh IDs and stages them until project Save');

  await delay(180);
  await ev('TemplateTestHooks.saveProject()');
  await until('TemplateTestHooks.saveDidComplete()','Project Save after import callback did not finish');
  assert.strictEqual(await ev('TemplateTestHooks.needSaving()'),false,'Project remained dirty after saving imported templates');
  disk=JSON.parse(fs.readFileSync(sidecar,'utf8'));
  assert.strictEqual(disk.templates.length,3);
  assert(disk.templates.some(t=>t.name==='Imported A')&&disk.templates.some(t=>t.name==='Imported C')&&!disk.templates.some(t=>t.name==='Imported B'));
  pass('Selected imported templates persist only when the destination LDtk project is saved');

  fs.writeFileSync(path.join(output,'results.json'),JSON.stringify({passed,platform:process.platform,electron:process.versions.electron},null,2));
  console.log(`SUCCESS: ${passed.length} template integration scenarios passed`);clearTimeout(timer);app.exit(0);
}
require('../assets/main.js');
