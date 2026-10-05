package test;
#if selection_regression_tests
@:expose("SceneSelectionTests")
@:keep
@:access(data.def.LayerDef)
@:access(data.inst.LayerInstance)
@:access(GenericLevelElementGroup)
@:access(tool.SelectionTool)
@:access(page.Editor)
@:access(display.Camera)
class SceneSelectionTests {
	static var aUid:Int;
	static var bUid:Int;
	static var eUid:Int;
	static var underUid:Int;
	static var hiddenUid:Int;
	static var edUid:Int;
	static var pathUid:Int;
	static var refUid:Int;
	static var sourceUid:Int;
	static var targetUid:Int;
	static var passes:Array<String>=[];
	static var assertions=0;
	static var caseName="";

	static function check(ok:Bool,message:String) {
		assertions++;
		if(!ok) throw caseName+": "+message;
	}
	static function same(a:Dynamic,b:Dynamic,message:String) {
		check(haxe.Json.stringify(a)==haxe.Json.stringify(b),message+"; actual="+haxe.Json.stringify(a)+" expected="+haxe.Json.stringify(b));
	}
	static function source():data.Level return Editor.ME.project.getLevelAnywhere(sourceUid);
	static function target():data.Level return Editor.ME.project.getLevelAnywhere(targetUid);
	static function li(uid:Int,other=false):data.inst.LayerInstance return (other?target():source()).getLayerInstance(uid);

	public static function setup(path:String):Dynamic {
		var p=data.Project.createEmpty(path);
		var a=p.defs.createLayerDef(IntGrid,"SelectionGrid"); aUid=a.uid;
		var b=p.defs.createLayerDef(Tiles,"SelectionTiles"); bUid=b.uid;
		var e=p.defs.createLayerDef(Entities,"SelectionEntities"); eUid=e.uid;
		var under=p.defs.createLayerDef(IntGrid,"UnselectedUnderlay"); underUid=under.uid;
		var hidden=p.defs.createLayerDef(IntGrid,"HiddenUnderlay"); hiddenUid=hidden.uid;
		for(ld in [a,under,hidden]) {
			ld.intGridValues=[];
			for(i in 1...10) ld.intGridValues.push({value:i,identifier:"V"+i,color:0x447766+i*0x10101,tile:null,groupUid:0});
		}
		under.canSelectWhenInactive=false;
		var ed=p.defs.createEntityDef(); edUid=ed.uid; ed.identifier="SelectionActor"; ed.width=12; ed.height=14; ed.setPivot(0,0);
		var pf=ed.createFieldDef(p,F_Point,"Path",true); pf.canBeNull=true; pathUid=pf.uid;
		var rf=ed.createFieldDef(p,F_EntityRef,"Target",false); rf.canBeNull=true; refUid=rf.uid;
		p.tidy();
		var s=p.worlds[0].levels[0]; sourceUid=s.uid; s.worldX=-512; s.worldY=-384; s.pxWid=768; s.pxHei=640;
		var t=p.worlds[0].createLevel(); targetUid=t.uid; t.worldX=512; t.worldY=-384; t.pxWid=768; t.pxHei=640;
		p.tidy();
		NT.writeFileString(path,haxe.Json.stringify(p.toJson()));
		App.ME.loadPage(()->new page.Editor(p),false);
		Editor.ME.setWorldMode(false); Editor.ME.selectLayerInstance(li(eUid));
		Editor.ME.camera.setZoom(2);
		passes=[]; assertions=0;
		return {source:sourceUid,target:targetUid};
	}

