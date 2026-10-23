package tool;

class SelectionTemplateTool extends Tool<Int> {
	var tpl : Dynamic;
	var ghostRoot : h2d.Object;
	var ghostLayers : h2d.Layers;
	var ghostOverlay : h2d.Graphics;
	var flipX = false;
	var flipY = false;
	var placedOnRelease = false;
	var previewEntities = 0;
	var previewTiles = 0;
	var previewIntGrid = 0;
	var configuration:Null<data.inst.EntityInstance>;
	var configurationGhost:h2d.Object;
	var configurationTarget:Null<String>;
	var configurationSignature:Null<String>;

	public function new(tpl:Dynamic,allowConfigurationApply=true) {
		super();
		var module:Dynamic=js.Node.require(JsTools.getAssetsDir()+"/js/selection-template-editor.js");
		this.tpl = module.materialize(tpl,ui.TemplateEditorBridge.catalog(tpl));
		canUseOutOfBounds = false;

		ghostRoot = new h2d.Object();
		editor.levelRender.root.add(ghostRoot, Const.DP_UI);
		configurationGhost=new h2d.Object();
		editor.levelRender.root.add(configurationGhost,Const.DP_UI);
		var entities=arr(this.tpl,"entities");
		if(allowConfigurationApply && entities.length==1 && arr(this.tpl,"cells").length==0) {
			var raw=entities[0],ed=project.defs.getEntityDef(intVal(field(field(raw,"json"),"defUid"),-1));
			if(data.DrawableShape.isEnabled(ed)) {
				try { configuration=ui.TemplateEditorBridge.entity(raw); }
				catch(error:Dynamic) { N.error("This saved configuration cannot be applied: "+Std.string(error)); }
			}
		}
		rebuildGhost();
	}

	override function onDispose() {
		super.onDispose();
		if( ghostRoot!=null )
			ghostRoot.remove();
		ghostRoot = null;
		ghostLayers = null;
		ghostOverlay = null;
		if(configurationGhost!=null) configurationGhost.remove();
		configurationGhost=null;
	}

	// SelectionTemplates.place records all affected layers as one transaction.
	override function saveToHistory() {}

	override function getDefaultValue() return 1;
	override public function canEdit() return true;

	inline function field(o:Dynamic, name:String) : Dynamic
		return o==null ? null : Reflect.field(o,name);

	function arr(o:Dynamic, name:String) : Array<Dynamic> {
		var v = field(o,name);
		return v==null ? [] : cast v;
	}

	function intVal(v:Dynamic, fallback=0) : Int {
		if( v==null )
			return fallback;
		var i = Std.parseInt(Std.string(v));
		return M.isValidNumber(i) ? i : fallback;
	}

	function cloneJson(v:Dynamic) : Dynamic
		return v==null ? null : haxe.Json.parse(haxe.Json.stringify(v));

	inline function relX(raw:Dynamic, itemWidth=0) {
		var x=intVal(field(raw,"relX"));
		return flipX ? intVal(field(tpl,"width"))-x-itemWidth : x;
	}

	inline function relY(raw:Dynamic, itemHeight=0) {
		var y=intVal(field(raw,"relY"));
		return flipY ? intVal(field(tpl,"height"))-y-itemHeight : y;
	}

