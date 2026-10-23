package tool;

import data.DrawableShape;
import data.inst.EntityInstance;

/** A stroke is an isolated candidate. Native fields change only on a valid mouse-up. */
class DrawableShapeTool extends Tool<Int> {
	public var entityDef(default,null):data.def.EntityDef;
	public var target(default,null):Null<EntityInstance>;
	public var brush(default,null):String;
	public var preset(default,null):String;
	public var thickness = 1;
	public var quarterTurns = 0;
	public var candidateError(default,null):Null<String>;
	var preview:h2d.Graphics;
	var candidate:Array<Int> = [];
	var before:Array<Int> = [];
	var baseX = 0;
	var baseY = 0;
	var grid = 16;
	var firstX = 0;
	var firstY = 0;
	var lastX = 0;
	var lastY = 0;
	var erasing = false;
	var filling = false;
	var configuration:Null<EntityInstance>;
	var strokeLayer:data.inst.LayerInstance;
	var previewState:Dynamic;
	var suppressed:Null<EntityInstance>;

	public function new(ed:data.def.EntityDef, ?ei:EntityInstance, brush="Paint", preset="Rectangle", ?configuration:EntityInstance) {
		super();
		entityDef = ed;
		target = ei;
		this.brush = brush;
		this.preset = preset;
		this.configuration = configuration;
		preview = new h2d.Graphics();
		editor.levelRender.root.add(preview,Const.DP_UI);
		editor.ge.addGlobalListener(onGlobalEvent);
		canUseOutOfBounds = ed.allowOutOfBounds;
	}

	override function getDefaultValue() return entityDef.uid;
	override public function canEdit() return super.canEdit() && data.DrawableShape.isEnabled(entityDef) && curLayerInstance!=null && curLayerInstance.def.type==Entities;

	override function onDispose() {
		curMode = null; // Cancellation never writes the candidate.
		restoreSource();
		if( preview!=null ) preview.remove();
		preview = null;
		editor.ge.removeListener(onGlobalEvent);
		super.onDispose();
	}
	function restoreSource() {
		if(suppressed!=null) {
			display.EntityRender.suppressedShapes.remove(suppressed.iid);
			editor.levelRender.invalidateLayer(suppressed._li);
			suppressed=null;
			editor.selectionTool.invalidateRender();
		}
	}

	override function onGlobalEvent(ev:GlobalEvent) {
		switch ev {
			case LevelRestoredFromHistory(_), LayerInstancesRestoredFromHistory(_), LevelSelected(_), LayerInstanceSelected(_):
				restoreSource();
				curMode = null;
				preview.clear();
				preview.removeChildren();
				if( target!=null ) {
					var iid = target.iid;
					target = null;
					if( curLayerInstance!=null ) for(ei in curLayerInstance.entityInstances)
						if( ei.iid==iid ) target = ei;
				}
			case EntityInstanceRemoved(ei): if( ei==target ) target=null;
			case _:
		}
	}

	function hit(m:Coords):Null<EntityInstance> {
		var ge=editor.getGenericLevelElementAt(m,Entities,true);
		return switch ge {
			case Entity(li,ei): ei.defUid==entityDef.uid && DrawableShape.isEnabled(ei.def) ? ei : null;
			case _: null;
		}
	}

	function makeState(ei:Null<EntityInstance>):Dynamic {
		var state=ei==null ? null : DrawableShape.read(ei);
		if( state!=null ) return {
			cells:state.cells.copy(),grid:state.grid,mode:state.mode,preset:state.preset,width:state.width,height:state.height,
			error:state.error,profile:state.profile,facing:state.facing,thickness:state.thickness,quarterTurns:state.quarterTurns,color:state.color
		};
		if(ei==null) {ei=new EntityInstance(project,curLayerInstance,entityDef.uid,"drawable-preview");ei.tidy(project,curLayerInstance);}
		var color=DrawableShape.field(ei,"Color",true);
		return {cells:[],grid:curLayerInstance.def.gridSize,mode:"Custom",preset:"Custom",width:1,height:1,error:null,
			profile:configuration==null && target==null && (brush=="Preset" || brush=="Rectangle") ? "Spikes" : DrawableShape.value(ei,"VisualProfile","SolidBarrier"),
			facing:DrawableShape.value(ei,"ShapeFacing","All"),thickness:thickness,quarterTurns:quarterTurns,color:color==null ? entityDef.color : color.getColorAsInt(0)};
	}