	static function reset(grid=16,offset=0) {
		var editor=Editor.ME;
		editor.selectionTool.clear(); editor.clearSpecialTool();
		for(ld in editor.project.defs.layers) {
			ld.gridSize=grid; ld.pxOffsetX=offset; ld.pxOffsetY=-offset;
			ld.parallaxFactorX=ld.parallaxFactorY=0; ld.parallaxScaling=false;
		}
		for(l in [source(),target()]) for(v in l.layerInstances) {
			v.pxOffsetX=v.pxOffsetY=0; v.visible=v.layerDefUid!=hiddenUid;
			if(v.def.type==IntGrid) {
				var keys=[for(k in v.intGrid.keys()) k];
				for(k in keys) v.removeIntGrid(k%v.cWid,Std.int(k/v.cWid),false);
			}
			v.gridTiles=[];
			for(e in v.entityInstances.copy()) v.removeEntityInstance(e);
		}
		editor.project.defs.getEntityDef(edUid).maxCount=0;
		App.ME.settings.v.tileStacking=false;
		App.ME.settings.v.emptySpaceSelection=false;
	}
	static function actor(x:Int,y:Int,other=false):data.inst.EntityInstance {
		var e=li(eUid,other).createEntityInstance(Editor.ME.project.defs.getEntityDef(edUid));
		e.x=x; e.y=y; return e;
	}
	static function coords(x:Float,y:Float,other=false):Coords {
		var l=other?target():source();
		return Coords.fromWorldCoords(l.worldX+x,l.worldY+y);
	}
	static function selection(elems:Array<GenericLevelElement>,rect=false,left=0.,top=0.,right=0.,bottom=0.):GenericLevelElementGroup {
		var g=new GenericLevelElementGroup(elems);
		if(rect) g.addSelectionRect(left,right,top,bottom);
		return g;
	}
	static function signature(v:data.inst.LayerInstance):Dynamic {
		var grids:Array<Dynamic>=[];
		if(v.def.type==IntGrid) {
			var keys=[for(k in v.intGrid.keys()) k]; keys.sort((a,b)->a-b);
			for(k in keys) grids.push({id:k,value:v.intGrid.get(k)});
		}
		var tiles:Array<Dynamic>=[], keys=[for(k in v.gridTiles.keys()) k]; keys.sort((a,b)->a-b);
		for(k in keys) tiles.push({id:k,stack:v.gridTiles.get(k).copy()});
		var entities:Array<Dynamic>=[];
		for(e in v.entityInstances) entities.push({id:e.iid,x:e.x,y:e.y,fields:[for(fi in e.fieldInstances) fi.toJson()]});
		return {grids:grids,tiles:tiles,entities:entities};
	}
	static function transfer(g:GenericLevelElementGroup,from:Coords,to:Coords,copy:Bool,drag:Bool,fx=false,fy=false):Array<data.inst.LayerInstance> {
		var d=SelectionMove.delta(g,from,to);
		if(drag) {
			g.onMoveStart(copy,from); g.setGhostFlip(fx,fy); g.showGhost(from,to,copy);
			check(Math.abs(g.ghost.x-g.bounds.left-d.x)<0.001,"ghost horizontal delta");
			check(Math.abs(g.ghost.y-g.bounds.top-d.y)<0.001,"ghost vertical delta");
			var changed=g.commitDragSnapshot(from,to,copy,fx,fy); g.onMoveEnd(); return changed;
		}
		return g.moveSelecteds(from,to,copy);
	}

	public static function matrix():Dynamic {
		var directions=[{x:-4,y:-4},{x:0,y:-4},{x:4,y:-4},{x:-4,y:0},{x:4,y:0},{x:-4,y:4},{x:0,y:4},{x:4,y:4}];
		for(grid in [8,16,32]) for(copy in [false,true]) for(drag in [false,true]) for(rect in [false,true]) for(phase in [0,1]) for(dir in directions) {
			caseName='grid=$grid copy=$copy drag=$drag rect=$rect phase=$phase delta=${dir.x},${dir.y}';
			reset(grid,3);
			var a=li(aUid), b=li(bUid), under=li(underUid), hidden=li(hiddenUid);
			a.setIntGrid(8,8,1,false); a.setIntGrid(10,8,2,false);
			b.addGridTile(8,10,7,1,false,false); b.addGridTile(8,10,8,2,true,false);
			var e=actor(8*grid+3,8*grid+5), oldIid=e.iid;
			var hx=9+dir.x, hy=8+dir.y;
			a.setIntGrid(hx,hy,9,false);
			under.setIntGrid(8+dir.x,8+dir.y,8,false); hidden.setIntGrid(10+dir.x,8+dir.y,7,false);
			var underBefore=signature(under), hiddenBefore=signature(hidden);
			App.ME.settings.v.emptySpaceSelection=rect;
			var g=selection([GridCell(a,8,8),GridCell(a,10,8),GridCell(b,8,10),Entity(e._li,e)],rect,8*grid+3,8*grid-3,11*grid+2,11*grid-4);
			var startPhase=phase==0 ? 1 : grid-2, endPhase=phase==0 ? grid-2 : 1;
			var from=coords(3+8*grid+startPhase,-3+8*grid+startPhase);
			var to=coords(3+(8+dir.x)*grid+endPhase,-3+(8+dir.y)*grid+endPhase);
			var changed=transfer(g,from,to,copy,drag);
			check(changed.length>=3,"all selected layers changed");
			check(a.getIntGrid(8+dir.x,8+dir.y)==1,"first grid cell shifted by a tile");
			check(a.getIntGrid(10+dir.x,8+dir.y)==2,"second grid cell shifted by a tile");
			check(a.getIntGrid(hx,hy)==9,"empty selection hole erased occupied destination");
			same(signature(under),underBefore,"unselected layer changed"); same(signature(hidden),hiddenBefore,"hidden layer changed");
			same([for(t in b.getGridTileStack(8+dir.x,10+dir.y)) {tileId:t.tileId,flips:t.flips}],[{tileId:7,flips:1},{tileId:8,flips:2}],"tile stack lost order, flip or alignment");
			var selected:data.inst.EntityInstance=null;
			for(ge in g.allElements()) switch ge { case Entity(_,ei): selected=ei; case _: }
			check(selected!=null && selected.x==8*grid+3+dir.x*grid && selected.y==8*grid+5+dir.y*grid,"entity no longer aligns with tile displacement");
			check((selected.iid!=oldIid)==copy,"copy/move identity wrong");
			check(a.getIntGrid(8,8)==(copy?1:0),"source incorrectly retained or removed");
			check(li(eUid).entityInstances.length==(copy?2:1),"unexpected entity count");
			g.dispose(); passes.push(caseName);
		}
		return {cases:passes.length,assertions:assertions};
	}

