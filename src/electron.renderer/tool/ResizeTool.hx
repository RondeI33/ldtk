package tool;

typedef ResizeRect = {
	var x: Int;
	var y: Int;
	var w: Int;
	var h: Int;
}

class ResizeTool extends Tool<Int> {
	static var DEFAULT_ALPHA = 0.75;
	static var HANDLE_RADIUS = 5;

	var draggedHandle: Null<RectHandlePos>;
	var dragOrigin : Coords;
	var g : h2d.Graphics;
	var ge: GenericLevelElement;
	var _handlePosIterator : Array<RectHandlePos>;

	var resizedAnything = false;
	var invalidated = true;
	var _rect : Null<ResizeRect>;
	var rect(get,never) : ResizeRect;
	var shapeSource:Null<data.inst.EntityInstance>;
	var shapeSnapshot:Dynamic;
	var shapeCandidate:Null<data.inst.EntityInstance>;
	var shapeGhost:Null<h2d.Graphics>;
	var shapeError:Null<String>;
	var shapeEditor:Editor;


	public function new(ge:GenericLevelElement) {
		super();
		this.ge = ge;
		shapeEditor=editor;
		createRootInLayers(editor.levelRender.root, Const.DP_UI);
		g = new h2d.Graphics(root);
		g.alpha = DEFAULT_ALPHA;

		_handlePosIterator = RectHandlePos.getConstructors().map( k->RectHandlePos.createByName(k) );
		editor.ge.addGlobalListener(onShapeContextEvent);
		render();
	}

	override function onDispose() {
		clearShapePreview();
		if(shapeEditor.ge!=null) shapeEditor.ge.removeListener(onShapeContextEvent);
		super.onDispose();
	}

	function clearShapePreview() {
		if(shapeSource!=null) {
			display.EntityRender.suppressedShapes.remove(shapeSource.iid);
			if(!shapeEditor.destroyed) {
				if(shapeSource._li==shapeEditor.curLayerInstance) shapeEditor.levelRender.invalidateLayer(shapeSource._li);
				shapeEditor.selectionTool.invalidateRender();
			}
		}
		if(shapeGhost!=null) shapeGhost.remove();
		shapeGhost=null;shapeSource=null;shapeSnapshot=null;shapeCandidate=null;shapeError=null;
	}

	function cancelShapeResize() {
		clearShapePreview();
		draggedHandle=null;curMode=null;resizedAnything=false;
		invalidate();
	}

	function onShapeContextEvent(ev:GlobalEvent) {
		if(shapeSource==null) return;
		switch ev {
			case LevelSelected(_), LayerInstanceSelected(_), LevelRestoredFromHistory(_), LayerInstancesRestoredFromHistory(_):
				cancelShapeResize();
			case EntityInstanceRemoved(ei): if(ei==shapeSource) cancelShapeResize();
			case _:
		}
	}

	/** Shape positions are layer-local; handles are drawn and hit-tested in level space. */
	function shapeLayer():Null<data.inst.LayerInstance> {
		return switch ge {
			case Entity(li,ei): data.DrawableShape.hasMetadata(ei) ? li : null;
			case _: null;
		}
	}

	function shapeContextIsCurrent():Bool {
		return editor==shapeEditor && shapeSource!=null && shapeSource._li==curLayerInstance
			&& shapeSource._li.levelId==editor.curLevelId
			&& project.getEntityInstanceByIid(shapeSource.iid)==shapeSource;
	}

	function render() {
		g.clear();

		// Draw handles
		var c = 0xffcc00;
		g.beginFill(c,1);
		for(p in _handlePosIterator) {
			if( isHandleActive(p) )
				g.drawCircle(getHandleX(p), getHandleY(p), HANDLE_RADIUS*0.6, 16);
		}
	}


	override function onGlobalEvent(ev:GlobalEvent) {
		super.onGlobalEvent(ev);

		switch ev {
			case EntityInstanceChanged(ei):
				if( isOnEntity(ei) )
					invalidate();

			case EntityInstanceRemoved(ei):
				if( isOnEntity(ei) ) {
					editor.clearResizeTool();
					return;
				}

			case _:
		}
	}

