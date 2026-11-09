import pathpreview.PathPreviewGeometry.PathPreviewPoint;

typedef SelectionBounds = { top:Float, left:Float, right:Float, bottom:Float }

private typedef PathPreviewDragSnapshot = {
	var ei:data.inst.EntityInstance;
	var li:data.inst.LayerInstance;
	var pivot:PathPreviewPoint;
	var points:Array<Null<PathPreviewPoint>>;
	var selectedPoints:Map<Int,Bool>;
	var entitySelected:Bool;
}

private typedef GridFlipSnapshot = {
	var elementIdx:Int;
	var li:data.inst.LayerInstance;
	var cx:Int;
	var cy:Int;
	var targetCx:Int;
	var targetCy:Int;
}

private typedef TileFlipSnapshot = {
	> GridFlipSnapshot,
	var tiles:Array<data.DataTypes.GridTileInfos>;
}

private typedef IntGridFlipSnapshot = {
	> GridFlipSnapshot,
	var value:Int;
}

private typedef ShapeTransformSnapshot = {
	var source:data.inst.EntityInstance;
	var transformed:data.inst.EntityInstance;
}

class GenericLevelElementGroup {
	static var SELECTION_COLOR = 0xffcc00;
	var editor(get,never): Editor; inline function get_editor() return Editor.ME;

	var renderWrapper : h2d.Object;
	var pathPreviewGhost : h2d.Object;
	var pathPreviewDragSnapshots:Array<PathPreviewDragSnapshot> = [];
	var suppressedPathPreviewIids:Array<String> = [];
	var ghost : h2d.Graphics;
	var selectRender : h2d.Graphics;
	var shapeSelectRender : h2d.Graphics;
	var arrow : h2d.Graphics;
	var pointLinks : h2d.Graphics;
	var ghostLayerStack : Null<h2d.Layers>;
	var ghostAutoTileGroups : Array<h2d.TileGroup> = [];
	var ghostIntGridTransforms : Array<h2d.Graphics> = [];
	var ghostFlipX = false;
	var ghostFlipY = false;
	var ghostTranspose = false;
	var elements : Array< Null<GenericLevelElement> > = [];
	var bounds(get,never) : SelectionBounds;
	var _cachedBounds : SelectionBounds;

	var invalidatedSelectRender = true;
	var movingGhost = false;

	var dragSnapshotActive = false;
	var dragSourceCut = false;
	var dragSourceLevel : Null<data.Level>;
	var lastDropTargetLevel : Null<data.Level>;
	var dragGridSnapshots : Array<Dynamic> = [];
	var dragEntitySnapshots : Array<Dynamic> = [];
	var dragPointSnapshots : Array<Dynamic> = [];

	var originalRects : Array< { leftPx:Float, rightPx:Float, topPx:Float, bottomPx:Float } > = [];

	public function new(?elems:Array<GenericLevelElement>) {
		if( elems!=null )
			elements = elems.copy();

		renderWrapper = new h2d.Object();
		editor.levelRender.root.add(renderWrapper, Const.DP_UI);

		// The complete transient path stays below point/entity selection handles.
		pathPreviewGhost = new h2d.Object(renderWrapper);
		ghost = new h2d.Graphics(renderWrapper);

		arrow = new h2d.Graphics(renderWrapper);
		pointLinks = new h2d.Graphics(renderWrapper);
		selectRender = new h2d.Graphics(renderWrapper);
		var f = new dn.heaps.filter.PixelOutline(SELECTION_COLOR);
		f.setPartialKnockout(0.66);
		selectRender.filter = new h2d.filter.Group([
			f, new dn.heaps.filter.PixelOutline(0x0),
		]);
		// Shapes need a lighter interior so native per-instance colors remain visible.
		// Use the same opaque mask/outline with a separate interior knockout value.
		shapeSelectRender = new h2d.Graphics(renderWrapper);
		var shapeOutline = new dn.heaps.filter.PixelOutline(SELECTION_COLOR);
		shapeOutline.setPartialKnockout(0.15);
		shapeSelectRender.filter = new h2d.filter.Group([
			shapeOutline, new dn.heaps.filter.PixelOutline(0x0),
		]);
		invalidateBounds();
	}

	@:keep
	public function toString() {
		return elements.length==0 ? "empty" : elements.map( e->e.getName() ).slice(0,10).join(",");
	}

	public function clear() {
		if( dragSnapshotActive && dragSourceCut )
			restoreDragSource();
		dragSnapshotActive = false;
		dragSourceCut = false;
		dragGridSnapshots = [];
		dragEntitySnapshots = [];
		dragPointSnapshots = [];
		pathPreviewDragSnapshots = [];
		elements = [];
		originalRects = [];
		clearGhost();
		invalidateBounds();
		invalidateSelectRender();
	}

	public function dispose() {
		clearPathPreviewGhost();
		pathPreviewDragSnapshots = [];
		renderWrapper.remove();
		originalRects = null;
		_cachedBounds = null;
		elements = null;
	}

	public inline function isEmpty() return elements.length==0 && originalRects.length==0;
	public inline function selectedElementsCount() return elements.length;
	public inline function allElements() return elements;
	public inline function getElement(idx:Int) return elements[idx];

	public function add(ge:GenericLevelElement) {
		// Already in selection?
		for(e in elements)
			if( ge.equals(e) )
				return false;

		// Add
		elements.push(ge);
		invalidateBounds();
		invalidateSelectRender();
		return true;
	}

	public function addSelectionRect(l,r,t,b) {
		originalRects.push({
			leftPx: M.imax(l, 0),
			rightPx: M.imin(r, editor.curLevel.pxWid-1),
			topPx: M.imax(t, 0),
			bottomPx: M.imin(b, editor.curLevel.pxHei-1),
		});

		// Discard rectangles included in other ones
		var i = 0;
		while( i<originalRects.length ) {
			var a = originalRects[i];

			var j = 0;
			while( j<originalRects.length ) {
				if( j!=i ) {
					var b = originalRects[j];
					if( b.leftPx>=a.leftPx && b.rightPx<=a.rightPx && b.topPx>=a.topPx && b.bottomPx<=a.bottomPx ) {
						originalRects.splice(j,1);
						j--;
					}
				}
				j++;
			}

			i++;
		}

		invalidateBounds();
		invalidateSelectRender();
	}

	public function getSelectedLayerInstances() {
		var map = new Map();
		for(ge in elements)
			switch ge {
				case GridCell(li, _), Entity(li, _), PointField(li, _):
					map.set(li,li);
			}

		var lis = [];
		for(li in map)
			lis.push(li);
		return lis;
	}


	/**
		Return the single manual Tiles layer that owns every selected element.
		Layer transfer deliberately rejects mixed selections, entities and IntGrid
		content so an incompatible shortcut can never partially mutate the level.
	**/
	public function getSingleTilesLayerForTransfer() : Null<data.inst.LayerInstance> {
		if( elements.length==0 )
			return null;

		var source : Null<data.inst.LayerInstance> = null;
		for(ge in elements)
			switch ge {
				case GridCell(li,cx,cy):
					if( li.def.type!=Tiles || !li.hasAnyGridTile(cx,cy) )
						return null;
					if( source==null )
						source = li;
					else if( source!=li )
						return null;

				case Entity(_, _), PointField(_, _, _, _):
					return null;
			}

		return source;
	}


	/**
		Move selected manual tile cells to another layer without moving them in
		level space. The operation is fully validated before the first mutation:
		both layers must use the same tileset and grid, offsets must map exactly,
		and every destination cell must be empty. Empty cells represented only by
		the selection rectangle stay transparent and never erase destination data.
	**/
	public function transferSelectedTilesToLayer(targetLi:data.inst.LayerInstance) : Array<data.inst.LayerInstance> {
		var sourceLi = getSingleTilesLayerForTransfer();
		if( sourceLi==null || targetLi==null || sourceLi==targetLi )
			return [];

		if( sourceLi.level!=targetLi.level || sourceLi.def.type!=Tiles || targetLi.def.type!=Tiles ) {
			N.warning("Selection can only move between manual Tiles layers in the same level.");
			return [];
		}

		var sourceTilesetUid = sourceLi.getTilesetUid();
		if( sourceTilesetUid==null || targetLi.getTilesetUid()!=sourceTilesetUid ) {
			N.warning("Target layer must use the same tileset as the selected tiles.");
			return [];
		}

		if( sourceLi.def.gridSize!=targetLi.def.gridSize ) {
			N.warning("Target layer uses the same tileset but a different grid size.");
			return [];
		}

		var grid = sourceLi.def.gridSize;
		var pending : Array<Dynamic> = [];
		var targetCells : Map<String,Bool> = new Map();

		// Validate the complete transfer before touching history or layer data.
		for(i in 0...elements.length)
			switch elements[i] {
				case GridCell(li,cx,cy):
					if( li!=sourceLi || !li.hasAnyGridTile(cx,cy) )
						return [];

					var px = sourceLi.pxTotalOffsetX + cx*grid;
					var py = sourceLi.pxTotalOffsetY + cy*grid;
					var rx = px - targetLi.pxTotalOffsetX;
					var ry = py - targetLi.pxTotalOffsetY;

					if( rx%grid!=0 || ry%grid!=0 ) {
						N.warning("Target layer offset does not align with the selected tile grid.");
						return [];
					}

					var tcx = Std.int(rx/grid);
					var tcy = Std.int(ry/grid);
					if( !targetLi.isValid(tcx,tcy) ) {
						N.warning("Selection would fall outside the target layer.");
						return [];
					}

					var key = tcx+":"+tcy;
					if( targetCells.exists(key) ) {
						N.warning("Selection cannot be mapped safely to the target layer.");
						return [];
					}
					targetCells.set(key,true);

					// Never destroy existing target content. A blocked transfer is a no-op.
					if( targetLi.hasAnyGridTile(tcx,tcy) ) {
						N.warning('Target layer "${targetLi.def.identifier}" already contains tiles at part of this selection.');
						return [];
					}

					pending.push({
						elementIdx:i,
						cx:cx,
						cy:cy,
						tcx:tcx,
						tcy:tcy,
						tiles:[
							for(t in sourceLi.getGridTileStack(cx,cy))
								{ tileId:t.tileId, flips:t.flips }
						],
					});

				case Entity(_, _), PointField(_, _, _, _):
					return [];
			}

		if( pending.length==0 )
			return [];

		// Mark both sides before mutation so Undo/Redo remains one atomic action.
		for(p in pending) {
			editor.curLevelTimeline.markGridChange(sourceLi,p.cx,p.cy);
			editor.curLevelTimeline.markGridChange(targetLi,p.tcx,p.tcy);
		}

		for(p in pending)
			sourceLi.removeAllGridTiles(p.cx,p.cy,false);

		for(p in pending) {
			var tiles : Array<Dynamic> = p.tiles;
			var stacking = tiles.length>1 || App.ME.settings.v.tileStacking;
			for(t in tiles)
				targetLi.addGridTile(p.tcx,p.tcy,t.tileId,t.flips,stacking,false);
			elements[p.elementIdx] = GridCell(targetLi,p.tcx,p.tcy);
		}

		for(li in [sourceLi,targetLi]) {
			editor.ge.emit( LayerInstanceChangedGlobally(li) );
			invalidateDragLayer(li);
		}

		clearGhost();
		invalidateBounds();
		invalidateSelectRender();
		return [sourceLi,targetLi];
	}

