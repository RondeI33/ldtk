package data;

/**
 * Project-local reusable scene selection templates.
 *
 * Stored beside the LDtk project so stock LDtk project JSON remains unchanged.
 */
class SelectionTemplates {
	public static inline var FORMAT = 1;
	static var jPanel : Null<J>;

	static inline function field(o:Dynamic, name:String) : Dynamic
		return o==null ? null : Reflect.field(o,name);

	static function arr(o:Dynamic, name:String) : Array<Dynamic> {
		var v = field(o,name);
		return v==null ? [] : cast v;
	}

	static function cloneJson(v:Dynamic) : Dynamic
		return v==null ? null : haxe.Json.parse(haxe.Json.stringify(v));

	static function intVal(v:Dynamic, fallback=0) : Int {
		if( v==null )
			return fallback;
		var i = Std.parseInt(Std.string(v));
		return M.isValidNumber(i) ? i : fallback;
	}

	public static inline function getPath(p:Project) : String {
		return p.filePath.full+"-templates.json";
	}

	public static function load(p:Project) : Array<Dynamic> {
		var path = getPath(p);
		if( !NT.fileExists(path) )
			return [];

		try {
			var root : Dynamic = haxe.Json.parse(NT.readFileString(path));
			var raw = field(root,"templates");
			return raw==null ? [] : cast raw;
		}
		catch(err:Dynamic) {
			App.LOG.error('Failed to load selection templates "$path": '+Std.string(err));
			return [];
		}
	}

	static function saveAll(p:Project, templates:Array<Dynamic>) {
		var root : Dynamic = {
			format: FORMAT,
			projectIid: p.iid,
			templates: templates,
		};
		try {
			NT.writeFileString(getPath(p), haxe.Json.stringify(root,null,"\t"));
		}
		catch(err:Dynamic) {
			App.LOG.error('Failed to save selection templates: '+Std.string(err));
			N.error("Could not save template library.");
		}
	}

	public static function add(p:Project, tpl:Dynamic) {
		var all = load(p);
		all.push(cloneJson(tpl));
		saveAll(p,all);
	}

	public static function remove(p:Project, id:String) {
		var all = load(p);
		var i = all.length-1;
		while( i>=0 ) {
			if( Std.string(field(all[i],"id"))==id )
				all.splice(i,1);
			i--;
		}
		saveAll(p,all);
	}

	public static function duplicate(p:Project, id:String) {
		var all = load(p);
		for(t in all)
			if( Std.string(field(t,"id"))==id ) {
				var copy = cloneJson(t);
				Reflect.setField(copy,"id",p.generateUniqueId_UUID());
				Reflect.setField(copy,"name",Std.string(field(t,"name"))+" Copy");
				all.push(copy);
				saveAll(p,all);
				return;
			}
	}

	public static function rename(p:Project, id:String, newName:String) {
		var all = load(p);
		for(t in all)
			if( Std.string(field(t,"id"))==id )
				Reflect.setField(t,"name",newName);
		saveAll(p,all);
	}

	public static function installUi(editor:Editor) {
		if( editor==null )
			return;

		editor.jMainPanel.find("#selectionTemplatesTab").remove();
		editor.jMainPanel.find("#selectionTemplatesPanel").remove();

		var tab = new J('<button id="selectionTemplatesTab" class="transparent">Templates</button>');
		var near = editor.jMainPanel.find("button.editLayers");
		if( near.length>0 )
			tab.insertAfter(near);
		else
			tab.prependTo(editor.jMainPanel);

		var panel = new J('<div id="selectionTemplatesPanel"></div>');
		panel.css({
			position: "absolute",
			left: "0",
			right: "0",
			top: "0",
			bottom: "0",
			zIndex: "40",
			background: "#20242b",
			padding: "10px",
			overflow: "hidden",
		});
		panel.hide();
		editor.jMainPanel.css("position","relative");
		panel.appendTo(editor.jMainPanel);
		jPanel = panel;

		tab.click(function(_) {
			if( panel.is(":visible") ) {
				panel.hide();
				editor.clearSpecialTool();
			}
			else {
				panel.show();
				renderPanel(editor);
			}
		});
	}

	public static function refreshUi(editor:Editor) {
		if( jPanel!=null && jPanel.is(":visible") )
			renderPanel(editor);
	}