	inline function get_rect() {
		if( _rect==null )
			_rect = switch ge {
				case GridCell(li, cx, cy):
					{ x:cx*li.def.gridSize, y:cy*li.def.gridSize, w:li.def.gridSize, h:li.def.gridSize }

				case Entity(li, ei):
					{ x:ei.left, y:ei.top, w:ei.width, h:ei.height }

				case PointField(li, ei, fi, arrayIdx):
					var pt = fi.getPointGrid(arrayIdx);
					{ x:pt.cx*li.def.gridSize, y:pt.cy*li.def.gridSize, w:li.def.gridSize, h:li.def.gridSize }
			}
		return _rect;
	}

	function isHandleActive(p:RectHandlePos) {
		switch ge {
			case GridCell(li, cx, cy):
			case Entity(li, ei):
				if( !ei.def.resizableX )
					switch p {
						case Left,Right,TopLeft,TopRight,BottomLeft,BottomRight: return false;
						case _:
					}
				if( !ei.def.resizableY )
					switch p {
						case Top,Bottom,TopLeft,TopRight,BottomLeft,BottomRight: return false;
						case _:
					}

			case PointField(li, ei, fi, arrayIdx):
		}

		return true;
		// return switch p {
		// 	case Top, Bottom: rect.w > HANDLE_RADIUS*2;
		// 	case Left, Right: rect.h > HANDLE_RADIUS*2;
		// 	case TopLeft, TopRight, BottomLeft, BottomRight: true;
		// }
	}

	function getOveredHandle(m:Coords) : Null<RectHandlePos> {
		for(p in _handlePosIterator)
			if( isHandleActive(p) && M.dist(m.levelX, m.levelY, getHandleX(p), getHandleY(p) ) <= HANDLE_RADIUS )
				return p;
		return null;
	}

	function getHandleX(pos:RectHandlePos) : Float {
		var li=shapeLayer(),scale=li==null ? 1. : li.def.getScale();
		var x=li==null ? rect.x : li.pxParallaxX+rect.x*scale;
		var w=rect.w*scale;
		return switch pos {
			case Top, Bottom: x + w*0.5;
			case Left, TopLeft, BottomLeft: x - HANDLE_RADIUS;
			case Right, TopRight, BottomRight: x + w-(li==null ? 1 : 0) + HANDLE_RADIUS;
		}
	}

	function getHandleY(pos:RectHandlePos) : Float {
		var li=shapeLayer(),scale=li==null ? 1. : li.def.getScale();
		var y=li==null ? rect.y : li.pxParallaxY+rect.y*scale;
		var h=rect.h*scale;
		return switch pos {
			case Left,Right: y + h*0.5;
			case Top, TopLeft, TopRight: y - HANDLE_RADIUS;
			case Bottom, BottomLeft, BottomRight: y + h + HANDLE_RADIUS;
		}
	}

	override function isRunning():Bool {
		return draggedHandle!=null;
	}

	override function startUsing(ev:hxd.Event, m:Coords, ?extraParam:String) {
		super.startUsing(ev,m,extraParam);
		curMode = null;

		resizedAnything = false;
		ev.cancel = true;
		draggedHandle = getOveredHandle(m);
		if( draggedHandle==null ) {
			// Can happen if startUsing() is manually called (like while creating an Entity)
			switch ge {
				case GridCell(li, cx, cy):
				case Entity(li, ei):
					draggedHandle = ei.def.resizableX && ei.def.resizableY ? BottomRight
						: ei.def.resizableX ? Right
						: Bottom;

				case PointField(li, ei, fi, arrayIdx):
			}
		}

		dragOrigin = m;
		clearShapePreview();
		switch ge {
			case Entity(li,ei):
				var state=data.DrawableShape.read(ei);
				if(state!=null) {
					if(state.error!=null) {
						N.error("Shape unchanged: "+state.error);
						draggedHandle=null;
						return;
					}
					shapeSource=ei;
					shapeSnapshot=ei.toJson(li);
					shapeGhost=new h2d.Graphics();
					editor.levelRender.root.add(shapeGhost,Const.DP_UI);
					shapeGhost.setPosition(li.pxParallaxX+ei.left*li.def.getScale(),li.pxParallaxY+ei.top*li.def.getScale());
					shapeGhost.setScale(li.def.getScale());shapeGhost.alpha=0.85;
					display.DrawableShapeRender.draw(shapeGhost,state,ei,ei.def);
					display.EntityRender.suppressedShapes.set(ei.iid,true);
					editor.levelRender.invalidateLayer(li);
					editor.selectionTool.invalidateRender();
				}
			case _:
		}
	}

