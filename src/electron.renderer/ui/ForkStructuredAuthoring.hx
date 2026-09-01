package ui;

import data.DataTypes;

/**
 * Structured authoring UI for Smartive fork-only entity features.
 *
 * The persisted format remains `<project>.ldtk-fork.json`; this class only replaces the
 * default authoring experience. The original JSON editor stays available as an advanced fallback.
 */
class ForkStructuredAuthoring {
	static var installed = false;
	static var showRawForkJson = false;
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

	static function getPanelContent() : js.jquery.JQuery {
		return new J(".defEditor.entityDefs").last();
	}

	static function buildSignature(ed:data.def.EntityDef) {
		var fields : Array<Dynamic> = [];
		for(fd in ed.fieldDefs)
			fields.push({
				uid: fd.uid,
				identifier: fd.identifier,
				type: Std.string(fd.type),
				isArray: fd.isArray,
				visibleWhenFieldUid: fd.visibleWhenFieldUid,
				visibleWhenValues: fd.visibleWhenValues,
				enumValueFilter: fd.enumValueFilter,
			});
		return haxe.Json.stringify({
			uid: ed.uid,
			appearanceOverrides: ed.appearanceOverrides,
			tileStamps: ed.tileStamps,
			fields: fields,
		});
	}

	static function tick() {
		if( !Editor.exists() ) {
			lastSignature = null;
			return;
		}
		var panel = getPanelContent();
		if( panel.length==0 || project==null ) {
			lastSignature = null;
			return;
		}

		var rawRoot = panel.find(".forkAuthoringEditor");
		if( rawRoot.length==0 )
			return;
		if( showRawForkJson ) rawRoot.show(); else rawRoot.hide();

		var ed = getSelectedEntity();
		if( ed==null )
			return;
		var sig = buildSignature(ed);
		if( sig!=lastSignature || panel.find(".forkAuthoringStructuredEditor").length==0 ) {
			lastSignature = sig;
			updateStructuredForkAuthoring();
		}
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

	static function getFloat(o:Dynamic, field:String, ?fallback:Null<Float>) : Null<Float> {
		var raw = getDyn(o,field);
		if( raw==null )
			return fallback;
		var out = Std.parseFloat(Std.string(raw));
		return M.isValidNumber(out) ? out : fallback;
	}

	static inline function sameValue(a:Dynamic,b:Dynamic) {
		return a==null || b==null ? a==b : Std.string(a)==Std.string(b);
	}

	static function getSelectedEntity() : Null<data.def.EntityDef> {
		var panel = getPanelContent();
		if( panel.length==0 )
			return null;
		var jActive = panel.find(".entityList li[uid].active").first();
		if( jActive.length==0 )
			return null;
		var uid = Std.parseInt(jActive.attr("uid"));
		return M.isValidNumber(uid) ? project.defs.getEntityDef(uid) : null;
	}

	static function saveForkChange(?rebuild=true) {
		if( !Editor.exists() || project==null )
			return;
		project.forkConfig.save();
		lastSignature = null;
		editor.ge.emit(EntityDefChanged);
	}

	static function removeField(o:Dynamic, field:String) {
		if( o!=null && Reflect.hasField(o,field) )
			Reflect.deleteField(o,field);
	}

	static function canConditionOn(fd:data.def.FieldDef) {
		if( fd==null || fd.isArray )
			return false;
		return switch fd.type {
			case F_Int, F_Float, F_String, F_Text, F_Bool, F_Color, F_Path, F_Enum(_): true;
			case _: false;
		}
	}

	static function getFirstConditionField(ed:data.def.EntityDef, ?excludeUid:Null<Int>) : Null<data.def.FieldDef> {
		for(fd in ed.fieldDefs)
			if( fd.uid!=excludeUid && canConditionOn(fd) )
				return fd;
		return null;
	}

	static function defaultConditionValue(fd:data.def.FieldDef) : Dynamic {
		if( fd==null )
			return null;
		return switch fd.type {
			case F_Int: 0;
			case F_Float: 0.0;
			case F_Bool: false;
			case F_Enum(enumUid):
				var en = project.defs.getEnumDef(enumUid);
				en!=null && en.values.length>0 ? en.values[0].id : "";
			case _: "";
		}
	}

	static function appendConditionFieldSelect(jParent:js.jquery.JQuery, ed:data.def.EntityDef, selected:Null<Int>, excludeUid:Null<Int>, cb:Null<Int>->Void, ?noneLabel="Always") {
		var jSelect = new J('<select class="forkConditionField"/>').appendTo(jParent);
		new J('<option value=""/>').text(noneLabel).appendTo(jSelect);
		for(fd in ed.fieldDefs)
			if( fd.uid!=excludeUid && canConditionOn(fd) ) {
				var jOpt = new J('<option/>');
				jOpt.attr("value",fd.uid);
				jOpt.text(fd.identifier);
				if( selected==fd.uid )
					jOpt.attr("selected","selected");
				jOpt.appendTo(jSelect);
			}
		jSelect.change(_->{
			var raw = Std.string(jSelect.val());
			var uid = raw=="" ? null : Std.parseInt(raw);
			cb(uid!=null && M.isValidNumber(uid) ? uid : null);
		});
		return jSelect;
	}

	static function appendValueEditor(jParent:js.jquery.JQuery, fd:data.def.FieldDef, value:Dynamic, cb:Dynamic->Void) : js.jquery.JQuery {
		if( fd==null ) {
			var j = new J('<input type="text" disabled placeholder="Choose a condition field"/>').appendTo(jParent);
			return j;
		}

		switch fd.type {
			case F_Bool:
				var j = new J('<select class="forkValue"/>').appendTo(jParent);
				new J('<option value="false">false</option>').appendTo(j);
				new J('<option value="true">true</option>').appendTo(j);
				j.val(value==true || Std.string(value)=="true" ? "true" : "false");
				j.change(_->cb(Std.string(j.val())=="true"));
				return j;

			case F_Enum(enumUid):
				var j = new J('<select class="forkValue"/>').appendTo(jParent);
				var en = project.defs.getEnumDef(enumUid);
				if( en!=null )
					for(ev in en.values) {
						var opt = new J('<option/>').attr("value",ev.id).text(ev.id);
						if( sameValue(value,ev.id) )
							opt.attr("selected","selected");
						opt.appendTo(j);
					}
				j.change(_->cb(Std.string(j.val())));
				return j;

			case F_Int:
				var j = new J('<input class="forkValue" type="number" step="1"/>').appendTo(jParent);
				j.val(value==null ? 0 : value);
				j.change(_->{
					var v = Std.parseInt(Std.string(j.val()));
					if( M.isValidNumber(v) ) cb(v);
				});
				return j;

			case F_Float:
				var j = new J('<input class="forkValue" type="number" step="any"/>').appendTo(jParent);
				j.val(value==null ? 0 : value);
				j.change(_->{
					var v = Std.parseFloat(Std.string(j.val()));
					if( M.isValidNumber(v) ) cb(v);
				});
				return j;

			case F_Color:
				var j = new J('<input class="forkValue" type="color"/>').appendTo(jParent);
				var raw = value==null ? "#ffffff" : Std.string(value);
				if( raw.charAt(0)!="#" ) raw = "#"+raw;
				j.val(raw);
				j.change(_->cb(Std.string(j.val())));
				return j;

			case _:
				var j = new J('<input class="forkValue" type="text"/>').appendTo(jParent);
				j.val(value==null ? "" : Std.string(value));
				j.change(_->cb(Std.string(j.val())));
				return j;
		}
	}

	static function appendOptionalInt(jParent:js.jquery.JQuery, label:String, o:Dynamic, field:String, rebuild=false) {
		var j = new J('<label style="display:flex;gap:5px;align-items:center;">'+label+' <input type="number" style="width:82px" placeholder="default"/></label>').appendTo(jParent);
		var input = j.find("input");
		var current = getInt(o,field);
		input.val(current==null ? "" : current);
		input.change(_->{
			var raw = Std.string(input.val());
			if( raw=="" ) removeField(o,field);
			else {
				var v = Std.parseInt(raw);
				if( M.isValidNumber(v) ) Reflect.setField(o,field,v);
			}
			saveForkChange(rebuild);
		});
	}

	static function appendOptionalFloat(jParent:js.jquery.JQuery, label:String, o:Dynamic, field:String, rebuild=false) {
		var j = new J('<label style="display:flex;gap:5px;align-items:center;">'+label+' <input type="number" step="any" style="width:82px" placeholder="default"/></label>').appendTo(jParent);
		var input = j.find("input");
		var current = getFloat(o,field);
		input.val(current==null ? "" : current);
		input.change(_->{
			var raw = Std.string(input.val());
			if( raw=="" ) removeField(o,field);
			else {
				var v = Std.parseFloat(raw);
				if( M.isValidNumber(v) ) Reflect.setField(o,field,v);
			}
			saveForkChange(rebuild);
		});
	}

	static function tileIdFromRect(td:data.def.TilesetDef, r:ldtk.Json.TilesetRect) {
		var cx = Std.int((r.x-td.padding)/(td.tileGridSize+td.spacing));
		var cy = Std.int((r.y-td.padding)/(td.tileGridSize+td.spacing));
		return cx + cy*td.cWid;
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

	static function appendAppearanceSection(jRoot:js.jquery.JQuery, ed:data.def.EntityDef) {
		var jSection = new J('<section style="border-top:1px solid rgba(255,255,255,0.16);padding:10px 0;"/>').appendTo(jRoot);
		jSection.append('<h3 style="margin:0 0 4px 0;">Sprite / appearance overrides</h3>');
		jSection.append('<p class="help">Change the entity visual when one of its fields has a specific value. You can replace the sprite and optionally override size, pivot, or color.</p>');

		for(i in 0...ed.appearanceOverrides.length) {
			final idx = i;
			var rule = ed.appearanceOverrides[i];
			var jCard = new J('<div style="padding:8px;margin:7px 0;border:1px solid rgba(255,255,255,0.12);border-radius:3px;"/>').appendTo(jSection);
			var top = new J('<div style="display:flex;align-items:center;justify-content:space-between;gap:8px;"/>').appendTo(jCard);
			top.append('<strong>Appearance rule '+(i+1)+'</strong>');
			new J('<button class="small">Remove</button>').appendTo(top).click(_->{
				ed.appearanceOverrides.splice(idx,1);
				saveForkChange(true);
			});

			var cond = new J('<div style="display:flex;gap:6px;align-items:center;flex-wrap:wrap;margin-top:6px;"><span>When</span></div>').appendTo(jCard);
			var whenUid = getInt(rule,"whenFieldUid");
			appendConditionFieldSelect(cond,ed,whenUid,null,uid->{
				if( uid==null ) {
					removeField(rule,"whenFieldUid");
					removeField(rule,"whenValue");
				}
				else {
					Reflect.setField(rule,"whenFieldUid",uid);
					Reflect.setField(rule,"whenValue",defaultConditionValue(ed.getFieldDef(uid)));
				}
				saveForkChange(true);
			});
			if( whenUid!=null ) {
				cond.append('<span>is</span>');
				appendValueEditor(cond,ed.getFieldDef(whenUid),getDyn(rule,"whenValue"),v->{
					Reflect.setField(rule,"whenValue",v);
					saveForkChange(false);
				});
			}

			var visual = new J('<div style="margin-top:8px;"/>').appendTo(jCard);
			var rect : Null<ldtk.Json.TilesetRect> = cast getDyn(rule,"tileRect");
			var useTile = rect!=null;
			var useRow = new J('<label style="display:flex;align-items:center;gap:6px;"><input type="checkbox"/> Replace sprite tile</label>').appendTo(visual);
			var useCheck = useRow.find("input");
			useCheck.prop("checked",useTile);
			useCheck.change(_->{
				if( useCheck.prop("checked")==true ) {
					var td = project.defs.tilesets.length>0 ? project.defs.tilesets[0] : null;
					if( td!=null ) Reflect.setField(rule,"tileRect",rectFromTileId(td,0));
				}
				else
					removeField(rule,"tileRect");
				saveForkChange(true);
			});

			if( useTile ) {
				var tileWrap = new J('<div style="margin:6px 0 0 20px;"/>').appendTo(visual);
				var tdUid = rect.tilesetUid;
				var td = project.defs.getTilesetDef(tdUid);
				var selectRow = new J('<div style="display:flex;gap:6px;align-items:center;margin-bottom:5px;"><span>Tileset</span><select></select></div>').appendTo(tileWrap);
				var select = selectRow.find("select");
				for(candidate in project.defs.tilesets) {
					var opt = new J('<option/>').attr("value",candidate.uid).text(candidate.identifier);
					if( candidate.uid==tdUid ) opt.attr("selected","selected");
					opt.appendTo(select);
				}
				select.change(_->{
					var uid = Std.parseInt(Std.string(select.val()));
					var next = M.isValidNumber(uid) ? project.defs.getTilesetDef(uid) : null;
					if( next!=null ) {
						Reflect.setField(rule,"tileRect",rectFromTileId(next,0));
						saveForkChange(true);
					}
				});
				if( td!=null ) {
					var picker = JsTools.createTileRectPicker(td.uid,rect,r->{
						if( r!=null ) {
							Reflect.setField(rule,"tileRect",r);
							saveForkChange(false);
						}
					});
					picker.appendTo(tileWrap);
				}
			}

			var overrides = new J('<div style="display:flex;gap:8px;flex-wrap:wrap;margin-top:8px;"/>').appendTo(jCard);
			appendOptionalInt(overrides,"Width",rule,"width");
			appendOptionalInt(overrides,"Height",rule,"height");
			appendOptionalFloat(overrides,"Pivot X",rule,"pivotX");
			appendOptionalFloat(overrides,"Pivot Y",rule,"pivotY");

			var colorRow = new J('<div style="display:flex;gap:6px;align-items:center;margin-top:7px;"><label><input class="useColor" type="checkbox"/> Override color</label><input class="color" type="color"/></div>').appendTo(jCard);
			var rawColor = getDyn(rule,"color");
			var colorCheck = colorRow.find(".useColor");
			var colorInput = colorRow.find(".color");
			colorCheck.prop("checked",rawColor!=null);
			var colorHex = rawColor==null ? C.intToHex(ed.color) : Type.typeof(rawColor)==TInt ? C.intToHex(cast rawColor) : Std.string(rawColor);
			if( colorHex.charAt(0)!="#" ) colorHex = "#"+colorHex;
			colorInput.val(colorHex);
			colorInput.prop("disabled",rawColor==null);
			colorCheck.change(_->{
				if( colorCheck.prop("checked")==true )
					Reflect.setField(rule,"color",Std.string(colorInput.val()));
				else
					removeField(rule,"color");
				saveForkChange(true);
			});
			colorInput.change(_->{
				Reflect.setField(rule,"color",Std.string(colorInput.val()));
				saveForkChange(false);
			});
		}

		new J('<button class="create">+ Appearance rule</button>').appendTo(jSection).click(_->{
			var rule : Dynamic = {};
			var cond = getFirstConditionField(ed);
			if( cond!=null ) {
				Reflect.setField(rule,"whenFieldUid",cond.uid);
				Reflect.setField(rule,"whenValue",defaultConditionValue(cond));
			}
			ed.appearanceOverrides.push(rule);
			saveForkChange(true);
		});
	}

	static function getStampLayers() : Array<data.def.LayerDef> {
		var out : Array<data.def.LayerDef> = [];
		for(ld in project.defs.layers)
			if( ld.type==Tiles && ld.tilesetDefUid!=null )
				out.push(ld);
		return out;
	}

	static function appendStampSection(jRoot:js.jquery.JQuery, ed:data.def.EntityDef) {
		var jSection = new J('<section style="border-top:1px solid rgba(255,255,255,0.16);padding:10px 0;"/>').appendTo(jRoot);
		jSection.append('<h3 style="margin:0 0 4px 0;">Extra tile placement / drawing</h3>');
		jSection.append('<p class="help">Stamp one or more tiles around this entity, on a chosen tile layer, optionally only for a field value.</p>');
		var layers = getStampLayers();
		if( layers.length==0 )
			jSection.append('<p class="warning">Create a Tiles layer with a tileset before adding stamps.</p>');

		for(si in 0...ed.tileStamps.length) {
			final stampIdx = si;
			var stamp = ed.tileStamps[si];
			var jCard = new J('<div style="padding:8px;margin:7px 0;border:1px solid rgba(255,255,255,0.12);border-radius:3px;"/>').appendTo(jSection);
			var top = new J('<div style="display:flex;align-items:center;justify-content:space-between;gap:8px;"/>').appendTo(jCard);
			top.append('<strong>Tile stamp '+(si+1)+'</strong>');
			new J('<button class="small">Remove</button>').appendTo(top).click(_->{
				ed.tileStamps.splice(stampIdx,1);
				saveForkChange(true);
			});

			var targetRow = new J('<div style="display:flex;gap:6px;align-items:center;flex-wrap:wrap;margin-top:6px;"><span>Target layer</span><select></select></div>').appendTo(jCard);
			var target = targetRow.find("select");
			var layerUid = getInt(stamp,"layerDefUid");
			for(ld in layers) {
				var opt = new J('<option/>').attr("value",ld.uid).text(ld.identifier);
				if( ld.uid==layerUid ) opt.attr("selected","selected");
				opt.appendTo(target);
			}
			target.change(_->{
				var uid = Std.parseInt(Std.string(target.val()));
				var ld = M.isValidNumber(uid) ? project.defs.getLayerDef(null,uid) : null;
				if( ld!=null && ld.type==Tiles ) {
					Reflect.setField(stamp,"layerDefUid",uid);
					var tiles : Array<Dynamic> = cast getDyn(stamp,"tiles");
					if( tiles!=null && ld.tilesetDefUid!=null )
						for(tile in tiles)
							Reflect.setField(tile,"tilesetUid",ld.tilesetDefUid);
					saveForkChange(true);
				}
			});

			var cond = new J('<div style="display:flex;gap:6px;align-items:center;flex-wrap:wrap;margin-top:6px;"><span>When</span></div>').appendTo(jCard);
			var whenUid = getInt(stamp,"whenFieldUid");
			appendConditionFieldSelect(cond,ed,whenUid,null,uid->{
				if( uid==null ) {
					removeField(stamp,"whenFieldUid");
					removeField(stamp,"whenValue");
				}
				else {
					Reflect.setField(stamp,"whenFieldUid",uid);
					Reflect.setField(stamp,"whenValue",defaultConditionValue(ed.getFieldDef(uid)));
				}
				saveForkChange(true);
			});
			if( whenUid!=null ) {
				cond.append('<span>is</span>');
				appendValueEditor(cond,ed.getFieldDef(whenUid),getDyn(stamp,"whenValue"),v->{
					Reflect.setField(stamp,"whenValue",v);
					saveForkChange(false);
				});
			}

			var targetLd = layerUid==null ? null : project.defs.getLayerDef(null,layerUid);
			var targetTd = targetLd==null || targetLd.tilesetDefUid==null ? null : project.defs.getTilesetDef(targetLd.tilesetDefUid);
			var tiles : Array<Dynamic> = cast getDyn(stamp,"tiles");
			if( tiles==null ) {
				tiles = [];
				Reflect.setField(stamp,"tiles",tiles);
			}
			var tileList = new J('<div style="margin-top:8px;"/>').appendTo(jCard);
			for(ti in 0...tiles.length) {
				final tileIdx = ti;
				var tile = tiles[ti];
				var row = new J('<div style="padding:6px;margin:5px 0;background:rgba(255,255,255,0.035);"/>').appendTo(tileList);
				var rowTop = new J('<div style="display:flex;gap:7px;align-items:center;flex-wrap:wrap;"/>').appendTo(row);
				rowTop.append('<strong>Tile '+(ti+1)+'</strong>');
				var dx = new J('<label>Offset X <input type="number" style="width:70px"/></label>').appendTo(rowTop).find("input");
				var dy = new J('<label>Offset Y <input type="number" style="width:70px"/></label>').appendTo(rowTop).find("input");
				dx.val(getInt(tile,"dx",0));
				dy.val(getInt(tile,"dy",0));
				dx.change(_->{ var v=Std.parseInt(Std.string(dx.val())); if(M.isValidNumber(v)){Reflect.setField(tile,"dx",v);saveForkChange(false);} });
				dy.change(_->{ var v=Std.parseInt(Std.string(dy.val())); if(M.isValidNumber(v)){Reflect.setField(tile,"dy",v);saveForkChange(false);} });
				var flipLabel = new J('<label>Flip <select><option value="0">None</option><option value="1">X</option><option value="2">Y</option><option value="3">X + Y</option></select></label>').appendTo(rowTop);
				var flip = flipLabel.find("select");
				flip.val(Std.string(getInt(tile,"flips",0)));
				flip.change(_->{ var v=Std.parseInt(Std.string(flip.val())); if(M.isValidNumber(v)){Reflect.setField(tile,"flips",v);saveForkChange(false);} });
				new J('<button class="small">Remove</button>').appendTo(rowTop).click(_->{
					tiles.splice(tileIdx,1);
					saveForkChange(true);
				});
				if( targetTd!=null ) {
					var tileId = getInt(tile,"tileId",0);
					if( tileId==null ) tileId = 0;
					var picker = JsTools.createTileRectPicker(targetTd.uid,rectFromTileId(targetTd,tileId),r->{
						if( r!=null ) {
							Reflect.setField(tile,"tilesetUid",targetTd.uid);
							Reflect.setField(tile,"tileId",tileIdFromRect(targetTd,r));
							saveForkChange(false);
						}
					});
					picker.appendTo(row);
				}
			}

			new J('<button class="small">+ Tile</button>').appendTo(jCard).click(_->{
				if( targetTd!=null ) {
					tiles.push({ tilesetUid:targetTd.uid, tileId:0, dx:0, dy:0, flips:0 });
					saveForkChange(true);
				}
			});
		}

		var add = new J('<button class="create">+ Tile stamp</button>').appendTo(jSection);
		add.prop("disabled",layers.length==0);
		add.click(_->{
			if( layers.length==0 ) return;
			var ld = layers[0];
			var tdUid = ld.tilesetDefUid;
			if( tdUid==null ) return;
			ed.tileStamps.push({
				layerDefUid: ld.uid,
				tiles: [ { tilesetUid:tdUid, tileId:0, dx:0, dy:0, flips:0 } ],
			});
			saveForkChange(true);
		});
	}

	static function appendAllowedEnumValues(jParent:js.jquery.JQuery, enumUid:Int, selected:Array<Dynamic>, cb:Array<Dynamic>->Void) {
		var j = new J('<select multiple size="5" style="min-width:180px;"/>').appendTo(jParent);
		var en = project.defs.getEnumDef(enumUid);
		if( en!=null )
			for(ev in en.values) {
				var opt = new J('<option/>').attr("value",ev.id).text(ev.id);
				for(v in selected)
					if( sameValue(v,ev.id) ) {
						opt.attr("selected","selected");
						break;
					}
				opt.appendTo(j);
			}
		j.change(_->{
			var raw : Dynamic = j.val();
			var out : Array<Dynamic> = [];
			if( raw!=null ) {
				if( Std.isOfType(raw,Array) )
					for(v in (cast raw:Array<Dynamic>)) out.push(Std.string(v));
				else
					out.push(Std.string(raw));
			}
			cb(out);
		});
		return j;
	}

	static function appendFieldRulesSection(jRoot:js.jquery.JQuery, ed:data.def.EntityDef) {
		var jSection = new J('<section style="border-top:1px solid rgba(255,255,255,0.16);padding:10px 0;"/>').appendTo(jRoot);
		jSection.append('<h3 style="margin:0 0 4px 0;">Conditional fields / enum options</h3>');
		jSection.append('<p class="help">Hide fields until another field has an allowed value, and restrict enum choices based on another field.</p>');

		for(fd in ed.fieldDefs) {
			var configured = fd.visibleWhenFieldUid!=null || fd.visibleWhenValues.length>0 || fd.enumValueFilter.length>0;
			var details = new J('<details style="padding:5px 0;border-top:1px solid rgba(255,255,255,0.08);"/>').appendTo(jSection);
			if( configured ) details.attr("open","open");
			new J('<summary style="cursor:pointer;font-weight:bold;"/>').text(fd.identifier+(configured ? "  • configured" : "")).appendTo(details);
			var body = new J('<div style="padding:7px 0 4px 16px;"/>').appendTo(details);

			body.append('<div style="font-weight:bold;margin-bottom:4px;">Visibility</div>');
			var visRow = new J('<div style="display:flex;gap:6px;align-items:center;flex-wrap:wrap;"><span>Visible when</span></div>').appendTo(body);
			appendConditionFieldSelect(visRow,ed,fd.visibleWhenFieldUid,fd.uid,uid->{
				fd.visibleWhenFieldUid = uid;
				fd.visibleWhenValues = [];
				if( uid!=null )
					fd.visibleWhenValues.push(defaultConditionValue(ed.getFieldDef(uid)));
				saveForkChange(true);
			},"Always visible");
			var source = fd.visibleWhenFieldUid==null ? null : ed.getFieldDef(fd.visibleWhenFieldUid);
			if( source!=null ) {
				var values = new J('<div style="margin-top:6px;"/>').appendTo(body);
				values.append('<span>Allowed trigger values</span>');
				for(vi in 0...fd.visibleWhenValues.length) {
					final valueIdx = vi;
					var row = new J('<div style="display:flex;gap:6px;align-items:center;margin-top:4px;"/>').appendTo(values);
					appendValueEditor(row,source,fd.visibleWhenValues[vi],v->{
						fd.visibleWhenValues[valueIdx] = v;
						saveForkChange(false);
					});
					new J('<button class="small">Remove</button>').appendTo(row).click(_->{
						fd.visibleWhenValues.splice(valueIdx,1);
						saveForkChange(true);
					});
				}
				new J('<button class="small" style="margin-top:4px;">+ Trigger value</button>').appendTo(values).click(_->{
					fd.visibleWhenValues.push(defaultConditionValue(source));
					saveForkChange(true);
				});
			}

			switch fd.type {
				case F_Enum(targetEnumUid):
					body.append('<div style="font-weight:bold;margin:10px 0 4px 0;">Allowed enum values</div>');
					body.append('<p class="help">Each rule activates for one condition. When active, only the selected enum values can be chosen.</p>');
					for(ri in 0...fd.enumValueFilter.length) {
						final ruleIdx = ri;
						var rule = fd.enumValueFilter[ri];
						var card = new J('<div style="padding:6px;margin:5px 0;background:rgba(255,255,255,0.035);"/>').appendTo(body);
						var line = new J('<div style="display:flex;gap:6px;align-items:center;flex-wrap:wrap;"><span>When</span></div>').appendTo(card);
						var whenUid = getInt(rule,"whenFieldUid");
						appendConditionFieldSelect(line,ed,whenUid,fd.uid,uid->{
							if( uid==null ) {
								removeField(rule,"whenFieldUid");
								removeField(rule,"whenValue");
							}
							else {
								Reflect.setField(rule,"whenFieldUid",uid);
								Reflect.setField(rule,"whenValue",defaultConditionValue(ed.getFieldDef(uid)));
							}
							saveForkChange(true);
						});
						if( whenUid!=null ) {
							line.append('<span>is</span>');
							appendValueEditor(line,ed.getFieldDef(whenUid),getDyn(rule,"whenValue"),v->{
								Reflect.setField(rule,"whenValue",v);
								saveForkChange(false);
							});
						}
						line.append('<span>allow</span>');
						var allowed : Array<Dynamic> = cast getDyn(rule,"allowedEnumValueIds");
						if( allowed==null ) allowed = [];
						appendAllowedEnumValues(line,targetEnumUid,allowed,v->{
							Reflect.setField(rule,"allowedEnumValueIds",v);
							saveForkChange(false);
						});
						new J('<button class="small">Remove rule</button>').appendTo(line).click(_->{
							fd.enumValueFilter.splice(ruleIdx,1);
							saveForkChange(true);
						});
					}
					new J('<button class="small">+ Enum filter rule</button>').appendTo(body).click(_->{
						var rule : Dynamic = {};
						var cond = getFirstConditionField(ed,fd.uid);
						if( cond!=null ) {
							Reflect.setField(rule,"whenFieldUid",cond.uid);
							Reflect.setField(rule,"whenValue",defaultConditionValue(cond));
						}
						var allowed : Array<Dynamic> = [];
						var en = project.defs.getEnumDef(targetEnumUid);
						if( en!=null ) for(ev in en.values) allowed.push(ev.id);
						Reflect.setField(rule,"allowedEnumValueIds",allowed);
						fd.enumValueFilter.push(rule);
						saveForkChange(true);
					});
				case _:
			}
		}
	}

	static function updateStructuredForkAuthoring() {
		if( !Editor.exists() || project==null )
			return;
		var jContent = getPanelContent();
		if( jContent.length==0 )
			return;
		var rawRoot = jContent.find(".forkAuthoringEditor");
		if( showRawForkJson ) rawRoot.show(); else rawRoot.hide();

		var jRoot = jContent.find(".forkAuthoringStructuredEditor");
		if( jRoot.length==0 ) {
			jRoot = new J('<div class="forkAuthoringStructuredEditor"/>');
			jRoot.insertBefore(rawRoot);
		}
		jRoot.empty();

		var ed = getSelectedEntity();
		if( ed==null ) {
			jRoot.hide();
			return;
		}
		jRoot.show();
		jRoot.append('<h2>Smartive authoring</h2>');
		jRoot.append('<p class="help">Fork-only behaviors are still stored in <code>'+project.filePath.fileWithExt+'-fork.json</code>, but you can author them here without writing JSON.</p>');

		var actions = new J('<div style="display:flex;gap:6px;flex-wrap:wrap;margin-bottom:8px;"/>').appendTo(jRoot);
		new J('<button class="small">Save sidecar</button>').appendTo(actions).click(_->{ project.forkConfig.save(); N.debug("Fork sidecar saved"); });
		new J('<button class="small">Reload sidecar</button>').appendTo(actions).click(_->{ project.forkConfig.load(); lastSignature=null; editor.ge.emit(EntityDefChanged); });
		new J('<button class="small">Re-stamp current level</button>').appendTo(actions).click(_->{
			if( editor.curLevel==null ) return;
			var changed = project.forkConfig.restampLevel(editor.curLevel);
			if( changed.length>0 ) {
				editor.curLevelTimeline.saveLayerStates(changed);
				for(li in changed) editor.levelRender.invalidateLayer(li);
			}
		});
		var advanced = new J('<button class="small">Advanced JSON</button>').appendTo(actions);
		advanced.click(_->{
			showRawForkJson = !showRawForkJson;
			if( showRawForkJson ) rawRoot.show(); else rawRoot.hide();
		});

		appendAppearanceSection(jRoot,ed);
		appendStampSection(jRoot,ed);
		appendFieldRulesSection(jRoot,ed);
		JsTools.parseComponents(jRoot);
	}
}
