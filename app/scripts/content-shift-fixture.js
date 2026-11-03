(() => {
 'use strict';
 const H=__ldtk, C=H.classes, E=H.enums, fs=require('fs'), path=require('path');
 const F=window.contentShiftFixture={};
 F.editor=()=>{
  const e=H.App.ME.curPageProcess;
  if(e && e.project && !e.destroyed) H.Editor.ME=e;
  return H.Editor.ME;
 };
 F.level=()=>F.editor().project.getLevelAnywhere(null,F.iid);
 F.timeline=()=>F.editor().levelTimelines.h[F.level().uid];
 F.state=(iid=F.iid)=>{
  const l=F.editor().project.getLevelAnywhere(null,iid);
  if(!l) return null;
  const li=l.getLayerInstance(F.layerUid);
  const ei=li && li.entityInstances[0];
  return {
   iid:l.iid, worldX:l.worldX,worldY:l.worldY,width:l.pxWid,height:l.pxHei,
   shift:[l.contentShiftX,l.contentShiftY],
   anchor:[l.worldX-l.contentShiftX,l.worldY-l.contentShiftY],
   entityWorld:ei ? [l.worldX+li.get_pxTotalOffsetX()+ei.x,l.worldY+li.get_pxTotalOffsetY()+ei.y] : null,
   entityLocal:ei ? [ei.x,ei.y] : null
  };
 };
 F.setup=(file, external=false)=>{
  H.App.ME.settings.v.openLastProject=false;
  const p=H.Project.createEmpty(file);
  p.externalLevels=external;
  const layer=p.defs.createLayerDef(E['ldtk.LayerType'].Entities,'MarkerLayer');
  layer.gridSize=16;
  const ed=p.defs.createEntityDef();
  ed.set_identifier('AnchorMarker');ed.width=ed.height=16;ed.setPivot(0,0);
  const l=p.worlds[0].levels[0];
  l.worldX=1000;l.worldY=500;l.pxWid=512;l.pxHei=256;
  p.tidy();
  const ei=l.getLayerInstance(layer.uid).createEntityInstance(ed);
  ei.x=100;ei.y=100;
  p.tidy();
  F.iid=l.iid;F.layerUid=layer.uid;F.path=file;F.external=external;
  p.forkConfig.save();
  H.App.ME.loadPage(()=>new H.Editor(p),false);
  const e=F.editor();
  e.setWorldMode(false);
  e.selectLevel(F.level());
  e.selectLayerInstance(F.level().getLayerInstance(layer.uid));
  F.timeline().clear(true);
  F.save();
  return F.state();
 };
 F.resize=(left,top,w,h)=>{
  const l=F.level();
  l.worldX+=left;l.worldY+=top;
  l.applyNewBounds(left,top,w,h);
  F.editor().invalidateLevelCache(l);
  F.timeline().saveFullLevelState();
  return F.state();
 };
 F.move=(x,y)=>{
  const l=F.level();
  l.worldX+=x;l.worldY+=y;
  F.editor().invalidateLevelCache(l);
  return F.state();
 };
 F.undo=()=>{const done=F.timeline().undo();return {done,state:F.state()};};
 F.redo=()=>{const done=F.timeline().redo();return {done,state:F.state()};};
 F.settingsResize=(w,h)=>{
  const l=F.level();l.applyNewBounds(0,0,w,h);
  F.editor().invalidateLevelCache(l);
  F.timeline().saveFullLevelState();
  return F.state();
 };
 F.duplicate=()=>{
  const copy=F.level()._world.duplicateLevel(F.level());
  F.editor().invalidateLevelCache(copy);
  return F.state(copy.iid);
 };
 F.save=()=>{
  const p=F.editor().project;
  // Mirror production: prepare all cached level data, sidecar first, then
  // primary LDtk and external level files, never a sidecar key in either.
  for(const w of p.worlds)for(const l of w.levels){l.invalidateJsonCache();l.rebuildCache();}
  p.forkConfig.save();
  const data=C['ui.ProjectSaver'].prepareProjectSavingData(p);
  fs.writeFileSync(F.path,data.projectJsonStr,'utf8');
  for(const item of data.externLevels){
   const dest=p.makeAbsoluteFilePath(item.relPath);
   fs.mkdirSync(path.dirname(dest),{recursive:true});
   fs.writeFileSync(dest,item.jsonStr,'utf8');
  }
  return {sidecar:fs.readFileSync(p.forkConfig.getPath(),'utf8'),
   project:fs.readFileSync(F.path,'utf8'),
   externalFiles:data.externLevels.map(item=>fs.readFileSync(p.makeAbsoluteFilePath(item.relPath),'utf8'))};
 };
 F.sidecar=()=>fs.readFileSync(F.editor().project.forkConfig.getPath(),'utf8');
 F.reopen=()=>{
  const p=H.Project.fromJson(F.path,JSON.parse(fs.readFileSync(F.path,'utf8')));
  p.forkConfig.load();
  p.tidy();
  H.App.ME.loadPage(()=>new H.Editor(p),false);
  F.editor().setWorldMode(false);
  return F.state();
 };
 F.beginLoader=()=>{
  F.loadedProject=null;F.loadError=null;
  new C['ui.ProjectLoader'](F.path,p=>{F.loadedProject=p;},err=>{F.loadError=String(err);},true);
  return true;
 };
 F.loadedState=()=>{
  if(!F.loadedProject)return null;
  const l=F.loadedProject.getLevelAnywhere(null,F.iid);
  if(!l)return {missing:true};
  const li=l.getLayerInstance(F.layerUid),ei=li.entityInstances[0];
  return {shift:[l.contentShiftX,l.contentShiftY],
   anchor:[l.worldX-l.contentShiftX,l.worldY-l.contentShiftY],
   entityWorld:[l.worldX+li.get_pxTotalOffsetX()+ei.x,l.worldY+li.get_pxTotalOffsetY()+ei.y]};
 };
 F.deleteUndo=()=>{
  const e=F.editor(),l=F.level(),w=l._world;
  const replacement=w.createLevel();
  e.ge.emit(E['GlobalEvent'].LevelAdded(replacement));
  // Unlike LDtk project JSON, LastChance has to snapshot contentShift
  // alongside its JSON snapshot.
  new C['ui.LastChance']('Level removed',e.project);
  e.selectLevel(replacement);
  w.removeLevel(l);
  e.ge.emit(E['GlobalEvent'].LevelRemoved(l));
  // Simulate saving after deletion and before invoking Last Chance Undo:
  // the old IID is no longer present in the sidecar on disk.
  F.save();
  const action=document.querySelector('.lastChance button');
  if(!action)throw Error('Last Chance Undo button missing');
  action.click();
  const restored=F.state();
  return {restored, currentLevelIids:e.project.worlds.flatMap(w2=>w2.levels.map(lv=>lv.iid)),
   activeLevel:e.curLevelId,undoButtonStillInDom:action.isConnected};
 };
 F.delete=()=>{
  const e=F.editor(),l=F.level(),w=l._world;
  const other=w.createLevel(),oldIID=l.iid;
  // Mirror the real world-panel deletion: register the replacement, select it,
  // remove the old level and emit removal to clean the rendered world cache.
  e.ge.emit(E['GlobalEvent'].LevelAdded(other));
  e.selectLevel(other);
  w.removeLevel(l);
  e.ge.emit(E['GlobalEvent'].LevelRemoved(l));
  e.setWorldMode(true);
  return {removed:!e.project.getLevelAnywhere(null,oldIID),iid:oldIID};
 };
 return true;
})()
