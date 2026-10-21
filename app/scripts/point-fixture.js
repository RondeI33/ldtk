(() => {
 const H=__ldtk,C=H.classes,E=H.enums,Coords=C['misc.Coords'],FT=E['ldtk.FieldType'];
 const F=window.pointFixture={};
 F.editor=()=>{const e=H.App.ME.curPageProcess;if(e&&e.project&&!e.destroyed)H.Editor.ME=e;return H.Editor.ME;};
 F.level=()=>F.editor().project.quickLevelAccessUid.h[F.levelId];
 F.entity=i=>F.editor().project.getEntityInstanceByIid(F.ids[i]);
 F.field=name=>{const ei=F.entity(0);return ei.getFieldInstance(ei.get_def().getFieldDef(name),true);};
 F.loadEditor=p=>{
  // Synchronous test reloads must finish disposing the old editor before the
  // new one attaches to the shared canvas and application input handlers.
  H.App.ME.clearCurPage();C['dn.Process'].forceProcessGarbageCollection();
  H.App.ME.loadPage(()=>new H.Editor(p),false);
 };
 F.setup=(file,options={})=>{
  H.App.ME.settings.v.openLastProject=false;
  H.EntityTool.PREV_CHAINABLE_EI=null;
  const p=H.Project.createEmpty(file);
  const layers=['Cables','OtherEntities'].map(id=>p.defs.createLayerDef(E['ldtk.LayerType'].Entities,id));
  for(const ld of layers){ld.gridSize=16;ld.canSelectWhenInactive=true;}
  const sentinel=p.defs.createLayerDef(E['ldtk.LayerType'].IntGrid,'Untouched');sentinel.gridSize=16;
  sentinel.intGridValues=[{value:1,identifier:'Keep',color:0x444444,tile:null,groupUid:0}];
  // Reproduce the cable's relevant field/geometry configuration without
  // embedding the user's project, tilesets or unrelated game content.
  p.nextUid=3873;
  const cable=p.defs.createEntityDef();cable.set_identifier('VeinCable');cable.width=cable.height=options.resizable?64:16;
  cable.setPivot(0.5,0.5);cable.color=0x4dd2ff;cable.resizableX=cable.resizableY=!!options.resizable;
  p.nextUid=3875;
  const from=cable.createFieldDef(p,FT.F_EntityRef,'From',false),to=cable.createFieldDef(p,FT.F_EntityRef,'To',false);
  from.autoChainRef=false;to.autoChainRef=true;
  for(const fd of [from,to]){fd.canBeNull=true;fd.allowedRefs=E['ldtk.EntityReferenceTarget'].Any;}
  p.nextUid=3884;
  const fromPoint=cable.createFieldDef(p,FT.F_Point,'FromPoint',false),toPoint=cable.createFieldDef(p,FT.F_Point,'ToPoint',false);
  const path=cable.createFieldDef(p,FT.F_Point,'Path',true);
  path.set_identifier('Path');
  for(const fd of [fromPoint,toPoint,path]){fd.canBeNull=true;fd.autoChainRef=false;fd.editorDisplayMode=E['ldtk.FieldDisplayMode'].PointStar;}
  const target=p.defs.createEntityDef();target.set_identifier('Device');target.width=target.height=64;target.setPivot(0.5,0.5);target.color=0xffa644;
  const level=p.worlds[0].levels[0];level.set_identifier('PointPicking');level.pxWid=640;level.pxHei=384;
  p.tidy();
  const make=(ed,layer,x,y)=>{const li=level.getLayerInstance(layers[layer].uid),ei=li.createEntityInstance(ed);ei.x=x;ei.y=y;ei.tidy(p,li);return ei;};
  const source=make(cable,0,104,104),device=make(target,0,264,104),other=make(target,1,424,104);
  source.getFieldInstance(fromPoint,true).parseValue(0,'4,14');
  source.getFieldInstance(to,true).setEntityRefTo(0,source,device);
  level.getLayerInstance(sentinel.uid).setIntGrid(30,18,1,false);
  p.tidy();require('fs').writeFileSync(file,JSON.stringify(p.toJson()));
  Object.assign(F,{file,ids:[source.iid,device.iid,other.iid],layers:layers.map(ld=>ld.uid),levelId:level.uid,sentinel:sentinel.uid,
   fields:Object.fromEntries(cable.fieldDefs.map(fd=>[fd.identifier,fd.uid]))});
  F.loadEditor(p);
  const e=F.editor();e.setWorldMode(false);e.selectLevel(level);e.selectLayerInstance(level.getLayerInstance(layers[0].uid));e.camera.fit(true);
  e.get_curTool().selectValue(cable.uid);
  return {fields:F.fields,ids:F.ids};
 };
 F.select=(i=0)=>{
  const e=F.editor();e.clearSpecialTool();H.EntityTool.PREV_CHAINABLE_EI=null;
  const ei=F.entity(i);e.selectionTool.select([E.GenericLevelElement.Entity(ei._li,ei)]);
  return true;
 };
 F.screen=(x,y)=>{const c=Coords.fromLevelCoords(x,y);return {x:c.pageX,y:c.pageY};};
 F.handle=()=>{
  const r=F.editor().resizeTool,pos=E.RectHandlePos.Right;
  if(!r||!r.isHandleActive(pos))throw Error('Fixture has no right resize handle');
  return {x:r.getHandleX(pos),y:r.getHandleY(pos)};
 };
 F.debug=()=>{
  const e=F.editor();return {mouse:e.getMouse().toString(),lastMove:e.specialTool?.lastMouse?.toString()||null,
   cursor:e.cursor.type._hx_index,picker:e.specialTool?.getShortName(),origin:e.specialTool?.pickOrigin,
   overCanvas:H.App.ME.overCanvas,focused:H.App.ME.focused,locked:e.isLocked(),paused:e.isPaused(),gl:H.App.ME.hasGlContext};
 };
 F.state=()=>{
  const e=F.editor(),picker=e.specialTool,selection=e.selectionTool;
  const points=fi=>Array.from({length:fi.getArrayLength()},(_,i)=>fi.valueIsNull(i)?null:fi.getPointGrid(i));
  return {
   picker:e.isSpecialToolActive(C['tool.PickPoint']),pickerRunning:!!picker&&picker.isRunning(),
   selectionRunning:selection.isRunning(),resizing:!!e.resizeTool&&e.resizeTool.isRunning(),
   linkPreview:e.cursor.type._hx_index===E.CursorType.Link(0,0,0,0,0)._hx_index,
   valuePicker:!!C['ui.ValuePicker'].ME&&!C['ui.ValuePicker'].ME.destroyed,
   activeLayer:e.curLayerDefUid,history:e.levelTimelines.h[e.curLevelId].curStateIdx,
   inspector:C['ui.EntityInstanceEditor'].CURRENT?.ei?.iid||null,
   selected:selection.group.allElements().map(ge=>({kind:ge._hx_index,iid:ge.ei?.iid||null})),
   sentinel:F.level().getLayerInstance(F.sentinel).getIntGrid(30,18),
   entities:F.ids.map(iid=>{
    const ei=e.project.getEntityInstanceByIid(iid),fields={};
    for(const fd of ei.get_def().fieldDefs){
     const fi=ei.getFieldInstance(fd,true);
     if(fd.type===FT.F_Point){const value=points(fi);fields[fd.identifier]=fd.isArray?value:value[0];}
     else if(fd.type===FT.F_EntityRef)fields[fd.identifier]=fi.getEntityRefIid(0);
    }
    return {iid,layer:ei._li.layerDefUid,x:ei.x,y:ei.y,width:ei.get_width(),height:ei.get_height(),fields};
   })
  };
 };
 F.undo=()=>{const e=F.editor();return e.levelTimelines.h[e.curLevelId].undo();};
 F.redo=()=>{const e=F.editor();return e.levelTimelines.h[e.curLevelId].redo();};
 F.reload=()=>{
  const fs=require('fs');fs.writeFileSync(F.file,JSON.stringify(F.editor().project.toJson()));
  const p=H.Project.fromJson(F.file,JSON.parse(fs.readFileSync(F.file,'utf8')));p.tidy();
  F.loadEditor(p);
  const e=F.editor();e.setWorldMode(false);e.selectLevel(F.level());e.selectLayerInstance(F.level().getLayerInstance(F.layers[0]));e.camera.fit(true);
  H.EntityTool.PREV_CHAINABLE_EI=null;return true;
 };
 return true;
})()