	public inline function invalidateSelectRender()  invalidatedSelectRender = true;
	public inline function invalidateBounds()  _cachedBounds = null;

	function get_bounds() {
		if( _cachedBounds==null ) {
			if( elements.length==0 )
				_cachedBounds = { top:0, left:0, right:0, bottom:0 }
			else {
				_cachedBounds = {
					top : Const.INFINITE,
					left : Const.INFINITE,
					right : -Const.INFINITE,
					bottom : -Const.INFINITE,
				}

				for(e in elements) {
					var x = switch e {
						case GridCell(li, cx, cy): li.pxParallaxX + cx*li.def.scaledGridSize;
						case Entity(li, ei): li.pxParallaxX + ei.x*li.def.getScale();
						case PointField(li, ei, fi, arrayIdx):
							var pt = fi.getPointGrid(arrayIdx);
							if( pt!=null )
								li.pxParallaxX + pt.cx*li.def.scaledGridSize;
							else
								0;
					}
					var y = switch e {
						case GridCell(li, cx, cy): li.pxParallaxY + cy*li.def.scaledGridSize;
						case Entity(li, ei): li.pxParallaxY + ei.y*li.def.getScale();
						case PointField(li, ei, fi, arrayIdx):
							var pt = fi.getPointGrid(arrayIdx);
							if( pt!=null )
								li.pxParallaxY + pt.cy*li.def.scaledGridSize;
							else
								0;
					}
					_cachedBounds.top = M.fmin( _cachedBounds.top, y );
					_cachedBounds.bottom = M.fmax( _cachedBounds.bottom, y );
					_cachedBounds.left = M.fmin( _cachedBounds.left, x );
					_cachedBounds.right = M.fmax( _cachedBounds.right, x );

					for(r in originalRects) {
						_cachedBounds.top = M.fmin( _cachedBounds.top, r.topPx );
						_cachedBounds.bottom = M.fmax( _cachedBounds.bottom, r.bottomPx );
						_cachedBounds.left = M.fmin( _cachedBounds.left, r.leftPx );
						_cachedBounds.right = M.fmax( _cachedBounds.right, r.rightPx );
					}

				}
			}
		}
		return _cachedBounds;
	}

	function clearGhost() {
		clearPathPreviewGhost();
		pointLinks.clear();
		pointLinks.visible = false;

		arrow.clear();
		arrow.visible = false;

		ghost.visible = false;
		ghost.clear();
		ghost.removeChildren();
		ghostLayerStack = null;
		ghostAutoTileGroups = [];
		ghostIntGridTransforms = [];
	}

	function clearPathPreviewGhost() {
		for(iid in suppressedPathPreviewIids)
			display.PathPreviewRender.suppressedEntities.remove(iid);
		suppressedPathPreviewIids = [];
		pathPreviewGhost.removeChildren();
		pathPreviewGhost.visible = false;
	}

	/** Capture raw Path indices before the move cuts entities from their source layer. */
	function capturePathPreviewDragSnapshots() {
		pathPreviewDragSnapshots = [];
		var candidates:Map<String,data.inst.EntityInstance> = new Map();
		for(ge in elements)
			switch ge {
				case Entity(_,ei), PointField(_,ei,_,_): candidates.set(ei.iid,ei);
				case _:
			}
		for(ei in candidates) {
			var config = editor.project.forkConfig.getPathPreview(ei);
			if( config==null )
				continue;
			var selected:Map<Int,Bool> = new Map();
			for(s in dragPointSnapshots) {
				var fi:data.inst.FieldInstance = s.fi;
				if( s.ei==ei && fi.defUid==config.pathField.uid )
					selected.set(s.arrayIdx,true);
			}
			var entitySelected = isEntitySelected(ei);
			if( !entitySelected && !selected.keys().hasNext() )
				continue;
			var points:Array<Null<PathPreviewPoint>> = [];
			var fi = ei.getFieldInstance(config.pathField,false);
			if( fi!=null )
				for(i in 0...fi.getArrayLength()) {
					var pt = fi.getPointGrid(i);
					points.push(pt==null ? null : {
						x:(pt.cx+0.5)*ei._li.def.gridSize,
						y:(pt.cy+0.5)*ei._li.def.gridSize,
					});
				}
			pathPreviewDragSnapshots.push({
				ei:ei,li:ei._li,pivot:{x:ei.x*1.,y:ei.y*1.},points:points,
				selectedPoints:selected,entitySelected:entitySelected,
			});
		}
	}

	/** Draw from snapshot overrides only. Dragging never writes temporary Point values. */
	function renderPathPreviewGhost(origin:Coords, now:Coords, isCopy:Bool) {
		clearPathPreviewGhost();
		if( pathPreviewDragSnapshots.length==0 )
			return;
		var delta = getLogicalDragDelta(origin,now);
		for(s in pathPreviewDragSnapshots) {
			var li = s.li;
			if( li.level!=editor.curLevel || !editor.levelRender.isLayerVisible(li) )
				continue;
			var grid = li.def.gridSize;
			var pathPx:Array<PathPreviewPoint> = [];
			for(i in 0...s.points.length) {
				var pt = s.points[i];
				if( pt==null )
					continue;
				if( s.selectedPoints.exists(i) ) {
					var cx = M.round((pt.x+delta.x)/grid-0.5);
					var cy = M.round((pt.y+delta.y)/grid-0.5);
					if( s.entitySelected || li.isValid(cx,cy) )
						pathPx.push({x:(cx+0.5)*grid,y:(cy+0.5)*grid});
					// Copying a point inserts the moved point before its original value.
					if( isCopy && !s.entitySelected )
						pathPx.push(pt);
				}
				else
					pathPx.push(pt);
			}
			var config = editor.project.forkConfig.getPathPreview(s.ei,{
				pivotPx:s.entitySelected ? {x:s.pivot.x+delta.x,y:s.pivot.y+delta.y} : s.pivot,
				pathPx:pathPx,
			});
			if( config==null )
				continue;
			var layerRoot = new h2d.Object(pathPreviewGhost);
			var scale = li.def.getScale();
			layerRoot.setPosition(li.pxParallaxX-li.pxTotalOffsetX*scale,li.pxParallaxY-li.pxTotalOffsetY*scale);
			layerRoot.setScale(scale);
			var preview = new display.PathPreviewRender(layerRoot);
			preview.setPosition(s.ei.x,s.ei.y);
			preview.render(s.ei,config,true);
			pathPreviewGhost.visible = true;
			// Entity copies retain their original line; point copies change the same line.
			if( (!isCopy || !s.entitySelected) && !display.PathPreviewRender.suppressedEntities.exists(s.ei.iid) ) {
				display.PathPreviewRender.suppressedEntities.set(s.ei.iid,true);
				suppressedPathPreviewIids.push(s.ei.iid);
			}
		}
	}

	function renderSelection() {
		selectRender.clear();
		shapeSelectRender.clear();
		if( movingGhost ) {
			selectRender.visible = shapeSelectRender.visible = false;
			return;
		}
		selectRender.visible = shapeSelectRender.visible = true;
		var c = SELECTION_COLOR;
		var alpha = 1;

		for(r in originalRects) {
			selectRender.beginFill(0x8ab7ff, alpha);
			selectRender.drawRect(r.leftPx, r.topPx, r.rightPx-r.leftPx, r.bottomPx-r.topPx);
		}

		for(ge in elements) {
			switch ge {
				case null:
				case GridCell(li, cx, cy):
					if( li.hasAnyGridValue(cx,cy) )
						selectRender.beginFill(c, alpha);
					else
						selectRender.beginFill(0x8ab7ff, alpha*0.6);
					selectRender.drawRect(
						li.pxParallaxX + cx*li.def.scaledGridSize,
						li.pxParallaxY + cy*li.def.scaledGridSize,
						li.def.scaledGridSize,
						li.def.scaledGridSize
					);

				case Entity(li, ei):
					if(display.EntityRender.suppressedShapes.exists(ei.iid)) continue;
					var shape=data.DrawableShape.read(ei);
					if(shape!=null && shape.error==null) {
						shapeSelectRender.beginFill(c,alpha);
						var scale=li.def.getScale(),g=shape.grid*scale;
						for(i in 0...Std.int(shape.cells.length/2)) shapeSelectRender.drawRect(
							li.pxParallaxX+ei.left*scale+shape.cells[i*2]*g,
							li.pxParallaxY+ei.top*scale+shape.cells[i*2+1]*g,g,g);
					}
					else if(shape==null) {
						selectRender.beginFill(c,alpha);
						selectRender.drawRect(
							li.pxParallaxX + ( ei.x - ei.width * ei.pivotX ) * li.def.getScale(),
							li.pxParallaxY + ( ei.y - ei.height * ei.pivotY ) * li.def.getScale(),
							ei.width * li.def.getScale(),
							ei.height * li.def.getScale()
						);
					}

				case PointField(li, ei, fi, arrayIdx):
					selectRender.beginFill(c, alpha);
					var pt = fi.getPointGrid(arrayIdx);
					if( pt!=null )
						selectRender.drawCircle(
							li.pxParallaxX + (pt.cx+0.5)*li.def.scaledGridSize,
							li.pxParallaxY + (pt.cy+0.5)*li.def.scaledGridSize,
							li.def.scaledGridSize*0.4
						);
			}
		}
	}

