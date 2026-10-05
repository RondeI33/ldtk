package test;
#if selection_template_tests
@:expose("TemplateTestHooks")
@:keep
@:access(App)
@:access(data.def.LayerDef)
@:access(page.Editor)
@:access(tool.SelectionTool)
class SelectionTemplatesTestHooks {
	static var devices:Array<data.inst.EntityInstance>=[];
	static var walls:data.inst.LayerInstance;
	static var floor:data.inst.LayerInstance;
	public static function setup(path:String):Dynamic {
		var p=data.Project.createEmpty(path);
		var ld=p.defs.createLayerDef(IntGrid,"Walls");
		ld.intGridValues=[
			{value:1,identifier:"Wall",color:0x889999,tile:null,groupUid:0},
			{value:2,identifier:"TemplateWall",color:0xcc8844,tile:null,groupUid:0},
		];
		var floorLd=p.defs.createLayerDef(Tiles,"Floor");
		var la=p.defs.createLayerDef(Entities,"Devices_A");
		var lb=p.defs.createLayerDef(Entities,"Devices_B");
		la.canSelectWhenInactive=lb.canSelectWhenInactive=true;
		var ed=p.defs.createEntityDef(); ed.identifier="Device"; ed.width=ed.height=16; ed.setPivot(0,0);
		var link=ed.createFieldDef(p,F_EntityRef,"Target",false);link.canBeNull=true;
		var amount=ed.createFieldDef(p,F_Int,"Amount",false);
		var label=ed.createFieldDef(p,F_String,"Label",false);
		var many=ed.createFieldDef(p,F_EntityRef,"Targets",true);many.canBeNull=true;
		var points=ed.createFieldDef(p,F_Point,"Path",true);points.canBeNull=true;
		p.tidy();
		var l=p.worlds[0].levels[0];l.pxWid=512;l.pxHei=320;
		walls=l.getLayerInstance(ld);walls.setIntGrid(2,2,1,false);
		floor=l.getLayerInstance(floorLd);
		floor.addGridTile(2,2,90,0,false,false);
		floor.addGridTile(2,2,91,0,true,false);
		devices=[];
		for(i in 0...3){
			var li=l.getLayerInstance(i==0?la:lb);
			var e=li.createEntityInstance(ed);e.x=64+i*64;e.y=64;e.getFieldInstance(amount,true).parseValue(0,Std.string(7+i));e.getFieldInstance(label,true).parseValue(0,"Source "+i);devices.push(e);
		}
		for(i in 0...3)devices[i].getFieldInstance(link,true).parseValue(0,devices[(i+1)%3].iid);
		var f=devices[0].getFieldInstance(many,true);f.addArrayValue();f.parseValue(0,devices[1].iid);f.addArrayValue();f.parseValue(1,devices[2].iid);
		var pf=devices[0].getFieldInstance(points,true);pf.addArrayValue();pf.parseValue(0,"6"+Const.POINT_SEPARATOR+"6");pf.addArrayValue();pf.parseValue(1,"7"+Const.POINT_SEPARATOR+"6");
		p.tidy();
		NT.writeFileString(path,haxe.Json.stringify(p.toJson()));
		App.ME.loadPage(()->new page.Editor(p),false);
		var editor=Editor.ME;editor.setWorldMode(false);editor.selectLayerInstance(l.getLayerInstance(la));editor.camera.fit(true);
		return {ids:devices.map(e->e.iid),walls:ld.uid,floor:floorLd.uid,layers:[la.uid,lb.uid],fields:{target:link.uid,targets:many.uid,amount:amount.uid,label:label.uid,path:points.uid}};
	}
	public static function selectAll():Void {
		var es:Array<GenericLevelElement>=[for(e in devices) Entity(e._li,e)];es.push(GridCell(walls,2,2));
		Editor.ME.selectionTool.select(es);
	}
	public static function dismissNotices():Void { ui.Modal.closeAll(); }
	public static function inputState():Dynamic return {
		alt:App.ME.isAltDown(),
		shift:App.ME.isShiftDown(),
		running:Editor.ME.selectionTool.isRunning(),
		selection:Editor.ME.selectionTool.debugContent(),
		selectedCount:Editor.ME.selectionTool.group.selectedElementsCount(),
		locked:Editor.ME.isLocked(),
		placing:Editor.ME.isSpecialToolActive(),
		specialRunning:Editor.ME.isSpecialToolActive() && Editor.ME.specialTool.isRunning()
	};
	public static function selectedEntityPositions():Array<Dynamic> {
		var out:Array<Dynamic>=[];
		for(ge in Editor.ME.selectionTool.group.allElements())
			switch ge {
				case Entity(_,ei): out.push({id:ei.iid,x:ei.x,y:ei.y});
				case _:
			}
		return out;
	}
	public static function selectionAnchor():Dynamic {
		for(ge in Editor.ME.selectionTool.group.allElements())
			switch ge {
				case Entity(_,ei):
					var c=Coords.fromLevelCoords(ei.centerX,ei.centerY);
					return {x:Math.round(c.pageX),y:Math.round(c.pageY)};
				case _:
			}
		return null;
	}
	public static function templateGhostStats():Dynamic {
		var t=Std.downcast(Editor.ME.specialTool,tool.SelectionTemplateTool);
		return t==null ? null : t.debugGhostStats();
	}
	public static function clear():Void Editor.ME.selectionTool.clear();
	public static function point(x:Int,y:Int):Dynamic {
		var c=Coords.fromLevelCoords(x,y);return {x:Math.round(c.pageX),y:Math.round(c.pageY)};
	}
	public static function source():String return haxe.Json.stringify(Editor.ME.curLevel.toJson(true));
	public static function templates():Array<Dynamic> return data.SelectionTemplates.load(Editor.ME.project);
	public static function needSaving():Bool return Editor.ME.needSaving;
	public static function saveProject():Void Editor.ME.onSave();
	public static function saveStatus():Dynamic {
		return {
			locked:Editor.ME.isLocked(),
			saver:ui.ProjectSaver.hasAny(),
			unclosable:ui.Modal.hasAnyUnclosable(),
			modalOpen:ui.Modal.hasAnyOpen(),
			needSaving:Editor.ME.needSaving,
			modals:[for(m in ui.Modal.ALL) {
				type:Type.getClassName(Type.getClass(m)),
				closing:m.isClosing(),
				manual:m.canBeClosedManually,
			}],
		};
	}
	public static function saveProjectDebug():Dynamic {
		var before=saveStatus();
		Editor.ME.onSave();
		var after=saveStatus();
		return {before:before,after:after};
	}
	public static function saveInProgress():Bool return ui.ProjectSaver.hasAny();
	public static function reloadTemplateStage():Void data.SelectionTemplates.loadProject(Editor.ME.project);
	public static function deleteTemplate(id:String):Void data.SelectionTemplates.remove(Editor.ME.project,id);
	public static function openImportPicker(absProjectPath:String):Void data.SelectionTemplates.openImportPickerFromPath(Editor.ME,absProjectPath);
	public static function place(index:Int,x:Int,y:Int):Bool return data.SelectionTemplates.place(Editor.ME,templates()[index],x,y);
	public static function placeOverwriteFixture():Bool {
		var cells:Array<Dynamic>=[
			{
				layerDefUid:walls.layerDefUid,
				gridSize:walls.def.gridSize,
				relX:0,
				relY:0,
				kind:"intgrid",
				value:2,
			},
			{
				layerDefUid:floor.layerDefUid,
				gridSize:floor.def.gridSize,
				relX:0,
				relY:0,
				kind:"tiles",
				tiles:[
					{tileId:7,flips:1},
					{tileId:8,flips:2},
				],
			},
		];
		var tpl:Dynamic={
			schemaVersion:1,
			id:"overwrite-fixture",
			name:"Overwrite fixture",
			width:walls.def.gridSize,
			height:walls.def.gridSize,
			excludedLayerUids:[],
			entities:[],
			cells:cells,
		};
		return data.SelectionTemplates.place(Editor.ME,tpl,2*walls.def.gridSize,2*walls.def.gridSize);
	}
	public static function overwriteGridState():Dynamic {
		var curWalls=Editor.ME.curLevel.getLayerInstance(walls.layerDefUid);
		var curFloor=Editor.ME.curLevel.getLayerInstance(floor.layerDefUid);
		return {
			intGrid:curWalls.getIntGrid(2,2),
			tiles:[for(t in curFloor.getGridTileStack(2,2)) {tileId:t.tileId,flips:t.flips}],
		};
	}
	public static function undo():Void Editor.ME.curLevelTimeline.undo();
	public static function redo():Void Editor.ME.curLevelTimeline.redo();
	public static function wallState():String { var j:Dynamic=Editor.ME.curLevel.getLayerInstance(walls.layerDefUid).toJson(); if(j.overrideTilesetUid==null) Reflect.deleteField(j,"overrideTilesetUid"); return haxe.Json.stringify(j); }
	public static function entityCount():Int {var n=0;for(li in Editor.ME.curLevel.layerInstances)n+=li.entityInstances.length;return n;}
	public static function references():Dynamic {
		var p=Editor.ME.project;var all:Array<Dynamic>=[];
		for(li in Editor.ME.curLevel.layerInstances)for(e in li.entityInstances){
			var refs:Array<Dynamic>=[];
			for(f in e.fieldInstances)if(f.def.type==F_EntityRef)for(i in 0...f.getArrayLength())if(!f.valueIsNull(i))refs.push({id:f.getEntityRefIid(i),resolved:f.getEntityRefInstance(i)!=null});
			all.push({id:e.iid,refs:refs});
		}return all;
	}
}
#end