	override function stopUsing(m:Coords) {
		if(shapeSource!=null) {
			// Selection changes and history restoration may call clearResizeTool
			// after changing the active level. Never commit an old candidate there.
			if(!shapeContextIsCurrent()) {cancelShapeResize();return;}
			var ei=shapeSource,candidate=shapeCandidate;
			if(shapeError!=null) N.error("Shape unchanged: "+shapeError);
			else if(candidate!=null && (ei.x!=candidate.x || ei.y!=candidate.y || ei.width!=candidate.width || ei.height!=candidate.height)) {
				var s=data.DrawableShape.read(candidate);
				if(s!=null && s.error==null) {
					var error=data.DrawableShape.applyCells(ei,s.cells,s.grid,candidate.left,candidate.top,s.mode,s.preset);
					if(error!=null) N.error("Shape unchanged: "+error);
					else {
						var timeline=editor.ensureLevelTimeline(ei._li.level);
						timeline.markEntityChange(ei);
						timeline.saveLayerState(ei._li);
						editor.ge.emit(EntityInstanceChanged(ei));
						editor.levelRender.invalidateLayer(ei._li);
						editor.selectionTool.invalidateRender();
					}
				}
			}
			clearShapePreview();
			draggedHandle=null;curMode=null;resizedAnything=false;
			invalidate();return;
		}
		super.stopUsing(m);
		if( resizedAnything ) {
			switch ge {
				case GridCell(li, cx, cy):
				case Entity(li, ei): editor.curLevelTimeline.markEntityChange(ei);
				case PointField(li, ei, fi, arrayIdx):
			}
			editor.curLevelTimeline.saveLayerState(curLayerInstance);
		}
		draggedHandle = null;
	}

	public function onMouseDown(ev:hxd.Event, m:Coords) {
		var p = getOveredHandle(m);
		if( p!=null )
			startUsing(ev, m);
	}

	override function onMouseMoveCursor(ev:hxd.Event, m:Coords) {
		super.onMouseMoveCursor(ev, m);

		if( ev.cancel )
			return;

		var p = getOveredHandle(m);
		switch p {
			case null:
			case _:
				editor.cursor.set(Resize(p));
				ev.cancel = true;
		}
	}