	public static function edgeCases():Dynamic {
		for(copy in [false,true]) for(vertical in [false,true]) for(sign in [-1,1]) {
			caseName='overlap copy=$copy vertical=$vertical sign=$sign'; reset();
			var a=li(aUid), elems:Array<GenericLevelElement>=[];
			for(i in 0...3) { var x=8+(vertical?0:i), y=8+(vertical?i:0); a.setIntGrid(x,y,i+1,false); elems.push(GridCell(a,x,y)); }
			var g=selection(elems,true,128,128,175,175);
			transfer(g,coords(129,129),coords(129+(vertical?0:16*sign),129+(vertical?16*sign:0)),copy,true);
			for(i in 0...3) check(a.getIntGrid(8+(vertical?0:i+sign),8+(vertical?i+sign:0))==i+1,"overlapping source was overwritten before snapshot");
			g.dispose(); passes.push(caseName);
		}
		for(copy in [false,true]) for(fx in [false,true]) for(fy in [false,true]) {
			caseName='flipped-hole copy=$copy fx=$fx fy=$fy'; reset();
			var a=li(aUid); a.setIntGrid(8,8,1,false);
			// The old paste-then-flip path erased the unflipped arrival cell.
			var tx=16+(fx?2:0), ty=16+(fy?2:0);
			var blockerX=fx?16:18, blockerY=fy?16:18;
			a.setIntGrid(blockerX,blockerY,9,false);
			var g=selection([GridCell(a,8,8)],true,128,128,175,175);
			transfer(g,coords(129,129),coords(257,257),copy,true,fx,fy);
			check(a.getIntGrid(tx,ty)==1,"flipped payload differs from ghost");
			check(a.getIntGrid(blockerX,blockerY)==9,"flip intermediate position erased background");
			g.dispose(); passes.push(caseName);
		}
		for(kind in ["end","clear","dispose","invalid"]) {
			caseName='cancel-$kind'; reset();
			var a=li(aUid), b=li(bUid), e=actor(128,128);
			a.setIntGrid(8,8,1,false); b.addGridTile(8,8,7,1,false,false); b.addGridTile(8,8,8,2,true,false);
			var before=[signature(a),signature(b),signature(li(eUid))];
			var g=selection([GridCell(a,8,8),GridCell(b,8,8),Entity(e._li,e)],true,128,128,175,175);
			g.onMoveStart(false,coords(129,129)); check(a.getIntGrid(8,8)==0,"move does not preview source cut");
			if(kind=="clear") g.clear();
			else if(kind=="dispose") g.dispose();
			else if(kind=="invalid") { var changed=g.commitDragSnapshot(coords(129,129),coords(-1024,-1024),false); check(changed.length==0,"out-of-bounds drop was partially committed"); g.onMoveEnd(); }
			else g.onMoveEnd();
			same([signature(a),signature(b),signature(li(eUid))],before,"cancel/invalid drop destroyed original content");
			if(kind!="dispose") g.dispose(); passes.push(caseName);
		}
		for(stack in [false,true]) {
			caseName='occupied-stack setting=$stack'; reset(); App.ME.settings.v.tileStacking=stack;
			var b=li(bUid); b.addGridTile(8,8,7,1,false,false); b.addGridTile(8,8,8,2,true,false); b.addGridTile(16,16,9,0,false,false);
			var g=selection([GridCell(b,8,8)]); transfer(g,coords(129,129),coords(257,257),true,true);
			var ids=[for(t in b.getGridTileStack(16,16)) t.tileId];
			same(ids,stack?[9,7,8]:[7,8],"stacking preference ignored"); g.dispose(); passes.push(caseName);
		}
		for(copy in [false,true]) for(offset in [0,16]) {
			caseName='cross-level copy=$copy offset=$offset'; reset();
			var a=li(aUid), da=li(aUid,true), e=actor(128,128); a.setIntGrid(8,8,1,false); da.pxOffsetY=offset;
			var g=selection([GridCell(a,8,8),Entity(e._li,e)],true,128,128,175,175);
			transfer(g,coords(129,129),coords(129,129,true),copy,true);
			check(da.getIntGrid(8,8-Std.int(offset/16))==1,"cross-level offset corrupted grid");
			check(li(eUid,true).entityInstances.length==1,"cross-level entity missing");
			check(li(eUid,true).entityInstances[0].y==128,"cross-level entity shifted");
			check(g.getLastDropTargetLevel()==target(),"wrong target level"); g.dispose(); passes.push(caseName);
		}
		caseName="incompatible-offset-rollback"; reset();
		var a=li(aUid), e=actor(128,128); a.setIntGrid(8,8,1,false); li(aUid,true).pxOffsetY=1;
		var g=selection([GridCell(a,8,8),Entity(e._li,e)]); var before=[signature(a),signature(li(eUid))];
		var changed=transfer(g,coords(129,129),coords(129,129,true),false,true);
		check(changed.length==0,"unaligned target accepted"); same([signature(a),signature(li(eUid))],before,"unaligned target lost source"); g.dispose(); passes.push(caseName);

		for(copy in [false,true]) {
			caseName='mixed-grids-offsets copy=$copy'; reset();
			var a=li(aUid), b=li(bUid), e=actor(131,133);
			a.def.gridSize=8; a.def.pxOffsetX=3; a.def.pxOffsetY=-5;
			b.def.pxOffsetX=-7; b.def.pxOffsetY=9;
			a.setIntGrid(16,16,1,false); b.addGridTile(8,8,7,0,false,false);
			var g=selection([GridCell(a,16,16),GridCell(b,8,8),Entity(e._li,e)]);
			transfer(g,coords(123,139),coords(187,203),copy,true);
			check(a.getIntGrid(24,24)==1,"small-grid position drifted"); check(b.getGridTileStack(12,12).length==1,"large-grid position drifted");
			for(ge in g.allElements()) switch ge { case Entity(_,ei): check(ei.x==195 && ei.y==197,"mixed-grid entity drifted"); case _: }
			g.dispose(); passes.push(caseName);
		}
		caseName="negative-coordinates-layer-conversion"; reset(16,7);
		var c=coords(6,-8).cloneRelativeToLayer(li(eUid));
		check(c.getLayerCx(li(aUid))==-1 && c.getLayerCy(li(aUid))==-1,"negative positions truncated toward zero"); passes.push(caseName);
		return {cases:passes.length,assertions:assertions};
	}

