package test;
#if selection_drag_tests
@:expose("SelectionDragTestHooks")
@:keep
@:access(App)
@:access(page.Editor)
@:access(data.def.LayerDef)
@:access(tool.SelectionTool)
@:access(GenericLevelElementGroup)
class SelectionDragTestHooks {
	static var tilesAUid:Int;
	static var tilesBUid:Int;
	static var intGridUid:Int;
	static var entitiesUid:Int;
	static var bigTilesUid:Int;
	static var entityDefUid:Int;
	static var pointFieldUid:Int;
	static var caseDx=0;
	static var caseDy=0;
	static var testGroup:GenericLevelElementGroup;
	static var flipDrop:Coords;

	static function editor() {
		var current=Std.downcast(@:privateAccess App.ME.curPageProcess,page.Editor);
		var e=current!=null ? current : Editor.ME;
		if( e!=null && !e.destroyed && Editor.ME!=e )
			Editor.ME=e;
		return e;
	}
	static inline function level() return editor().curLevel;
	static inline function tilesA() return level().getLayerInstance(tilesAUid);
	static inline function tilesB() return level().getLayerInstance(tilesBUid);
	static inline function ints() return level().getLayerInstance(intGridUid);
	static inline function entities() return level().getLayerInstance(entitiesUid);
	static inline function bigTiles() return level().getLayerInstance(bigTilesUid);

	public static function ready():Bool {
		var e=editor();
		return e!=null
			&& !e.destroyed
			&& e.levelRender!=null
			&& e.curLevel!=null;
	}

	public static function setup(path:String, ?atlasPath:String):Dynamic {
		if(testGroup!=null) {
			testGroup.dispose();
			testGroup=null;
		}
		var p=data.Project.createEmpty(path);
		var a=p.defs.createLayerDef(Tiles,"Tiles_A");
		var b=p.defs.createLayerDef(Tiles,"Tiles_B");
		var ig=p.defs.createLayerDef(IntGrid,"Collision");
		var ent=p.defs.createLayerDef(Entities,"Entities");
		var big=p.defs.createLayerDef(Tiles,"BigTiles");
		a.gridSize=b.gridSize=ig.gridSize=ent.gridSize=16;
		big.gridSize=32;
		var sharedTileset=p.defs.createTilesetDef();
		sharedTileset.identifier="SharedTiles";
		sharedTileset.tileGridSize=16;
		a.tilesetDefUid=b.tilesetDefUid=big.tilesetDefUid=sharedTileset.uid;
		a.canSelectWhenInactive=b.canSelectWhenInactive=ig.canSelectWhenInactive=ent.canSelectWhenInactive=big.canSelectWhenInactive=true;
		ig.intGridValues=[
			{value:1,identifier:"Keep",color:0x446688,tile:null,groupUid:0},
			{value:2,identifier:"Move",color:0xcc8844,tile:null,groupUid:0},
		];
		if(atlasPath!=null) {
			if(sharedTileset.importAtlasImage(atlasPath)!=Ok)
				throw "Could not load the selection flip fixture atlas";
			ig.tilesetDefUid=sharedTileset.uid;
			var rules=ig.createEmptyRuleGroup(p.generateUniqueId_int(),"Flip regression");
			for(value in 1...3) {
				var rule=new data.def.AutoLayerRuleDef(p.generateUniqueId_int(),1);
				rule.fill(value);
				rule.tileRectsIds=[[69+value]];
				rules.rules.push(rule);
			}
		}
		var ed=p.defs.createEntityDef();
		ed.identifier="Marker";
		ed.width=ed.height=16;
		ed.setPivot(0,0);
		var pf=ed.createFieldDef(p,F_Point,"Path",true);
		pf.canBeNull=true;
		p.tidy();

		tilesAUid=a.uid; tilesBUid=b.uid; intGridUid=ig.uid; entitiesUid=ent.uid; bigTilesUid=big.uid;
		entityDefUid=ed.uid; pointFieldUid=pf.uid;

		var l=p.worlds[0].levels[0];
		l.pxWid=640; l.pxHei=384;
		seedOnProject(p,l,5,1,false);
		p.tidy();
		NT.writeFileString(path,haxe.Json.stringify(p.toJson()));
		App.ME.loadPage(()->new page.Editor(p),false);
		var e=editor();
		e.setWorldMode(false);
		e.selectLayerInstance(e.curLevel.getLayerInstance(a));
		e.camera.fit(true);
		if(testGroup!=null) testGroup.dispose();
		testGroup=new GenericLevelElementGroup();
		selectNormal();
		return {grid:16,bigGrid:32};
	}

