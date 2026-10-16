(() => {
 const H=__ldtk, C=H.classes, E=H.enums, Coords=C['misc.Coords'];
 const F=window.entityHistoryFixture={};
 F.setup=function(path=F.path){
  if(!path)throw Error('A temporary fixture path is required');
  F.path=path;
  H.App.ME.settings.v.openLastProject=false;
  const p=H.Project.createEmpty(path);
  const ld=p.defs.createLayerDef(E['ldtk.LayerType'].Entities,'Entities');ld.gridSize=16;ld.canSelectWhenInactive=true;
  const ig=p.defs.createLayerDef(E['ldtk.LayerType'].IntGrid,'Sentinels');ig.gridSize=16;
  ig.intGridValues=[{value:1,identifier:'Keep',color:0x444444,tile:null,groupUid:0}];
  const ed=p.defs.createEntityDef();ed.set_identifier('Marker');ed.width=ed.height=16;ed.setPivot(0,0);
  const fd=ed.createFieldDef(p,E['ldtk.FieldType'].F_Int,'Value',false);
  const ref=ed.createFieldDef(p,E['ldtk.FieldType'].F_EntityRef,'Link',false);ref.canBeNull=true;
  const w=p.worlds[0],a=w.levels[0],b=w.createLevel();
  a.set_identifier('Level_A');b.set_identifier('Level_B');
  a.pxWid=b.pxWid=640;a.pxHei=b.pxHei=384;a.worldX=0;a.worldY=0;b.worldX=704;b.worldY=0;
  p.tidy();
  for(const l of [a,b]){
   const ei=l.getLayerInstance(ld.uid).createEntityInstance(ed);ei.x=64;ei.y=64;ei.tidy(p,ei._li);
   ei.getFieldInstance(fd,true).parseValue(0,'7');l.getLayerInstance(ig.uid).setIntGrid(2,2,1,false);
  }
  p.tidy();require('fs').writeFileSync(path,JSON.stringify(p.toJson()));
  H.App.ME.loadPage(()=>new H.Editor(p),false);
  const e=H.Editor.ME;e.setWorldMode(false);e.selectLevel(a);e.selectLayerInstance(a.getLayerInstance(ld.uid));e.camera.fit(true);
  Object.assign(F,{a:a.uid,b:b.uid,ld:ld.uid,fd:fd.uid,ref:ref.uid,ed:ed.uid,ig:ig.uid});
  return F.state();
 };
 // Disposing the previous editor is deferred. Resolve the live page before
 // every operation, just like SelectionDragTestHooks.editor().
 F.editor=()=>{const e=H.App.ME.curPageProcess;if(e&&e.project&&!e.destroyed)H.Editor.ME=e;return H.Editor.ME;};
 F.level=id=>F.editor().project.quickLevelAccessUid.h[id];
 F.entity=id=>F.level(id).getLayerInstance(F.ld).entityInstances[0];
 F.switch=id=>{F.editor().selectLevel(F.level(id));return F.state();};
 F.state=()=>{
  const e=F.editor(),t=e.selectionTool;
  return {active:e.curLevelId,selectionRunning:t.curMode!=null,moveStarted:t.moveStarted,lastDrop:t.group.lastDropTargetLevel?.uid,
   timelines:Object.fromEntries(Object.entries(e.levelTimelines.h).map(([id,tl])=>[id,{idx:tl.curStateIdx,states:tl.states.filter(Boolean).length}])),
   levels:[F.a,F.b].map(id=>{const l=F.level(id);return {id,sentinel:l.getLayerInstance(F.ig).getIntGrid(2,2),entities:l.getLayerInstance(F.ld).entityInstances.map(ei=>({iid:ei.iid,owner:ei._li.levelId,x:ei.x,y:ei.y,value:ei.getFieldInstance(e.project.defs.getFieldDef(F.fd),true).getInt(0)}))};})};
 };
 F.drag=(targetId=F.a)=>{
  const e=F.editor(),src=F.level(e.curLevelId),target=F.level(targetId),ei=src.getLayerInstance(F.ld).entityInstances[0],t=e.selectionTool;
  const o=Coords.fromLevelCoords(ei.x+2,ei.y+2),d=Coords.fromWorldCoords(target.worldX+146,target.worldY+66);
  t.selectAndStartUsing({button:0,cancel:false},o,E.GenericLevelElement.Entity(ei._li,ei));
  t.onMouseMove({button:0,cancel:false},d);t.stopUsing(d);
  return F.state();
 };
 F.click=id=>{
  const e=F.editor(),ei=F.entity(id),m=Coords.fromLevelCoords(ei.x+2,ei.y+2);
  e.get_curTool().startUsing({button:0,cancel:false},m);
  e.selectionTool.stopUsing(m);
  return F.state();
 };
 F.edit=(id,value)=>{
  const e=F.editor(),ei=F.entity(id),panel=C['ui.EntityInstanceEditor'].openFor(ei);
  ei.getFieldInstance(e.project.defs.getFieldDef(F.fd),true).parseValue(0,String(value));
  panel.onEntityFieldChanged();return F.state();
 };
 F.idleStop=()=>{const e=F.editor();e.selectionTool.stopUsing(Coords.fromLevelCoords(66,66));return F.state();};
 F.undo=()=>{const e=F.editor();return e.levelTimelines.h[e.curLevelId].undo();};
 F.redo=()=>{const e=F.editor();return e.levelTimelines.h[e.curLevelId].redo();};
 F.emptySave=()=>{const e=F.editor(),t=e.levelTimelines.h[e.curLevelId];t.saveLayerStates([]);t.saveLayerStates([null]);t.saveLayerStates(null);t.saveLayerState(null);return F.state();};
 F.newHistory=()=>{
  const e=F.editor(),l=F.level(e.curLevelId),t=new H.Timeline(l.uid,l._world.iid,false);
  t.saveLayerStates([l.getLayerInstance(F.ld)]);
  return {index:t.curStateIdx,undo:t.undo(),full:!!t.states[t.curStateIdx].fullLevelJson,layers:Object.keys(t.states[t.curStateIdx].layerJsons.h).length,expected:l.layerInstances.length};
 };
 F.cancel=()=>{
  const e=F.editor(),ei=F.entity(e.curLevelId),t=e.selectionTool,o=Coords.fromLevelCoords(ei.x+2,ei.y+2),d=Coords.fromLevelCoords(ei.x+82,ei.y+2);
  t.selectAndStartUsing({button:0,cancel:false},o,E.GenericLevelElement.Entity(ei._li,ei));
  t.onMouseMove({button:0,cancel:false},d);t.clear();t.stopUsing(d);return F.state();
 };
 F.link=()=>{
  const e=F.editor(),a=F.entity(F.a),b=F.entity(F.b);
  a.getFieldInstance(e.project.defs.getFieldDef(F.ref),true).setEntityRefTo(0,a,b);
  e.levelTimelines.h[F.a].saveLayerStates([a._li]);
  return {source:a.iid,target:b.iid};
 };
 F.reload=()=>{
  const e=F.editor(),path=e.project.filePath.get_full(),json=e.project.toJson();
  require('fs').writeFileSync(path,JSON.stringify(json));
  const p=H.Project.fromJson(path,JSON.parse(require('fs').readFileSync(path,'utf8')));p.tidy();
  H.App.ME.loadPage(()=>new H.Editor(p),false);
  const n=F.editor();n.setWorldMode(false);n.selectLayerInstance(F.level(n.curLevelId).getLayerInstance(F.ld));
  return F.state();
 };
 F.linkState=()=>{
  const e=F.editor();return [F.a,F.b].flatMap(id=>F.level(id).getLayerInstance(F.ld).entityInstances.map(ei=>({iid:ei.iid,owner:ei._li.levelId,ref:ei.getFieldInstance(e.project.defs.getFieldDef(F.ref),true).getEntityRefIid(0)})));
 };
 return true;
})()