	public static function pointCases():Dynamic {
		for(copy in [false,true]) for(owner in [false,true]) {
			caseName='point-handles copy=$copy owner=$owner'; reset();
			var e=actor(128,128), fi=e.getFieldInstance(Editor.ME.project.defs.getFieldDef(pathUid),true);
			for(i in 0...3) { fi.addArrayValue(); fi.parseValue(i,(10+i)+Const.POINT_SEPARATOR+10); }
			var elems:Array<GenericLevelElement>=[PointField(e._li,e,fi,0),PointField(e._li,e,fi,2)];
			if(owner) elems.unshift(Entity(e._li,e));
			var g=selection(elems); transfer(g,coords(161,161),coords(193,193),copy,true);
			var dest=e;
			if(copy && owner) for(ge in g.allElements()) switch ge { case Entity(_,ei): dest=ei; case _: }
			var df=dest.getFieldInstance(fi.def,true);
			if(copy && !owner) {
				check(df.getArrayLength()==5,"standalone point copy did not insert both entries");
				same([for(i in 0...5) df.getPointStr(i)],["12"+Const.POINT_SEPARATOR+"12","10"+Const.POINT_SEPARATOR+"10","11"+Const.POINT_SEPARATOR+"10","14"+Const.POINT_SEPARATOR+"12","12"+Const.POINT_SEPARATOR+"10"],"point array indices shifted");
			}
			else {
				check(df.getPointGrid(0).cx==12 && df.getPointGrid(0).cy==12,"first point displaced twice or not at all");
				check(df.getPointGrid(2).cx==14 && df.getPointGrid(2).cy==12,"last point displaced twice or not at all");
				check(df.getPointGrid(1).cx==(copy?13:11),"unselected path point copy/move semantics changed");
				if(copy) check(fi.getPointGrid(0).cx==10,"copy modified original path");
			}
			g.dispose(); passes.push(caseName);
		}
		caseName="copy-linked-entities"; reset();
		var e1=actor(128,128), e2=actor(160,128), rf=Editor.ME.project.defs.getFieldDef(refUid);
		e1.getFieldInstance(rf,true).parseValue(0,e2.iid); e2.getFieldInstance(rf,true).parseValue(0,e1.iid);
		var g=selection([Entity(e1._li,e1),Entity(e2._li,e2)]); transfer(g,coords(129,129),coords(257,257),true,true);
		var clones:Array<data.inst.EntityInstance>=[]; for(ge in g.allElements()) switch ge { case Entity(_,e): clones.push(e); case _: }
		check(clones[0].getFieldInstance(rf,true).getEntityRefIid(0)==clones[1].iid,"copy link still targets source");
		check(clones[1].getFieldInstance(rf,true).getEntityRefIid(0)==clones[0].iid,"copy cycle broken");
		check(e1.getFieldInstance(rf,true).getEntityRefIid(0)==e2.iid,"source cycle modified"); g.dispose(); passes.push(caseName);
		caseName="entity-limit-no-partial-copy"; reset();
		var e1=actor(128,128), e2=actor(160,128), ed=e1.def; ed.maxCount=3;
		var g=selection([Entity(e1._li,e1),Entity(e2._li,e2)]);
		check(transfer(g,coords(129,129),coords(257,257),true,true).length==0,"limit copied partial group");
		check(li(eUid).entityInstances.length==2 && e1.x==128 && e2.x==160,"limit moved/deleted originals"); g.dispose(); ed.maxCount=0; passes.push(caseName);
		return {cases:passes.length,assertions:assertions};
	}