	override function onMouseMove(ev:hxd.Event, m:Coords) {
		super.onMouseMove(ev, m);

		if( !isRunning() ) {
			// Overing
			var p = getOveredHandle(m);
			if( p!=null ) {
				g.alpha = 1;
				ev.cancel = true;
				editor.cursor.set( Resize(p) );
			}
			else
				g.alpha = DEFAULT_ALPHA;
		}
		else {
			// Actual resizing
			ev.cancel = true;
			if(shapeSource!=null && !shapeContextIsCurrent()) {cancelShapeResize();return;}
			var shape=shapeSource==null ? null : data.DrawableShape.read(shapeSource);
			var scale=shapeSource==null ? 1. : shapeSource._li.def.getScale();
			var mouseX=shapeSource==null ? m.levelX : (m.levelX-shapeSource._li.pxParallaxX)/scale;
			var mouseY=shapeSource==null ? m.levelY : (m.levelY-shapeSource._li.pxParallaxY)/scale;
			var handlePad=HANDLE_RADIUS/scale;
			var snapSize=shape==null ? (settings.v.grid ? editor.curLayerDef.gridSize : 1) : shape.grid;

			// Width
			var newWid = M.round(switch draggedHandle {
				case Top, Bottom: rect.w;

				case Left, TopLeft, BottomLeft:
					(rect.x+rect.w) - handlePad - mouseX;

				case Right, TopRight, BottomRight:
					mouseX - rect.x - handlePad;
				});
			if( newWid!=rect.w )
				newWid = M.round(newWid/snapSize) * snapSize;

			// Height
			var newHei = M.round(switch draggedHandle {
				case Left, Right: rect.h;

				case Top, TopLeft, TopRight:
					(rect.y+rect.h) - handlePad - mouseY;

				case Bottom, BottomLeft, BottomRight:
					mouseY - rect.y - handlePad;
			});
			if( newHei!=rect.h )
				newHei = M.round(newHei/snapSize) * snapSize;

			// Apply new bounds
			switch ge {
				case GridCell(li, cx, cy):

				case Entity(li, ei):
					if(shapeSource!=null) {
						var source=data.DrawableShape.read(shapeSource);
						shapeCandidate=data.inst.EntityInstance.fromJson(project,li,shapeSnapshot);
						var fromLeft=switch draggedHandle {case Left,TopLeft,BottomLeft:true;case _:false;};
						var fromTop=switch draggedHandle {case Top,TopLeft,TopRight:true;case _:false;};
						shapeError=ui.DrawableShapeEditor.resize(shapeCandidate,M.round(newWid/source.grid),M.round(newHei/source.grid),fromLeft,fromTop);
						shapeGhost.clear();shapeGhost.removeChildren();
						var previewState=data.DrawableShape.read(shapeCandidate);
						if(shapeError!=null) {
							shapeCandidate=null;
							var draft:Dynamic={cells:source.cells,grid:source.grid,mode:source.mode,preset:source.preset,width:source.width,height:source.height,
								error:shapeError,profile:source.profile,facing:source.facing,thickness:source.thickness,quarterTurns:source.quarterTurns,color:source.color,occupied:source.occupied};
							previewState=cast draft;
						}
						var x=shapeCandidate==null ? ei.left : shapeCandidate.left,y=shapeCandidate==null ? ei.top : shapeCandidate.top;
						shapeGhost.setPosition(li.pxParallaxX+x*li.def.getScale(),li.pxParallaxY+y*li.def.getScale());
						shapeGhost.setScale(li.def.getScale());shapeGhost.alpha=0.85;
						display.DrawableShapeRender.draw(shapeGhost,previewState,shapeCandidate,ei.def);
						App.ME.requestCpu();
						return;
					}
					var oldW = ei.width;
					var oldH = ei.height;

					// Aspect ratio
					if( ei.def.resizableX && ei.def.resizableY && ei.def.keepAspectRatio ) {
						var ar = ei.def.height/ei.def.width;
						switch draggedHandle {
							case null:
							case Top, Bottom:
								newWid = M.round( newHei*1/ar );

							case Left, Right:
								newHei = M.round( newWid*ar );

							case TopLeft, TopRight, BottomLeft, BottomRight:
								newHei = M.round( newWid*ar );
						}
					}


					if( ei.def.minWidth!=null ) newWid = M.imax(ei.def.minWidth, newWid);
					if( ei.def.maxWidth!=null ) newWid = M.imin(ei.def.maxWidth, newWid);
					ei.customWidth = M.imax( 1, newWid );
					if( ei.customWidth==ei.def.width ) ei.customWidth = null;

					if( ei.def.minHeight!=null ) newHei = M.imax(ei.def.minHeight, newHei);
					if( ei.def.maxHeight!=null ) newHei = M.imin(ei.def.maxHeight, newHei);
					ei.customHeight = M.imax( 1, newHei );
					if( ei.customHeight==ei.def.height ) ei.customHeight = null;

					switch draggedHandle {
						case Left, TopLeft, BottomLeft: if( ei.def.pivotX==0 ) ei.x -= ( ei.width - oldW );
						case Right, TopRight, BottomRight: if( ei.def.pivotX==1 ) ei.x += ( ei.width - oldW );
						case _:
					}

					switch draggedHandle {
						case Top, TopLeft, TopRight: if( ei.def.pivotY==0 ) ei.y -= ( ei.height - oldH );
						case Bottom, BottomLeft, BottomRight: if( ei.def.pivotY==1 ) ei.y += ( ei.height - oldH );
						case _:
					}

					editor.ge.emit( EntityInstanceChanged(ei) );
					editor.selectionTool.invalidateRender();
					invalidate();

				case PointField(li, ei, fi, arrayIdx):
			}
			resizedAnything = true;
			dragOrigin = m;
		}
	}

	public function isOnEntity(targetEi:data.inst.EntityInstance) {
		return switch ge {
			case GridCell(li, cx, cy): false;
			case Entity(li, ei): ei==targetEi;
			case PointField(li, ei, fi, arrayIdx): ei==targetEi;
		}
	}

	override function onKeyPress(keyId:Int) {
		if(keyId==K.ESCAPE && shapeSource!=null) {
			cancelShapeResize();
		}
	}

	public inline function invalidate() {
		invalidated = true;
	}

	override function postUpdate() {
		super.postUpdate();
		if( invalidated ) {
			_rect = null;
			render();
			invalidated = false;
		}
	}
}