	static function clearLayerGrid(li:data.inst.LayerInstance) {
		for(cy in 0...li.cHei)
		for(cx in 0...li.cWid)
			switch li.def.type {
				case Tiles: li.removeAllGridTiles(cx,cy,false);
				case IntGrid: li.removeIntGrid(cx,cy,false);
				case _:
			}
	}

	static function seedOnProject(p:data.Project,l:data.Level,dx:Int,dy:Int,mixed:Bool) {
		var a=l.getLayerInstance(tilesAUid);
		var b=l.getLayerInstance(tilesBUid);
		var ig=l.getLayerInstance(intGridUid);
		var ent=l.getLayerInstance(entitiesUid);
		var big=l.getLayerInstance(bigTilesUid);
		clearLayerGrid(a); clearLayerGrid(b); clearLayerGrid(ig); clearLayerGrid(big);
		for(e in ent.entityInstances.copy()) ent.removeEntityInstance(e);

		a.addGridTile(2,2,10,0,false,false);
		a.addGridTile(4,2,20,0,false,false);
		b.addGridTile(2,3,30,0,false,false);
		ig.setIntGrid(2,4,2,false);

		// Data inside the selected rectangle but at positions where the selection
		// itself is empty. These must survive a copy/move.
		a.addGridTile(3+dx,3+dy,90,0,false,false);
		b.addGridTile(3+dx,3+dy,91,0,false,false);
		ig.setIntGrid(3+dx,3+dy,1,false);

		var ed=p.defs.getEntityDef(entityDefUid);
		var ei=ent.createEntityInstance(ed);
		ei.x=2*16; ei.y=5*16;
		var fi=ei.getFieldInstance(ed.getFieldDef(pointFieldUid),true);
		fi.addArrayValue();
		fi.parseValue(0,"3"+Const.POINT_SEPARATOR+"5");

		if(mixed) {
			big.addGridTile(1,1,50,0,false,false);
			// empty-space sentinel inside the 32px selection rectangle destination
			big.addGridTile(2+Std.int(dx/2),2+Std.int(dy/2),95,0,false,false);
		}
	}

	public static function prepare(dx:Int,dy:Int,mixed=false):Void {
		caseDx=dx; caseDy=dy;
		if(testGroup!=null) testGroup.dispose();
		testGroup=new GenericLevelElementGroup();
		seedOnProject(editor().project,level(),dx,dy,mixed);
		selectNormal(mixed);
		// Keep this regression focused on Selection transfer semantics. The
		// fixture intentionally uses data-only Tiles cells without an atlas, so
		// forcing a full level render here would test an invalid tileset setup
		// instead of move/copy behavior.
	}

	static function selectNormal(mixed=false) {
		var es:Array<GenericLevelElement>=[
			GridCell(tilesA(),2,2),
			GridCell(tilesA(),4,2),
			GridCell(tilesB(),2,3),
			GridCell(ints(),2,4),
		];
		var ei=entities().entityInstances[0];
		es.push(Entity(entities(),ei));
		var fi=ei.getFieldInstance(editor().project.defs.getFieldDef(pointFieldUid),true);
		es.push(PointField(entities(),ei,fi,0));
		if(mixed)
			es.push(GridCell(bigTiles(),1,1));
		for(e in es)
			testGroup.add(e);
		testGroup.addSelectionRect(2*16,5*16,2*16,6*16);
	}

