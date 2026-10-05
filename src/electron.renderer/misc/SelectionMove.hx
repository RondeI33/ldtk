package misc;

/** Shared by ordinary selection drag, duplicate and programmatic movement.
 * A selection rectangle is a visual bound, never an instruction to erase a layer.
 */
@:access(GenericLevelElementGroup)
class SelectionMove {
	public static function anchor(g:GenericLevelElementGroup, from:Coords):Dynamic {
		var li=g.getSmartRelativeLayerInstance();
		return {
			x:from.worldXf, y:from.worldYf,
			grid:li==null ? 1. : li.def.scaledGridSize*1.,
			offsetX:li==null ? 0. : li.level.worldX+li.pxParallaxX*1.,
			offsetY:li==null ? 0. : li.level.worldY+li.pxParallaxY*1.,
		};
	}

	public static function delta(g:GenericLevelElementGroup, from:Coords, to:Coords):{x:Float,y:Float} {
		var a:Dynamic=g.dragAnchor==null ? anchor(g,from) : g.dragAnchor;
		if(!g.snapToGrid()) return {x:to.worldXf-a.x,y:to.worldYf-a.y};
		var grid:Float=a.grid;
		// Quantize the two pointer positions in ONE frame. Do not round the raw
		// displacement again per layer: that disagreed with the displayed ghost.
		return {
			x:(Math.floor((to.worldXf-a.offsetX)/grid)-Math.floor((a.x-a.offsetX)/grid))*grid,
			y:(Math.floor((to.worldYf-a.offsetY)/grid)-Math.floor((a.y-a.offsetY)/grid))*grid,
		};
	}

	static inline function aligned(v:Float):Bool return Math.abs(v-Math.round(v))<0.00001;