	function renderGhost() {
		clearGhost();

		// Tile/auto-tile ghost groups use the same rendering helpers as the
		// actual layer renderer. This avoids the old IntGrid color-box preview
		// and keeps pivots, flips and layer scaling consistent with the scene.
		ghostLayerStack = new h2d.Layers();
		ghost.addChild(ghostLayerStack);
		var tileRoots : Map<Int,h2d.Object> = new Map();
		var tileGroups : Map<Int,h2d.TileGroup> = new Map();
		var fallbackGraphics : Map<Int,h2d.Graphics> = new Map();
		var intGridTransformGraphics : Map<Int,h2d.Graphics> = new Map();

		function getLayerGhostRoot(li:data.inst.LayerInstance) : h2d.Object {
			if( !tileRoots.exists(li.layerDefUid) ) {
				var layerRoot = new h2d.Object();
				var scale = li.def.getScale();
				layerRoot.x = li.pxParallaxX - bounds.left - li.pxTotalOffsetX*scale;
				layerRoot.y = li.pxParallaxY - bounds.top - li.pxTotalOffsetY*scale;
				layerRoot.setScale(scale);

				// Match the scene's actual layer depth instead of relying on selection
				// iteration order. This is required for multi-layer ghost correctness.
				ghostLayerStack.add(layerRoot, editor.project.defs.getLayerDepth(li.def));
				tileRoots.set(li.layerDefUid, layerRoot);
			}
			return tileRoots.get(li.layerDefUid);
		}

		function getFallbackGraphics(li:data.inst.LayerInstance) : h2d.Graphics {
			if( !fallbackGraphics.exists(li.layerDefUid) )
				fallbackGraphics.set(li.layerDefUid, new h2d.Graphics(getLayerGhostRoot(li)));
			return fallbackGraphics.get(li.layerDefUid);
		}

		function getTileGhostGroup(li:data.inst.LayerInstance, td:data.def.TilesetDef) : Null<h2d.TileGroup> {
			if( td==null )
				return null;

			// A non-active layer can be visible/selected before its atlas has been
			// touched by the active tool. Force the same project image cache load
			// here so multi-layer preview does not degrade to a gray fallback.
			if( !td.isAtlasLoaded() ) {
				if( td.embedAtlas!=null )
					editor.project.getOrLoadEmbedImage(td.embedAtlas);
				else if( td.relPath!=null )
					editor.project.getOrLoadImage(td.relPath);
			}

			if( !td.isAtlasLoaded() )
				return null;

			if( !tileGroups.exists(li.layerDefUid) )
				tileGroups.set(li.layerDefUid, new h2d.TileGroup(td.getAtlasTile(), getLayerGhostRoot(li)));
			return tileGroups.get(li.layerDefUid);
		}

		function renderAutoTilesAt(li:data.inst.LayerInstance, cx:Int, cy:Int) : Bool {
			if( li==null || !editor.levelRender.isLayerVisible(li) || !li.def.isAutoLayer() || !li.isValid(cx,cy) )
				return false;

			var td = li.getTilesetDef();
			if( td==null || !td.isAtlasLoaded() )
				return false;

			if( li.autoTilesCache==null )
				li.applyAllRules();

			var tg = getTileGhostGroup(li, td);
			if( tg==null || li.autoTilesCache==null )
				return false;
			if( ghostAutoTileGroups.indexOf(tg)<0 )
				ghostAutoTileGroups.push(tg);

			var rendered = false;
			var coordId = li.coordId(cx,cy);
			li.def.iterateActiveRulesInDisplayOrder(li, (r)->{
				if( li.autoTilesCache.exists(r.uid) ) {
					var byCoord = li.autoTilesCache.get(r.uid);
					if( byCoord.exists(coordId) )
						for(tileInfos in byCoord.get(coordId)) {
							display.LayerRender.renderAutoTileInfos(li, td, tileInfos, tg, false);
							rendered = true;
						}
				}
			});
			return rendered;
		}

		for(ge in elements) {
			switch ge {
				case null:

				case GridCell(li, cx, cy):
					if( li.hasAnyGridValue(cx,cy) )
						switch li.def.type {
							case IntGrid:
								// Render both auto-rules owned by the IntGrid itself and any
								// separate visible AutoLayer that uses this IntGrid as source.
								// The latter is the common case where the old drag ghost was
								// only a solid IntGrid/gray rectangle.
								var renderedAutoTiles = renderAutoTilesAt(li, cx, cy);
								for(other in editor.curLevel.layerInstances)
									if( other!=li && other.def.type==AutoLayer && other.def.autoSourceLayerDefUid==li.layerDefUid )
										renderedAutoTiles = renderAutoTilesAt(other, cx, cy) || renderedAutoTiles;

								// Truly plain IntGrid layers still use their authored cell color.
								if( !renderedAutoTiles ) {
									var gr = getFallbackGraphics(li);
									gr.lineStyle();
									gr.beginFill( li.getIntGridColorAt(cx,cy) );
									gr.drawRect(
										cx*li.def.gridSize + li.pxTotalOffsetX,
										cy*li.def.gridSize + li.pxTotalOffsetY,
										li.def.gridSize,
										li.def.gridSize
									);
									gr.endFill();
								}
								else {
									// Auto-layer artwork is generated by rules and has no authored
									// rotation. Preview transformed IntGrid values in their own
									// colours instead of promising rotated rule output at drop.
									if( !intGridTransformGraphics.exists(li.layerDefUid) ) {
										var gr = new h2d.Graphics(getLayerGhostRoot(li));
										gr.visible = false;
										intGridTransformGraphics.set(li.layerDefUid,gr);
										ghostIntGridTransforms.push(gr);
									}
									var gr = intGridTransformGraphics.get(li.layerDefUid);
									gr.beginFill(li.getIntGridColorAt(cx,cy));
									gr.drawRect(cx*li.def.gridSize+li.pxTotalOffsetX,cy*li.def.gridSize+li.pxTotalOffsetY,li.def.gridSize,li.def.gridSize);
									gr.endFill();
								}

							case Tiles:
								var td = li.getTilesetDef();
								var tg = getTileGhostGroup(li, td);
								if( tg!=null )
									for(t in li.getGridTileStack(cx,cy))
										display.LayerRender.renderGridTile(li, td, t, cx, cy, tg, false);
								else {
									// Keep a visible fallback if a tileset failed to load, but
									// keep it at the correct scene layer depth.
									var gr = getFallbackGraphics(li);
									gr.lineStyle();
									gr.beginFill(0x777777, 0.8);
									gr.drawRect(
										cx*li.def.gridSize + li.pxTotalOffsetX,
										cy*li.def.gridSize + li.pxTotalOffsetY,
										li.def.gridSize,
										li.def.gridSize
									);
									gr.endFill();
								}

							case Entities:
							case AutoLayer:
						}

				case Entity(li, ei):
					var core = display.EntityRender.renderCore(ei);
					if(data.DrawableShape.read(ei)!=null) ghostLayerStack.addChild(core.wrapper); else ghost.addChild(core.wrapper);
					core.wrapper.alpha = 0.5;
					core.wrapper.setScale(li.def.getScale());
					core.wrapper.x = li.pxParallaxX + ei.x*li.def.getScale() - bounds.left;
					core.wrapper.y = li.pxParallaxY + ei.y*li.def.getScale() - bounds.top;

				case PointField(li, ei, fi, arrayIdx):
					var pt = fi.getPointGrid(arrayIdx);
					if( pt!=null ) {
						var x = li.pxParallaxX + (pt.cx+0.5)*li.def.scaledGridSize - bounds.left;
						var y = li.pxParallaxY + (pt.cy+0.5)*li.def.scaledGridSize - bounds.top;
						ghost.lineStyle(1, ei.getSmartColor(false));
						ghost.drawCircle(x, y, li.def.scaledGridSize*0.5);

						ghost.lineStyle();
						ghost.beginFill(ei.getSmartColor(false) );
						ghost.drawCircle(x, y, li.def.scaledGridSize*0.3);
						ghost.endFill();
					}
			}
		}

		ghost.endFill();
		var rectGhost = new h2d.Graphics(ghostLayerStack);
		for(r in originalRects) {
			rectGhost.lineStyle(1,SELECTION_COLOR,0.5);
			rectGhost.drawRect(r.leftPx-bounds.left, r.topPx-bounds.top, r.rightPx-r.leftPx, r.bottomPx-r.topPx);
		}

		applyGhostFlipTransform();
		return ghost;
	}


	function applyGhostFlipTransform() {
		if( ghostLayerStack==null )
			return;
		for(tg in ghostAutoTileGroups)
			tg.visible = getGhostTransform()==0;
		for(gr in ghostIntGridTransforms)
			gr.visible = getGhostTransform()!=0;

		var sx = ghostFlipX ? -1 : 1;
		var sy = ghostFlipY ? -1 : 1;
		ghostLayerStack.scaleX = ghostTranspose ? sy : sx;
		ghostLayerStack.scaleY = ghostTranspose ? -sx : sy;
		ghostLayerStack.rotation = ghostTranspose ? Math.PI/2 : 0;
		ghostLayerStack.x = 0;
		ghostLayerStack.y = 0;

		var flipBounds = getFlippableGridBounds();
		if( flipBounds==null )
			return;

		// The ghost's children use level coordinates relative to bounds.left/top.
		// Transform that origin through the same matrix used by the final drop.
		var origin = transformSelectionPoint(bounds.left, bounds.top, getGhostTransform(), flipBounds);
		ghostLayerStack.x = origin.x - bounds.left;
		ghostLayerStack.y = origin.y - bounds.top;
	}

	inline function getGhostTransform() : Int {
		return (ghostFlipX ? 1 : 0) | (ghostFlipY ? 2 : 0) | (ghostTranspose ? 4 : 0);
	}

	public function setGhostTransform(transform:Int) {
		ghostFlipX = (transform & 1)!=0;
		ghostFlipY = (transform & 2)!=0;
		ghostTranspose = (transform & 4)!=0;
		applyGhostFlipTransform();
	}

	public function setGhostFlip(flipX:Bool, flipY:Bool) {
		setGhostTransform((flipX ? 1 : 0) | (flipY ? 2 : 0));
	}


	public inline function resetGhostFlip() {
		setGhostFlip(false, false);
	}


	function getDeltaX(origin:Coords, now:Coords) {
		return snapToGrid()
			? ( now.cx - origin.cx ) * getSmartSnapGrid()
			: now.levelX - origin.levelX;
	}

	function getDeltaY(origin:Coords, now:Coords) {
		return snapToGrid()
			? ( now.cy - origin.cy ) * getSmartSnapGrid()
			: now.levelY - origin.levelY;
	}

	/**
	 * Logical movement used when mutating LDtk data.
	 *
	 * The live ghost works in rendered/scaled level pixels, while entity and grid
	 * coordinates are stored in unscaled LDtk pixels. Both paths must derive from
	 * the exact same snapped cell delta or dropping near a cell edge can differ
	 * from the preview by one tile.
	 */
	function getLogicalDragDelta(origin:Coords, now:Coords) {
		var rel = getSmartRelativeLayerInstance();
		if( rel==null )
			return {
				x: now.levelX-origin.levelX,
				y: now.levelY-origin.levelY,
			};

		var o = origin.cloneRelativeToLayer(rel);
		var n = now.cloneRelativeToLayer(rel);
		if( !snapToGrid() )
			return {
				x: n.levelX-o.levelX,
				y: n.levelY-o.levelY,
			};

		return {
			x: (n.cx-o.cx) * rel.def.gridSize,
			y: (n.cy-o.cy) * rel.def.gridSize,
		};
	}

	public function getSmartRelativeLayerInstance() : Null<data.inst.LayerInstance> {
		var l : data.inst.LayerInstance = null;
		for(ge in elements)
			switch ge {
				case null:

				case GridCell(li, _), Entity(li, _), PointField(li, _):
					if( l==null || li.def.scaledGridSize>l.def.scaledGridSize )
						l = li;
			}
		return l;
	}

	inline function getSmartSnapGrid() {
		var li = getSmartRelativeLayerInstance();
		return li==null ? 1 : li.def.scaledGridSize;
	}