	public static function drag(isCopy:Bool,originX:Int,originY:Int,toX:Int,toY:Int,saveHistory=false):Dynamic {
		var e=editor(); // resync Editor.ME for Coords helpers immediately before use
		var g=testGroup;
		var o=Coords.fromLevelCoords(originX,originY);
		var t=Coords.fromLevelCoords(toX,toY);
		g.onMoveStart(isCopy);
		g.showGhost(o,t,isCopy);
		var ghost={x:g.ghost.x,y:g.ghost.y};
		var changed=g.commitDragSnapshot(o,t,isCopy);
		if(saveHistory && changed.length>0)
			editor().saveLayerStatesByLevel(changed);
		g.onMoveEnd();
		return {ghost:ghost,changed:changed.length};
	}

	public static function startAndCancel(isCopy:Bool):Void {
		var g=testGroup;
		g.onMoveStart(isCopy);
		g.onMoveEnd();
	}

	static function tileStack(li:data.inst.LayerInstance,cx:Int,cy:Int):Array<Dynamic>
		return [for(t in li.getGridTileStack(cx,cy)) {tileId:t.tileId,flips:t.flips}];


	public static function prepareLayerTransfer(blockDestination=false, fromB=false, mixed=false):Void {
		var a=tilesA(),b=tilesB();
		clearLayerGrid(a);clearLayerGrid(b);clearLayerGrid(ints());clearLayerGrid(bigTiles());

		var source=fromB ? b : a;
		var target=fromB ? a : b;
		source.addGridTile(2,2,10,0,false,false);
		source.addGridTile(2,2,11,1,true,false);
		source.addGridTile(4,2,20,2,false,false);
		source.addGridTile(6,2,66,0,false,false);
		// This lies inside the visual selection rectangle but is not selected data.
		target.addGridTile(3,2,88,0,false,false);
		if(blockDestination)
			target.addGridTile(4,2,77,0,false,false);

		var e=editor();
		// The fixture mutates layer data directly after hundreds of history-free
		// matrix cases. Record this exact pre-transfer state so Undo validates the
		// transfer itself instead of restoring an unrelated earlier test state.
		e.curLevelTimeline.saveLayerStates([a,b]);
		e.selectionTool.clear();
		e.selectLayerInstance(source);
		e.selectionTool.select([
			GridCell(source,2,2),
			GridCell(source,4,2),
		]);
		e.selectionTool.group.addSelectionRect(2*16,5*16,2*16,3*16);
		if(mixed)
			e.selectionTool.select([GridCell(target,3,2)],true);
	}


	public static function layerTransfer(direction:Int):Bool
		return editor().selectionTool.moveSelectionToCompatibleLayer(direction);



	public static function layerTransferShortcut(direction:Int):Bool {
		@:privateAccess App.ME.jsKeyDowns.set(K.CTRL,true);
		@:privateAccess App.ME.jsKeyDowns.set(K.ALT,true);
		var handled=false;
		try handled=editor().selectionTool.handleLayerTransferShortcut(direction<0 ? K.UP : K.DOWN)
		catch(e:Dynamic) {
			@:privateAccess App.ME.jsKeyDowns.remove(K.CTRL);
			@:privateAccess App.ME.jsKeyDowns.remove(K.ALT);
			throw e;
		}
		@:privateAccess App.ME.jsKeyDowns.remove(K.CTRL);
		@:privateAccess App.ME.jsKeyDowns.remove(K.ALT);
		return handled;
	}


	public static function layerTransferState():Dynamic {
		var e=editor();
		return {
			a22:tileStack(tilesA(),2,2),
			a32:tileStack(tilesA(),3,2),
			a42:tileStack(tilesA(),4,2),
			a62:tileStack(tilesA(),6,2),
			b22:tileStack(tilesB(),2,2),
			b32:tileStack(tilesB(),3,2),
			b42:tileStack(tilesB(),4,2),
			b62:tileStack(tilesB(),6,2),
			active:e.curLayerInstance==null ? null : e.curLayerInstance.def.identifier,
			selectionLayers:e.selectionTool.group.getSelectedLayerInstances().map(li->li.def.identifier),
		};
	}


