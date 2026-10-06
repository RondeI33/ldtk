package test;
#if selection_drag_tests
/** Test-only access to the real selection input path, never compiled in releases. */
@:expose("SelectionInputTestHooks")
@:keep
@:access(App)
@:access(Tool)
@:access(page.Editor)
@:access(tool.SelectionTool)
@:access(GenericLevelElementGroup)
@:access(test.SelectionDragTestHooks)
@:access(data.def.LayerDef)
class SelectionInputTestHooks {
	static function editor() return SelectionDragTestHooks.editor();

	static function layers():Array<data.inst.LayerInstance> return [
		SelectionDragTestHooks.tilesA(), SelectionDragTestHooks.tilesB(),
		SelectionDragTestHooks.ints(), SelectionDragTestHooks.bigTiles()
	];

	static function layerKey(li:data.inst.LayerInstance):String {
		if(li.layerDefUid==SelectionDragTestHooks.tilesAUid) return "a";
		if(li.layerDefUid==SelectionDragTestHooks.tilesBUid) return "b";
		if(li.layerDefUid==SelectionDragTestHooks.intGridUid) return "i";
		return "big";
	}

	/** Every occupied grid cell, including data outside the selection rectangle. */
	public static function grids():Array<Dynamic> {
		var out:Array<Dynamic>=[];
		for(li in layers())
			for(cy in 0...li.cHei)
				for(cx in 0...li.cWid)
					if(li.hasAnyGridValue(cx,cy)) {
						if(li.def.type==IntGrid)
							out.push({layer:layerKey(li),cx:cx,cy:cy,value:li.getIntGrid(cx,cy)});
						else
							out.push({layer:layerKey(li),cx:cx,cy:cy,tiles:[
								for(t in li.getGridTileStack(cx,cy)) {tileId:t.tileId,flips:t.flips}
							]});
					}
		return out;
	}

	public static function selectedCells():Array<Dynamic> {
		var out:Array<Dynamic>=[];
		for(ge in SelectionDragTestHooks.testGroup.allElements())
			switch ge {
				case GridCell(li,cx,cy): out.push({layer:layerKey(li),cx:cx,cy:cy,grid:li.def.gridSize});
				case _:
			}
		return out;
	}

	public static function configure():Void {
		App.ME.settings.v.tileStacking=false;
		App.ME.settings.v.singleLayerMode=false;
		App.ME.settings.v.emptySpaceSelection=true;
	}

	static function adoptSelection():tool.SelectionTool {
		var t=editor().selectionTool;
		t.clear();
		for(ge in SelectionDragTestHooks.testGroup.allElements()) t.group.add(ge);
		for(r in SelectionDragTestHooks.testGroup.originalRects)
			t.group.addSelectionRect(Std.int(r.leftPx),Std.int(r.rightPx),Std.int(r.topPx),Std.int(r.bottomPx));
		return t;
	}

	/** Drive start/move/release handlers; copy mode is injected, not remapped. */
	public static function mouseDrag(isCopy:Bool,ox:Int,oy:Int,tx:Int,ty:Int):Dynamic {
		var t=adoptSelection();
		var o=Coords.fromLevelCoords(ox,oy);
		var n=Coords.fromLevelCoords(tx,ty);
		var ev:hxd.Event=cast {button:0,cancel:false};
		t.startUsing(ev,o);
		if(!t.isRunning()) throw "SelectionTool did not start";
		t.isCopy=isCopy;
		t.onMouseMove(ev,n);
		var preview={visible:t.group.ghost.visible,x:t.group.ghost.x,y:t.group.ghost.y};
		var moving=t.moveStarted;
		t.stopUsing(n);
		return {moving:moving,preview:preview,running:t.isRunning()};
	}

	/** Rectangle gestures must never cut existing source data, even temporarily. */
	public static function marquee(hasSelection:Bool,isCopy:Bool):Dynamic {
		var t=adoptSelection();
		if(!hasSelection) t.clear();
		var before=grids();
		var o=Coords.fromLevelCoords(33,33);
		var n=Coords.fromLevelCoords(240,176);
		var ev:hxd.Event=cast {button:0,cancel:false};
		t.startUsing(ev,o,"noDefaultSelection");
		if(!t.isRunning()) throw "Marquee tool did not start";
		// Tool.startUsing normally takes this flag from Shift. Injecting only the
		// modifier state lets the actual mouse-move/release handlers be tested.
		t.rectangle=true;
		t.isCopy=isCopy;
		t.onMouseMove(ev,n);
		var during=grids();
		var moving=t.moveStarted;
		var cut=t.group.dragSourceCut;
		t.stopUsing(n);
		return {before:before,during:during,after:grids(),moving:moving,cut:cut};
	}

	public static function emptyDrag():Dynamic {
		var t=editor().selectionTool;
		t.clear();
		var before=grids();
		var o=Coords.fromLevelCoords(400,240);
		var n=Coords.fromLevelCoords(560,304);
		var ev:hxd.Event=cast {button:0,cancel:false};
		t.startUsing(ev,o,"noDefaultSelection");
		t.rectangle=false;
		t.onMouseMove(ev,n);
		var moving=t.moveStarted;
		t.stopUsing(n);
		return {moving:moving,before:before,after:grids()};
	}

	/** A rectangle immediately above/left of an offset layer excludes cell zero. */
	public static function offsetBoundary(horizontal:Bool,offset:Int):Dynamic {
		var e=editor();
		var t=e.selectionTool;
		t.clear();
		var li=SelectionDragTestHooks.ints();
		SelectionDragTestHooks.clearLayerGrid(li);
		var oldX=li.def.pxOffsetX;
		var oldY=li.def.pxOffsetY;
		li.def.pxOffsetX=horizontal ? offset : 0;
		li.def.pxOffsetY=horizontal ? 0 : offset;
		li.setIntGrid(horizontal ? 0 : 1,horizontal ? 1 : 0,2,false);
		e.selectLayerInstance(SelectionDragTestHooks.tilesA());
		var m=Coords.fromLevelCoords(0,0);
		// The active 16px layer covers [0,15] on the tested axis. An offset
		// of 16..31 puts that entire span before the other layer's first cell.
		if(horizontal) t.useOnRectangle(m,0,0,0,2);
		else t.useOnRectangle(m,0,2,0,0);
		var selected=false;
		for(ge in t.group.allElements())
			switch ge {
				case GridCell(found,_,_): if(found==li) selected=true;
				case _:
			}
		li.def.pxOffsetX=oldX;
		li.def.pxOffsetY=oldY;
		t.clear();
		return {selected:selected};
	}
}
#end
