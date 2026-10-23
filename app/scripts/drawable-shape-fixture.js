(() => {
 const H=__ldtk,C=H.classes,E=H.enums,S=C['data.DrawableShape'],G=C['DrawableShapeGeometry'],FT=E['ldtk.FieldType'],Coords=C['misc.Coords'];
 H.EntityTool=H.EntityTool||C['tool.lt.EntityTool'];
 const F=window.shapeFixture={};
 F.editor=()=>{const e=H.App.ME.curPageProcess;if(e&&e.project&&!e.destroyed)H.Editor.ME=e;return H.Editor.ME;};
 F.entity=i=>F.editor().project.getEntityInstanceByIid(typeof i==='number'?F.ids[i]:i);
 F.level=(i=0)=>F.editor().project.quickLevelAccessUid.h[F.levels[i]];
 F.field=(i,name)=>S.field(F.entity(i),name,true);
 F.load=p=>{H.App.ME.clearCurPage();C['dn.Process'].forceProcessGarbageCollection();H.App.ME.loadPage(()=>new H.Editor(p),false);};
 F.setup=(file,options={})=>{
  H.App.ME.settings.v.openLastProject=false;H.EntityTool.PREV_CHAINABLE_EI=null;
  const p=H.Project.createEmpty(file);if(options.style)p.identifierStyle=E['ldtk.IdentifierStyle'][options.style];
  const ld=p.defs.createLayerDef(E['ldtk.LayerType'].Entities,'DrawableEntities');ld.gridSize=16;ld.canSelectWhenInactive=true;
  const other=p.defs.createLayerDef(E['ldtk.LayerType'].Entities,'OtherEntities');other.gridSize=16;
  const sentinel=p.defs.createLayerDef(E['ldtk.LayerType'].IntGrid,'Untouched');sentinel.gridSize=16;
  sentinel.intGridValues=[{value:1,identifier:'Keep',color:0x444444,tile:null,groupUid:0}];
  const ed=p.defs.createEntityDef();ed.set_identifier('DrawableHazard');ed.width=ed.height=16;ed.setPivot(0.5,0.5);ed.color=0xf7a44f;
  const err=S.enable(ed);if(err)throw Error(err);
  const damage=ed.createFieldDef(p,FT.F_Int,'Damage',false);damage.setDefault('10');
  const note=ed.createFieldDef(p,FT.F_String,'DesignerNote',false);note.setDefault('Preserve authored behavior');
  const link=ed.createFieldDef(p,FT.F_EntityRef,'Link',false);link.canBeNull=true;link.autoChainRef=false;link.allowedRefs=E['ldtk.EntityReferenceTarget'].Any;
  const anchor=ed.createFieldDef(p,FT.F_Point,'Anchor',false);anchor.canBeNull=true;
  const timed=p.defs.createEntityDef();timed.set_identifier('TimedPlatform');timed.width=timed.height=16;timed.setPivot(0.5,1);timed.color=0x57c5ff;
  if(S.enable(timed))throw Error('Could not enable timed platform');
  for(const [name,value] of Object.entries({HiddenDuration:2,ExtendDuration:0.2,VisibleDuration:3,RetractDuration:0.3,PhaseOffsetSeconds:1.25}))timed.createFieldDef(p,FT.F_Float,name,false).setDefault(String(value));
  const ordinary=p.defs.createEntityDef();ordinary.set_identifier('Ordinary');ordinary.width=ordinary.height=12;ordinary.setPivot(0.5,0.5);ordinary.color=0x48df7b;
  const a=p.worlds[0].levels[0],b=p.worlds[0].createLevel();a.set_identifier('Shapes');b.set_identifier('Destination');
  for(const level of [a,b]){level.pxWid=768;level.pxHei=512;level.worldY=options.offsets?-144:0;}
  a.worldX=options.offsets?320:0;b.worldX=a.worldX+832;p.tidy();
  for(const level of [a,b]){level.getLayerInstance(sentinel.uid).setIntGrid(45,28,1,false);if(options.offsets){const li=level.getLayerInstance(ld.uid);li.pxOffsetX=8;li.pxOffsetY=24;}}
  const ids=[],li=a.getLayerInstance(ld.uid);
  const make=(def,x,y)=>{const ei=li.createEntityInstance(def);ei.x=x;ei.y=y;ei.tidy(p,li);ids.push(ei.iid);return ei;};
  if(!options.empty){
   const l=make(ed,64,64);S.applyCells(l,[0,0,0,1,0,2,1,2,2,2],16,64,64);S.set(l,'VisualProfile','Spikes');S.set(l,'Color','#F7A44F');
   const ring=make(ed,256,64);S.applyCells(ring,G.preset('Ring',7,7,1,0).cells,16,256,64,'Preset','Ring');S.set(ring,'VisualProfile','EnergyPool');S.set(ring,'Color','#AB65F5');
   const stairs=make(ed,448,64);S.applyCells(stairs,G.preset('Staircase',7,5,1,0).cells,16,448,64,'Preset','Staircase');S.set(stairs,'VisualProfile','SolidBarrier');
   const platform=make(timed,64,256);S.applyCells(platform,G.preset('Strip',8,2,1,0).cells,16,64,256,'Preset','Strip');S.set(platform,'VisualProfile','SolidBarrier');S.set(platform,'Color','#57C5FF');S.set(platform,'PhaseOffsetSeconds',1.25);
   make(ordinary,104,88);
  }
  p.tidy();for(const level of [a,b])level.invalidateJsonCache();require('fs').writeFileSync(file,JSON.stringify(p.toJson()));p.forkConfig.save();
  Object.assign(F,{file,ids,levels:[a.uid,b.uid],layers:[ld.uid,other.uid],sentinel:sentinel.uid,defs:{hazard:ed.uid,timed:timed.uid,ordinary:ordinary.uid},fields:Object.fromEntries(ed.fieldDefs.map(fd=>[fd.identifier,fd.uid]))});
  F.load(p);const e=F.editor();e.setWorldMode(false);e.selectLevel(a);e.selectLayerInstance(a.getLayerInstance(ld.uid));e.camera.fit(true);e.get_curTool().selectValue(ed.uid);
  return F.state();
 };
 F.screen=(x,y)=>{const c=Coords.fromLevelCoords(x,y);return {x:c.pageX,y:c.pageY};};
 F.select=(i=0)=>{const e=F.editor();e.clearSpecialTool();const ei=F.entity(i);e.selectionTool.select([E.GenericLevelElement.Entity(ei._li,ei)]);return true;};
 F.undo=()=>{const e=F.editor();return e.levelTimelines.h[e.curLevelId].undo();};
 F.redo=()=>{const e=F.editor();return e.levelTimelines.h[e.curLevelId].redo();};
 F.state=()=>{
  const e=F.editor(),read=ei=>{const fields={};for(const fd of ei.get_def().fieldDefs)fields[fd.identifier]=ei.getFieldInstance(fd,true).getFullJsonValue();const s=S.read(ei);return {iid:ei.iid,def:ei.get_def().identifier,level:ei._li.levelId,layer:ei._li.layerDefUid,x:ei.x,y:ei.y,left:ei.get_left(),top:ei.get_top(),width:ei.get_width(),height:ei.get_height(),fields,shape:s?{cells:s.cells,grid:s.grid,mode:s.mode,preset:s.preset,error:s.error,profile:s.profile,facing:s.facing,color:s.color}:null};};
  return {ids:F.ids.slice(),fields:F.fields,defs:F.defs,history:e.levelTimelines.h[e.curLevelId].curStateIdx,activeLayer:e.curLayerDefUid,
   special:e.specialTool?.getShortName()||null,selected:e.selectionTool.group.allElements().map(ge=>ge.ei?.iid).filter(Boolean),
   entities:F.levels.flatMap((_,i)=>F.layers.flatMap(uid=>F.level(i).getLayerInstance(uid).entityInstances.map(read))),
   sentinel:F.level().getLayerInstance(F.sentinel).getIntGrid(45,28)};
 };
 F.save=()=>{const p=F.editor().project;for(const world of p.worlds)for(const level of world.levels)level.invalidateJsonCache();require('fs').writeFileSync(F.file,JSON.stringify(p.toJson()));p.forkConfig.save();return true;};
 F.reload=()=>{F.save();const p=H.Project.fromJson(F.file,JSON.parse(require('fs').readFileSync(F.file,'utf8')));p.tidy();p.forkConfig.load();F.load(p);const e=F.editor();e.setWorldMode(false);e.selectLevel(F.level());e.selectLayerInstance(F.level().getLayerInstance(F.layers[0]));e.camera.fit(true);e.get_curTool().selectValue(F.defs.hazard);return F.state();};
 F.runCore=()=>{
  const assert=require('assert/strict'),passes=[],pass=name=>passes.push(name),p=F.editor().project,li=F.level().getLayerInstance(F.layers[0]);
  let a=F.entity(0),ring=F.entity(1);const saved=a.toJson(li);
  assert.equal(S.read(a).error,null);assert.equal(a.get_width(),48);assert.equal(a.get_height(),48);
  assert.equal(a.isOver(72,72),true);assert.equal(a.isOver(104,88),false);assert.equal(ring.isOver(312,120),false);assert.equal(F.entity(4).isOver(104,88),true);
  pass('Occupied-cell hit tests preserve concavities and ring holes for other entities');
  const error=S.applyCells(a,[0,0,1,1],16,a.get_left(),a.get_top(),'Custom','Custom');assert(error);assert.deepEqual(a.toJson(li),saved);
  pass('Invalid diagonal/disconnected candidates leave all native fields, bounds and IID untouched');
  assert.equal(S.applyCells(a,[-1,-1,0,-1,0,0,0,1,0,2,1,2,2,2],16,64,64,'Custom','Custom'),null);
  assert.equal(a.get_left(),48);assert.equal(a.get_top(),48);assert.equal(a.get_width(),64);assert.equal(a.get_height(),64);assert.equal(a.iid,saved.iid);
  assert.equal(S.applyCells(a,[1,1,1,2,1,3,2,3,3,3],16,48,48,'Custom','Custom'),null);assert.equal(a.get_left(),64);assert.equal(a.get_top(),64);
  assert.deepEqual(S.read(a).cells,[0,0,0,1,0,2,1,2,2,2]);pass('Painting left/up and trimming extreme cells preserve surviving world positions at a centered pivot');
  const odd=new C['data.inst.EntityInstance'](p,li,a.defUid,'odd-grid-pivot-validation');odd.tidy(p,li);
  assert.equal(S.applyCells(odd,[0,0,0,1,0,2,1,2,2,2],3,7,11),null);assert.equal(odd.get_left(),7);assert.equal(odd.get_top(),11);
  assert.equal(S.applyCells(odd,[-1,-1,0,-1,0,0,0,1,0,2,1,2,2,2],3,7,11),null);assert.equal(odd.get_left(),4);assert.equal(odd.get_top(),8);
  const oddBefore=odd.toJson(li);assert.match(S.applyCells(odd,[0,0],3,0,0),/pivot.*origin|pixel positions/i);assert.deepEqual(odd.toJson(li),oddBefore);
  pass('Odd-grid centered-pivot edits preserve exact pixel origins, and unrepresentable half-pixel origins reject before mutation');
  const cellField=S.field(a,'ShapeCells'),json=cellField.toJson();assert.deepEqual(json.__value,json.realEditorValues.map(v=>v.params[0]));assert.equal(cellField.get_def().arrayMaxLength,null);
  pass('Native Array<Int> export and realEditorValues agree without an arbitrary length limit');
  const defaultShape=F.entity(2),faceFd=S.field(defaultShape,'ShapeFacing',true).get_def(),profileFi=S.field(defaultShape,'VisualProfile',true),profileFd=profileFi.get_def();
  const faceDefault=faceFd.getDefault(),profileDefault=profileFd.getDefault();profileFi.parseValue(0,null);S.read(defaultShape);
  faceFd.setDefault('Right');profileFd.setDefault('EnergyPool');assert.equal(S.read(defaultShape).facing,'Right');assert.equal(S.read(defaultShape).profile,'EnergyPool');
  faceFd.setDefault(faceDefault);profileFd.setDefault(profileDefault);profileFi.parseValue(0,'SolidBarrier');assert.equal(S.read(defaultShape).facing,'All');assert.equal(S.read(defaultShape).profile,'SolidBarrier');
  pass('Changing native scalar defaults immediately invalidates cached shape facing and appearance without scanning the cell array');
  const copy=li.duplicateEntityInstance(a);assert.notEqual(copy.iid,a.iid);assert.deepEqual(S.read(copy).cells,S.read(a).cells);S.set(copy,'Damage',77);S.set(copy,'Color','#12ABEF');
  S.field(a,'Link',true).setEntityRefTo(0,a,ring);S.field(a,'Anchor',true).parseValue(0,'13,11');
  const ownerCount=li.entityInstances.length,targetBefore=JSON.stringify(S.read(a).cells),targetIid=a.iid;assert.equal(S.applyConfiguration(a,copy),null);assert.equal(li.entityInstances.length,ownerCount);assert.equal(a.iid,targetIid);assert.equal(JSON.stringify(S.read(a).cells),targetBefore);assert.equal(S.value(a,'Damage',0),77);
  assert.equal(S.field(a,'Link',true).getEntityRefIid(0),ring.iid);assert(p.getEntityInstancesReferingTo(ring).includes(a));assert.deepEqual(S.field(a,'Anchor',true).getPointGrid(0),{cx:13,cy:11});
  pass('Native duplication gives a fresh IID; settings keep one owner, mask, point anchors and valid references with their reverse cache');
  S.set(a,'ShapeFacing','Left');assert.equal(S.transform(a,true,false,0),null);assert.equal(S.read(a).facing,'Right');S.transform(a,true,false,0);assert.equal(S.read(a).facing,'Left');assert.equal(S.read(a).mode,'Custom');
  pass('Mirroring transforms resolved geometry and directional faces together');
  const destination=F.level(1).getLayerInstance(F.layers[0]),beforeMove=copy.toJson(li);li.detachEntityInstanceForMove(copy);destination.attachEntityInstanceForMove(copy);assert.equal(copy.iid,beforeMove.iid);assert.deepEqual(S.read(copy).cells,S.read(a).cells);assert.equal(copy._li,destination);
  pass('Cross-level entity ownership transfer keeps mask, native behavior fields and IID');
  const valid=a.toJson(li),invalid=JSON.parse(JSON.stringify(valid)),cf=invalid.fieldInstances.find(f=>f.__identifier==='ShapeCells');cf.__value=[0,0,2,0];cf.realEditorValues=cf.__value.map(v=>({id:'V_Int',params:[v]}));
  const malformed=C['data.inst.EntityInstance'].fromJson(p,li,invalid);assert(S.read(malformed).error);assert.deepEqual(S.read(malformed).cells,[]);
  const mismatched=JSON.parse(JSON.stringify(valid));mismatched.fieldInstances.find(f=>f.__identifier==='ShapeCells').__value=[0,0];assert(S.read(C['data.inst.EntityInstance'].fromJson(p,li,mismatched)).error);
  const hidden=JSON.parse(JSON.stringify(valid));for(const f of hidden.fieldInstances)if(S.GEOMETRY.includes(f.__identifier))f.realEditorValues=[];
  assert(S.read(C['data.inst.EntityInstance'].fromJson(p,li,hidden)).error);
  pass('Malformed versioned masks and mismatched native/public values report errors without bounding-box fallback');
  const editor=F.editor();editor.selectionTool.select([E.GenericLevelElement.Entity(li,ring),E.GenericLevelElement.Entity(li,a)]);
  const brokenTemplate=editor.selectionTool.group.toSelectionTemplate('Invalid second shape'),badField=brokenTemplate.entities[1].json.fieldInstances.find(f=>f.__identifier==='ShapeCells');
  badField.__value=[0,0,2,0];badField.realEditorValues=badField.__value.map(v=>({id:'V_Int',params:[v]}));
  const beforeTemplate=F.state();assert.equal(C['data.SelectionTemplates'].place(editor,brokenTemplate,128,320,false,false),false);
  assert.deepEqual(F.state().entities,beforeTemplate.entities);assert.equal(F.state().history,beforeTemplate.history);editor.selectionTool.clear();
  pass('Malformed geometry in a multi-entity template is rejected before any attachment, field change or history transaction');
  const ordinary=F.entity(4);assert.equal(S.read(ordinary),null);assert.equal(ordinary.get_width(),12);
  const legacy=li.createEntityInstance(a.get_def());legacy.x=600;legacy.y=300;legacy.tidy(p,li);assert.equal(S.read(legacy),null);assert.equal(legacy.get_width(),16);
  pass('Ordinary entities and untouched enabled legacy rectangles retain their existing interpretation');
  const before=F.state().entities;F.reload();assert.deepEqual(F.state().entities,before);
  assert.equal(F.entity(0).toJson(F.entity(0)._li).fieldInstances.find(f=>f.__identifier==='Color').__value,'#12ABEF');
  pass('Save/reopen preserves masks, enum fields, per-instance color, behavior and IDs');
  return passes;
 };
 F.runStyleCases=directory=>{
  const assert=require('assert/strict'),path=require('path'),passes=[];
  for(const style of ['Uppercase','Lowercase']) {
   F.setup(path.join(directory,'style-'+style+'.ldtk'),{style});
   const p=F.editor().project,ei=F.entity(0),ring=F.entity(1);
   assert.equal(S.read(ei).error,null);assert.equal(S.value(ei,'ShapeMode',''),'Custom');assert.equal(S.value(ring,'ShapePreset',''),'Ring');
   const ordinary=p.defs.createEnumDef();ordinary.set_identifier('UnrelatedMovement');const normal=ordinary.addValue('Walk');assert.equal(normal.id,style==='Uppercase'?'WALK':'walk');
   const old=p.identifierStyle;p.identifierStyle=E['ldtk.IdentifierStyle'][style==='Uppercase'?'Lowercase':'Uppercase'];p.applyIdentifierStyleEverywhere(old);p.tidy();
   assert.equal(S.read(ei).error,null);assert.equal(S.value(ei,'ShapeMode',''),'Custom');assert.equal(S.value(ring,'ShapePreset',''),'Ring');
   assert.equal(ordinary.values[0].id,style==='Uppercase'?'walk':'WALK');
   F.reload();assert.equal(S.read(F.entity(0)).error,null);assert.equal(S.value(F.entity(0),'ShapeMode',''),'Custom');assert.equal(S.value(F.entity(1),'ShapePreset',''),'Ring');
   passes.push('Exact contract enum and field identifiers survive '+style+' creation, naming-policy changes and native save/reopen without changing unrelated enum policy');
  }
  return passes;
 };
 F.exportExamples=directory=>{
  const fs=require('fs'),path=require('path'),p=F.editor().project;
  for(const world of p.worlds)for(const level of world.levels)level.invalidateJsonCache();
  const json=p.toJson();json.externalLevels=true;
  fs.mkdirSync(path.join(directory,'drawable-shapes'),{recursive:true});
  const fixtures=[];
  for(const level of json.levels){const rel='drawable-shapes/'+level.identifier+'.ldtkl';fs.writeFileSync(path.join(directory,rel),JSON.stringify(level,null,2)+'\n');
   for(const layer of level.layerInstances)for(const entity of layer.entityInstances){const fields=Object.fromEntries(entity.fieldInstances.map(f=>[f.__identifier,f.__value]));if(fields.ShapeVersion===1&&fields.ShapeCells)fixtures.push({levelIid:level.iid,worldOrigin:[level.worldX,level.worldY],layerOffset:[layer.__pxTotalOffsetX,layer.__pxTotalOffsetY],entity});}
   level.externalRelPath=rel;level.layerInstances=null;}
  fs.writeFileSync(path.join(directory,'drawable-shapes.ldtk'),JSON.stringify(json,null,2)+'\n');
  fs.copyFileSync(F.file+'-fork.json',path.join(directory,'drawable-shapes.ldtk-fork.json'));
  fs.writeFileSync(path.join(directory,'drawable-shapes-v1-export.json'),JSON.stringify({contractVersion:1,coordinateSystem:'LDtk pixels, Y down; masks are final orientation',fixtures},null,2)+'\n');return fixtures.length;
 };
 F.beginExternalLoad=file=>{
  F.externalResult=null;F.externalError=null;
  new C['ui.ProjectLoader'](file,p=>{
   try{p.tidy();F.externalResult=p.worlds.flatMap(w=>w.levels.flatMap(l=>l.layerInstances.flatMap(li=>li.entityInstances.map(ei=>({iid:ei.iid,fields:Object.fromEntries(ei.toJson(li).fieldInstances.map(f=>[f.__identifier,f.__value])),shape:S.read(ei)?.cells||null,error:S.read(ei)?.error||null,offset:[li.get_pxTotalOffsetX(),li.get_pxTotalOffsetY()],world:[l.worldX,l.worldY]})))));}catch(error){F.externalError=String(error.stack||error);}
  },error=>{F.externalError=String(error);},true);
  return true;
 };
 return true;
})()
