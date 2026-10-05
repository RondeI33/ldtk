package data;

/**
 * Project-local reusable scene selection templates.
 *
 * Stored beside the LDtk project so stock LDtk project JSON remains unchanged.
 */
class SelectionTemplates {
	public static inline var FORMAT = 1;
	static var jPanel : Null<J>;
	static var jSave : Null<J>;
	static var saveEnabled:Null<Bool>;

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

	static function saveAll(p:Project, templates:Array<Dynamic>):Bool {
		var path=getPath(p), tmp=path+".tmp";
		try {
			if(NT.fileExists(path)) {
				var previous:Dynamic=haxe.Json.parse(NT.readFileString(path));
				if(previous.format!=FORMAT || !Std.isOfType(previous.templates,Array)) throw "Unsupported or damaged template library.";
			}
			NT.writeFileString(tmp,haxe.Json.stringify({format:FORMAT,projectIid:p.iid,templates:templates},null,"	"));
			var fs:Dynamic=js.Node.require("fs");
			fs.renameSync(tmp,path);
			return true;
		}
		catch(e:Dynamic) {
			try { if(NT.fileExists(tmp)) { var fs:Dynamic=js.Node.require("fs"); fs.unlinkSync(tmp); } } catch(_:Dynamic) {}
			N.error("Could not save template library: "+Std.string(e));
			return false;
		}
	}

	public static function put(p:Project, tpl:Dynamic):Bool {
		var all=load(p);
		var name=tpl.name==null ? "" : StringTools.trim(Std.string(tpl.name));
		if(name.length==0) { N.error("Enter a template name."); return false; }
		var copy=cloneJson(tpl); copy.name=name;
		if(copy.id==null) copy.id=p.generateUniqueId_UUID();
		var found=false;
		for(i in 0...all.length) if(all[i].id==copy.id) { all[i]=copy; found=true; break; }
		if(!found) all.push(copy);
		return saveAll(p,all);
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
		editor.jMainPanel.find("#selectionTemplatesTab, #selectionTemplatesPanel").remove();
		jSave=null; saveEnabled=null;
		var tab=new J('<button id="selectionTemplatesTab" class="selectionTemplates" title="Templates" aria-label="Templates"><div class="icon copy"></div></button>');
		tab.insertAfter(editor.jMainPanel.find("button.editTilesets"));
		var panel=new J('<div id="selectionTemplatesPanel"/>');
		panel.css({position:"absolute",left:"0",right:"0",top:editor.jMainPanel.find("#mainBar").outerHeight()+"px",bottom:"0",zIndex:"40",background:"#20242b",padding:"10px",overflow:"hidden"});
		panel.hide().appendTo(editor.jMainPanel); jPanel=panel;
		tab.click(ev->{
			ev.stopPropagation();
			if(panel.is(":visible")) { panel.hide(); editor.clearSpecialTool(); }
			else { panel.show(); renderPanel(editor); }
		});
	}

