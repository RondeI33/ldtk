package ui;

import data.DataTypes;

/**
 * Intuitive authoring UI for Smartive automatic neighbour-based entity appearance.
 *
 * This deliberately builds on the existing appearanceOverrides feature. Each generated
 * rule is still a normal field-conditioned appearance rule, with a small `smartiveNeighbour`
 * metadata object in the fork sidecar. No raw JSON editing is required.
 */
class NeighbourAppearanceAuthoring {
	static var installed = false;
	static var lastSignature : Null<String> = null;
	static inline var ROOT_CLASS = "smartiveNeighbourAppearance";

	static var editor(get,never) : Editor;
	static inline function get_editor() return Editor.ME;
	static var project(get,never) : data.Project;
	static inline function get_project() return Editor.ME.project;

	static var probes = [
		{ id:misc.NeighbourAppearanceRuntime.BACKGROUND, label:"Background wall / floating" },
		{ id:misc.NeighbourAppearanceRuntime.LEFT, label:"Left wall" },
		{ id:misc.NeighbourAppearanceRuntime.RIGHT, label:"Right wall" },
		{ id:misc.NeighbourAppearanceRuntime.CEILING, label:"Ceiling" },
		{ id:misc.NeighbourAppearanceRuntime.FLOOR, label:"Floor" },
	];

	public static function install() {
		if( installed )
			return;
		installed = true;
		js.Browser.window.setInterval(tick, 170);
	}

	static inline function getDyn(o:Dynamic, field:String) : Dynamic {
		return o==null ? null : Reflect.field(o,field);
	}

	static function getInt(o:Dynamic, field:String, ?fallback:Null<Int>) : Null<Int> {
		var raw = getDyn(o,field);
		if( raw==null )
			return fallback;
		var out = Std.parseInt(Std.string(raw));
		return M.isValidNumber(out) ? out : fallback;
	}

	static function getArray(o:Dynamic, field:String) : Array<Dynamic> {
		var raw = getDyn(o,field);
		return raw==null || !Std.isOfType(raw,Array) ? [] : cast raw;
	}

	static function cloneDynamic(v:Dynamic) : Dynamic {
		return v==null ? null : haxe.Json.parse(haxe.Json.stringify(v));
	}

	static function getPanel() : js.jquery.JQuery {
		return new J(".defEditor.entityDefs").last();
	}

	static function getSelectedEntity() : Null<data.def.EntityDef> {
		if( !Editor.exists() || project==null )
			return null;
		var panel = getPanel();
		if( panel.length==0 )
			return null;
		var active = panel.find(".entityList li[uid].active").first();
		if( active.length==0 )
			return null;
		var uid = Std.parseInt(active.attr("uid"));
		return M.isValidNumber(uid) ? project.defs.getEntityDef(uid) : null;
	}

	static function getIntGridDefs() : Array<data.def.LayerDef> {
		var out : Array<data.def.LayerDef> = [];
		for(ld in project.defs.layers)
			if( ld.type==IntGrid )
				out.push(ld);
		return out;
	}

	static function isManaged(rule:Dynamic) {
		return getDyn(rule,misc.NeighbourAppearanceRuntime.META_FIELD)!=null;
	}

	static function getManagedRules(ed:data.def.EntityDef) : Array<Dynamic> {
		var out : Array<Dynamic> = [];
		for(rule in ed.appearanceOverrides)
			if( isManaged(rule) )
				out.push(rule);
		return out;
	}

	static function findRule(ed:data.def.EntityDef, probe:String) : Dynamic {
		for(rule in ed.appearanceOverrides) {
			var cfg = getDyn(rule,misc.NeighbourAppearanceRuntime.META_FIELD);
			if( cfg!=null && Std.string(getDyn(cfg,"probe"))==probe )
				return rule;
		}
		return null;
	}

	static function getSharedConfig(ed:data.def.EntityDef) : Dynamic {
		var rules = getManagedRules(ed);
		return rules.length==0 ? null : getDyn(rules[0],misc.NeighbourAppearanceRuntime.META_FIELD);
	}

	static function buildSignature(ed:data.def.EntityDef) {
		var layers : Array<Dynamic> = [];
		for(ld in getIntGridDefs())
			layers.push({ uid:ld.uid, identifier:ld.identifier, values:ld.getAllIntGridValues() });
		return haxe.Json.stringify({
			entityUid: ed.uid,
			rules: getManagedRules(ed),
			layers: layers,
			tilesets: project.defs.tilesets.map(td->{ uid:td.uid, identifier:td.identifier, grid:td.tileGridSize }),
		});
	}