	public static function prepareIntGridLayerTransfer():Void {
		clearLayerGrid(ints());
		ints().setIntGrid(2,2,2,false);
		var e=editor();
		e.selectionTool.clear();
		e.selectLayerInstance(ints());
		e.selectionTool.select([GridCell(ints(),2,2)]);
	}


	public static function prepareFlip(kind:String):Void {
		var e=editor();
		e.selectionTool.clear();
		if(testGroup!=null) testGroup.clear();
		var a=tilesA(),b=tilesB(),ig=ints();
		for(li in [a,b,ig,bigTiles()]) clearLayerGrid(li);
		var selected:Array<GenericLevelElement>=[];
		if(kind=="tiles" || kind=="mixed") {
			a.addGridTile(2,2,10,0,false,false);
			a.addGridTile(2,2,11,1,true,false);
			a.addGridTile(4,2,20,2,false,false);
			a.addGridTile(2,4,30,3,false,false);
			for(c in [{x:2,y:2},{x:4,y:2},{x:2,y:4}])
				selected.push(GridCell(a,c.x,c.y));
		}
		if(kind=="mixed") {
			b.addGridTile(4,4,40,0,false,false);
			b.addGridTile(2,3,41,1,false,false);
			selected.push(GridCell(b,4,4));
			selected.push(GridCell(b,2,3));
		}
		if(kind=="intgrid" || kind=="mixed") {
			ig.setIntGrid(2,2,1,false);
			ig.setIntGrid(4,2,2,false);
			ig.setIntGrid(2,4,2,false);
			for(c in [{x:2,y:2},{x:4,y:2},{x:2,y:4}])
				selected.push(GridCell(ig,c.x,c.y));
		}
		// The unselected center remains a hole under either reflection. Test
		// both the source and destination, plus an unrelated different-grid layer.
		for(c in [{x:3,y:3},{x:11,y:8}]) {
			a.addGridTile(c.x,c.y,90,0,false,false);
			b.addGridTile(c.x,c.y,91,0,false,false);
			ig.setIntGrid(c.x,c.y,1,false);
		}
		bigTiles().addGridTile(1,1,95,0,false,false);
		for(li in [a,b,ig,bigTiles()])
			e.ge.emit(LayerInstanceChangedGlobally(li));
		e.selectLayerInstance(kind=="intgrid" ? ig : a);
		e.curLevelTimeline.clear();
		e.selectionTool.select(selected);
		// addSelectionRect stores inclusive pixel edges.
		e.selectionTool.group.addSelectionRect(32,79,32,79);
		flipDrop=null;
	}


	public static function flipCommands(axes:String):Void {
		var tool=editor().selectionTool;
		if(!tool.canFlipSelection()) throw "Fixture selection is not flippable";
		for(i in 0...axes.length)
			switch axes.charAt(i) {
				case "x": tool.onAppCommand(C_FlipX);
				case "y": tool.onAppCommand(C_FlipY);
				case _: throw "Unknown flip axis";
			}
	}


	public static function startFlipDrag(isCopy:Bool):Dynamic {
		var e=editor(),tool=e.selectionTool;
		var origin=Coords.fromLevelCoords(40,40);
		flipDrop=Coords.fromLevelCoords(40+8*16,40+5*16);
		var commandKey=App.isMac() ? 91 : K.CTRL;
		var previousCommand=App.ME.jsKeyDowns.get(commandKey);
		var previousAlt=App.ME.jsKeyDowns.get(K.ALT);
		App.ME.jsKeyDowns.set(commandKey,isCopy);
		App.ME.jsKeyDowns.set(K.ALT,isCopy);
		try {
			var push=new hxd.Event(EPush);
			push.button=0;
			tool.startUsing(push,origin);
		}
		catch(error:Dynamic) {
			App.ME.jsKeyDowns.set(commandKey,previousCommand);
			App.ME.jsKeyDowns.set(K.ALT,previousAlt);
			throw error;
		}
		App.ME.jsKeyDowns.set(commandKey,previousCommand);
		App.ME.jsKeyDowns.set(K.ALT,previousAlt);
		tool.onMouseMove(new hxd.Event(EMove),flipDrop);
		if(!tool.isRunning() || !tool.moveStarted || tool.isCopy!=isCopy)
			throw "SelectionTool did not enter the expected move/copy gesture";
		return {running:tool.isRunning(),moving:tool.moveStarted,isCopy:tool.isCopy};
	}