	function rebuildGhost() {
		ghostRoot.removeChildren();
		previewEntities=0;
		previewTiles=0;
		previewIntGrid=0;

		ghostLayers = new h2d.Layers(ghostRoot);
		ghostOverlay = new h2d.Graphics(ghostRoot);
		var layerRoots:Map<Int,h2d.Object>=new Map();

		function getLayerRoot(li:data.inst.LayerInstance):h2d.Object {
			if( !layerRoots.exists(li.layerDefUid) ) {
				var root=new h2d.Object();
				root.alpha=0.72 * li.def.displayOpacity;
				root.setScale(li.def.getScale());
				ghostLayers.add(root, editor.project.defs.getLayerDepth(li.def));
				layerRoots.set(li.layerDefUid,root);
			}
			return layerRoots.get(li.layerDefUid);
		}

		// Explicit Tiles and IntGrid cells.
		for(cell in arr(tpl,"cells")) {
			var li=editor.curLevel.getLayerInstance(intVal(field(cell,"layerDefUid"),-1));
			if(li==null)
				continue;
			var grid=intVal(field(cell,"gridSize"),li.def.gridSize);
			var x=relX(cell,grid);
			var y=relY(cell,grid);
			switch Std.string(field(cell,"kind")) {
				case "tiles":
					var td=li.getTilesetDef();
					if(td==null)
						continue;
					if(!td.isAtlasLoaded()) {
						if(td.embedAtlas!=null)
							editor.project.getOrLoadEmbedImage(td.embedAtlas);
						else if(td.relPath!=null)
							editor.project.getOrLoadImage(td.relPath);
					}
					if(!td.isAtlasLoaded())
						continue;
					for(t in arr(cell,"tiles")) {
						var tile=td.getTileById(intVal(field(t,"tileId")));
						if(tile==null)
							continue;
						var renderTile=tile.sub(0,0,tile.width,tile.height);
						renderTile.setCenterRatio(li.def.tilePivotX,li.def.tilePivotY);
						var flips=intVal(field(t,"flips")) ^ (flipX?1:0) ^ (flipY?2:0);
						var sx=M.hasBit(flips,0) ? -1 : 1;
						var sy=M.hasBit(flips,1) ? -1 : 1;
						var bmp=new h2d.Bitmap(renderTile,getLayerRoot(li));
						bmp.x=x + (li.def.tilePivotX + (sx<0?1:0))*grid;
						bmp.y=y + (li.def.tilePivotY + (sy<0?1:0))*grid;
						bmp.scaleX=sx;
						bmp.scaleY=sy;
						previewTiles++;
					}

				case "intgrid":
					var g=new h2d.Graphics(getLayerRoot(li));
					g.beginFill(li.def.getIntGridValueColor(intVal(field(cell,"value"))),0.85);
					g.drawRect(x,y,grid,grid);
					g.endFill();
					previewIntGrid++;

				case _:
			}
		}

		// Entities use the same render core as the real level scene.
		for(raw in arr(tpl,"entities")) {
			var li=editor.curLevel.getLayerInstance(intVal(field(raw,"layerDefUid"),-1));
			var json:Dynamic=cloneJson(field(raw,"json"));
			if(li==null || json==null)
				continue;
			try {
				json.iid=editor.project.generateUniqueId_UUID();
				json.px=[relX(raw),relY(raw)];
				var ei=data.inst.EntityInstance.fromJson(editor.project,li,cast json);
				if((flipX || flipY) && data.DrawableShape.read(ei)!=null) {
					data.DrawableShape.transform(ei,flipX,flipY);
					if(flipX) ei.x+=M.round(ei.width*(2*ei.pivotX-1));
					if(flipY) ei.y+=M.round(ei.height*(2*ei.pivotY-1));
				}
				var core=display.EntityRender.renderCore(ei,null,li.def);
				getLayerRoot(li).addChild(core.wrapper);
				core.wrapper.x=ei.x;
				core.wrapper.y=ei.y;
				core.wrapper.alpha=0.9;
				previewEntities++;
			}
			catch(e:Dynamic) {
				var fallback=new h2d.Graphics(getLayerRoot(li));
				fallback.lineStyle(1,0xff6688,0.9);
				var jsonW=intVal(field(json,"width"),16);
				var jsonH=intVal(field(json,"height"),16);
				fallback.drawRect(relX(raw)-jsonW*0.5,relY(raw)-jsonH*0.5,jsonW,jsonH);
			}
		}

		// Point/path handles remain visible on top of the real entity/tile preview.
		for(raw in arr(tpl,"entities")) {
			var li=editor.curLevel.getLayerInstance(intVal(field(raw,"layerDefUid"),-1));
			if(li==null)
				continue;
			for(pf in arr(raw,"points"))
				for(pt in arr(pf,"values")) {
					var px=intVal(field(pt,"relX"));
					var py=intVal(field(pt,"relY"));
					if(flipX) px=intVal(field(tpl,"width"))-px;
					if(flipY) py=intVal(field(tpl,"height"))-py;
					ghostOverlay.lineStyle(1,0x66ccff,0.9);
					ghostOverlay.beginFill(0x66ccff,0.35);
					ghostOverlay.drawCircle(px,py,M.fmax(3,li.def.gridSize*0.22));
					ghostOverlay.endFill();
				}
		}

		// Keep only a thin anchor outline; actual content is the primary preview.
		ghostOverlay.lineStyle(1,0x66ccff,0.45);
		ghostOverlay.drawRect(0,0,intVal(field(tpl,"width"),1),intVal(field(tpl,"height"),1));
	}