	public function hasIncompatibleGridSizes() {
		var li  = getSmartRelativeLayerInstance();
		var grid = li==null ? 1 : li.def.gridSize;
		for( ge in elements )
			switch ge {
			case null:
			case GridCell(li, _), Entity(li, _), PointField(li, _):
				if( li.def.gridSize<grid && grid % li.def.gridSize != 0 )
					return true;
			}

		return false;
	}

	function isEntitySelected(e:data.inst.EntityInstance) {
		for( ge in elements)
			switch ge {
				case Entity(li, ei):
					if( ei==e )
						return true;

				case _:
			}

		return false;
	}

	function isFieldValueSelected(f:data.inst.FieldInstance, idx:Int) {
		return getFieldValueSelectionIdx(f,idx) >= 0;
	}

	function getFieldValueSelectionIdx(f:data.inst.FieldInstance, idx:Int) : Int {
		for( i in 0...elements.length )
			switch elements[i] {
				case PointField(li, ei, fi, arrayIdx):
					if( fi==f && arrayIdx==idx )
						return i;

				case _:
			}

		return -1;
	}



	inline function levelToGhostX(v:Float) {
		return v - bounds.left + ghost.x;
	}

	inline function levelToGhostY(v:Float) {
		return v - bounds.top + ghost.y;
	}

	public function onMoveStart(isCopy:Bool) {
		deduplicateElementsForDrag();
		captureDragSnapshot();
		capturePathPreviewDragSnapshots();
		movingGhost = true;
		selectRender.visible = shapeSelectRender.visible = false;
		renderGhost();

		// A true move previews the source hole immediately. Copy keeps source.
		if( !isCopy )
			cutDragSource();
	}

	public function onMoveEnd() {
		// If no drop committed (cancel, focus loss, etc.), restore the temporary cut.
		if( dragSnapshotActive && dragSourceCut )
			restoreDragSource();

		dragSnapshotActive = false;
		dragSourceCut = false;
		dragGridSnapshots = [];
		dragEntitySnapshots = [];
		dragPointSnapshots = [];
		pathPreviewDragSnapshots = [];
		movingGhost = false;
		ghostFlipX = false;
		ghostFlipY = false;
		ghostTranspose = false;
		clearGhost();
		arrow.clear();
		arrow.visible = false;
		invalidateSelectRender();
	}

	public function showGhost(origin:Coords, now:Coords, isCopy:Bool) {
		var rel = getSmartRelativeLayerInstance();
		origin = origin.cloneRelativeToLayer(rel);
		now = now.cloneRelativeToLayer(rel);

		selectRender.visible = shapeSelectRender.visible = false;

		// Preview movement is derived only from snapped cell deltas. Drop commit
		// uses the same cell delta (converted to logical/unscaled LDtk pixels).
		ghost.visible = true;
		ghost.x = bounds.left + getDeltaX(origin,now);
		ghost.y = bounds.top + getDeltaY(origin,now);
		renderPathPreviewGhost(origin,now,isCopy);


		// Movement arrow
		var onlyMovingPoints = true;
		for(ge in elements)
			if( !ge.match(PointField(_)) ) {
				onlyMovingPoints = false;
				break;
			}
		if( onlyMovingPoints || now.cx==origin.cx && now.cy==origin.cy )
			arrow.visible = false;
		else {
			var grid = getSmartSnapGrid();
			var fx = rel.pxParallaxX + (origin.cx+0.5) * grid;
			var fy = rel.pxParallaxY + (origin.cy+0.5) * grid;
			var tx = rel.pxParallaxX + (now.cx+0.5) * grid;
			var ty = rel.pxParallaxY + (now.cy+0.5) * grid;

			var a = Math.atan2(ty-fy, tx-fx);
			var size = 6;

			// Main line
			var c = isCopy ? SELECTION_COLOR : 0xffffff;
			arrow.clear();
			arrow.visible = true;
			arrow.lineStyle(1, c);
			if( !isCopy ) {
				arrow.moveTo(fx,fy);
				arrow.lineTo(tx,ty);
			}
			else {
				var d = 2;
				arrow.moveTo( fx+Math.cos(a+M.PIHALF)*d*0.5, fy+Math.sin(a+M.PIHALF)*d*0.5 );
				arrow.lineTo( tx+Math.cos(a+M.PIHALF)*d*0.5, ty+Math.sin(a+M.PIHALF)*d*0.5 );

				arrow.moveTo( fx+Math.cos(a-M.PIHALF)*d*0.5, fy+Math.sin(a-M.PIHALF)*d*0.5 );
				arrow.lineTo( tx+Math.cos(a-M.PIHALF)*d*0.5, ty+Math.sin(a-M.PIHALF)*d*0.5 );
			}

			// "Wings"
			arrow.lineStyle(2, c, 1);
			arrow.moveTo( tx, ty );
			arrow.lineTo( tx + Math.cos(a+M.PI*0.8)*size, ty + Math.sin(a+M.PI*0.8)*size );

			arrow.moveTo(tx,ty);
			arrow.lineTo( tx + Math.cos(a-M.PI*0.8)*size, ty + Math.sin(a-M.PI*0.8)*size );

			// Arrow peak fix
			arrow.beginFill(c);
			arrow.lineStyle();
			arrow.drawCircle(tx,ty,1,8);
			arrow.endFill();

		}


		// Render point links
		pointLinks.clear();
		pointLinks.visible = !isCopy;
		for(ge in elements)
			switch ge {
				case Entity(li,ei):
					for(fi in ei.getFieldInstancesOfType(F_Point)) {
						switch fi.def.editorDisplayMode {
							case PointStar, PointPath, PointPathLoop:
							case RefLinkBetweenCenters: continue;
							case RefLinkBetweenPivots: continue;
							case Points: continue;
							case EntityTile, LevelTile: continue;
							case Hidden, ValueOnly, NameAndValue, ArrayCountNoLabel, ArrayCountWithLabel, RadiusPx, RadiusGrid: continue;
						}

						// Links to Entity own field points
						for( i in 0...fi.getArrayLength() ) {
							if( i>0 && fi.def.editorDisplayMode==PointPath )
								continue;

							pointLinks.lineStyle(1,ei.getSmartColor(true));
							pointLinks.moveTo(
								levelToGhostX(ei.getPointOriginX(li.def)),
								levelToGhostY(ei.getPointOriginY(li.def))
							);
							var pt = fi.getPointGrid(i);
							if( pt!=null )
								if( isFieldValueSelected(fi,i) ) {
									pointLinks.lineTo(
										levelToGhostX( li.pxParallaxX+(pt.cx+0.5)*li.def.scaledGridSize ),
										levelToGhostY( li.pxParallaxY+(pt.cy+0.5)*li.def.scaledGridSize )
									);
								}
								else
									pointLinks.lineTo(
										li.pxParallaxX+(pt.cx+0.5)*li.def.scaledGridSize,
										li.pxParallaxY+(pt.cy+0.5)*li.def.scaledGridSize
									);
						}
					}

				case PointField(li, ei, fi, arrayIdx):
					pointLinks.lineStyle(1,ei.getSmartColor(true));
					var pt = fi.getPointGrid(arrayIdx);
					if( pt!=null ) {
						var x = levelToGhostX( li.pxParallaxX+(pt.cx+0.5)*li.def.scaledGridSize );
						var y = levelToGhostY( li.pxParallaxY+(pt.cy+0.5)*li.def.scaledGridSize );

						// Link to entity
						if( fi.def.editorDisplayMode==PointStar || arrayIdx==0 ) {
							pointLinks.moveTo(x,y);
							if( !isEntitySelected(ei) )
								pointLinks.lineTo(ei.getPointOriginX(li.def), ei.getPointOriginY(li.def));
							else
								pointLinks.lineTo(
									levelToGhostX(ei.getPointOriginX(li.def)),
									levelToGhostY(ei.getPointOriginY(li.def))
								);
						}

						if( fi.def.editorDisplayMode==PointPath ) {
							// Link to previous point in path
							if( arrayIdx>0 ) {
								var prev = fi.getPointGrid(arrayIdx-1);
								if( prev!=null ) {
									pointLinks.moveTo(x,y);
									if( isFieldValueSelected(fi,arrayIdx-1) )
										pointLinks.lineTo(
											levelToGhostX( li.pxParallaxX+(prev.cx+0.5)*li.def.scaledGridSize ),
											levelToGhostY( li.pxParallaxX+(prev.cy+0.5)*li.def.scaledGridSize )
										);
									else
										pointLinks.lineTo(
											li.pxParallaxX+(prev.cx+0.5)*li.def.scaledGridSize,
											li.pxParallaxY+(prev.cy+0.5)*li.def.scaledGridSize
										);
								}
							}

							// Link to next point in path
							if( arrayIdx<fi.getArrayLength()-1 ) {
								var next = fi.getPointGrid(arrayIdx+1);
								if( next!=null ) {
									pointLinks.moveTo(x,y);
									if( isFieldValueSelected(fi,arrayIdx+1) )
										pointLinks.lineTo(
											levelToGhostX( li.pxParallaxX+(next.cx+0.5)*li.def.scaledGridSize ),
											levelToGhostY( li.pxParallaxX+(next.cy+0.5)*li.def.scaledGridSize )
										);
									else
										pointLinks.lineTo(
											li.pxParallaxX+(next.cx+0.5)*li.def.scaledGridSize,
											li.pxParallaxY+(next.cy+0.5)*li.def.scaledGridSize
										);
								}
							}
						}
					}

				case _:
			}
	}


	public function isOveringSelection(m:Coords) {
		for(ge in elements) {
			switch ge {
				case GridCell(li, cx, cy):
					if( m.getLayerCx(li)==cx && m.getLayerCy(li)==cy )
						return true;

				case Entity(li, ei):
					if( ei.isOver(m.layerX, m.layerY) )
						return true;

				case PointField(li, ei, fi, arrayIdx):
					var pt = fi.getPointGrid(arrayIdx);
					if( pt!=null && m.getLayerCx(li)==pt.cx && m.getLayerCy(li)==pt.cy )
						return true;
			}
		}

		for(r in originalRects)
			if( m.levelX>=r.leftPx && m.levelX<=r.rightPx && m.levelY>=r.topPx && m.levelY<=r.bottomPx )
				return true;

		return false;
	}


	function deduplicateElementsForDrag() {
		var seen : Map<String,Bool> = new Map();
		var clean : Array<Null<GenericLevelElement>> = [];

		for(ge in elements) {
			if( ge==null )
				continue;

			var key = switch ge {
				case GridCell(li,cx,cy): 'G:' + li.iid + ':' + cx + ':' + cy;
				case Entity(li,ei): 'E:' + ei.iid;
				case PointField(li,ei,fi,arrayIdx): 'P:' + ei.iid + ':' + fi.defUid + ':' + arrayIdx;
			}

			if( !seen.exists(key) ) {
				seen.set(key,true);
				clean.push(ge);
			}
		}

		elements = clean;
		invalidateBounds();
	}