	public static function updateSaveState(editor:Editor) {
		if(jPanel==null || jSave==null || !jPanel.is(":visible")) return;
		var enabled=editor.project!=null && !editor.project.isBackup() && !editor.worldMode
			&& editor.selectionTool.any() && !editor.selectionTool.isRunning();
		if(saveEnabled!=enabled) {
			saveEnabled=enabled;
			jSave.prop("disabled",!enabled);
			jSave.attr("title",enabled ? "Create template from current selection" : "Select objects in the level first");
		}
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
		jSave=new J('<button id="saveSelectionTemplate" aria-label="Create template from selection"><span class="icon save"></span></button>');
		jSave.appendTo(header);
		saveEnabled=null;
		jSave.click(ev->{ ev.stopPropagation(); editor.selectionTool.saveSelectionAsTemplate(); });
		updateSaveState(editor);
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
				empty.text("Select objects in the level, then click the save icon above. You can edit the contents and exclude layers before saving.");
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
					new ui.modal.dialog.InputDialog<String>(L.t._("Template name:"),name,"",
						v->v==null || StringTools.trim(v).length==0 ? "Enter a template name." : null,
						v->StringTools.trim(v),
						v->{ var edited=cloneJson(captured); edited.name=v; if(put(editor.project,edited)) renderPanel(editor); }
					);
				});
				var editBtn=new J('<button class="editTemplate">Edit</button>');
				editBtn.appendTo(actions);
				editBtn.click(_->new ui.modal.dialog.SelectionTemplateEditor(captured));

				var duplicateBtn = new J('<button class="transparent">Duplicate</button>');
				duplicateBtn.appendTo(actions);
				duplicateBtn.click(function(_) {
					duplicate(editor.project,templateId);
					renderPanel(editor);
				});

				var deleteBtn = new J('<button class="transparent">Delete</button>');
				deleteBtn.appendTo(actions);
				deleteBtn.click(function(_) {
					new ui.modal.dialog.Confirm(L.t._("Delete this template? Placed copies are not affected."),true,()->{
						remove(editor.project,templateId); renderPanel(editor);
					});
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
		var module:Dynamic=js.Node.require(JsTools.getAssetsDir()+"/js/selection-template-editor.js");
		tpl=module.materialize(tpl,ui.TemplateEditorBridge.catalog(tpl));
		var excluded:Array<Int>=cast tpl.excludedLayerUids;
		if(arr(tpl,"entities").length==0 && arr(tpl,"cells").length==0) { N.error("This template has no included contents."); return false; }
		for(raw in arr(tpl,"entities")) {
			var li=level.getLayerInstance(intVal(raw.layerDefUid,-1));
			var ed=project.defs.getEntityDef(intVal(raw.json.defUid,-1));
			if(li==null || li.def.type!=Entities || ed==null) { N.error("A required entity or layer definition is missing."); return false; }
			for(f in arr(raw.json,"fieldInstances")) if(ed.getFieldDef(intVal(f.defUid,-1))==null) { N.error("A template field definition is missing. Edit the template first."); return false; }
			var tx=atX+(flipX ? intVal(tpl.width)-intVal(raw.relX) : intVal(raw.relX));
			var ty=atY+(flipY ? intVal(tpl.height)-intVal(raw.relY) : intVal(raw.relY));
			if(!ed.allowOutOfBounds && !level.inBounds(tx,ty)) { N.error("Template entities would be outside the level."); return false; }
			for(ref in arr(raw,"refs")) {
				var fd=ed.getFieldDef(intVal(ref.fieldDefUid,-1));
				if(fd!=null && !fd.canBeNull) for(target in arr(ref,"values")) if(target==null) {
					N.error("A required connection is empty or targets an excluded entity. Edit the template first."); return false;
				}
			}
		}
		editor.ensureLevelTimeline(level);

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
		var placedSelection : Array<GenericLevelElement> = [];

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
			for(fi in ei.fieldInstances) if(fi.def.type==F_EntityRef)
				for(i in 0...fi.getArrayLength()) fi.parseValue(i,null);
			li.attachEntityInstanceForMove(ei);
			project.registerEntityInstance(ei);
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
			project.registerEntityInstance(ei);
			var stampTouched:Map<Int,data.inst.LayerInstance>=new Map();
			for(stamp in ei.def.tileStamps) if(excluded.indexOf(intVal(stamp.layerDefUid,-1))<0) {
				@:privateAccess if(project.forkConfig.stampIsActive(ei,stamp))
					project.forkConfig.paintStampAt(ei,stamp,ei.x,ei.y,stampTouched);
			}
			for(stampLi in stampTouched) touched.set(stampLi.iid,stampLi);
			project.forkConfig.trackEntity(ei);
			editor.ge.emit(EntityInstanceChanged(ei));

			placedSelection.push(Entity(li,ei));
			for(fi in ei.fieldInstances)
				if( fi.def.type==F_Point )
					for(i in 0...fi.getArrayLength())
						if( !fi.valueIsNull(i) )
							placedSelection.push(PointField(li,ei,fi,i));
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
					li.addGridTile(cx,cy,intVal(field(t,"tileId")),(intVal(field(t,"flips")) ^ (flipX ? 1 : 0) ^ (flipY ? 2 : 0)),stacking,false);
			}
			touched.set(li.iid,li);
			placedSelection.push(GridCell(li,cx,cy));
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

		// Hand control back to the normal multi-layer selection workflow.
		// Only elements created by this placement are selected; generated
		// entity stamp output is intentionally excluded because it follows
		// its owning entity when the selection is moved.
		editor.selectionTool.select(placedSelection);
		N.quick("Template placed and selected");
		return true;
	}
}
