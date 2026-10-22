(() => {
 const H=__ldtk,C=H.classes,E=H.enums,FT=E['ldtk.FieldType'],GE=E.GenericLevelElement,Events=E.GlobalEvent;
 const Coords=C['misc.Coords'],fs=require('fs');
 const F=window.pathPreviewFixture={};
 F.editor=()=>{const e=H.App.ME.curPageProcess;if(e&&e.project&&!e.destroyed)H.Editor.ME=e;return H.Editor.ME;};
 F.level=()=>F.editor().project.quickLevelAccessUid.h[F.levelId];
 F.entity=()=>F.editor().project.getEntityInstanceByIid(F.iid)||F.drag?.source;
 F.field=name=>{const ei=F.entity();return ei.getFieldInstance(ei.get_def().getFieldDef(F.fields[name]),true);};
 F.loadEditor=p=>{
  H.App.ME.clearCurPage();C['dn.Process'].forceProcessGarbageCollection();
  H.App.ME.loadPage(()=>new H.Editor(p),false);
  const e=F.editor();e.setWorldMode(false);e.selectLevel(F.level());e.selectLayerInstance(F.level().getLayerInstance(F.layer));e.camera.fit(true);
  H.EntityTool.PREV_CHAINABLE_EI=null;e.get_curTool().selectValue(F.entity().defUid);
 };
 F.setup=file=>{
  H.App.ME.settings.v.openLastProject=false;
  const p=H.Project.createEmpty(file),ld=p.defs.createLayerDef(E['ldtk.LayerType'].Entities,'Cargo');ld.gridSize=16;ld.canSelectWhenInactive=true;
  const sentinel=p.defs.createLayerDef(E['ldtk.LayerType'].IntGrid,'Untouched');sentinel.gridSize=16;
  sentinel.intGridValues=[{value:1,identifier:'Keep',color:0x444444,tile:null,groupUid:0}];
  p.nextUid=4007;
  const mode=p.defs.createEnumDef();mode.set_identifier('CargoLineMode');
  for(const name of ['Loop','Teleport','PingPong','Circuit','Warp','Bounce'])mode.addValue(name);
  const ed=p.defs.createEntityDef();ed.set_identifier('CargoLine');ed.width=ed.height=16;ed.setPivot(.5,.5);ed.color=0xe8a33d;
  const fields={};
  const add=(name,type,initial,array=false)=>{const fd=ed.createFieldDef(p,type,name,array);fd.set_identifier(name);fields[name]=fd.uid;if(initial!==null)fd.setDefault(String(initial));return fd;};
  const path=add('Path',FT.F_Point,null,true);path.editorDisplayMode=E['ldtk.FieldDisplayMode'].PointPath;path.editorAlwaysShow=true;
  add('Mode',FT.F_Enum(mode.uid),'Loop');add('BlockCount',FT.F_Int,4);add('BlockWidth',FT.F_Int,3);add('BlockHeight',FT.F_Int,1);
  add('Gap',FT.F_Float,2);add('EvenSpacing',FT.F_Bool,false);add('Speed',FT.F_Float,2);add('StartOffset',FT.F_Float,0);
  const level=p.worlds[0].levels[0];level.set_identifier('CargoPreview');level.pxWid=640;level.pxHei=384;p.tidy();
  const li=level.getLayerInstance(ld.uid),ei=li.createEntityInstance(ed);ei.x=104;ei.y=104;ei.tidy(p,li);
  const fi=ei.getFieldInstance(path,true);for(const pt of [[16,6],[16,10],[6,10]]){fi.addArrayValue();fi.parseValue(fi.getArrayLength()-1,pt.join(','));}
  level.getLayerInstance(sentinel.uid).setIntGrid(30,18,1,false);p.tidy();
  const binding=name=>({fieldUid:fields[name],fieldIdentifier:name});
  const config={_note:'Preserve exact game-authored configuration',path:binding('Path'),mode:{...binding('Mode'),loopValue:'Loop',teleportValue:'Teleport',pingPongValue:'PingPong'},
   blockCount:binding('BlockCount'),blockWidth:binding('BlockWidth'),blockHeight:binding('BlockHeight'),gap:binding('Gap'),evenSpacing:binding('EvenSpacing'),startOffset:binding('StartOffset'),
   unitPx:16,blockColor:'#E8A33D',overlapColor:'#FF3030',futureNested:{keep:[1,{tag:'game-owned'}]}};
  const sidecar={format:1,projectIid:p.iid,gameMetadata:{revision:7,keep:['one','two']},entities:{[ed.uid]:{
   identifier:ed.identifier,autoChildren:[],appearanceOverrides:[],tileStamps:[],fields:{[path.uid]:{identifier:'Path',foreignField:{keep:true}}},
   gameOnly:{nested:['untouched']},pathPreview:config},87654321:{identifier:'MissingGameToolEntity',unknown:{preserve:true}}}};
  Object.assign(F,{file,fields,iid:ei.iid,entityDef:ed.uid,layer:ld.uid,levelId:level.uid,sentinel:sentinel.uid,originalConfig:JSON.parse(JSON.stringify(config))});
  fs.writeFileSync(file,JSON.stringify(p.toJson()));fs.writeFileSync(file+'-fork.json',JSON.stringify(sidecar));p.forkConfig.load();F.loadEditor(p);
  return {fields,entityDef:ed.uid,iid:ei.iid};
 };
 F.screen=(x,y)=>{const c=Coords.fromLevelCoords(x,y);return {x:Math.round(c.pageX),y:Math.round(c.pageY)};};
 F.select=(kind='entity',indices=[0])=>{
  const e=F.editor(),ei=F.entity(),fi=F.field('Path');e.clearSpecialTool();H.EntityTool.PREV_CHAINABLE_EI=null;
  const elements=kind==='entity'||kind==='both'?[GE.Entity(ei._li,ei)]:[];
  if(kind==='points'||kind==='both')for(const idx of indices)elements.push(GE.PointField(ei._li,ei,fi,idx));
  e.selectionTool.select(elements);return true;
 };
 F.edit=(values,history=true)=>{
  const e=F.editor(),ei=F.entity();
  for(const [name,value] of Object.entries(values)){
   const fi=F.field(name);
   if(name==='Path'){fi.clearValue();for(const pt of value){fi.addArrayValue();if(pt!==null)fi.parseValue(fi.getArrayLength()-1,pt.join(','));}}
   else fi.parseValue(0,String(value));
   e.ge.emit(Events.EntityFieldInstanceChanged(ei,fi));
  }
  if(history)e.levelTimelines.h[e.curLevelId].saveLayerState(ei._li);return true;
 };
 F.values=()=>{const ei=F.entity(),out={x:ei.x,y:ei.y,fields:{}};for(const fd of ei.get_def().fieldDefs){const fi=ei.getFieldInstance(fd,false);out.fields[fd.identifier]=fi?fi.getFullJsonValue():fd.getDefault();}return out;};
 F.effectiveVisible=o=>{for(;o;o=o.parent)if(o.visible===false)return false;return true;};
 F.describe=r=>r?{
  blocks:r.drawnBlockCount,ghosts:r.drawnGhostCount,gaps:r.drawnGapCount,gapValues:r.gapValues||[],color:r.drawnColor,warning:r.warning,cue:r.modeCue,
  visible:F.effectiveVisible(r),labels:r.labels.children.map(t=>t.text),geometry:F.geometry(r.geometry)
 }:null;
 F.geometry=g=>g?{length:g.length,extent:g.extent,pitch:g.pitch,range:g.range,seamGap:g.seamGap,overlap:g.overlap,isStatic:g.isStatic,
  width:g.width,height:g.height,count:g.count,mode:g.mode,vertices:g.vertices,blocks:g.sample()}:null;
 F.render=()=>{const lr=F.editor().levelRender.layerRenders.h[F.layer];return lr&&lr.entityRenders.find(er=>er.ei.iid===F.iid);};
 F.stats=()=>{
  const e=F.editor(),er=F.render(),out=F.describe(er&&er.pathPreview),group=e.selectionTool.group,ghosts=[];
  const visit=node=>{if(!node)return;if(node.__class__?.__name__==='display.PathPreviewRender')ghosts.push(F.describe(node));for(const child of node.children||[])visit(child);};visit(group.pathPreviewGhost);
  return {preview:out,ghostPreviews:ghosts,values:F.values(),sentinel:F.level().getLayerInstance(F.sentinel).getIntGrid(30,18),history:e.levelTimelines.h[e.curLevelId].curStateIdx,
   selectionRunning:e.selectionTool.isRunning(),moveStarted:e.selectionTool.moveStarted,picker:e.isSpecialToolActive(C['tool.PickPoint']),
   suppressed:!!C['display.PathPreviewRender'].suppressedEntities.h[F.iid],
   stockGraphics:!!er&&((er.fieldGraphics.content.index?.length||0)+(er.fieldGraphics.content.buffers||[]).reduce((n,b)=>n+b.idx.length,0)>0),
   underFields:!!er&&!!er.pathPreview&&er.root.children.indexOf(er.pathPreview)<er.root.children.indexOf(er.fieldGraphics)};
 };
 F.undo=()=>{const e=F.editor();return e.levelTimelines.h[e.curLevelId].undo();};
 F.redo=()=>{const e=F.editor();return e.levelTimelines.h[e.curLevelId].redo();};
 F.visibility=visible=>{F.editor().levelRender.setLayerVisibility(F.entity()._li,visible);return true;};
 F.rawSidecar=()=>JSON.parse(fs.readFileSync(F.file+'-fork.json','utf8'));
 F.saveSidecar=()=>{F.editor().project.forkConfig.save();return F.rawSidecar();};
 F.config=patch=>{const raw=F.rawSidecar();Object.assign(raw.entities[F.entityDef].pathPreview,patch);fs.writeFileSync(F.file+'-fork.json',JSON.stringify(raw));F.editor().project.forkConfig.load();F.editor().ge.emit(Events.EntityDefChanged);return true;};
 F.roundtrip=()=>{
  const p=F.editor().project,before=JSON.stringify(p.toJson()),rawBefore=F.rawSidecar();
  for(let i=0;i<3;i++){p.forkConfig.getPathPreview(F.entity());p.forkConfig.save();}
  const withPreview=JSON.stringify(p.toJson()),rawAfter=F.rawSidecar();
  const config=p.forkConfig.sidecarRoot.entities[F.entityDef].pathPreview;
  delete p.forkConfig.sidecarRoot.entities[F.entityDef].pathPreview;
  const withoutPreview=JSON.stringify(p.toJson());p.forkConfig.sidecarRoot.entities[F.entityDef].pathPreview=config;
  return {before,withPreview,withoutPreview,rawBefore,rawAfter};
 };
 F.missingDefaults=()=>{
  const p=F.editor().project,ei=F.entity(),uid=F.fields.BlockCount,original=ei.fieldInstances.h[uid];delete ei.fieldInstances.h[uid];
  const before=Object.keys(ei.fieldInstances.h),resolved=p.forkConfig.getPathPreview(ei),after=Object.keys(ei.fieldInstances.h);ei.fieldInstances.h[uid]=original;
  return {before,after,count:resolved.geometry.count};
 };
 F.reload=()=>{
  const p=F.editor().project;p.forkConfig.save();fs.writeFileSync(F.file,JSON.stringify(p.toJson()));
  const loaded=H.Project.fromJson(F.file,JSON.parse(fs.readFileSync(F.file,'utf8')));loaded.tidy();loaded.forkConfig.load();F.loadEditor(loaded);return true;
 };
 F.moveEntity=(dx,dy)=>{const ei=F.entity();ei.x+=dx;ei.y+=dy;F.editor().ge.emit(Events.EntityInstanceChanged(ei));return true;};
 F.beginGroup=(kind,indices,dx,dy,copy=false)=>{
  F.select(kind,indices);const ei=F.entity(),g=F.editor().selectionTool.group;
  const origin=Coords.fromLevelCoords(ei.x,ei.y),target=Coords.fromLevelCoords(ei.x+dx,ei.y+dy);
  F.drag={g,origin,target,copy,source:ei};g.onMoveStart(copy);g.showGhost(origin,target,copy);return true;
 };
 F.endGroup=(action='cancel')=>{
  const d=F.drag;if(!d)return false;
  if(action==='commit'){const changed=d.g.commitDragSnapshot(d.origin,d.target,d.copy);F.editor().saveLayerStatesByLevel(changed);}
  if(action==='clear')d.g.clear();else d.g.onMoveEnd();F.drag=null;return true;
 };
 F.disposeGroup=()=>{
  const ei=F.entity(),fi=F.field('Path'),g=new C.GenericLevelElementGroup([GE.PointField(ei._li,ei,fi,0)]);
  const from=Coords.fromLevelCoords(ei.x,ei.y),to=Coords.fromLevelCoords(ei.x+16,ei.y);
  g.onMoveStart(false);g.showGhost(from,to,false);
  const suppressed=!!C['display.PathPreviewRender'].suppressedEntities.h[ei.iid];g.dispose();
  return {suppressed,after:!!C['display.PathPreviewRender'].suppressedEntities.h[ei.iid]};
 };
 F.remapSidecar=()=>{
  F.editor().project.forkConfig.save();
  const raw=F.rawSidecar(),cfg=raw.entities[F.entityDef];delete raw.entities[F.entityDef];raw.entities['900001']=cfg;
  cfg.fields['900002']=cfg.fields[F.fields.Path];delete cfg.fields[F.fields.Path];
  cfg.pathPreview.blockCount.fieldUid=900003;
  fs.writeFileSync(F.file+'-fork.json',JSON.stringify(raw));F.editor().project.forkConfig.load();F.editor().ge.emit(Events.EntityDefChanged);return F.saveSidecar();
 };
 return true;
})()