	function captureDragSnapshot() {
		dragGridSnapshots = [];
		dragEntitySnapshots = [];
		dragPointSnapshots = [];
		dragSourceLevel = null;
		lastDropTargetLevel = null;

		for(i in 0...elements.length) {
			var ge = elements[i];
			if( ge==null )
				continue;

			switch ge {
				case GridCell(li,cx,cy):
					if( dragSourceLevel==null )
						dragSourceLevel = li.level;

					switch li.def.type {
						case Tiles:
							if( li.hasAnyGridTile(cx,cy) )
								dragGridSnapshots.push({
									elementIdx:i,
									li:li,
									cx:cx,
									cy:cy,
									isTiles:true,
									value:0,
									tiles:[
										for(t in li.getGridTileStack(cx,cy))
											{ tileId:t.tileId, flips:t.flips }
									],
								});
						case IntGrid:
							if( li.hasIntGrid(cx,cy) )
								dragGridSnapshots.push({
									elementIdx:i,
									li:li,
									cx:cx,
									cy:cy,
									isTiles:false,
									value:li.getIntGrid(cx,cy),
									tiles:[],
								});
						case Entities, AutoLayer:
					}

				case Entity(li,ei):
					if( dragSourceLevel==null )
						dragSourceLevel = li.level;
					dragEntitySnapshots.push({
						elementIdx:i,
						li:li,
						ei:ei,
						x:ei.x,
						y:ei.y,
					});

				case PointField(li,ei,fi,arrayIdx):
					if( dragSourceLevel==null )
						dragSourceLevel = li.level;
					var pt = fi.getPointGrid(arrayIdx);
					if( pt!=null )
						dragPointSnapshots.push({
							elementIdx:i,
							li:li,
							ei:ei,
							fi:fi,
							arrayIdx:arrayIdx,
							cx:pt.cx,
							cy:pt.cy,
						});
			}
		}

		dragSnapshotActive = dragGridSnapshots.length>0 || dragEntitySnapshots.length>0 || dragPointSnapshots.length>0;
	}


	function invalidateDragLayer(li:data.inst.LayerInstance) {
		if( li.level==editor.curLevel )
			editor.levelRender.invalidateLayer(li);
		else
			editor.worldRender.invalidateLevelRender(li.level);
	}


	function cutDragSource() {
		if( !dragSnapshotActive || dragSourceCut )
			return;

		var touched : Map<String,data.inst.LayerInstance> = new Map();

		for(s in dragGridSnapshots) {
			var li : data.inst.LayerInstance = s.li;
			if( s.isTiles )
				li.removeAllGridTiles(s.cx,s.cy,false);
			else
				li.removeIntGrid(s.cx,s.cy,false);
			touched.set(li.iid,li);
		}

		for(s in dragEntitySnapshots) {
			var li : data.inst.LayerInstance = s.li;
			var ei : data.inst.EntityInstance = s.ei;
			li.detachEntityInstanceForMove(ei);
			touched.set(li.iid,li);
		}

		dragSourceCut = true;
		for(li in touched)
			invalidateDragLayer(li);
	}


	function restoreGridSnapshot(s:Dynamic) {
		var li : data.inst.LayerInstance = s.li;
		if( !li.isValid(s.cx,s.cy) )
			return;

		if( s.isTiles ) {
			var tiles : Array<Dynamic> = s.tiles;
			var stacking = tiles.length>1 || App.ME.settings.v.tileStacking;
			for(t in tiles)
				li.addGridTile(s.cx,s.cy,t.tileId,t.flips,stacking,false);
		}
		else
			li.setIntGrid(s.cx,s.cy,s.value,false);
	}


	public function restoreDragSource() {
		if( !dragSnapshotActive || !dragSourceCut )
			return;

		var touched : Map<String,data.inst.LayerInstance> = new Map();
		for(s in dragGridSnapshots) {
			restoreGridSnapshot(s);
			var li : data.inst.LayerInstance = s.li;
			touched.set(li.iid,li);
		}

		for(s in dragEntitySnapshots) {
			var li : data.inst.LayerInstance = s.li;
			var ei : data.inst.EntityInstance = s.ei;
			ei.x = s.x;
			ei.y = s.y;
			li.attachEntityInstanceForMove(ei);
			touched.set(li.iid,li);
		}

		dragSourceCut = false;
		for(li in touched)
			invalidateDragLayer(li);
	}


	function getDragTargetLevel(to:Coords) : data.Level {
		var source = dragSourceLevel!=null ? dragSourceLevel : editor.curLevel;
		var best : data.Level = null;

		for(l in source._world.levels)
			if( l.isWorldOver(to.worldX,to.worldY) ) {
				if( l==source )
					return source;
				if( best==null || l.worldDepth==source.worldDepth && best.worldDepth!=source.worldDepth )
					best = l;
			}

		return best!=null ? best : source;
	}


	public inline function getLastDropTargetLevel() return lastDropTargetLevel;

	function rejectTransformedDrop(message:String) : Array<data.inst.LayerInstance> {
		restoreDragSource();
		lastDropTargetLevel = null;
		N.warning(message);
		return [];
	}