	public static function commit(g:GenericLevelElementGroup, origin:Coords, to:Coords, copy:Bool, flipX=false, flipY=false):Array<data.inst.LayerInstance> {
		var editor=Editor.ME, project=editor.project;
		if(!g.dragSnapshotActive) {
			g.deduplicateElementsForDrag();
			g.captureDragSnapshot();
		}
		if(!g.dragSnapshotActive) return [];
		if(g.dragAnchor==null) g.dragAnchor=anchor(g,origin);
		var source=g.dragSourceLevel==null ? editor.curLevel : g.dragSourceLevel;
		var target=g.getDragTargetLevel(to);
		var d=delta(g,origin,to);
		var fb=g.getFlippableGridBounds();
		g.lastDropTargetLevel=source;

		function abort(message:String):Array<data.inst.LayerInstance> {
			g.restoreDragSource();
			g.dragSnapshotActive=false;
			g.dragSourceCut=false;
			g.invalidateBounds();
			g.invalidateSelectRender();
			N.error(message);
			return [];
		}

		if(g.hasIncompatibleGridSizes())
			return abort("The selected layer grids cannot share one movement step.");
		if(!copy && source==target && d.x==0 && d.y==0 && !flipX && !flipY) {
			g.restoreDragSource();
			g.dragSnapshotActive=false;
			return [];
		}

		var gridPlans:Array<Dynamic>=[];
		var entityPlans:Array<Dynamic>=[];
		var pointPlans:Array<Dynamic>=[];
		var entityPlanById:Map<String,Dynamic>=new Map();
		var pointCopies:Map<String,Dynamic>=new Map();
		var addedCounts:Map<String,Int>=new Map();

		// Plan every destination before writing anything. Incompatible offsets
		// or an out-of-bounds drop cancel the whole operation, not half the group.
		for(s in g.dragGridSnapshots) {
			var src:data.inst.LayerInstance=s.li;
			var dst=target.getLayerInstance(src.layerDefUid);
			if(dst==null || dst.def.type!=src.def.type) return abort("A destination selection layer is missing.");
			var step=src.def.scaledGridSize;
			var x=src.pxParallaxX+s.cx*step, y=src.pxParallaxY+s.cy*step;
			if(fb!=null) {
				if(flipX) x=fb.left+fb.right-x-step;
				if(flipY) y=fb.top+fb.bottom-y-step;
			}
			var cx=(src.level.worldX+x+d.x-target.worldX-dst.pxParallaxX)/step;
			var cy=(src.level.worldY+y+d.y-target.worldY-dst.pxParallaxY)/step;
			if(!aligned(cx) || !aligned(cy)) return abort("Destination layer offsets do not align with this selection's grid.");
			var ix=M.round(cx), iy=M.round(cy);
			if(!dst.isValid(ix,iy)) return abort("The selection would leave the destination level. Nothing was moved.");
			gridPlans.push({s:s,src:src,dst:dst,cx:ix,cy:iy});
		}

		for(s in g.dragEntitySnapshots) {
			var src:data.inst.LayerInstance=s.li;
			var ei:data.inst.EntityInstance=s.ei;
			var dst=target.getLayerInstance(src.layerDefUid);
			if(dst==null || dst.def.type!=Entities) return abort("A destination entity layer is missing.");
			var scale=src.def.getScale();
			var x=s.x+(src.level.worldX+src.pxParallaxX+d.x-target.worldX-dst.pxParallaxX)/scale;
			var y=s.y+(src.level.worldY+src.pxParallaxY+d.y-target.worldY-dst.pxParallaxY)/scale;
			if(!aligned(x) || !aligned(y)) return abort("The destination layer scale would shift part of the selection off its pixel grid.");
			if(!ei.def.allowOutOfBounds && !target.inBounds(M.round(x),M.round(y)))
				return abort("The selection would leave the destination level. Nothing was moved.");
			if(copy && ei.def.maxCount>0) {
				var scope=Std.string(ei.def.limitScope);
				var key=ei.defUid+":"+scope;
				if(scope=="PerLayer") key+=":"+dst.iid;
				else if(scope=="PerLevel") key+=":"+dst.levelId;
				else if(scope=="PerWorld") key+=":"+dst.level._world.iid;
				var added=addedCounts.exists(key) ? addedCounts.get(key) : 0;
				var count=project.getAllEntitiesFromLimitScope(dst,ei.def,ei.def.limitScope).length;
				if(count+added+1>ei.def.maxCount) return abort("Copying this selection would exceed the instance limit for "+ei.def.identifier+".");
				addedCounts.set(key,added+1);
			}
			var plan:Dynamic={s:s,src:src,dst:dst,x:M.round(x),y:M.round(y),ei:null};
			entityPlans.push(plan);
			entityPlanById.set(ei.iid,plan);
		}

		// A copied entity carries all its own point fields, including handles
		// outside the marquee. Explicitly selected handles must not move twice.
		var points:Array<Dynamic>=g.dragPointSnapshots.copy();
		var seenPoints:Map<String,Bool>=new Map();
		for(s in points) seenPoints.set(s.ei.iid+":"+s.fi.defUid+":"+s.arrayIdx,true);
		if(copy) for(s in g.dragEntitySnapshots) {
			var ei:data.inst.EntityInstance=s.ei;
			for(fi in ei.getFieldInstancesOfType(F_Point)) for(i in 0...fi.getArrayLength()) {
				var key=ei.iid+":"+fi.defUid+":"+i, pt=fi.getPointGrid(i);
				if(pt!=null && !seenPoints.exists(key)) {
					points.push({elementIdx:-1,li:s.li,ei:ei,fi:fi,arrayIdx:i,cx:pt.cx,cy:pt.cy});
					seenPoints.set(key,true);
				}
			}
		}
		for(s in points) {
			var src:data.inst.LayerInstance=s.li;
			var ei:data.inst.EntityInstance=s.ei;
			var fi:data.inst.FieldInstance=s.fi;
			var owner:Dynamic=entityPlanById.get(ei.iid);
			var dst:data.inst.LayerInstance=owner==null ? src : owner.dst;
			var step=src.def.scaledGridSize;
			var cx=(src.level.worldX+src.pxParallaxX+s.cx*step+d.x-dst.level.worldX-dst.pxParallaxX)/step;
			var cy=(src.level.worldY+src.pxParallaxY+s.cy*step+d.y-dst.level.worldY-dst.pxParallaxY)/step;
			if(!aligned(cx) || !aligned(cy) || !dst.isValid(M.round(cx),M.round(cy)))
				return abort("A selected point would leave its layer or lose grid alignment. Nothing was moved.");
			var plan:Dynamic={s:s,owner:owner,dst:dst,cx:M.round(cx),cy:M.round(cy),index:s.arrayIdx};
			if(owner==null && copy && fi.def.isArray) {
				var key=ei.iid+":"+fi.defUid;
				if(!pointCopies.exists(key)) pointCopies.set(key,{fi:fi,ei:ei,plans:[]});
				var pc:Dynamic=pointCopies.get(key);
				var ps:Array<Dynamic>=pc.plans;
				ps.push(plan);
				if(fi.def.arrayMaxLength!=null && fi.getArrayLength()+ps.length>fi.def.arrayMaxLength)
					return abort("Copying the selected points would exceed their array length limit.");
			}
			else pointPlans.push(plan);
		}

		editor.ensureLevelTimeline(source);
		editor.ensureLevelTimeline(target);
		var changed:Map<String,data.inst.LayerInstance>=new Map();
		var copied:Map<String,data.inst.EntityInstance>=new Map();
		if(!copy && !g.dragSourceCut) g.cutDragSource();

		// Erase all source stamps BEFORE inserting any destination content.
		// Otherwise an overlapping move could erase tiles it had just pasted.
		if(!copy) for(p in entityPlans) {
			var ei:data.inst.EntityInstance=p.s.ei;
			for(li in project.forkConfig.eraseEntityStamps(ei)) changed.set(li.iid,li);
		}
		for(p in entityPlans) {
			var src:data.inst.LayerInstance=p.src, dst:data.inst.LayerInstance=p.dst;
			var old:data.inst.EntityInstance=p.s.ei;
			var ei=copy ? dst.duplicateEntityInstance(old) : old;
			if(!copy) { dst.attachEntityInstanceForMove(ei); changed.set(src.iid,src); }
			else copied.set(old.iid,ei);
			ei.x=p.x; ei.y=p.y; p.ei=ei;
			g.elements[p.s.elementIdx]=Entity(dst,ei);
			changed.set(dst.iid,dst);
			if(editor.resizeTool!=null && editor.resizeTool.isOnEntity(old)) editor.createResizeToolFor(Entity(dst,ei));
			if(ui.EntityInstanceEditor.existsFor(old)) ui.EntityInstanceEditor.openFor(ei);
		}

		for(p in gridPlans) {
			var src:data.inst.LayerInstance=p.src, dst:data.inst.LayerInstance=p.dst;
			var s:Dynamic=p.s;
			if(s.isTiles) {
				// Preserve the authored source stack; only the explicit stacking
				// setting decides whether destination tiles are merged or replaced.
				if(!App.ME.settings.v.tileStacking) dst.removeAllGridTiles(p.cx,p.cy,false);
				var tiles:Array<Dynamic>=s.tiles;
				for(t in tiles) dst.addGridTile(p.cx,p.cy,t.tileId,t.flips ^ (flipX?1:0) ^ (flipY?2:0),true,false);
			}
			else dst.setIntGrid(p.cx,p.cy,s.value,false);
			g.elements[s.elementIdx]=GridCell(dst,p.cx,p.cy);
			changed.set(dst.iid,dst);
			if(!copy) changed.set(src.iid,src);
		}

		for(p in pointPlans) {
			var ei:data.inst.EntityInstance=p.owner==null ? p.s.ei : p.owner.ei;
			var fi=ei.getFieldInstance(p.s.fi.def,true);
			fi.parseValue(p.index,p.cx+Const.POINT_SEPARATOR+p.cy);
			if(p.s.elementIdx>=0) g.elements[p.s.elementIdx]=PointField(ei._li,ei,fi,p.index);
			changed.set(ei._li.iid,ei._li);
			editor.ge.emit(EntityFieldInstanceChanged(ei,fi));
		}
		for(pc in pointCopies) {
			var fi:data.inst.FieldInstance=pc.fi;
			var ei:data.inst.EntityInstance=pc.ei;
			var plans:Array<Dynamic>=pc.plans;
			var values:Array<Null<String>>=[];
			for(i in 0...fi.getArrayLength()) {
				for(p in plans) if(p.s.arrayIdx==i) {
					p.index=values.length;
					values.push(p.cx+Const.POINT_SEPARATOR+p.cy);
				}
				values.push(fi.valueIsNull(i) ? null : fi.getPointStr(i));
			}
			while(fi.getArrayLength()<values.length) fi.addArrayValue();
			for(i in 0...values.length) fi.parseValue(i,values[i]);
			for(p in plans) g.elements[p.s.elementIdx]=PointField(ei._li,ei,fi,p.index);
			changed.set(ei._li.iid,ei._li);
			editor.ge.emit(EntityFieldInstanceChanged(ei,fi));
		}

		for(p in entityPlans) {
			var ei:data.inst.EntityInstance=p.ei;
			if(copy) for(fi in ei.getFieldInstancesOfType(F_EntityRef)) for(i in 0...fi.getArrayLength()) {
				var ref=fi.getEntityRefIid(i);
				if(ref!=null && copied.exists(ref)) fi.parseValue(i,copied.get(ref).iid);
			}
			for(li in project.forkConfig.paintEntityStamps(ei)) changed.set(li.iid,li);
			editor.ge.emit(EntityInstanceChanged(ei));
		}

		// Rectangles only follow the selection visually. Never turn their holes
		// into removals, and never touch layers absent from the selected payload.
		for(r in g.originalRects) {
			r.leftPx+=source.worldX+d.x-target.worldX;
			r.rightPx+=source.worldX+d.x-target.worldX;
			r.topPx+=source.worldY+d.y-target.worldY;
			r.bottomPx+=source.worldY+d.y-target.worldY;
		}
		g.dragSnapshotActive=false;
		g.dragSourceCut=false;
		g.lastDropTargetLevel=target;
		var derived:Array<data.inst.LayerInstance>=[];
		for(li in changed) if(li.def.type==IntGrid) {
			if(li.def.isAutoLayer()) li.applyAllRules();
			for(other in li.level.layerInstances) if(other.def.type==AutoLayer && other.def.autoSourceLayerDefUid==li.layerDefUid) {
				other.applyAllRules(); derived.push(other);
			}
		}
		for(li in derived) changed.set(li.iid,li);
		var affected:Array<data.inst.LayerInstance>=[];
		for(li in changed) {
			editor.ge.emit(LayerInstanceChangedGlobally(li));
			g.invalidateDragLayer(li);
			affected.push(li);
		}
		editor.worldRender.invalidateLevelRender(source);
		if(target!=source) editor.worldRender.invalidateLevelRender(target);
		g.invalidateBounds();
		g.invalidateSelectRender();
		return affected;
	}
}