	static function renderPanel(editor:Editor) {
		if( jPanel==null )
			return;

		var panel = jPanel;
		panel.off().empty();

		var header = new J('<div style="display:flex;align-items:center;gap:8px;margin-bottom:8px"></div>');
		header.appendTo(panel);
		var title = new J('<strong style="flex:1">Templates</strong>');
		title.appendTo(header);
		var close = new J('<button class="transparent">×</button>');
		close.appendTo(header);
		close.click(function(_) {
			panel.hide();
			editor.clearSpecialTool();
		});

		var search = new J('<input type="text" placeholder="Search templates..." style="width:100%;box-sizing:border-box;margin-bottom:8px"/>');
		search.appendTo(panel);
		var list = new J('<div style="overflow:auto;height:calc(100% - 68px)"></div>');
		list.appendTo(panel);

		function rebuild() {
			list.empty();
			var q = Std.string(search.val()).toLowerCase();
			var all = load(editor.project);
			if( all.length==0 ) {
				var empty = new J('<div style="opacity:.65;padding:12px 4px"></div>');
				empty.text("Select part of a level, right-click and choose Save to template.");
				empty.appendTo(list);
				return;
			}

			for(tpl in all) {
				var name = Std.string(field(tpl,"name"));
				if( q.length>0 && name.toLowerCase().indexOf(q)<0 )
					continue;

				var row = new J('<div style="border:1px solid #3a414c;border-radius:4px;padding:8px;margin-bottom:6px"></div>');
				row.appendTo(list);

				var nameEl = new J('<div style="font-weight:bold;margin-bottom:4px"></div>');
				nameEl.text(name);
				nameEl.appendTo(row);

				var count = arr(tpl,"entities").length;
				var cellCount = arr(tpl,"cells").length;
				var meta = new J('<div style="opacity:.65;font-size:11px;margin-bottom:6px"></div>');
				meta.text(count+" entities · "+cellCount+" grid cells");
				meta.appendTo(row);

				var actions = new J('<div style="display:flex;gap:4px;flex-wrap:wrap"></div>');
				actions.appendTo(row);

				var place = new J('<button>Place</button>');
				place.appendTo(actions);
				var captured = cloneJson(tpl);
				place.click(function(_) {
					editor.setSpecialTool(new tool.SelectionTemplateTool(captured));
					N.quick("Template placement active. Click the level to place, Esc to cancel.");
				});

				var renameBtn = new J('<button class="transparent">Rename</button>');
				renameBtn.appendTo(actions);
				var templateId = Std.string(field(tpl,"id"));
				renameBtn.click(function(_) {
					var n = js.Browser.window.prompt("Template name:",name);
					if( n!=null && StringTools.trim(n).length>0 ) {
						rename(editor.project,templateId,StringTools.trim(n));
						renderPanel(editor);
					}
				});

				var duplicateBtn = new J('<button class="transparent">Duplicate</button>');
				duplicateBtn.appendTo(actions);
				duplicateBtn.click(function(_) {
					duplicate(editor.project,templateId);
					renderPanel(editor);
				});

				var deleteBtn = new J('<button class="transparent">Delete</button>');
				deleteBtn.appendTo(actions);
				deleteBtn.click(function(_) {
					if( js.Browser.window.confirm('Delete template "'+name+'"?') ) {
						remove(editor.project,templateId);
						renderPanel(editor);
					}
				});
			}
		}

		search.on("input",function(_) rebuild());
		rebuild();
	}

	static function transformedX(tpl:Dynamic, rel:Int, itemWidth:Int, flipX:Bool) {
		return flipX ? intVal(field(tpl,"width")) - rel - itemWidth : rel;
	}
	static function transformedY(tpl:Dynamic, rel:Int, itemHeight:Int, flipY:Bool) {
		return flipY ? intVal(field(tpl,"height")) - rel - itemHeight : rel;
	}