	override public function startUsing(ev:hxd.Event,m:Coords,?extraParam:String) {
		if( ev.button!=0 && ev.button!=1 || !canEdit() || !entityDef.allowOutOfBounds && !curLevel.inBounds(m.levelX,m.levelY) ) return;
		ui.DrawableShapeEditor.clearPreview();
		erasing=brush=="Erase" || ev.button==1 || App.ME.isMacCtrlDown();
		if( target!=null && !target._li.containsEntity(target) ) target=null;
		if( target==null ) target=hit(m);
		if(erasing && target==null) return;
		strokeLayer=target==null ? curLayerInstance : target._li;
		if( strokeLayer!=curLayerInstance ) return;
		previewState=makeState(target==null ? configuration : target);
		if( previewState.error!=null ) { N.error(previewState.error); return; }
		grid=target==null ? strokeLayer.def.gridSize : previewState.grid;
		if( grid<=0 ) return;
		baseX=target==null ? M.floor(m.layerX/grid)*grid : target.left;
		baseY=target==null ? M.floor(m.layerY/grid)*grid : target.top;
		before=target==null ? [] : cast previewState.cells;
		if( target!=null && DrawableShape.read(target)==null ) {
			if( target.width%grid!=0 || target.height%grid!=0 ) {
				N.error("Align this legacy rectangle's width and height to the layer grid before drawing."); return;
			}
			before=DrawableShapeGeometry.preset("Rectangle",Std.int(target.width/grid),Std.int(target.height/grid)).cells;
		}
		candidate=before.copy();
		filling=brush=="Fill" || App.ME.isShiftDown() || !erasing && (brush=="Preset" || brush=="Rectangle");
		firstX=lastX=M.floor((m.layerX-baseX)/grid);
		firstY=lastY=M.floor((m.layerY-baseY)/grid);
		curMode=erasing ? Remove : Add;
		origin=m; lastMouse=m;
		tool.lt.EntityTool.cancelRefChaining();
		editor.clearResizeTool();
		if(target!=null) {
			suppressed=target;
			display.EntityRender.suppressedShapes.set(target.iid,true);
			editor.levelRender.invalidateLayer(target._li);
			editor.selectionTool.invalidateRender();
		}
		updateCandidate(m);
		ev.cancel=true;
	}

	function cellIndex(x:Int,y:Int):Int {
		for(i in 0...Std.int(candidate.length/2)) if( candidate[i*2]==x && candidate[i*2+1]==y ) return i*2;
		return -1;
	}
	function paint(x:Int,y:Int) {
		var i=cellIndex(x,y);
		if( erasing ) { if(i>=0) candidate.splice(i,2); }
		else if(i<0) { candidate.push(x); candidate.push(y); }
	}

	function updateCandidate(m:Coords) {
		var x=M.floor((m.layerX-baseX)/grid), y=M.floor((m.layerY-baseY)/grid);
		candidateError=null;
		if( !erasing && (brush=="Preset" || brush=="Rectangle") ) {
			var left=M.imin(firstX,x),top=M.imin(firstY,y);
			var result=DrawableShapeGeometry.preset(brush=="Rectangle" ? "Rectangle" : preset,M.iabs(x-firstX)+1,M.iabs(y-firstY)+1,thickness,quarterTurns);
			candidateError=result.error;
			candidate=[];
			for(i in 0...Std.int(result.cells.length/2)) {candidate.push(left+result.cells[i*2]);candidate.push(top+result.cells[i*2+1]);}
			// Show the requested extent even below the preset's minimum dimensions.
			previewState.width=M.iabs(x-firstX)+1; previewState.height=M.iabs(y-firstY)+1;
		}
		else if( filling ) {
			candidate=before.copy();
			for(cy in M.imin(firstY,y)...M.imax(firstY,y)+1)
				for(cx in M.imin(firstX,x)...M.imax(firstX,x)+1) paint(cx,cy);
		}
		else {
			// Supercover with shared-edge steps: fast diagonal motion cannot create gaps.
			var cx=lastX,cy=lastY;
			paint(cx,cy);
			var dx=M.iabs(x-cx),dy=M.iabs(y-cy),sx=x>cx ? 1 : -1,sy=y>cy ? 1 : -1;
			var ix=0,iy=0;
			while(ix<dx || iy<dy) {
				if(ix<dx && (iy>=dy || (1+2*ix)*dy<=(1+2*iy)*dx)) {cx+=sx;ix++;}
				else {cy+=sy;iy++;}
				paint(cx,cy);
			}
		}
		lastX=x;lastY=y;lastMouse=m;
		if(candidateError==null) candidateError=DrawableShapeGeometry.validate(candidate,true);
		if(candidateError==null && !entityDef.allowOutOfBounds) for(i in 0...Std.int(candidate.length/2)) {
			// Bounds use exported layer offsets; camera parallax only affects the preview.
			var px=strokeLayer.pxTotalOffsetX+baseX+candidate[i*2]*grid,py=strokeLayer.pxTotalOffsetY+baseY+candidate[i*2+1]*grid;
			if(px<0 || py<0 || px+grid>strokeLayer.level.pxWid || py+grid>strokeLayer.level.pxHei) {candidateError="The shape would extend outside this level.";break;}
		}
		renderCandidate();
	}