	static function saveSidecar() {
		project.forkConfig.save();
		lastSignature = null;
		editor.ge.emit(EntityDefChanged);
	}

	static function markProjectDefinitionChanged(?fd:data.def.FieldDef, enumAdded=false) {
		project.tidy();
		editor.needSaving = true;
		if( enumAdded )
			editor.ge.emit(EnumDefAdded);
		if( fd!=null )
			editor.ge.emit(FieldDefAdded(fd));
		editor.ge.emit(EntityDefChanged);
		lastSignature = null;
	}

	static function ensureSurfaceEnum() : { en:data.def.EnumDef, added:Bool } {
		var expected = probes.map(p->p.id);
		for(en in project.defs.enums) {
			if( en.identifier=="SmartiveSurface" || en.identifier.indexOf("SmartiveSurface_")==0 ) {
				var compatible = true;
				for(v in expected)
					if( !en.hasValue(v) ) {
						compatible = false;
						break;
					}
				if( compatible )
					return { en:en, added:false };
			}
		}

		var en = project.defs.createEnumDef();
		var base = "SmartiveSurface";
		var id = base;
		var idx = 2;
		while( !project.defs.isEnumIdentifierUnique(id,en) )
			id = base+"_"+(idx++);
		en.identifier = id;
		for(v in expected)
			en.addValue(v);
		return { en:en, added:true };
	}

	static function ensureSurfaceField(ed:data.def.EntityDef) : { fd:data.def.FieldDef, changedProject:Bool, enumAdded:Bool } {
		var rules = getManagedRules(ed);
		if( rules.length>0 ) {
			var uid = getInt(rules[0],"whenFieldUid");
			var existing = uid==null ? null : ed.getFieldDef(uid);
			if( existing!=null )
				return { fd:existing, changedProject:false, enumAdded:false };
		}

		for(fd in ed.fieldDefs)
			if( fd.identifier=="SmartiveSurface" || fd.identifier.indexOf("SmartiveSurface_")==0 )
				switch fd.type {
					case F_Enum(enumUid):
						var en = project.defs.getEnumDef(enumUid);
						if( en!=null ) {
							var ok = true;
							for(p in probes)
								if( !en.hasValue(p.id) ) { ok=false; break; }
							if( ok )
								return { fd:fd, changedProject:false, enumAdded:false };
						}
					case _:
				}

		var enumResult = ensureSurfaceEnum();
		var fd = ed.createFieldDef(project,F_Enum(enumResult.en.uid),"SmartiveSurface",false);
		fd.doc = "Managed by Smartive auto surface appearance. Exported as a normal LDtk field.";
		return { fd:fd, changedProject:true, enumAdded:enumResult.added };
	}

	static function ensureRules(ed:data.def.EntityDef, fd:data.def.FieldDef, ld:data.def.LayerDef) {
		var oldRules = getManagedRules(ed);
		var solids : Array<Dynamic> = oldRules.length==0 ? [] : getArray(getDyn(oldRules[0],misc.NeighbourAppearanceRuntime.META_FIELD),"solidValues").copy();
		for(p in probes) {
			var rule = findRule(ed,p.id);
			if( rule==null ) {
				rule = {
					whenFieldUid: fd.uid,
					whenValue: p.id,
				};
				var fallbackTile = ed.getDefaultTile();
				if( fallbackTile!=null )
					Reflect.setField(rule,"tileRect",cloneDynamic(fallbackTile));
				ed.appearanceOverrides.push(rule);
			}
			Reflect.setField(rule,"whenFieldUid",fd.uid);
			Reflect.setField(rule,"whenValue",p.id);
			Reflect.setField(rule,misc.NeighbourAppearanceRuntime.META_FIELD,{
				probe: p.id,
				layerDefUid: ld.uid,
				layerIdentifier: ld.identifier,
				solidValues: solids.copy(),
			});
		}
	}

	static function enable(ed:data.def.EntityDef) {
		var layers = getIntGridDefs();
		if( layers.length==0 ) {
			N.error("Create an IntGrid layer first. Auto surface appearance needs an IntGrid layer to detect walls, floor and ceiling.");
			return;
		}
		var fieldResult = ensureSurfaceField(ed);
		ensureRules(ed,fieldResult.fd,layers[0]);
		if( fieldResult.changedProject )
			markProjectDefinitionChanged(fieldResult.fd,fieldResult.enumAdded);
		saveSidecar();
	}

