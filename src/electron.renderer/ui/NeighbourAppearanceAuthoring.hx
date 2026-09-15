package ui;

import data.DataTypes;

/**
 * Adds structured authoring controls for neighbour-driven appearance rules.
 *
 * The normal appearance editor still owns sprite selection and field/value conditions. This
 * section only marks an appearance rule as being resolved from nearby IntGrid geometry.
 */
class NeighbourAppearanceAuthoring {
	static var installed = false;
	static var lastSignature : Null<String> = null;

	static var editor(get,never) : Editor;
	static inline function get_editor() return Editor.ME;
	static var project(get,never) : data.Project;
	static inline function get_project() return Editor.ME.project;

	public static function install() {
		if( installed )
			return;
		installed = true;
		js.Browser.window.setInterval(tick,150);
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

	static function removeField(o:Dynamic, field:String) {
		if( o!=null && Reflect.hasField(o,field) )
			Reflect.deleteField(o,field);
	}

	static function getPanelContent() : js.jquery.JQuery {
		return new J(".defEditor.entityDefs").last();
	}

	static function getSelectedEntity() : Null<data.def.EntityDef> {
		var panel = getPanelContent();
		if( panel.length==0 || project==null )
			return null;
		var active = panel.find(".entityList li[uid].active").first();
		if( active.length==0 )
			return null;
		var uid = Std.parseInt(active.attr("uid"));
		return M.isValidNumber(uid) ? project.defs.getEntityDef(uid) : null;
	}

	static function getIntGridLayers() : Array<data.def.LayerDef> {
		var out : Array<data.def.LayerDef> = [];
		for(ld in project.defs.layers)
			if( ld.type==IntGrid )
				out.push(ld);
		return out;
	}

	static function buildSignature(ed:data.def.EntityDef) {
		var rows : Array<Dynamic> = [];
		for(rule in ed.appearanceOverrides)
			rows.push({
				whenFieldUid: getInt(rule,"whenFieldUid"),
				whenValue: getDyn(rule,"whenValue"),
				whenNeighbour: getDyn(rule,"whenNeighbour"),
				neighbourLayerDefUid: getInt(rule,"neighbourLayerDefUid"),
				neighbourIntGridValue: getInt(rule,"neighbourIntGridValue"),
			});
		return haxe.Json.stringify({ uid:ed.uid, rows:rows });
	}

	static function saveChange() {
		if( !Editor.exists() || project==null )
			return;
		project.forkConfig.save();
		lastSignature = null;
	}

	static function addModeOptions(select:js.jquery.JQuery, selected:String) {
		var modes = [
			{ value:misc.NeighbourAppearance.FLOOR, label:"Floor (below)" },
			{ value:misc.NeighbourAppearance.CEILING, label:"Ceiling (above)" },
			{ value:misc.NeighbourAppearance.LEFT_WALL, label:"Left wall" },
			{ value:misc.NeighbourAppearance.RIGHT_WALL, label:"Right wall" },
			{ value:misc.NeighbourAppearance.BACKGROUND_WALL, label:"Background wall / overlapping IntGrid" },
			{ value:misc.NeighbourAppearance.AIR, label:"Air / no surface fallback" },
		];
		for(m in modes) {
			var option = new J('<option/>').attr("value",m.value).text(m.label);
			if( selected==m.value ) option.attr("selected","selected");
			option.appendTo(select);
		}
	}

	static function appendRuleControls(card:js.jquery.JQuery, ed:data.def.EntityDef, rule:Dynamic, idx:Int, intGridLayers:Array<data.def.LayerDef>) {
		var whenUid = getInt(rule,"whenFieldUid");
		var whenFd = whenUid==null ? null : ed.getFieldDef(whenUid);
		var modeRaw = getDyn(rule,"whenNeighbour");
		var enabled = modeRaw!=null;
		var mode = enabled ? Std.string(modeRaw) : misc.NeighbourAppearance.FLOOR;

		var title = new J('<div style="display:flex;gap:7px;align-items:center;flex-wrap:wrap;"/>').appendTo(card);
		title.append('<strong>Appearance rule '+(idx+1)+'</strong>');
		if( whenFd!=null )
			new J('<span class="help"/>').text('writes '+whenFd.identifier+' = '+Std.string(getDyn(rule,"whenValue"))).appendTo(title);
		else
			title.append('<span class="warning">Choose a normal field/value condition for this appearance rule first.</span>');

		var enableRow = new J('<label style="display:flex;align-items:center;gap:6px;margin-top:6px;"><input type="checkbox"/> Resolve this rule from nearby IntGrid</label>').appendTo(card);
		var check = enableRow.find("input");
		check.prop("checked",enabled);
		check.prop("disabled",whenFd==null || whenFd.isArray);
		check.change(_->{
			if( check.prop("checked")==true ) {
				Reflect.setField(rule,"whenNeighbour",misc.NeighbourAppearance.FLOOR);
				if( intGridLayers.length>0 )
					Reflect.setField(rule,"neighbourLayerDefUid",intGridLayers[0].uid);
			}
			else {
				removeField(rule,"whenNeighbour");
				removeField(rule,"neighbourLayerDefUid");
				removeField(rule,"neighbourIntGridValue");
			}
			saveChange();
		});

		if( !enabled )
			return;

		var body = new J('<div style="margin:7px 0 0 20px;padding:7px;border-left:2px solid rgba(255,255,255,0.12);"/>').appendTo(card);
		var modeRow = new J('<div style="display:flex;gap:6px;align-items:center;flex-wrap:wrap;"><span>Surface</span><select></select></div>').appendTo(body);
		var modeSelect = modeRow.find("select");
		addModeOptions(modeSelect,mode);
		modeSelect.change(_->{
			var next = Std.string(modeSelect.val());
			Reflect.setField(rule,"whenNeighbour",next);
			if( next==misc.NeighbourAppearance.AIR ) {
				removeField(rule,"neighbourLayerDefUid");
				removeField(rule,"neighbourIntGridValue");
			}
			else if( getInt(rule,"neighbourLayerDefUid")==null && intGridLayers.length>0 )
				Reflect.setField(rule,"neighbourLayerDefUid",intGridLayers[0].uid);
			saveChange();
		});

		if( mode==misc.NeighbourAppearance.AIR ) {
			body.append('<p class="help">Fallback used when no Floor/Ceiling/Left/Right/Background rule for the same field matches. The entity is not moved or snapped.</p>');
			return;
		}

		if( intGridLayers.length==0 ) {
			body.append('<p class="warning">This project has no IntGrid layer. Create one before using neighbour rules.</p>');
			return;
		}

		var selectedLayerUid = getInt(rule,"neighbourLayerDefUid",intGridLayers[0].uid);
		var layerRow = new J('<div style="display:flex;gap:6px;align-items:center;flex-wrap:wrap;margin-top:6px;"><span>IntGrid layer</span><select></select></div>').appendTo(body);
		var layerSelect = layerRow.find("select");
		for(ld in intGridLayers) {
			var option = new J('<option/>').attr("value",ld.uid).text(ld.identifier);
			if( ld.uid==selectedLayerUid ) option.attr("selected","selected");
			option.appendTo(layerSelect);
		}
		layerSelect.change(_->{
			var uid = Std.parseInt(Std.string(layerSelect.val()));
			if( M.isValidNumber(uid) ) {
				Reflect.setField(rule,"neighbourLayerDefUid",uid);
				removeField(rule,"neighbourIntGridValue");
				saveChange();
			}
		});

		var selectedLd = project.defs.getLayerDef(selectedLayerUid);
		if( selectedLd!=null && selectedLd.type==IntGrid ) {
			var valueRow = new J('<div style="display:flex;gap:6px;align-items:center;flex-wrap:wrap;margin-top:6px;"><span>Required value</span><select></select></div>').appendTo(body);
			var valueSelect = valueRow.find("select");
			var any = new J('<option value="">Any non-empty IntGrid value</option>').appendTo(valueSelect);
			var selectedValue = getInt(rule,"neighbourIntGridValue");
			if( selectedValue==null ) any.attr("selected","selected");
			for(iv in selectedLd.getAllIntGridValues()) {
				var label = iv.identifier==null || iv.identifier=="" ? Std.string(iv.value) : iv.identifier+' ('+iv.value+')';
				var option = new J('<option/>').attr("value",iv.value).text(label);
				if( selectedValue==iv.value ) option.attr("selected","selected");
				option.appendTo(valueSelect);
			}
			valueSelect.change(_->{
				var raw = Std.string(valueSelect.val());
				if( raw=="" )
					removeField(rule,"neighbourIntGridValue");
				else {
					var value = Std.parseInt(raw);
					if( M.isValidNumber(value) )
						Reflect.setField(rule,"neighbourIntGridValue",value);
				}
				saveChange();
			});
		}
	}

	static function appendSection(root:js.jquery.JQuery, ed:data.def.EntityDef) {
		root.find(".neighbourAppearanceSection").remove();
		var section = new J('<section class="neighbourAppearanceSection" style="border-top:1px solid rgba(255,255,255,0.16);padding:10px 0;"/>').appendTo(root);
		section.append('<h3 style="margin:0 0 4px 0;">Auto orientation from IntGrid neighbours</h3>');
		section.append('<p class="help">Attach an existing appearance rule to Floor, Ceiling, Left wall, Right wall, Background wall, or Air. Smartive only updates the rule field value; it never snaps or moves the entity. Priority is Floor → Ceiling → Left → Right → Background → Air.</p>');

		if( ed.appearanceOverrides.length==0 ) {
			section.append('<p class="help">Create appearance rules above first, one for each sprite/orientation you need.</p>');
			return;
		}

		var intGridLayers = getIntGridLayers();
		for(i in 0...ed.appearanceOverrides.length) {
			var card = new J('<div style="padding:8px;margin:7px 0;border:1px solid rgba(255,255,255,0.12);border-radius:3px;"/>').appendTo(section);
			appendRuleControls(card,ed,ed.appearanceOverrides[i],i,intGridLayers);
		}
	}

	static function tick() {
		if( !Editor.exists() || project==null ) {
			lastSignature = null;
			return;
		}
		var panel = getPanelContent();
		if( panel.length==0 ) {
			lastSignature = null;
			return;
		}
		var root = panel.find(".forkAuthoringStructuredEditor");
		if( root.length==0 || !root.is(":visible") )
			return;
		var ed = getSelectedEntity();
		if( ed==null )
			return;
		var signature = buildSignature(ed);
		if( signature!=lastSignature || root.find(".neighbourAppearanceSection").length==0 ) {
			lastSignature = signature;
			appendSection(root,ed);
		}
	}
}
