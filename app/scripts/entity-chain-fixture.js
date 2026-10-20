(() => {
 const H=__ldtk,C=H.classes,E=H.enums,Coords=C['misc.Coords'],FT=E['ldtk.FieldType'];
 const F=window.entityChainFixture={};
 F.editor=()=>{const e=H.App.ME.curPageProcess;if(e&&e.project&&!e.destroyed)H.Editor.ME=e;return H.Editor.ME;};
 F.entity=i=>F.editor().project.getEntityInstanceByIid(typeof i==='number'?F.ids[i]:i);
 F.level=i=>F.editor().project.quickLevelAccessUid.h[F.levels[i]];
 F.field=(i,name)=>{const ei=F.entity(i),fd=ei.get_def().getFieldDef(name);return fd?ei.getFieldInstance(fd,true):null;};
 F.setup=function(path,options={}){
  const fs=require('fs');
  H.App.ME.settings.v.openLastProject=false;
  H.EntityTool.PREV_CHAINABLE_EI=null;
  const p=H.Project.createEmpty(path);
  const layers=['Cables_A','Cables_B'].map(id=>p.defs.createLayerDef(E['ldtk.LayerType'].Entities,id));
  const sentinel=p.defs.createLayerDef(E['ldtk.LayerType'].IntGrid,'Sentinels');
  for(const ld of [...layers,sentinel]){ld.gridSize=16;ld.canSelectWhenInactive=true;}
  sentinel.intGridValues=[{value:1,identifier:'Keep',color:0x444444,tile:null,groupUid:0}];
  p.nextUid=3873;
  const cable=p.defs.createEntityDef();cable.set_identifier('VeinCable');cable.width=cable.height=16;cable.setPivot(0,0);
  p.nextUid=3875;
  const from=options.backType==='missing'?null:cable.createFieldDef(p,options.backType==='int'?FT.F_Int:FT.F_EntityRef,'From',!!options.array);
  if(from){from.set_identifier('From');from.autoChainRef=false;from.canBeNull=true;from.symmetricalRef=!!options.symmetricBack;from.arrayMaxLength=options.max==null?null:options.max;}
  p.nextUid=3876;
  const to=cable.createFieldDef(p,FT.F_EntityRef,'To',!!options.chainArray);to.set_identifier('To');to.autoChainRef=true;to.canBeNull=true;
  const appearance=cable.createFieldDef(p,FT.F_Bool,'AppearanceEnabled',false);appearance.autoChainRef=false;
  const patrol=p.defs.createEntityDef();patrol.set_identifier('PatrolPoint');patrol.width=patrol.height=16;patrol.setPivot(0,0);
  const next=patrol.createFieldDef(p,FT.F_EntityRef,'Next',false);next.autoChainRef=true;next.canBeNull=true;
  const other=p.defs.createEntityDef();other.set_identifier('Other');other.width=other.height=16;other.setPivot(0,0);
  if(options.reject&&from){from.allowedRefs=E['ldtk.EntityReferenceTarget'].OnlySpecificEntity;from.allowedRefsEntityUid=other.uid;}
  if(options.localBack&&from)from.allowOutOfLevelRef=false;
  const world=p.worlds[0],a=world.levels[0],b=world.createLevel();
  a.set_identifier('Level_A');b.set_identifier('Level_B');
  for(const level of [a,b]){level.pxWid=640;level.pxHei=384;level.worldY=0;}
  a.worldX=0;b.worldX=704;
  p.tidy();
  for(const level of [a,b])level.getLayerInstance(sentinel.uid).setIntGrid(25,12,1,false);
  const appearanceRules=[{whenFieldUid:appearance.uid,whenFieldIdentifier:'AppearanceEnabled',whenValue:true,color:'#a1b2c3'}];
  const cfg={format:1,projectIid:p.iid,entities:{'3873':{identifier:'VeinCable',appearanceOverrides:appearanceRules}}};
  if(options.config!==null)cfg.entities['3873'].autoChainBackRefs=options.config===undefined?[{chainField:'To',backField:'From'}]:options.config;
  fs.writeFileSync(path+'-fork.json',JSON.stringify(cfg,null,2));
  p.forkConfig.load();
  const defs={cable,patrol,other},ids=[];
  for(const [i,seed] of (options.seeds||[]).entries()){
   const li=[a,b][seed.level||0].getLayerInstance(layers[seed.layer||0].uid);
   const ei=li.createEntityInstance(defs[seed.def||'cable']);ei.x=seed.x==null?64+i*128:seed.x;ei.y=seed.y==null?64:seed.y;
   ei.tidy(p,li);ids.push(ei.iid);
  }
  p.tidy();fs.writeFileSync(path,JSON.stringify(p.toJson()));
  H.App.ME.loadPage(()=>new H.Editor(p),false);
  const e=H.Editor.ME;e.setWorldMode(false);e.selectLevel(a);e.selectLayerInstance(a.getLayerInstance(layers[0].uid));e.camera.fit(true);
  Object.assign(F,{path,ids,layers:layers.map(ld=>ld.uid),levels:[a.uid,b.uid],sentinel:sentinel.uid,defs:Object.fromEntries(Object.entries(defs).map(([k,d])=>[k,d.uid])),events:[]});
  e.get_curTool().selectValue(cable.uid);
  e.ge.addGlobalListener(event=>{if(event._hx_index===E.GlobalEvent.EntityInstanceChanged(null)._hx_index)F.events.push(event.ei.iid);});
  return F.state();
 };
 F.activate=(level=0,layer=0,def='cable')=>{
  const e=F.editor(),l=F.level(level);
  if(e.curLevelId!==l.uid)e.selectLevel(l);
  e.selectLayerInstance(l.getLayerInstance(F.layers[layer]));
  e.get_curTool().selectValue(F.defs[def]);return true;
 };
 F.place=(x,y,def='cable',level=0,layer=0)=>{
  F.activate(level,layer,def);F.events=[];
  const e=F.editor(),li=F.level(level).getLayerInstance(F.layers[layer]),before=new Set(li.entityInstances.map(ei=>ei.iid));
  const m=Coords.fromLevelCoords(x+2,y+2);
  e.get_curTool().startUsing({button:0,cancel:false},m);
  e.selectionTool.stopUsing(m);
  const created=li.entityInstances.filter(ei=>!before.has(ei.iid));
  if(created.length!==1)throw Error('Placement did not create exactly one entity: '+created.length);
  F.ids.push(created[0].iid);return F.state();
 };
 F.click=(targetIndex,sourceIndex=null)=>{
  const target=F.entity(targetIndex),li=target._li;
  F.activate(F.levels.indexOf(li.levelId),F.layers.indexOf(li.layerDefUid),Object.keys(F.defs).find(k=>F.defs[k]===target.defUid));
  if(sourceIndex!==null)H.EntityTool.PREV_CHAINABLE_EI=F.entity(sourceIndex);
  F.events=[];
  const e=F.editor(),m=Coords.fromLevelCoords(target.x+2,target.y+2);
  e.get_curTool().startUsing({button:0,cancel:false},m);e.selectionTool.stopUsing(m);return F.state();
 };
 F.seedRef=(i,name,targetIndex)=>{
  const source=F.entity(i),target=F.entity(targetIndex),fi=F.field(i,name);
  if(fi.get_def().isArray)fi.addArrayValue();
  fi.setEntityRefTo(fi.getArrayLength()-1,source,target);return true;
 };
 F.checkpoint=()=>{const e=F.editor();e.selectionTool.clear();for(const tl of Object.values(e.levelTimelines.h))tl.clear();F.events=[];return F.state();};
 F.undo=()=>{const e=F.editor();return e.levelTimelines.h[e.curLevelId].undo();};
 F.redo=()=>{const e=F.editor();return e.levelTimelines.h[e.curLevelId].redo();};
 F.state=()=>{
  const e=F.editor();
  const read=ei=>{
   const refs={};
   for(const fd of ei.get_def().fieldDefs)if(fd.type===FT.F_EntityRef){
    const fi=ei.getFieldInstance(fd,true),values=Array.from({length:fi.getArrayLength()},(_,i)=>fi.getEntityRefIid(i));
    refs[fd.identifier]=fd.isArray?values:values[0];
   }
   return {iid:ei.iid,def:ei.get_def().identifier,level:ei._li.levelId,layer:ei._li.layerDefUid,x:ei.x,y:ei.y,refs};
  };
  return {active:e.curLevelId,ids:F.ids.slice(),events:F.events.slice(),
   timelines:Object.fromEntries(Object.entries(e.levelTimelines.h).map(([id,t])=>[id,t.curStateIdx])),
   levels:F.levels.map((_,i)=>{const l=F.level(i);return {id:l.uid,sentinel:l.getLayerInstance(F.sentinel).getIntGrid(25,12),
    entities:F.layers.flatMap(uid=>l.getLayerInstance(uid).entityInstances.map(read))};})};
 };
 F.logs=()=>H.App.LOG.entries.map(entry=>entry.str);
 F.referrers=i=>F.editor().project.getEntityInstancesReferingTo(F.entity(i)).map(ei=>ei.iid);
 F.sidecar=()=>JSON.parse(require('fs').readFileSync(F.path+'-fork.json','utf8'));
 F.save=()=>{const p=F.editor().project;require('fs').writeFileSync(F.path,JSON.stringify(p.toJson()));p.forkConfig.save();return F.sidecar();};
 F.reload=()=>{
  const fs=require('fs'),p=H.Project.fromJson(F.path,JSON.parse(fs.readFileSync(F.path,'utf8')));p.tidy();p.forkConfig.load();
  H.EntityTool.PREV_CHAINABLE_EI=null;H.App.ME.loadPage(()=>new H.Editor(p),false);
  const e=H.Editor.ME;e.setWorldMode(false);e.selectLevel(p.quickLevelAccessUid.h[F.levels[0]]);e.selectLayerInstance(e.get_curLevel().getLayerInstance(F.layers[0]));
  e.get_curTool().selectValue(F.defs.cable);F.events=[];
  e.ge.addGlobalListener(event=>{if(event._hx_index===E.GlobalEvent.EntityInstanceChanged(null)._hx_index)F.events.push(event.ei.iid);});
  return true;
 };
 F.reloadConfig=cfg=>{
  const fs=require('fs');if(cfg===null)fs.unlinkSync(F.path+'-fork.json');else fs.writeFileSync(F.path+'-fork.json',JSON.stringify(cfg));
  F.editor().project.forkConfig.load();return true;
 };
 F.runtimeConfig=()=>F.editor().project.defs.getEntityDef(F.defs.cable).autoChainBackRefs;
 return true;
})()