	public function debugGhostStats():Dynamic {
		return {
			entities:previewEntities,
			tiles:previewTiles,
			intGrid:previewIntGrid,
			childCount:ghostRoot==null ? 0 : ghostRoot.numChildren,
			appliesSettings:configurationTarget!=null,
			targetIid:configurationTarget,
		};
	}

	override function customCursor(ev:hxd.Event, m:Coords) {
		updateConfigurationPreview(m);
		if(configurationTarget!=null) {ghostRoot.visible=false;ev.cancel=true;return;}
		ghostRoot.setPosition(m.levelX,m.levelY);
		ghostRoot.visible=true;
		ev.cancel = true;
	}

	override function useAt(m:Coords, isOnStop:Bool) : Bool {
		if( !isOnStop )
			return false;
		var target=getConfigurationTarget(m);
		if(target!=null) {
			if(target.defUid!=configuration.defUid) {N.error("Choose a saved configuration of the same entity type. The existing shape was kept.");return false;}
			placedOnRelease=ui.DrawableShapeEditor.commit(target,()->data.DrawableShape.applyConfiguration(target,configuration));
			if(placedOnRelease) {editor.selectionTool.select([Entity(target._li,target)]);N.quick("Settings applied. Shape and IID preserved.");}
			return placedOnRelease;
		}
		placedOnRelease = data.SelectionTemplates.place(editor,tpl,Std.int(m.levelX),Std.int(m.levelY),flipX,flipY);
		return placedOnRelease;
	}

	function getConfigurationTarget(m:Coords):Null<data.inst.EntityInstance> {
		if(configuration==null || curLayerInstance==null || curLayerInstance.def.type!=Entities) return null;
		var instances=curLayerInstance.entityInstances;
		var i=instances.length;
		while(i-->0) {
			var ei=instances[i];
			if(data.DrawableShape.read(ei)!=null && ei.isOver(m.layerX,m.layerY)) return ei;
		}
		return null;
	}

	function updateConfigurationPreview(m:Coords) {
		var target=getConfigurationTarget(m);
		configurationTarget=target==null ? null : target.iid;
		configurationGhost.visible=target!=null;
		if(target==null) {configurationSignature=null;return;}
		var signature=target.iid+":"+target.x+":"+target.y+":"+target.drawableShapeSignature;
		if(signature==configurationSignature) return;
		configurationSignature=signature;
		configurationGhost.removeChildren();
		configurationGhost.setScale(target._li.def.getScale());
		configurationGhost.setPosition(target._li.pxParallaxX+target.x*target._li.def.getScale(),target._li.pxParallaxY+target.y*target._li.def.getScale());
		var same=target.defUid==configuration.defUid;
		if(same) {
			var candidate=data.inst.EntityInstance.fromJson(project,target._li,target.toJson(target._li));
			candidate.iid="configuration-preview-"+target.iid;
			var error=data.DrawableShape.applyConfiguration(candidate,configuration);
			if(error==null) {
				var core=display.EntityRender.renderCore(candidate);configurationGhost.addChild(core.wrapper);core.wrapper.alpha=0.9;
			}
			else same=false;
		}
		var label=new h2d.Text(Assets.getRegularFont(),configurationGhost);
		label.text=same ? "Apply settings · keep shape and IID" : "Incompatible configuration · shape stays unchanged";
		label.textColor=same ? 0x88ffbb : 0xff6666;
		label.x=-target.width*target.pivotX;
		label.y=-target.height*target.pivotY-label.textHeight-4;
	}

	/** Native HTML drag and ordinary click placement share the same validated commit path. */
	public function previewDrop(m:Coords) {var ev=new hxd.Event(EMove);customCursor(ev,m);}
	public function dropAt(m:Coords):Bool {
		var result=useAt(m,true);
		if(result) editor.clearSpecialTool();
		return result;
	}

	override function stopUsing(m:Coords) {
		placedOnRelease = false;
		super.stopUsing(m);

		if( placedOnRelease )
			editor.clearSpecialTool();
	}

	override function onAppCommand(cmd:AppCommand) {
		super.onAppCommand(cmd);
		switch cmd {
			case C_FlipX:
				flipX = !flipX;
				rebuildGhost();
			case C_FlipY:
				flipY = !flipY;
				rebuildGhost();
			case _:
		}
	}

	override function onKeyPress(keyId:Int) {
		super.onKeyPress(keyId);
		if( keyId==K.ESCAPE )
			editor.clearSpecialTool();
	}
}