	public function commitDragSnapshot(origin:Coords, to:Coords, isCopy:Bool) : Array<data.inst.LayerInstance> {
		if( !dragSnapshotActive )
			return moveSelecteds(origin,to,isCopy);

		var sourceLevel = dragSourceLevel!=null ? dragSourceLevel : editor.curLevel;
		// A field point remains owned by its entity, even when dragged over another level.
		var targetLevel = dragEntitySnapshots.length==0 && dragGridSnapshots.length==0
			? sourceLevel : getDragTargetLevel(to);
		lastDropTargetLevel = targetLevel;

		// Ensure destination history exists BEFORE any destination mutation.
		editor.ensureLevelTimeline(targetLevel);

		// Use the same snapped cell delta as the live ghost. Raw world-pixel
		// differences depend on where inside the source/destination cells the
		// mouse was grabbed/released and were the source of +/-1 tile drift.
		var dragDelta = getLogicalDragDelta(origin,to);
		var dx = dragDelta.x;
		var dy = dragDelta.y;
		var changed : Map<String,data.inst.LayerInstance> = new Map();
		var copiedEntities : Map<String,data.inst.EntityInstance> = new Map();
		var movedEntityIids : Map<String,Bool> = new Map();
		var transform = getGhostTransform();
		var transformBounds = getFlippableGridBounds();
		var gridTargets : Map<Int,{li:data.inst.LayerInstance,cx:Int,cy:Int}> = new Map();
		var transformedShapes : Map<Int,data.inst.EntityInstance> = new Map();

		// Plan the transformed drop from immutable source snapshots. Never stamp
		// an unrotated rectangle first: even a short-lived intermediate placement
		// can destroy unselected cells that are holes in the final selection.
		for(s in dragGridSnapshots) {
			var srcLi : data.inst.LayerInstance = s.li;
			var dstLi = targetLevel.getLayerInstance(srcLi.layerDefUid);
			var grid = srcLi.def.gridSize;
			var sourceCx:Float = s.cx;
			var sourceCy:Float = s.cy;
			if( transform!=0 && transformBounds!=null ) {
				var scaledGrid = srcLi.def.scaledGridSize;
				var p = transformSelectionPoint(srcLi.pxParallaxX+(sourceCx+0.5)*scaledGrid,
					srcLi.pxParallaxY+(sourceCy+0.5)*scaledGrid,transform,transformBounds);
				sourceCx = (p.x-srcLi.pxParallaxX)/scaledGrid-0.5;
				sourceCy = (p.y-srcLi.pxParallaxY)/scaledGrid-0.5;
				if( Math.abs(sourceCx-M.round(sourceCx))>0.0001 || Math.abs(sourceCy-M.round(sourceCy))>0.0001 )
					return rejectTransformedDrop("The transformed selection does not align with all selected layer grids.");
			}
			var worldX = srcLi.level.worldX+srcLi.pxTotalOffsetX+sourceCx*grid;
			var worldY = srcLi.level.worldY+srcLi.pxTotalOffsetY+sourceCy*grid;
			var targetX = (worldX+dx-targetLevel.worldX-dstLi.pxTotalOffsetX)/grid;
			var targetY = (worldY+dy-targetLevel.worldY-dstLi.pxTotalOffsetY)/grid;
			var tcx = M.round(targetX);
			var tcy = M.round(targetY);
			if( transform!=0 && (!dstLi.isValid(tcx,tcy)
				|| Math.abs(targetX-tcx)>0.0001 || Math.abs(targetY-tcy)>0.0001) )
				return rejectTransformedDrop("The transformed selection does not fit the destination. The original selection has been kept.");
			gridTargets.set(s.elementIdx,{li:dstLi,cx:tcx,cy:tcy});
		}
		if( transform!=0 && transformBounds!=null )
			for(s in dragEntitySnapshots) {
				var ei : data.inst.EntityInstance = s.ei;
				var shape = data.DrawableShape.read(ei);
				if( shape!=null && shape.error==null ) {
					var prepared = prepareShapeTransform(ei,transform,transformBounds);
					if( prepared==null )
						return rejectTransformedDrop("The selection could not be transformed. The original selection has been kept.");
					var tx = ei._li.level.worldX+prepared.x+dx-targetLevel.worldX;
					var ty = ei._li.level.worldY+prepared.y+dy-targetLevel.worldY;
					if( !shapeFitsLevel(prepared,targetLevel,tx-prepared.x,ty-prepared.y) )
						return rejectTransformedDrop("The transformed selection does not fit the destination. The original selection has been kept.");
					transformedShapes.set(s.elementIdx,prepared);
				}
			}

		// Empty cells in the rectangle are transparent during move/copy.
		// Only elements that actually exist in dragGridSnapshots/entities/points
		// may mutate destination data. originalRects is visual/hit-test metadata.

		// Grid data
		for(s in dragGridSnapshots) {
			var srcLi : data.inst.LayerInstance = s.li;
			var target = gridTargets.get(s.elementIdx);
			var dstLi = target.li;
			var tcx = target.cx;
			var tcy = target.cy;

			if( dstLi.isValid(tcx,tcy) ) {
				if( s.isTiles ) {
					var tiles : Array<Dynamic> = s.tiles;
					var stacking = tiles.length>1 || App.ME.settings.v.tileStacking;
					for(t in tiles)
						dstLi.addGridTile(tcx,tcy,t.tileId,data.TileTransform.compose(t.flips,transform),stacking,false);
				}
				else
					dstLi.setIntGrid(tcx,tcy,s.value,false);

				elements[s.elementIdx] = GridCell(dstLi,tcx,tcy);
				changed.set(dstLi.iid,dstLi);
				if( !isCopy )
					changed.set(srcLi.iid,srcLi);
			}
			else if( !isCopy ) {
				restoreGridSnapshot(s);
				elements[s.elementIdx] = GridCell(srcLi,s.cx,s.cy);
				changed.set(srcLi.iid,srcLi);
			}
		}

		// Entities
		for(s in dragEntitySnapshots) {
			var srcLi : data.inst.LayerInstance = s.li;
			var srcEi : data.inst.EntityInstance = s.ei;
			var dstLi = targetLevel.getLayerInstance(srcLi.layerDefUid);
			var prepared = transformedShapes.get(s.elementIdx);
			var tx = srcLi.level.worldX + (prepared==null ? s.x : prepared.x) + dx - targetLevel.worldX;
			var ty = srcLi.level.worldY + (prepared==null ? s.y : prepared.y) + dy - targetLevel.worldY;

			if( !srcEi.def.allowOutOfBounds && !targetLevel.inBounds(tx,ty) ) {
				if( !isCopy ) {
					srcEi.x = s.x;
					srcEi.y = s.y;
					srcLi.attachEntityInstanceForMove(srcEi);
					elements[s.elementIdx] = Entity(srcLi,srcEi);
					changed.set(srcLi.iid,srcLi);
				}
				continue;
			}

			var dstEi : data.inst.EntityInstance;
			if( isCopy ) {
				dstEi = dstLi.duplicateEntityInstance(srcEi);
				copiedEntities.set(srcEi.iid,dstEi);
			}
			else {
				// Erase source-side entity stamps while the entity still points to
				// its original level/layer.
				for(stampLi in editor.project.forkConfig.eraseEntityStamps(srcEi))
					changed.set(stampLi.iid,stampLi);
				dstLi.attachEntityInstanceForMove(srcEi);
				dstEi = srcEi;
				movedEntityIids.set(srcEi.iid,true);
				changed.set(srcLi.iid,srcLi);
			}

			if( prepared!=null )
				applyPreparedShape(dstEi,prepared);
			dstEi.x = tx;
			dstEi.y = ty;
			elements[s.elementIdx] = Entity(dstLi,dstEi);
			changed.set(dstLi.iid,dstLi);

			for(stampLi in editor.project.forkConfig.paintEntityStamps(dstEi))
				changed.set(stampLi.iid,stampLi);
			editor.ge.emit( EntityInstanceChanged(dstEi) );
		}

		var standalonePoints:Map<String,Array<Dynamic>> = new Map();
		// Selected point fields that belong to a moved/copied entity follow it.
		for(s in dragPointSnapshots) {
			var srcEi : data.inst.EntityInstance = s.ei;
			var dstEi : data.inst.EntityInstance = null;
			if( isCopy && copiedEntities.exists(srcEi.iid) )
				dstEi = copiedEntities.get(srcEi.iid);
			else if( !isCopy && movedEntityIids.exists(srcEi.iid) )
				dstEi = srcEi;

			if( dstEi==null ) {
				// Point-only selections have no entry in movedEntityIids. They still
				// commit into their owner; previously this branch discarded the drag.
				if( !isEntitySelected(srcEi) ) {
					var fi:data.inst.FieldInstance = s.fi;
					var key = srcEi.iid+":"+fi.defUid;
					if( !standalonePoints.exists(key) )
						standalonePoints.set(key,[]);
					standalonePoints.get(key).push(s);
				}
				continue;
			}

			var srcLi : data.inst.LayerInstance = s.li;
			var dstLi = dstEi._li;
			var grid = srcLi.def.gridSize;
			var srcWorldX = srcLi.level.worldX + srcLi.pxTotalOffsetX + s.cx*grid;
			var srcWorldY = srcLi.level.worldY + srcLi.pxTotalOffsetY + s.cy*grid;
			var pcx = M.round( (srcWorldX + dx - dstLi.level.worldX - dstLi.pxTotalOffsetX) / grid );
			var pcy = M.round( (srcWorldY + dy - dstLi.level.worldY - dstLi.pxTotalOffsetY) / grid );
			var pointFd = editor.project.defs.getFieldDef(s.fi.defUid);
			var dstFi = pointFd==null ? null : dstEi.getFieldInstance(pointFd,true);
			if( dstFi!=null && s.arrayIdx<dstFi.getArrayLength() ) {
				dstFi.parseValue(s.arrayIdx, pcx+Const.POINT_SEPARATOR+pcy);
				elements[s.elementIdx] = PointField(dstLi,dstEi,dstFi,s.arrayIdx);
			}
		}

		for(snapshots in standalonePoints) {
			// Insert/remove from the back so the captured source indices stay valid.
			snapshots.sort((a,b)->b.arrayIdx-a.arrayIdx);
			for(s in snapshots) {
				var li:data.inst.LayerInstance = s.li;
				var ei:data.inst.EntityInstance = s.ei;
				var fi:data.inst.FieldInstance = s.fi;
				var idx:Int = s.arrayIdx;
				var cx = M.round(s.cx+dx/li.def.gridSize);
				var cy = M.round(s.cy+dy/li.def.gridSize);
				if( idx>=fi.getArrayLength() || (isCopy && !li.isValid(cx,cy)) )
					continue;
				editor.ensureLevelTimeline(li.level).markEntityChange(ei);
				if( !li.isValid(cx,cy) ) {
					fi.removeArrayValue(idx);
					decrementAllFieldArrayIdxAbove(fi,idx);
					elements[s.elementIdx] = null;
				}
				else {
					if( isCopy && fi.def.isArray ) {
						fi.addArrayValue();
						var i = fi.getArrayLength()-1;
						while( i>idx ) {
							fi.parseValue(i,fi.getPointStr(i-1));
							i--;
						}
						for(j in 0...elements.length)
							switch elements[j] {
								case PointField(pointLi,pointEi,pointFi,pointIdx):
									if( pointFi==fi && pointIdx>=idx )
										elements[j] = PointField(pointLi,pointEi,pointFi,pointIdx+1);
								case _:
							}
					}
					fi.parseValue(idx,cx+Const.POINT_SEPARATOR+cy);
					elements[s.elementIdx] = PointField(li,ei,fi,idx);
				}
				changed.set(li.iid,li);
				editor.ge.emit( EntityInstanceChanged(ei) );
			}
		}
		elements = elements.filter(e->e!=null);

		// Move stored rectangle into destination level space.
		if( transform!=0 && transformBounds!=null )
			transformSelectionRects(transform,transformBounds);
		if( originalRects.length>0 )
			for(r in originalRects) {
				r.leftPx = sourceLevel.worldX + r.leftPx + dx - targetLevel.worldX;
				r.rightPx = sourceLevel.worldX + r.rightPx + dx - targetLevel.worldX;
				r.topPx = sourceLevel.worldY + r.topPx + dy - targetLevel.worldY;
				r.bottomPx = sourceLevel.worldY + r.bottomPx + dy - targetLevel.worldY;
			}

		dragSnapshotActive = false;
		dragSourceCut = false;

		var affected = [];
		for(li in changed) {
			// Ensure any auto-layer output reflects the final transferred data.
			if( li.def.type==IntGrid ) {
				if( li.def.isAutoLayer() )
					li.applyAllRules();
				for(other in li.level.layerInstances)
					if( other.def.type==AutoLayer && other.def.autoSourceLayerDefUid==li.layerDefUid )
						other.applyAllRules();
			}

			editor.ge.emit( LayerInstanceChangedGlobally(li) );
			invalidateDragLayer(li);
			affected.push(li);
		}

		if( targetLevel!=sourceLevel )
			editor.worldRender.invalidateLevelRender(targetLevel);
		editor.worldRender.invalidateLevelRender(sourceLevel);

		invalidateBounds();
		invalidateSelectRender();
		return affected;
	}



	public function toSelectionTemplate(name:String) : Dynamic {
		if( elements.length==0 )
			return null;

		var minX = 0x3fffffff;
		var minY = 0x3fffffff;
		var maxX = -0x3fffffff;
		var maxY = -0x3fffffff;

		function addBounds(x:Int,y:Int,w:Int,h:Int) {
			minX = M.imin(minX,x);
			minY = M.imin(minY,y);
			maxX = M.imax(maxX,x+w);
			maxY = M.imax(maxY,y+h);
		}

		var selectedEntities : Map<String,Bool> = new Map();
		for(ge in elements)
			switch ge {
				case null:
				case GridCell(li,cx,cy):
					var g = li.def.gridSize;
					addBounds(li.pxTotalOffsetX+cx*g, li.pxTotalOffsetY+cy*g, g,g);

				case Entity(li,ei):
					selectedEntities.set(ei.iid,true);
					var shape=data.DrawableShape.read(ei)!=null;
					addBounds(ei.left+(shape ? li.pxTotalOffsetX : 0),ei.top+(shape ? li.pxTotalOffsetY : 0),ei.width,ei.height);
					for(fi in ei.fieldInstances)
						if( fi.def.type==F_Point )
							for(i in 0...fi.getArrayLength()) {
								var pt = fi.getPointGrid(i);
								if( pt!=null ) {
									var g = li.def.gridSize;
									addBounds(li.pxTotalOffsetX+pt.cx*g,li.pxTotalOffsetY+pt.cy*g,g,g);
								}
							}

				case PointField(li,ei,fi,arrayIdx):
					var pt = fi.getPointGrid(arrayIdx);
					if( pt!=null ) {
						var g = li.def.gridSize;
						addBounds(li.pxTotalOffsetX+pt.cx*g,li.pxTotalOffsetY+pt.cy*g,g,g);
					}
			}

		if( minX==0x3fffffff )
			return null;

		var entityData : Array<Dynamic> = [];
		var doneEntities : Map<String,Bool> = new Map();
		for(ge in elements)
			switch ge {
				case Entity(li,ei):
					if( doneEntities.exists(ei.iid) )
						continue;
					doneEntities.set(ei.iid,true);

					var refs : Array<Dynamic> = [];
					var points : Array<Dynamic> = [];
					for(fi in ei.fieldInstances)
						switch fi.def.type {
							case F_EntityRef:
								var values : Array<Dynamic> = [];
								for(i in 0...fi.getArrayLength())
									values.push( fi.valueIsNull(i) ? null : fi.getEntityRefIid(i) );
								refs.push({
									fieldDefUid: fi.defUid,
									values: values,
								});

							case F_Point:
								var values : Array<Dynamic> = [];
								for(i in 0...fi.getArrayLength()) {
									var pt = fi.getPointGrid(i);
									if( pt!=null ) {
										var g = li.def.gridSize;
										values.push({
											idx:i,
											relX: li.pxTotalOffsetX + pt.cx*g - minX,
											relY: li.pxTotalOffsetY + pt.cy*g - minY,
										});
									}
								}
								points.push({
									fieldDefUid: fi.defUid,
									values: values,
								});

							case _:
						}

					entityData.push({
						sourceIid: ei.iid,
						layerDefUid: li.layerDefUid,
						relX: ei.x-minX+(data.DrawableShape.read(ei)!=null ? li.pxTotalOffsetX : 0),
						relY: ei.y-minY+(data.DrawableShape.read(ei)!=null ? li.pxTotalOffsetY : 0),
						coordinateSpace: data.DrawableShape.read(ei)!=null ? "layer" : "legacy",
						json: ei.toJson(li),
						refs: refs,
						points: points,
					});

				case _:
			}

		var cellData : Array<Dynamic> = [];
		var seenCells : Map<String,Bool> = new Map();
		for(ge in elements)
			switch ge {
				case GridCell(li,cx,cy):
					var key = li.iid+":"+cx+":"+cy;
					if( seenCells.exists(key) )
						continue;
					seenCells.set(key,true);
					var g = li.def.gridSize;
					switch li.def.type {
						case IntGrid:
							if( li.hasIntGrid(cx,cy) )
								cellData.push({
									kind:"intgrid",
									layerDefUid:li.layerDefUid,
									gridSize:g,
									relX:li.pxTotalOffsetX+cx*g-minX,
									relY:li.pxTotalOffsetY+cy*g-minY,
									value:li.getIntGrid(cx,cy),
								});

						case Tiles:
							if( li.hasAnyGridTile(cx,cy) ) {
								var stack : Array<Dynamic> = [];
								for(t in li.getGridTileStack(cx,cy))
									stack.push({tileId:t.tileId, flips:t.flips});
								cellData.push({
									kind:"tiles",
									layerDefUid:li.layerDefUid,
									gridSize:g,
									relX:li.pxTotalOffsetX+cx*g-minX,
									relY:li.pxTotalOffsetY+cy*g-minY,
									tiles:stack,
								});
							}

						case Entities, AutoLayer:
					}

				case _:
			}

		return {
			schemaVersion: 1,
			id: editor.project.generateUniqueId_UUID(),
			name: name,
			width: M.imax(1,maxX-minX),
			height: M.imax(1,maxY-minY),
			entities: entityData,
			cells: cellData,
		};
	}