	public static function place(editor:Editor, tpl:Dynamic, atX:Int, atY:Int, flipX=false, flipY=false) : Bool {
		if( editor==null || tpl==null )
			return false;

		var level = editor.curLevel;
		var project = editor.project;

		for(cell in arr(tpl,"cells")) {
			var layerUid = intVal(field(cell,"layerDefUid"),-1);
			var li = level.getLayerInstance(layerUid);
			if( li==null ) {
				N.error("Template cannot be placed: a required layer is missing.");
				return false;
			}
			var grid = li.def.gridSize;
			var rx = transformedX(tpl,intVal(field(cell,"relX")),grid,flipX);
			var ry = transformedY(tpl,intVal(field(cell,"relY")),grid,flipY);
			var cx = M.round((atX + rx - li.pxTotalOffsetX)/grid);
			var cy = M.round((atY + ry - li.pxTotalOffsetY)/grid);
			if( !li.isValid(cx,cy) ) {
				N.error("Template cannot be placed outside the level.");
				return false;
			}
			if( li.hasAnyGridValue(cx,cy) ) {
				N.error("Template cannot be placed on occupied grid cells.");
				return false;
			}
		}

		var touched : Map<String,data.inst.LayerInstance> = new Map();
		var newByOld : Map<String,data.inst.EntityInstance> = new Map();
		var pending : Array<{ raw:Dynamic, ei:data.inst.EntityInstance }> = [];

		for(raw in arr(tpl,"entities")) {
			var layerUid = intVal(field(raw,"layerDefUid"),-1);
			var li = level.getLayerInstance(layerUid);
			var json : Dynamic = cloneJson(field(raw,"json"));
			if( li==null || json==null ) {
				N.error("Template cannot be placed: an entity layer or definition is missing.");
				return false;
			}

			var oldIid = Std.string(field(raw,"sourceIid"));
			var newIid = project.generateUniqueId_UUID();
			var rx = intVal(field(raw,"relX"));
			var ry = intVal(field(raw,"relY"));
			if( flipX ) rx = intVal(field(tpl,"width")) - rx;
			if( flipY ) ry = intVal(field(tpl,"height")) - ry;

			Reflect.setField(json,"iid",newIid);
			Reflect.setField(json,"px",[atX+rx,atY+ry]);
			var ei = data.inst.EntityInstance.fromJson(project,li,cast json);
			li.attachEntityInstanceForMove(ei);
			newByOld.set(oldIid,ei);
			pending.push({raw:raw,ei:ei});
			touched.set(li.iid,li);
		}

		for(pendingItem in pending) {
			var ei = pendingItem.ei;
			var li = ei._li;

			for(ref in arr(pendingItem.raw,"refs")) {
				var fd = project.defs.getFieldDef(intVal(field(ref,"fieldDefUid"),-1));
				if( fd==null )
					continue;
				var fi = ei.getFieldInstance(fd,true);
				var values : Array<Dynamic> = cast field(ref,"values");
				if( values==null )
					continue;
				for(i in 0...values.length) {
					var oldTarget = values[i]==null ? null : Std.string(values[i]);
					var target = oldTarget==null ? null : newByOld.get(oldTarget);
					fi.parseValue(i,target==null ? null : target.iid);
				}
			}

			for(ptField in arr(pendingItem.raw,"points")) {
				var fd = project.defs.getFieldDef(intVal(field(ptField,"fieldDefUid"),-1));
				if( fd==null )
					continue;
				var fi = ei.getFieldInstance(fd,true);
				for(pt in arr(ptField,"values")) {
					var idx = intVal(field(pt,"idx"));
					var grid = li.def.gridSize;
					var rx = intVal(field(pt,"relX"));
					var ry = intVal(field(pt,"relY"));
					if( flipX ) rx = intVal(field(tpl,"width")) - rx;
					if( flipY ) ry = intVal(field(tpl,"height")) - ry;
					var cx = M.round((atX+rx-li.pxTotalOffsetX)/grid);
					var cy = M.round((atY+ry-li.pxTotalOffsetY)/grid);
					fi.parseValue(idx,cx+Const.POINT_SEPARATOR+cy);
				}
			}

			ei.tidy(project,li);
			for(stampLi in project.forkConfig.paintEntityStamps(ei))
				touched.set(stampLi.iid,stampLi);
			editor.ge.emit(EntityInstanceChanged(ei));
		}

		for(cell in arr(tpl,"cells")) {
			var li = level.getLayerInstance(intVal(field(cell,"layerDefUid"),-1));
			var grid = li.def.gridSize;
			var rx = transformedX(tpl,intVal(field(cell,"relX")),grid,flipX);
			var ry = transformedY(tpl,intVal(field(cell,"relY")),grid,flipY);
			var cx = M.round((atX + rx - li.pxTotalOffsetX)/grid);
			var cy = M.round((atY + ry - li.pxTotalOffsetY)/grid);
			var kind = Std.string(field(cell,"kind"));
			if( kind=="intgrid" )
				li.setIntGrid(cx,cy,intVal(field(cell,"value")),false);
			else if( kind=="tiles" ) {
				var tiles = arr(cell,"tiles");
				var stacking = tiles.length>1 || App.ME.settings.v.tileStacking;
				for(t in tiles)
					li.addGridTile(cx,cy,intVal(field(t,"tileId")),intVal(field(t,"flips")),stacking,false);
			}
			touched.set(li.iid,li);
		}

		var changed : Array<data.inst.LayerInstance> = [];
		for(li in touched) {
			if( li.def.type==IntGrid ) {
				if( li.def.isAutoLayer() )
					li.applyAllRules();
				for(other in li.level.layerInstances)
					if( other.def.type==AutoLayer && other.def.autoSourceLayerDefUid==li.layerDefUid ) {
						other.applyAllRules();
						if( !touched.exists(other.iid) )
							changed.push(other);
					}
			}
			editor.levelRender.invalidateLayer(li);
			editor.ge.emit(LayerInstanceChangedGlobally(li));
			changed.push(li);
		}
		editor.saveLayerStatesByLevel(changed);
		editor.invalidateResizeTool();
		N.quick("Template placed");
		return true;
	}
}
