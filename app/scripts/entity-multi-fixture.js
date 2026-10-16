(() => {
 const H=__ldtk,C=H.classes,E=H.enums,Coords=C['misc.Coords'];
 const F=window.multiFixture={};
 F.editor=()=>{const e=H.App.ME.curPageProcess;if(e&&e.project&&!e.destroyed)H.Editor.ME=e;return H.Editor.ME;};
 F.entity=i=>F.editor().project.getEntityInstanceByIid(F.ids[i]);
 F.field=(i,name)=>F.entity(i).getFieldInstance(F.editor().project.defs.getFieldDef(F.fields[name]),true);
 F.select=(indexes=[0,1])=>{const e=F.editor();e.selectionTool.select(indexes.map(i=>{const ei=F.entity(i);return E.GenericLevelElement.Entity(ei._li,ei)}));return true;};
 F.setup=function(path){
  H.App.ME.settings.v.openLastProject=false;
  const p=H.Project.createEmpty(path);
  const a=p.defs.createLayerDef(E['ldtk.LayerType'].Entities,'Entities_A');
  const b=p.defs.createLayerDef(E['ldtk.LayerType'].Entities,'Entities_B');
  const ig=p.defs.createLayerDef(E['ldtk.LayerType'].IntGrid,'Sentinels');
  const tiles=p.defs.createLayerDef(E['ldtk.LayerType'].Tiles,'Stamps');
  for(const d of [a,b,ig,tiles]){d.gridSize=16;d.canSelectWhenInactive=true;}
  ig.intGridValues=[{value:1,identifier:'Keep',color:0x444444,tile:null,groupUid:0}];
  const en=p.defs.createEnumDef();en.set_identifier('Mode');for(const v of ['A','B','C'])en.addValue(v);
  const ed=p.defs.createEntityDef();ed.set_identifier('Device');ed.width=ed.height=16;ed.setPivot(0,0);
  const make=(name,type,arr=false)=>{const fd=ed.createFieldDef(p,type,name,arr);fd.autoChainRef=false;return fd};
  const FT=E['ldtk.FieldType'];
  const fds={
   Amount:make('Amount',FT.F_Int),Rate:make('Rate',FT.F_Float),Active:make('Active',FT.F_Bool),
   Label:make('Label',FT.F_String),Text:make('Text',FT.F_Text),Color:make('Color',FT.F_Color),
   Mode:make('Mode',FT.F_Enum(en.uid)),Steps:make('Steps',FT.F_Int,true),Anchor:make('Anchor',FT.F_Point),
   Link:make('Link',FT.F_EntityRef),Links:make('Links',FT.F_EntityRef,true),
   Nullable:make('Nullable',FT.F_Int),Path:make('Path',FT.F_Path),Pair:make('Pair',FT.F_EntityRef)
  };
  fds.Amount.setMin('0');fds.Amount.setMax('100');fds.Amount.setDefault('3');
  fds.Mode.setDefault('A');fds.Steps.arrayMaxLength=5;fds.Nullable.canBeNull=true;fds.Pair.symmetricalRef=true;
  fds.Path.canBeNull=true;fds.Link.canBeNull=true;fds.Links.canBeNull=true;
  const other=p.defs.createEntityDef();other.set_identifier('Other');other.width=other.height=16;other.setPivot(0,0);
  const level=p.worlds[0].levels[0];level.pxWid=640;level.pxHei=384;
  const second=p.worlds[0].createLevel();second.worldX=704;second.worldY=0;second.pxWid=640;second.pxHei=384;
  p.tidy();
  const all=[];
  for(let i=0;i<4;i++){
   const li=level.getLayerInstance(i===1?b.uid:a.uid);
   const ei=li.createEntityInstance(i===3?other:ed);ei.x=[64,128,360,480][i];ei.y=64;ei.tidy(p,li);all.push(ei);
   if(i===3)continue;
   const vals={Amount:i===1?'8':'3',Rate:i===1?'2.25':'1.5',Active:i===1?'true':'false',
    Label:'unchanged',Text:i===1?'second\\ntext':'first\\ntext',Color:i===1?'#88aaff':'#ff9900',
    Mode:i===1?'B':'A',Anchor:i===1?'8,9':'2,3',Nullable:i===1?'0':null};
   for(const [name,v] of Object.entries(vals))ei.getFieldInstance(fds[name],true).parseValue(0,v);
   for(let j=0;j<(i===1?3:2);j++){const f=ei.getFieldInstance(fds.Steps,true);f.addArrayValue();f.parseValue(j,String(i*10+j+1));}
  }
  all[2].getFieldInstance(fds.Link,true).setEntityRefTo(0,all[2],all[0]);
  const background=level.getLayerInstance(ig.uid);background.setIntGrid(25,12,1,false);
  p.tidy();
  require('fs').writeFileSync(path,JSON.stringify(p.toJson()));
  H.App.ME.loadPage(()=>new H.Editor(p),false);
  const e=H.Editor.ME;e.setWorldMode(false);e.selectLevel(level);e.selectLayerInstance(level.getLayerInstance(a.uid));e.camera.fit(true);
  Object.assign(F,{ids:all.map(x=>x.iid),fields:Object.fromEntries(Object.entries(fds).map(([n,d])=>[n,d.uid])),
   layers:[a.uid,b.uid],ig:ig.uid,stamps:tiles.uid,level:level.uid,second:second.uid,path,ed:ed.uid});
  return {fields:F.fields,ids:F.ids};
 };
 F.state=()=>{const e=F.editor(),l=e.get_curLevel();return {
  active:e.curLevelId,history:e.levelTimelines.h[e.curLevelId].curStateIdx,dirty:e.needSaving,
  data:JSON.stringify(l.toJson(true)),entities:F.ids.map(id=>{const x=e.project.getEntityInstanceByIid(id);return x?x.toJson(x._li):null}),
  selected:e.selectionTool.group.elements.length,
  panel:!!C['ui.MultiEntityInstanceEditor'].CURRENT&&!C['ui.MultiEntityInstanceEditor'].CURRENT.destroyed
 }};
 F.values=name=>F.ids.slice(0,3).map((_,i)=>F.field(i,name).getFullJsonValue());
 F.edit=(name,value,idx=0)=>C['data.MultiEntityEdit'].setValue([F.entity(0),F.entity(1)],F.fields[name],idx,value);
 F.resize=(name,size)=>C['data.MultiEntityEdit'].resizeArray([F.entity(0),F.entity(1)],F.fields[name],size);
 F.undo=()=>{const e=F.editor();return e.levelTimelines.h[e.curLevelId].undo()};
 F.redo=()=>{const e=F.editor();return e.levelTimelines.h[e.curLevelId].redo()};
 F.point=(x,y)=>{const c=Coords.fromLevelCoords(x,y);return {x:Math.round(c.pageX),y:Math.round(c.pageY)}};
 F.keys=()=>({alt:H.App.ME.isAltDown(),shift:H.App.ME.isShiftDown()});
 F.refresh=()=>{F.editor().selectionTool.clear();F.select();return true};
 F.seedValue=(i,name,value,idx=0)=>{F.field(i,name).parseValue(idx,value);F.editor().curLevelTimeline;return true};
 F.checkpoint=()=>{const e=F.editor();e.levelTimelines.h[e.curLevelId].clear();return F.refresh()};
 F.stampFixture=()=>{
  const e=F.editor(),p=e.project,ed=p.defs.getEntityDef(F.ed);
  ed.tileStamps=[{whenFieldUid:F.fields.Active,whenValue:true,layerDefUid:F.stamps,tiles:[{tileId:1,dx:0,dy:0,flips:0}]}];
  // Data-only stamp layer: no renderer dependency on external art is required.
  for(const i of [0,1])F.field(i,'Active').parseValue(0,'false');
  F.checkpoint();return true;
 };
 F.stampValues=()=>{const l=F.editor().get_curLevel().getLayerInstance(F.stamps);return [l.getGridTileStack(4,4),l.getGridTileStack(8,4)].map(v=>v.map(t=>t.tileId))};
 F.filters=()=>{
  const p=F.editor().project,mode=p.defs.getFieldDef(F.fields.Mode),label=p.defs.getFieldDef(F.fields.Label);
  mode.enumValueFilter=[{whenFieldUid:F.fields.Active,whenValue:false,allowedEnumValueIds:['A','C']},
   {whenFieldUid:F.fields.Active,whenValue:true,allowedEnumValueIds:['B','C']}];
  label.visibleWhenFieldUid=F.fields.Active;label.visibleWhenValues=[true];F.refresh();return true;
 };
 F.reload=()=>{
  const e=F.editor(),json=e.project.toJson();
  require('fs').writeFileSync(F.path,JSON.stringify(json));
  const p=H.Project.fromJson(F.path,JSON.parse(require('fs').readFileSync(F.path,'utf8')));p.tidy();
  H.App.ME.loadPage(()=>new H.Editor(p),false);return true;
 };
 return true;
})()