	static function disable(ed:data.def.EntityDef) {
		var i = ed.appearanceOverrides.length-1;
		while( i>=0 ) {
			if( isManaged(ed.appearanceOverrides[i]) )
				ed.appearanceOverrides.splice(i,1);
			i--;
		}
		// Keep the generated normal LDtk field: gameplay/import code may already use it.
		saveSidecar();
	}

	static function rectFromTileId(td:data.def.TilesetDef, tileId:Int) : ldtk.Json.TilesetRect {
		return {
			tilesetUid: td.uid,
			x: td.getTileSourceX(tileId),
			y: td.getTileSourceY(tileId),
			w: td.tileGridSize,
			h: td.tileGridSize,
		};
	}

	static function setLayerForRules(ed:data.def.EntityDef, ld:data.def.LayerDef) {
		for(rule in getManagedRules(ed)) {
			var cfg = getDyn(rule,misc.NeighbourAppearanceRuntime.META_FIELD);
			Reflect.setField(cfg,"layerDefUid",ld.uid);
			Reflect.setField(cfg,"layerIdentifier",ld.identifier);
		}
		saveSidecar();
	}

	static function setSolidValues(ed:data.def.EntityDef, values:Array<Dynamic>) {
		for(rule in getManagedRules(ed)) {
			var cfg = getDyn(rule,misc.NeighbourAppearanceRuntime.META_FIELD);
			Reflect.setField(cfg,"solidValues",values.copy());
		}
		saveSidecar();
	}

	static function appendVariantEditor(jParent:js.jquery.JQuery, ed:data.def.EntityDef, probe:{id:String,label:String}) {
		var rule = findRule(ed,probe.id);
		if( rule==null )
			return;
		var card = new J('<div style="padding:8px;margin:7px 0;border:1px solid rgba(255,255,255,0.12);border-radius:3px;"/>').appendTo(jParent);
		card.append('<strong>'+probe.label+'</strong>');
		var rect : Null<ldtk.Json.TilesetRect> = cast getDyn(rule,"tileRect");
		var td = rect==null || rect.tilesetUid==null ? null : project.defs.getTilesetDef(rect.tilesetUid);
		if( td==null && project.defs.tilesets.length>0 )
			td = project.defs.tilesets[0];
		if( td==null ) {
			card.append('<p class="warning">Add a tileset before choosing this sprite variant.</p>');
			return;
		}

		var row = new J('<div style="display:flex;gap:6px;align-items:center;flex-wrap:wrap;margin-top:6px;"><span>Tileset</span><select></select></div>').appendTo(card);
		var select = row.find("select");
		for(candidate in project.defs.tilesets) {
			var opt = new J('<option/>').attr("value",candidate.uid).text(candidate.identifier);
			if( candidate.uid==td.uid ) opt.attr("selected","selected");
			opt.appendTo(select);
		}
		select.change(_->{
			var uid = Std.parseInt(Std.string(select.val()));
			var next = M.isValidNumber(uid) ? project.defs.getTilesetDef(uid) : null;
			if( next!=null ) {
				Reflect.setField(rule,"tileRect",rectFromTileId(next,0));
				saveSidecar();
			}
		});

		if( rect==null )
			card.append('<p class="help">Currently uses the entity default sprite. Pick a tile below to make this variant unique.</p>');
		var seed = rect!=null && rect.tilesetUid==td.uid ? rect : rectFromTileId(td,0);
		var picker = JsTools.createTileRectPicker(td.uid,seed,r->{
			if( r!=null ) {
				Reflect.setField(rule,"tileRect",r);
				saveSidecar();
			}
		});
		picker.appendTo(card);
		var clear = new J('<button class="small" style="margin-top:5px;">Use default sprite</button>').appendTo(card);
		clear.prop("disabled",rect==null);
		clear.click(_->{
			if( Reflect.hasField(rule,"tileRect") )
				Reflect.deleteField(rule,"tileRect");
			saveSidecar();
		});
	}