	public static function prepareUi(copy:Bool):Dynamic {
		reset(); Editor.ME.camera.fit(true); ui.Modal.closeAll();
		var a=li(aUid), b=li(bUid), e1=actor(131,133), e2=actor(163,133);
		a.setIntGrid(8,8,1,false); a.setIntGrid(10,8,2,false); b.addGridTile(8,8,7,0,false,false);
		a.setIntGrid(17,16,9,false); li(underUid).setIntGrid(16,16,8,false);
		Editor.ME.selectionTool.select([GridCell(a,8,8),GridCell(a,10,8),GridCell(b,8,8),Entity(e1._li,e1),Entity(e2._li,e2)]);
		Editor.ME.selectionTool.group.addSelectionRect(128,175,128,159);
		Editor.ME.ensureLevelTimeline(source()).saveLayerStates(source().layerInstances);
		Editor.ME.levelRender.invalidateAll();
		return {ids:[e1.iid,e2.iid],hole:{cx:17,cy:16},copy:copy};
	}
	public static function uiPoint(x:Float,y:Float):Dynamic { var c=coords(x,y); return {x:c.pageX,y:c.pageY}; }
	public static function uiState():Dynamic {
		var g=Editor.ME.selectionTool.group;
		return {running:Editor.ME.selectionTool.isRunning(),moving:Editor.ME.selectionTool.moveStarted,
			ghost:g.ghost.visible, dx:g.ghost.x-g.bounds.left,dy:g.ghost.y-g.bounds.top,
			gridA:li(aUid).getIntGrid(16,16),gridB:li(aUid).getIntGrid(18,16),hole:li(aUid).getIntGrid(17,16),under:li(underUid).getIntGrid(16,16),
			entities:[for(e in li(eUid).entityInstances) {id:e.iid,x:e.x,y:e.y}],
			selected:g.selectedElementsCount()};
	}
	public static function undo():Void Editor.ME.curLevelTimeline.undo();
	public static function redo():Void Editor.ME.curLevelTimeline.redo();
	public static function allResults():Dynamic return {cases:passes.length,assertions:assertions,names:passes};
}
#end