	function renderCandidate() {
		preview.clear();preview.removeChildren();
		preview.setScale(strokeLayer.def.getScale());
		preview.setPosition(strokeLayer.pxParallaxX+baseX*strokeLayer.def.getScale(),strokeLayer.pxParallaxY+baseY*strokeLayer.def.getScale());
		previewState.cells=candidate;
		previewState.grid=grid;
		previewState.error=candidateError;
		previewState.preset=brush=="Preset" ? preset : "Custom";
		if(brush=="Preset" && preset=="Strip") previewState.facing="Up";
		preview.alpha=0.85;
		if(candidate.length==0 && candidateError==null) {
			previewState.cells=before;
			display.DrawableShapeRender.draw(preview,cast previewState,target,entityDef,0xff4455);
			preview.alpha=0.35;
			var label=new h2d.Text(Assets.getRegularFont(),preview);label.text="Release to delete shape";label.textColor=0xff4455;label.y=-20;
			return;
		}
		display.DrawableShapeRender.draw(preview,cast previewState,target,entityDef,candidateError==null ? null : 0xff4455);
		if(target!=null && !erasing && (brush=="Preset" || brush=="Rectangle")) {
			var label=new h2d.Text(Assets.getRegularFont(),preview);label.text="Replace geometry · keep this entity";label.textColor=0xffcc77;label.y=-20;
		}
		App.ME.requestCpu();
	}

	override public function onMouseMove(ev:hxd.Event,m:Coords) {
		if(isRunning()) {updateCandidate(m);ev.cancel=true;}
	}
	override function customCursor(ev:hxd.Event,m:Coords) {
		editor.cursor.set(GridCell(curLayerInstance,m.cx,m.cy,candidateError==null ? 0x77ddbb : 0xff4455));
		ev.cancel=true;
	}

	override public function stopUsing(m:Coords) {
		if(!isRunning()) return;
		updateCandidate(m);
		curMode=null;
		restoreSource();
		preview.clear();preview.removeChildren();
		if(candidateError!=null) {N.error("Shape unchanged: "+candidateError);return;}
		var normalized=DrawableShapeGeometry.normalize(candidate);
		var oldNormalized=DrawableShapeGeometry.normalize(before);
		if(target!=null && normalized.x==oldNormalized.x && normalized.y==oldNormalized.y && normalized.cells.join(",")==oldNormalized.cells.join(",") && brush!="Preset" && brush!="Rectangle") return;
		if(candidate.length==0) {
			if(target==null) return;
			var removed=target;
			editor.curLevelTimeline.markEntityChange(removed);
			strokeLayer.removeEntityInstance(removed);
			editor.ge.emit(EntityInstanceRemoved(removed));
			target=null;
			editor.selectionTool.clear();
		}
		else {
			var fresh=target==null;
			if(fresh) {
				if(entityDef.maxCount>0 && project.getAllEntitiesFromLimitScope(strokeLayer,entityDef,entityDef.limitScope).length>=entityDef.maxCount) {
					N.error("The entity count limit prevents another shape.");return;
				}
				target=strokeLayer.createEntityInstance(entityDef);
				target.tidy(project,strokeLayer);
				if(configuration==null && (brush=="Preset" || brush=="Rectangle")) DrawableShape.set(target,"VisualProfile","Spikes");
				if(configuration!=null) {
					var configError=DrawableShape.applyConfiguration(target,configuration);
					if(configError!=null) {strokeLayer.removeEntityInstance(target);target=null;N.error(configError);return;}
				}
			}
			var mode=!erasing && brush=="Rectangle" ? "Rectangle" : !erasing && brush=="Preset" ? "Preset" : "Custom";
			var error=DrawableShape.applyCells(target,candidate,grid,baseX,baseY,mode,mode=="Rectangle" ? "Rectangle" : mode=="Preset" ? preset : "Custom");
			if(error!=null) {if(fresh){strokeLayer.removeEntityInstance(target);target=null;}N.error(error);return;}
			if(mode=="Preset") {
				target.getFieldInstance(entityDef.getFieldDef("ShapeThickness"),true).parseValue(0,Std.string(thickness));
				target.getFieldInstance(entityDef.getFieldDef("ShapeQuarterTurns"),true).parseValue(0,Std.string(quarterTurns));
				if(configuration==null && preset=="Strip") target.getFieldInstance(entityDef.getFieldDef("ShapeFacing"),true).parseValue(0,"Up");
			}
			editor.curLevelTimeline.markEntityChange(target);
			editor.ge.emit(fresh ? EntityInstanceAdded(target) : EntityInstanceChanged(target));
			editor.selectionTool.select([Entity(strokeLayer,target)]);
			editor.clearResizeTool();
		}
		editor.curLevelTimeline.saveLayerState(strokeLayer);
		editor.ge.emit(LayerInstanceEditedByTool(strokeLayer));
		editor.levelRender.invalidateLayer(strokeLayer);
		editor.selectionTool.invalidateRender();
		// A preset drag starts another independent instance; brush edits keep their owner.
		if(brush=="Preset" || brush=="Rectangle") target=null;
	}

	override public function onKeyPress(keyId:Int) {
		if(keyId==K.ESCAPE) editor.clearSpecialTool();
	}
}