	public static function finishFlipDrag():Dynamic {
		var tool=editor().selectionTool;
		if(flipDrop==null) throw "No flip drag to finish";
		// This is the mouse-up path from the reported crash, including useAt,
		// commitDragSnapshot, both pending flips, and one history transaction.
		tool.stopUsing(flipDrop);
		return {running:tool.isRunning(),moving:tool.moveStarted,flipX:tool.dragFlipX,flipY:tool.dragFlipY};
	}


	public static function flipState():Dynamic {
		// Flush normal pending renders, including the temporary source cut, so
		// an animation frame between IPC calls cannot look like a flip mutation.
		editor().levelRender.updateInvalidations();
		function tiles(li:data.inst.LayerInstance):Array<Dynamic> {
			var result:Array<Dynamic>=[];
			for(cy in 0...li.cHei)
			for(cx in 0...li.cWid)
				if(li.hasAnyGridTile(cx,cy))
					result.push({cx:cx,cy:cy,tiles:tileStack(li,cx,cy)});
			return result;
		}
		var ig=ints(),values:Array<Dynamic>=[],autoTiles:Array<Dynamic>=[];
		for(cy in 0...ig.cHei)
		for(cx in 0...ig.cWid)
			if(ig.hasIntGrid(cx,cy)) values.push({cx:cx,cy:cy,value:ig.getIntGrid(cx,cy)});
		if(ig.autoTilesCache!=null)
			for(byCell in ig.autoTilesCache)
			for(stack in byCell)
			for(tile in stack)
				autoTiles.push({cx:Std.int(tile.x/16),cy:Std.int(tile.y/16),tileId:tile.tid,flips:tile.flips});
		autoTiles.sort((a,b)->a.cy==b.cy ? a.cx-b.cx : a.cy-b.cy);
		return {tilesA:tiles(tilesA()),tilesB:tiles(tilesB()),ints:values,autoTiles:autoTiles,bigTiles:tiles(bigTiles())};
	}


	public static function state():Dynamic {
		var dx=caseDx,dy=caseDy;
		var allEntities:Array<Dynamic>=[];
		for(e in entities().entityInstances) {
			var fi=e.getFieldInstance(editor().project.defs.getFieldDef(pointFieldUid),true);
			var pts:Array<Dynamic>=[];
			if(fi!=null)
				for(i in 0...fi.getArrayLength()) {
					var pt=fi.getPointGrid(i);
					if(pt!=null) pts.push({cx:pt.cx,cy:pt.cy});
				}
			allEntities.push({x:e.x,y:e.y,points:pts});
		}
		allEntities.sort((a,b)->a.x==b.x ? a.y-b.y : a.x-b.x);
		return {
			source:{
				a22:tileStack(tilesA(),2,2),
				a42:tileStack(tilesA(),4,2),
				b23:tileStack(tilesB(),2,3),
				i24:ints().getIntGrid(2,4),
			},
			dest:{
				a22:tileStack(tilesA(),2+dx,2+dy),
				a42:tileStack(tilesA(),4+dx,2+dy),
				b23:tileStack(tilesB(),2+dx,3+dy),
				i24:ints().getIntGrid(2+dx,4+dy),
			},
			sentinels:{
				a:tileStack(tilesA(),3+dx,3+dy),
				b:tileStack(tilesB(),3+dx,3+dy),
				i:ints().getIntGrid(3+dx,3+dy),
			},
			entities:allEntities,
		};
	}

	public static function undo():Void editor().curLevelTimeline.undo();
	public static function redo():Void editor().curLevelTimeline.redo();
	public static function settle():Void {}
}
#end