	static function build(jRoot:js.jquery.JQuery, ed:data.def.EntityDef) {
		var old = jRoot.find("."+ROOT_CLASS);
		if( old.length>0 )
			old.remove();

		var section = new J('<section class="'+ROOT_CLASS+'" style="border-top:1px solid rgba(255,255,255,0.16);padding:10px 0;"/>');
		var firstSection = jRoot.find("section").first();
		if( firstSection.length>0 ) section.insertBefore(firstSection); else section.appendTo(jRoot);
		section.append('<h3 style="margin:0 0 4px 0;">Auto surface appearance</h3>');
		section.append('<p class="help">Automatically selects a sprite variant from nearby IntGrid geometry. It <strong>never snaps or moves the entity</strong>: away from side/floor/ceiling contact it stays exactly where placed and uses the background/floating variant.</p>');

		var rules = getManagedRules(ed);
		if( rules.length==0 ) {
			var layers = getIntGridDefs();
			if( layers.length==0 )
				section.append('<p class="warning">No IntGrid layer exists in this project yet.</p>');
			var enableButton = new J('<button class="create">Enable auto surface appearance</button>').appendTo(section);
			enableButton.prop("disabled",layers.length==0);
			enableButton.click(_->enable(ed));
			return;
		}

		var cfg = getSharedConfig(ed);
		var fieldUid = getInt(rules[0],"whenFieldUid");
		var fd = fieldUid==null ? null : ed.getFieldDef(fieldUid);
		if( fd!=null )
			section.append('<p class="help">Resolved surface is also exported in normal LDtk field <code>'+fd.identifier+'</code>.</p>');

		var layers = getIntGridDefs();
		var layerUid = getInt(cfg,"layerDefUid");
		var controls = new J('<div style="display:flex;gap:10px;align-items:flex-start;flex-wrap:wrap;margin:8px 0;"/>').appendTo(section);
		var layerWrap = new J('<label>Geometry IntGrid<br/><select></select></label>').appendTo(controls);
		var layerSelect = layerWrap.find("select");
		for(ld in layers) {
			var opt = new J('<option/>').attr("value",ld.uid).text(ld.identifier);
			if( ld.uid==layerUid ) opt.attr("selected","selected");
			opt.appendTo(layerSelect);
		}
		layerSelect.change(_->{
			var uid = Std.parseInt(Std.string(layerSelect.val()));
			var ld = M.isValidNumber(uid) ? project.defs.getLayerDef(null,uid) : null;
			if( ld!=null && ld.type==IntGrid )
				setLayerForRules(ed,ld);
		});

		var selectedLd = layerUid==null ? null : project.defs.getLayerDef(null,layerUid);
		if( selectedLd==null && layers.length>0 ) selectedLd = layers[0];
		if( selectedLd!=null ) {
			var solids = getArray(cfg,"solidValues");
			var solidWrap = new J('<label>Solid IntGrid values <span class="help">(none = any non-zero)</span><br/><select multiple size="5" style="min-width:180px;"></select></label>').appendTo(controls);
			var solidSelect = solidWrap.find("select");
			for(iv in selectedLd.getAllIntGridValues()) {
				var opt = new J('<option/>').attr("value",iv.value).text(selectedLd.getIntGridValueDisplayName(iv.value));
				for(v in solids)
					if( Std.string(v)==Std.string(iv.value) ) { opt.attr("selected","selected"); break; }
				opt.appendTo(solidSelect);
			}
			solidSelect.change(_->{
				var raw : Dynamic = solidSelect.val();
				var out : Array<Dynamic> = [];
				if( raw!=null ) {
					var values : Array<Dynamic> = Std.isOfType(raw,Array) ? cast raw : [raw];
					for(v in values) {
						var parsed = Std.parseInt(Std.string(v));
						if( M.isValidNumber(parsed) ) out.push(parsed);
					}
				}
				setSolidValues(ed,out);
			});
		}

		section.append('<p class="help">Detection uses the strongest contact edge. Exact ties resolve as Floor → Ceiling → Left wall → Right wall. With no edge contact, Background wall / floating is used.</p>');
		var variants = new J('<div/>').appendTo(section);
		for(p in probes)
			appendVariantEditor(variants,ed,p);

		new J('<button class="small danger" style="margin-top:8px;">Disable auto surface appearance</button>').appendTo(section).click(_->disable(ed));
		JsTools.parseComponents(section);
	}

	static function tick() {
		if( !Editor.exists() || project==null ) {
			lastSignature = null;
			return;
		}
		var panel = getPanel();
		if( panel.length==0 ) {
			lastSignature = null;
			return;
		}
		var root = panel.find(".forkAuthoringStructuredEditor");
		if( root.length==0 )
			return;
		var ed = getSelectedEntity();
		if( ed==null )
			return;
		var signature = buildSignature(ed);
		if( signature!=lastSignature || root.find("."+ROOT_CLASS).length==0 ) {
			lastSignature = signature;
			build(root,ed);
		}
	}
}