	function snapToGrid() {
		return true;
	}


	/**
		Move or duplicate the selection
	**/
	public function moveSelecteds(origin:Coords, to:Coords, isCopy:Bool) : Array<data.inst.LayerInstance> {
		if( elements.length==0 )
			return [];

		var rel = getSmartRelativeLayerInstance();
		origin = origin.cloneRelativeToLayer(rel);
		to = to.cloneRelativeToLayer(rel);

		invalidateBounds();
		invalidateSelectRender();

		var postRemovals : Array< Void->Void > = [];
		var postInserts : Array< Void->Void > = [];
		var changedLayers : Map<data.inst.LayerInstance, data.inst.LayerInstance> = [];

		// Keep the visual selection rectangle aligned with the moved selection,
		// but never treat empty cells inside it as data to paste/erase.
		if( originalRects.length>0 ) {
			for(r in originalRects) {
				r.leftPx += getDeltaX(origin,to);
				r.rightPx += getDeltaX(origin,to);
				r.topPx += getDeltaY(origin,to);
				r.bottomPx += getDeltaY(origin,to);
			}
		}

		// Prepare movement effects
		var outOfBoundsRemovals : Array<String> = [];
		var moveGrid = getSmartSnapGrid();
		for( i in 0...elements.length ) {
			var ge = elements[i];
			switch ge {
				case null:

				case Entity(li, ei):
					var i = i;

					// Moving an existing entity erases its stamp at the old position first.
					if( !isCopy )
						for(stampLi in editor.project.forkConfig.eraseEntityStamps(ei))
							changedLayers.set(stampLi,stampLi);

					// Duplicate entity
					if( isCopy ) {
						var ed = ei.def;
						var oldEi = ei;
						var newEi : data.inst.EntityInstance = null;

						// Check limits
						if( ed.maxCount<=0 )
							newEi = li.duplicateEntityInstance(ei);
						else {
							var all = ei._project.getAllEntitiesFromLimitScope(li, ed, ed.limitScope);
							switch ed.limitBehavior {
								case DiscardOldOnes:
									if( all.length>=ed.maxCount )
										N.error(L.t._("You cannot have more than ::n:: ::name::.", { n:ed.maxCount, name:ed.identifier }));
									else
										newEi = li.duplicateEntityInstance(ei);

								case PreventAdding:
									if( all.length>=ed.maxCount )
										N.error(L.t._("You cannot have more than ::n:: ::name::.", { n:ed.maxCount, name:ed.identifier }));
									else
										newEi = li.duplicateEntityInstance(ei);

								case MoveLastOne:
									if( all.length>=ed.maxCount )
										N.error(L.t._("You cannot have more than ::n:: ::name::.", { n:ed.maxCount, name:ed.identifier }));
									else
										newEi = li.duplicateEntityInstance(ei);
							}
						}

						// Allow duplication
						if( newEi!=null ) {
							elements[i] = Entity(li,newEi);

							if( editor.resizeTool!=null && editor.resizeTool.isOnEntity(oldEi) )
								editor.createResizeToolFor( Entity(li,newEi) );

							if( ui.EntityInstanceEditor.existsFor(oldEi) )
								ui.EntityInstanceEditor.openFor(newEi);

							ei = newEi;
						}
					}

					// Apply movement
					ei.x += Std.int( getDeltaX(origin, to) );
					ei.y += Std.int( getDeltaY(origin, to) );
					changedLayers.set(li,li);

					// Out of bounds
					if( !ei.def.allowOutOfBounds && ei.isOutOfLayerBounds() ) {
						outOfBoundsRemovals.push(ei.def.identifier);
						li.removeEntityInstance(ei);
						elements[i] = null;

						// Unselect lost entity points
						for(fi in ei.fieldInstances)
						for(i in 0...fi.getArrayLength()) {
							var selIdx = getFieldValueSelectionIdx(fi,i);
							elements[selIdx] = null;
						}

						editor.ge.emit( EntityInstanceRemoved(ei) );
					}
					else {
						for(stampLi in editor.project.forkConfig.paintEntityStamps(ei))
							changedLayers.set(stampLi,stampLi);
						editor.ge.emit( EntityInstanceChanged(ei) );
					}

					editor.curLevelTimeline.markEntityChange(ei);

					// Remap points
					if( isCopy ) {
						var dcx = Std.int( getDeltaX(origin,to) / li.def.scaledGridSize );
						var dcy = Std.int( getDeltaY(origin,to) / li.def.scaledGridSize );

						for(fi in ei.getFieldInstancesOfType(F_Point))
						for( i in 0...fi.getArrayLength() ) {
							var pt = fi.getPointGrid(i);
							if( pt!=null ) {
								pt.cx+=dcx;
								pt.cy+=dcy;
								fi.parseValue(i, pt.cx+Const.POINT_SEPARATOR+pt.cy);
							}
						}
					}

				case GridCell(li, cx,cy):
					if( li.hasAnyGridValue(cx,cy) ) {
						editor.curLevelTimeline.markGridChange(li, cx,cy);
						switch li.def.type {
							case IntGrid:
								var v = li.getIntGrid(cx,cy);
								var gridRatio = Std.int( moveGrid / li.def.scaledGridSize );
								var tcx = cx + (to.cx-origin.cx)*gridRatio;
								var tcy = cy + (to.cy-origin.cy)*gridRatio;
								if( !isCopy && li.hasIntGrid(cx,cy) )
									postRemovals.push( ()-> li.removeIntGrid(cx,cy,false) );
								postInserts.push( ()-> li.setIntGrid(tcx, tcy, v, false) );

								elements[i] = li.isValid(tcx,tcy) ? GridCell(li, tcx, tcy) : null; // update selection
								changedLayers.set(li,li);
								editor.curLevelTimeline.markGridChange(li, tcx,tcy);

							case Tiles:
								var gridRatio = Std.int( moveGrid / li.def.scaledGridSize );
								var tcx = cx + (to.cx-origin.cx)*gridRatio;
								var tcy = cy + (to.cy-origin.cy)*gridRatio;

								if( !isCopy && li.hasAnyGridTile(cx,cy) )
									postRemovals.push( ()-> li.removeAllGridTiles(cx,cy,false) );

								var stacking = li.getGridTileStack(cx,cy).length>1 || App.ME.settings.v.tileStacking;
								for( t in li.getGridTileStack(cx,cy) )
									postInserts.push( ()-> li.addGridTile(tcx, tcy, t.tileId, t.flips, stacking, false) );

								elements[i] = li.isValid(tcx,tcy) ? GridCell(li, tcx, tcy) : null; // update selection
								changedLayers.set(li,li);
								editor.curLevelTimeline.markGridChange(li, tcx,tcy);

							case Entities:
							case AutoLayer:
						}
					}

				case PointField(li, ei, fi, arrayIdx):
					var pt = fi.getPointGrid(arrayIdx);
					if( pt!=null ) {
						// Duplicate (only arrays)
						if( isCopy && fi.def.isArray ) {
							fi.addArrayValue();
							var i = fi.getArrayLength()-1;
							while( i>arrayIdx ) {
								fi.parseValue(i, fi.getPointStr(i-1));
								i--;
							}
						}

						// Move point
						pt.cx += Std.int( getDeltaX(origin, to) / li.def.scaledGridSize );
						pt.cy += Std.int( getDeltaY(origin, to) / li.def.scaledGridSize );

						if( li.isValid(pt.cx,pt.cy) )
							fi.parseValue(arrayIdx, pt.cx+Const.POINT_SEPARATOR+pt.cy);
						else {
							// Out of bounds
							outOfBoundsRemovals.push(fi.def.identifier);
							fi.removeArrayValue(arrayIdx);
							decrementAllFieldArrayIdxAbove(fi, arrayIdx);
							elements[i] = null;
						}

						editor.ge.emit( EntityInstanceChanged(ei) );
						changedLayers.set(li,li);
					}
			}
		}

		if( outOfBoundsRemovals.length>0 )
			N.warning( L.t._("Out-of-bounds entity removed: ::names::", {names:outOfBoundsRemovals.join(", ")}) );

		// Execute move
		for(cb in postRemovals) cb();
		for(cb in postInserts) cb();

		// Call refresh events
		var affectedLayers = [];
		for(li in changedLayers) {
			editor.ge.emit( LayerInstanceChangedGlobally(li) );
			invalidateDragLayer(li);
			affectedLayers.push(li);
		}

		// Grabage collect "null" selections
		var i = 0;
		while( i<elements.length )
			if( elements[i]==null )
				elements.splice(i,1);
			else
				i++;

		return affectedLayers;
	}



	public function hasFlippableGridContent() {
		if( dragSnapshotActive && dragGridSnapshots.length>0 )
			return true;

		for(ge in elements)
			switch ge {
				case GridCell(li, cx, cy):
					switch li.def.type {
						case Tiles:
							if( li.hasAnyGridTile(cx,cy) )
								return true;
						case IntGrid:
							if( li.hasIntGrid(cx,cy) )
								return true;
						case Entities, AutoLayer:
					}

				case Entity(_,ei):
					var shape=data.DrawableShape.read(ei);
					if(shape!=null && shape.error==null) return true;
				case _:
			}
		return false;
	}


	function getFlippableGridBounds() : Null<SelectionBounds> {
		var b : Null<SelectionBounds> = null;

		inline function includeRect(left:Float, top:Float, right:Float, bottom:Float) {
			if( b==null )
				b = { left:left, top:top, right:right, bottom:bottom };
			else {
				b.left = M.fmin(b.left, left);
				b.top = M.fmin(b.top, top);
				b.right = M.fmax(b.right, right);
				b.bottom = M.fmax(b.bottom, bottom);
			}
		}

		// Preserve the authored selection rectangle when empty-space selection
		// stores one. Otherwise derive one shared visual rectangle from every
		// selected Tiles + IntGrid cell across all selected layers.
		for(r in originalRects)
			includeRect(r.leftPx, r.topPx, r.rightPx+1, r.bottomPx+1);

		for(ge in elements)
			switch ge {
				case GridCell(li, cx, cy):
					var include = switch li.def.type {
						case Tiles: dragSnapshotActive || li.hasAnyGridTile(cx,cy);
						case IntGrid: dragSnapshotActive || li.hasIntGrid(cx,cy);
						case Entities, AutoLayer: false;
					}
					if( include ) {
						var grid = li.def.scaledGridSize;
						var left = li.pxParallaxX + cx*grid;
						var top = li.pxParallaxY + cy*grid;
						includeRect(left, top, left+grid, top+grid);
					}

				case Entity(li,ei):
					var shape=data.DrawableShape.read(ei);
					if(shape!=null && shape.error==null) {
						var scale=li.def.getScale();
						includeRect(li.pxParallaxX+ei.left*scale,li.pxParallaxY+ei.top*scale,li.pxParallaxX+ei.right*scale,li.pxParallaxY+ei.bottom*scale);
					}
				case _:
			}

		return b;
	}


	/** Transform a point in the shared rendered rectangle, retaining its top-left. */
	function transformSelectionPoint(x:Float, y:Float, transform:Int, area:SelectionBounds) {
		var px = x-area.left;
		var py = y-area.top;
		var width = area.right-area.left;
		var height = area.bottom-area.top;
		if( (transform & 4)!=0 ) {
			var swap = px; px = py; py = swap;
			swap = width; width = height; height = swap;
		}
		if( (transform & 1)!=0 ) px = width-px;
		if( (transform & 2)!=0 ) py = height-py;
		return { x:area.left+px, y:area.top+py };
	}


	function transformSelectionRects(transform:Int, area:SelectionBounds) {
		for(r in originalRects) {
			var a = transformSelectionPoint(r.leftPx,r.topPx,transform,area);
			var b = transformSelectionPoint(r.rightPx+1,r.bottomPx+1,transform,area);
			r.leftPx = M.fmin(a.x,b.x);
			r.topPx = M.fmin(a.y,b.y);
			r.rightPx = M.fmax(a.x,b.x)-1;
			r.bottomPx = M.fmax(a.y,b.y)-1;
		}
	}


	/** Prepare shape geometry on a detached instance, so validation never partially edits the level. */
	function prepareShapeTransform(ei:data.inst.EntityInstance, transform:Int, area:SelectionBounds) : Null<data.inst.EntityInstance> {
		var li = ei._li;
		var scale = li.def.getScale();
		var a = transformSelectionPoint(li.pxParallaxX+ei.left*scale,li.pxParallaxY+ei.top*scale,transform,area);
		var b = transformSelectionPoint(li.pxParallaxX+ei.right*scale,li.pxParallaxY+ei.bottom*scale,transform,area);
		var left = (M.fmin(a.x,b.x)-li.pxParallaxX)/scale;
		var top = (M.fmin(a.y,b.y)-li.pxParallaxY)/scale;
		if( Math.abs(left-M.round(left))>0.0001 || Math.abs(top-M.round(top))>0.0001 ) {
			N.warning("This transform does not align with the selected shape's pixel grid.");
			return null;
		}

		var result = data.inst.EntityInstance.fromJson(ei._project,li,ei.toJson(li));
		var transpose = (transform & 4)!=0;
		var error = data.DrawableShape.transform(result,
			transpose ? (transform & 2)!=0 : (transform & 1)!=0,
			transpose ? (transform & 1)==0 : (transform & 2)!=0,
			transpose ? 1 : 0);
		if( error==null ) {
			var shape = data.DrawableShape.read(result);
			error = data.DrawableShape.applyCells(result,shape.cells,shape.grid,M.round(left),M.round(top),shape.mode,shape.preset);
		}
		if( error!=null ) {
			N.warning(error);
			return null;
		}
		return result;
	}


	function applyPreparedShape(ei:data.inst.EntityInstance, transformed:data.inst.EntityInstance) {
		ei.x = transformed.x;
		ei.y = transformed.y;
		ei.customWidth = transformed.customWidth;
		ei.customHeight = transformed.customHeight;
		// Keep references and PointField instances alive. Only native shape fields
		// are replaced; selected points must not retain a detached FieldInstance.
		for(fi in transformed.fieldInstances)
			if( StringTools.startsWith(fi.def.identifier,"Shape") )
				ei.fieldInstances.set(fi.defUid,fi);
		ei.drawableShapeCache = null;
		ei.drawableShapeSignature = null;
		ei.drawableShapeSourceError = null;
	}

	function shapeFitsLevel(ei:data.inst.EntityInstance, level:data.Level, dx=0., dy=0.) : Bool {
		return ei.def.allowOutOfBounds || ei.left+dx>=0 && ei.top+dy>=0
			&& ei.right+dx<=level.pxWid && ei.bottom+dy<=level.pxHei;
	}


	public inline function hasRotatableContent() return hasFlippableGridContent();

	public function rotateSelectedContent(clockwise:Bool) : Array<data.inst.LayerInstance> {
		return transformSelectedGridContent(data.TileTransform.rotate(0,clockwise));
	}

	public function flipSelectedGridContent(horizontal:Bool) : Array<data.inst.LayerInstance> {
		return transformSelectedGridContent(horizontal ? 1 : 2);
	}


	function transformSelectedGridContent(transform:Int) : Array<data.inst.LayerInstance> {
		deduplicateElementsForDrag();
		var area = getFlippableGridBounds();
		if( area==null )
			return [];

		var pendingTiles : Array<TileFlipSnapshot> = [];
		var pendingIntGrid : Array<IntGridFlipSnapshot> = [];
		var pendingShapes : Array<ShapeTransformSnapshot> = [];

		function getTarget(li:data.inst.LayerInstance, cx:Int, cy:Int) {
			var grid = li.def.scaledGridSize;
			var p = transformSelectionPoint(li.pxParallaxX+(cx+0.5)*grid,li.pxParallaxY+(cy+0.5)*grid,transform,area);
			var x = (p.x-li.pxParallaxX)/grid-0.5;
			var y = (p.y-li.pxParallaxY)/grid-0.5;
			return { cx:M.round(x), cy:M.round(y), aligned:Math.abs(x-M.round(x))<0.0001 && Math.abs(y-M.round(y))<0.0001 };
		}

		// Validate every destination before removing any source. Mixed grids must
		// map exactly, and a quarter turn near a level edge must never delete data.
		for(i in 0...elements.length)
			switch elements[i] {
				case GridCell(li,cx,cy):
					if( (li.def.type==Tiles || li.def.type==IntGrid) && li.hasAnyGridValue(cx,cy) ) {
						var target = getTarget(li,cx,cy);
						if( !target.aligned ) {
							N.warning("This transform does not align with all selected layer grids.");
							return [];
						}
						if( !li.isValid(target.cx,target.cy) ) {
							N.warning("Move the selection away from the level edge before transforming it.");
							return [];
						}
						if( li.def.type==Tiles )
							pendingTiles.push({elementIdx:i,li:li,cx:cx,cy:cy,targetCx:target.cx,targetCy:target.cy,
								tiles:[for(t in li.getGridTileStack(cx,cy)) {tileId:t.tileId,flips:t.flips}]});
						else
							pendingIntGrid.push({elementIdx:i,li:li,cx:cx,cy:cy,targetCx:target.cx,targetCy:target.cy,value:li.getIntGrid(cx,cy)});
					}
				case Entity(li,ei):
					var shape = data.DrawableShape.read(ei);
					if( shape!=null && shape.error==null ) {
						var transformed = prepareShapeTransform(ei,transform,area);
						if( transformed==null ) return [];
						if( !shapeFitsLevel(transformed,li.level) ) {
							N.warning("Move the selection away from the level edge before transforming it.");
							return [];
						}
						pendingShapes.push({source:ei,transformed:transformed});
					}
				case _:
			}

		if( pendingTiles.length==0 && pendingIntGrid.length==0 && pendingShapes.length==0 )
			return [];

		var changedLayers : Map<data.inst.LayerInstance,data.inst.LayerInstance> = [];
		for(c in pendingTiles) {
			editor.ensureLevelTimeline(c.li.level).markGridChange(c.li,c.cx,c.cy);
			editor.ensureLevelTimeline(c.li.level).markGridChange(c.li,c.targetCx,c.targetCy);
			c.li.removeAllGridTiles(c.cx,c.cy,false);
			changedLayers.set(c.li,c.li);
		}
		for(c in pendingIntGrid) {
			editor.ensureLevelTimeline(c.li.level).markGridChange(c.li,c.cx,c.cy);
			editor.ensureLevelTimeline(c.li.level).markGridChange(c.li,c.targetCx,c.targetCy);
			c.li.removeIntGrid(c.cx,c.cy,false);
			changedLayers.set(c.li,c.li);
		}

		// Sparse holes stay transparent. Only occupied source cells write a target.
		for(c in pendingTiles) {
			var stacking = c.tiles.length>1 || App.ME.settings.v.tileStacking;
			for(t in c.tiles)
				c.li.addGridTile(c.targetCx,c.targetCy,t.tileId,data.TileTransform.compose(t.flips,transform),stacking,false);
			elements[c.elementIdx] = GridCell(c.li,c.targetCx,c.targetCy);
		}
		for(c in pendingIntGrid) {
			c.li.setIntGrid(c.targetCx,c.targetCy,c.value,false);
			elements[c.elementIdx] = GridCell(c.li,c.targetCx,c.targetCy);
		}
		for(s in pendingShapes) {
			var li = s.source._li;
			editor.ensureLevelTimeline(li.level).markEntityChange(s.source);
			applyPreparedShape(s.source,s.transformed);
			editor.ge.emit(EntityInstanceChanged(s.source));
			changedLayers.set(li,li);
		}

		transformSelectionRects(transform,area);
		var affectedLayers = [];
		for(li in changedLayers) {
			editor.ge.emit(LayerInstanceChangedGlobally(li));
			invalidateDragLayer(li);
			affectedLayers.push(li);
		}
		clearGhost();
		invalidateBounds();
		invalidateSelectRender();
		return affectedLayers;
	}


	@:allow(tool.SelectionTool)
	function decrementAllFieldArrayIdxAbove(f:data.inst.FieldInstance, above:Int) {
		for(i in 0...elements.length)
			switch elements[i] {
				case PointField(li, ei, fi, arrayIdx):
					if( fi==f && arrayIdx>=above )
						elements[i] = PointField(li,ei,fi,arrayIdx-1);

				case _:
			}
	}

	public function onPostUpdate() {
		if( movingGhost ) {
			selectRender.visible = shapeSelectRender.visible = false;
			return;
		}

		if( invalidatedSelectRender ) {
			invalidatedSelectRender = false;
			renderSelection();
		}
	}
}
