package data;

import data.DataTypes;

/**
 * Runtime-only configuration for the RondeI33 LDtk fork.
 *
 * Configuration is stored beside the project in `<project>.ldtk-fork.json` and is NEVER
 * serialized into the LDtk project/level schema. This deliberately keeps files readable by
 * stock LDtk 1.5.3 and stock importers.
 */
class ForkConfig {
	public static inline var FORMAT = 1;

	var project : Project;
	var trackedEntities : Map<String, Dynamic> = new Map();
	// Keep the document, not just the editor features this build understands. Game tools
	// may add their own sidecar keys, which must survive any editor-side save.
	var sidecarRoot : Dynamic = {};
	var loadedEntityKeys : Map<String, Bool> = new Map();

	public function new(p:Project) {
		project = p;
	}

	public inline function getPath() : String {
		return project.filePath.full + "-fork.json";
	}

	static inline function getDyn(o:Dynamic, field:String) : Dynamic {
		return o==null ? null : Reflect.field(o, field);
	}

	static function getArray(o:Dynamic, field:String) : Array<Dynamic> {
		var v = getDyn(o, field);
		return v==null ? [] : cast v;
	}

	static function getInt(o:Dynamic, field:String, ?fallback:Null<Int>) : Null<Int> {
		var v = getDyn(o, field);
		if( v==null )
			return fallback;
		var parsed = Std.parseInt(Std.string(v));
		return M.isValidNumber(parsed) ? parsed : fallback;
	}

	static function getFloat(o:Dynamic, field:String, ?fallback:Null<Float>) : Null<Float> {
		var v = getDyn(o, field);
		if( v==null )
			return fallback;
		var parsed = Std.parseFloat(Std.string(v));
		return M.isValidNumber(parsed) ? parsed : fallback;
	}

	static inline function cloneJson(v:Dynamic) : Dynamic {
		return v==null ? null : haxe.Json.parse(haxe.Json.stringify(v));
	}

	static function isJsonObject(v:Dynamic) : Bool {
		return v!=null && Reflect.isObject(v) && !Std.isOfType(v,Array) && !Std.isOfType(v,String);
	}

	/** Merge editor-owned properties while retaining unrecognized properties at any depth. */
	static function mergeSidecarValue(previous:Dynamic, current:Dynamic) : Dynamic {
		if( isJsonObject(current) ) {
			var out : Dynamic = isJsonObject(previous) ? cloneJson(previous) : {};
			for(key in Reflect.fields(current))
				Reflect.setField(out,key,mergeSidecarValue(getDyn(previous,key),Reflect.field(current,key)));
			return out;
		}
		if( Std.isOfType(current,Array) ) {
			var old : Array<Dynamic> = Std.isOfType(previous,Array) ? cast previous : [];
			var values : Array<Dynamic> = cast current;
			var used : Map<Int,Bool> = new Map();
			var out : Array<Dynamic> = [];
			for(i in 0...values.length) {
				var value = values[i];
				var match = -1;
				// Stable references keep unknown metadata with its rule when rules are reordered.
				for(identity in ["chainField","fieldIdentifier","entityDefIdentifier","fieldDefUid","entityDefUid","whenFieldUid"]) {
					if( !isJsonObject(value) || getDyn(value,identity)==null )
						continue;
					for(j in 0...old.length)
						if( !used.exists(j) && getDyn(old[j],identity)==getDyn(value,identity) ) {
							match = j;
							break;
						}
					// A new identified item must not inherit another item's unknown settings.
					break;
				}
				if( match<0 && i<old.length && !used.exists(i) && !hasSidecarIdentity(value) )
					match = i;
				if( match>=0 )
					used.set(match,true);
				out.push(mergeSidecarValue(match<0 ? null : old[match],value));
			}
			return out;
		}
		return cloneJson(current);
	}

	static function hasSidecarIdentity(v:Dynamic) : Bool {
		if( !isJsonObject(v) )
			return false;
		for(key in ["chainField","fieldIdentifier","entityDefIdentifier","fieldDefUid","entityDefUid","whenFieldUid"])
			if( getDyn(v,key)!=null )
				return true;
		return false;
	}

	public function hasPathPreview(ed:data.def.EntityDef) : Bool {
		return ed!=null && isJsonObject(getDyn(getDyn(getDyn(sidecarRoot,"entities"),Std.string(ed.uid)),"pathPreview"));
	}

	public function hasDrawableShape(ed:data.def.EntityDef) : Bool {
		var cfg=getDyn(getDyn(getDyn(sidecarRoot,"entities"),ed==null ? "":Std.string(ed.uid)),"drawableShape");
		return cfg==true || isJsonObject(cfg) && getDyn(cfg,"enabled")!=false;
	}

	/** UI capability only: every per-instance runtime value lives in native fields. */
	public function setDrawableShapeEnabled(ed:data.def.EntityDef,enabled:Bool) {
		var entities=getDyn(sidecarRoot,"entities");
		if(!isJsonObject(entities)) {entities={};Reflect.setField(sidecarRoot,"entities",entities);}
		var id=Std.string(ed.uid),cfg=getDyn(entities,id);
		if(!isJsonObject(cfg)) {cfg={};Reflect.setField(entities,id,cfg);}
		Reflect.setField(cfg,"identifier",ed.identifier);
		Reflect.setField(cfg,"drawableShape",mergeSidecarValue(getDyn(cfg,"drawableShape"),{enabled:enabled,version:1}));
		loadedEntityKeys.set(id,true);
	}

	/** Read-only adapter: never generates entities, tiles or default FieldInstances. */
	public function getPathPreview(ei:data.inst.EntityInstance, ?overrides:PathPreviewConfig.PathPreviewOverrides) : Null<PathPreviewConfig.ResolvedPathPreview> {
		if( ei==null || !hasPathPreview(ei.def) )
			return null;
		return PathPreviewConfig.resolve(ei,getDyn(getDyn(getDyn(sidecarRoot,"entities"),Std.string(ei.def.uid)),"pathPreview"),overrides);
	}

	static function sameValue(a:Dynamic, b:Dynamic) {
		if( a==null || b==null )
			return a==b;
		return Std.string(a)==Std.string(b);
	}

	function resolveEntityUid(uid:Null<Int>, identifier:Null<String>) : Null<Int> {
		if( uid!=null && project.defs.getEntityDef(uid)!=null )
			return uid;
		if( identifier!=null )
			for(ed in project.defs.entities)
				if( ed.identifier==identifier )
					return ed.uid;
		return null;
	}

	function resolveFieldUid(ed:data.def.EntityDef, uid:Null<Int>, identifier:Null<String>) : Null<Int> {
		if( uid!=null && ed.getFieldDef(uid)!=null )
			return uid;
		if( identifier!=null )
			for(fd in ed.fieldDefs)
				if( fd.identifier==identifier )
					return fd.uid;
		return null;
	}

	function resolveLayerUid(uid:Null<Int>, identifier:Null<String>) : Null<Int> {
		if( uid!=null && project.defs.getLayerDef(uid)!=null )
			return uid;
		if( identifier!=null )
			for(ld in project.defs.layers)
				if( ld.identifier==identifier )
					return ld.uid;
		return null;
	}

	function resolveTilesetUid(uid:Null<Int>, identifier:Null<String>) : Null<Int> {
		if( uid!=null && project.defs.getTilesetDef(uid)!=null )
			return uid;
		if( identifier!=null )
			for(td in project.defs.tilesets)
				if( td.identifier==identifier )
					return td.uid;
		return null;
	}

	function normalizeAppearance(ed:data.def.EntityDef, raw:Dynamic) {
		var out = cloneJson(raw);
		var uid = resolveFieldUid(ed, getInt(out,"whenFieldUid"), getDyn(out,"whenFieldIdentifier"));
		if( uid!=null )
			Reflect.setField(out, "whenFieldUid", uid);

		var rect = getDyn(out,"tileRect");
		if( rect!=null ) {
			var tdUid = resolveTilesetUid(getInt(rect,"tilesetUid"), getDyn(rect,"tilesetIdentifier"));
			if( tdUid!=null )
				Reflect.setField(rect,"tilesetUid",tdUid);
		}
		return out;
	}

	function normalizeStamp(ed:data.def.EntityDef, raw:Dynamic) {
		var out = cloneJson(raw);
		var layerUid = resolveLayerUid(getInt(out,"layerDefUid"), getDyn(out,"layerIdentifier"));
		if( layerUid!=null )
			Reflect.setField(out,"layerDefUid",layerUid);

		var whenUid = resolveFieldUid(ed, getInt(out,"whenFieldUid"), getDyn(out,"whenFieldIdentifier"));
		if( whenUid!=null )
			Reflect.setField(out,"whenFieldUid",whenUid);

		for(tile in getArray(out,"tiles")) {
			var tdUid = resolveTilesetUid(getInt(tile,"tilesetUid"), getDyn(tile,"tilesetIdentifier"));
			if( tdUid!=null )
				Reflect.setField(tile,"tilesetUid",tdUid);
			if( getDyn(tile,"flips")==null )
				Reflect.setField(tile,"flips",0);
		}
		return out;
	}

	function normalizeEnumFilter(ed:data.def.EntityDef, raw:Dynamic) {
		var out = cloneJson(raw);
		var uid = resolveFieldUid(ed, getInt(out,"whenFieldUid"), getDyn(out,"whenFieldIdentifier"));
		if( uid!=null )
			Reflect.setField(out,"whenFieldUid",uid);
		return out;
	}

	function readAutoChainBackRefs(ed:data.def.EntityDef, cfg:Dynamic) : Array<{ chainField:String, backField:String }> {
		var out : Array<{ chainField:String, backField:String }> = [];
		var rules = getDyn(cfg,"autoChainBackRefs");
		if( rules==null )
			return out;
		if( !Std.isOfType(rules,Array) ) {
			App.LOG.add("fork", 'Ignoring invalid autoChainBackRefs for "${ed.identifier}": expected an array');
			return out;
		}

		var seen : Map<String,Bool> = new Map();
		for(raw in (cast rules:Array<Dynamic>)) {
			var chain = getDyn(raw,"chainField");
			var back = getDyn(raw,"backField");
			if( !Std.isOfType(chain,String) || !Std.isOfType(back,String) || chain.length==0 || back.length==0 ) {
				App.LOG.add("fork", 'Ignoring invalid autoChainBackRefs rule for "${ed.identifier}": expected field identifiers');
				continue;
			}
			if( seen.exists(chain) ) {
				App.LOG.add("fork", 'Ignoring duplicate autoChainBackRefs rule for "${ed.identifier}.$chain"');
				continue;
			}
			seen.set(chain,true);
			out.push({ chainField:chain, backField:back });
		}
		return out;
	}

	/** Back fields are resolved on the target, which may have a different entity definition. */
	public function getAutoChainBackRef(ed:data.def.EntityDef, chainFd:data.def.FieldDef) : Null<String> {
		if( ed==null || chainFd==null )
			return null;
		for(rule in ed.autoChainBackRefs)
			if( rule.chainField==chainFd.identifier )
				return rule.backField;
		return null;
	}

	public function load() {
		trackedEntities = new Map();
		sidecarRoot = {};
		loadedEntityKeys = new Map();

		// Clear all sidecar-only runtime state. Legacy embedded autoChildren are intentionally kept
		// until/unless the sidecar contains an explicit autoChildren entry, allowing one-time migration.
		for(ed in project.defs.entities) {
			ed.autoChainBackRefs = [];
			ed.appearanceOverrides = [];
			ed.tileStamps = [];
			for(fd in ed.fieldDefs) {
				fd.visibleWhenFieldUid = null;
				fd.visibleWhenValues = [];
				fd.enumValueFilter = [];
			}
		}

		var path = getPath();
		if( !NT.fileExists(path) ) {
			var hasLegacy = false;
			for(ed in project.defs.entities)
				if( ed.autoChildren.length>0 ) {
					hasLegacy = true;
					break;
				}
			if( hasLegacy )
				save();
			return;
		}

		try {
			var root : Dynamic = haxe.Json.parse(NT.readFileString(path));
			if( !isJsonObject(root) )
				throw "Expected a sidecar object";
			sidecarRoot = cloneJson(root);
			var entities = getDyn(root,"entities");
			if( !isJsonObject(entities) )
				return;

			var remapped = false;
			for(key in Reflect.fields(entities)) {
				var cfg = Reflect.field(entities,key);
				if( !isJsonObject(cfg) )
					continue;
				var keyUid = Std.parseInt(key);
				var resolvedUid = resolveEntityUid(M.isValidNumber(keyUid) ? keyUid : null, getDyn(cfg,"identifier"));
				if( resolvedUid==null ) {
					App.LOG.add("fork", 'Ignoring fork config for missing entity "$key"');
					continue;
				}
				var resolvedKey = Std.string(resolvedUid);
				var savedEntities = getDyn(sidecarRoot,"entities");
				if( !M.isValidNumber(keyUid) || resolvedUid!=keyUid ) {
					remapped = true;
					// Move the preserved entry as well, so the old UID cannot survive a rewrite.
					var canonical = getDyn(entities,resolvedKey);
					cfg = isJsonObject(canonical) ? mergeSidecarValue(cfg,canonical) : cloneJson(cfg);
					Reflect.deleteField(savedEntities,key);
					Reflect.setField(savedEntities,resolvedKey,cloneJson(cfg));
				}
				loadedEntityKeys.set(resolvedKey,true);

				var ed = project.defs.getEntityDef(resolvedUid);

				if( Reflect.hasField(cfg,"autoChildren") ) {
					ed.autoChildren = [];
					for(raw in getArray(cfg,"autoChildren")) {
						var childUid = resolveEntityUid(getInt(raw,"entityDefUid"), getDyn(raw,"entityDefIdentifier"));
						if( childUid==null )
							continue;
						var ac = ed.createAutoChild(childUid);
						ac.offsetX = getInt(raw,"offsetX",0);
						ac.offsetY = getInt(raw,"offsetY",0);
						ac.count = M.imax(1,getInt(raw,"count",1));
						ac.spacingX = getInt(raw,"spacingX",0);
						ac.spacingY = getInt(raw,"spacingY",0);
						ac.linkFieldUid = resolveFieldUid(ed, getInt(raw,"linkFieldUid"), getDyn(raw,"linkFieldIdentifier"));

						var childDef = project.defs.getEntityDef(childUid);
						for(pr in getArray(raw,"fieldPresets")) {
							var fieldUid = childDef==null ? null : resolveFieldUid(childDef, getInt(pr,"fieldDefUid"), getDyn(pr,"fieldIdentifier"));
							if( fieldUid!=null )
								ac.fieldPresets.push({ fieldDefUid:fieldUid, value:getDyn(pr,"value") });
						}
					}
				}

				ed.autoChainBackRefs = readAutoChainBackRefs(ed,cfg);
				ed.appearanceOverrides = getArray(cfg,"appearanceOverrides").map(raw->normalizeAppearance(ed,raw));
				ed.tileStamps = getArray(cfg,"tileStamps").map(raw->normalizeStamp(ed,raw));

				var fields = getDyn(cfg,"fields");
				if( isJsonObject(fields) )
					for(fieldKey in Reflect.fields(fields)) {
						var fcfg = Reflect.field(fields,fieldKey);
						if( !isJsonObject(fcfg) )
							continue;
						var keyFieldUid = Std.parseInt(fieldKey);
						var fdUid = resolveFieldUid(ed, M.isValidNumber(keyFieldUid) ? keyFieldUid : null, getDyn(fcfg,"identifier"));
						if( fdUid==null )
							continue;
						if( fieldKey!=Std.string(fdUid) ) {
							remapped = true;
							var savedFields = getDyn(getDyn(savedEntities,resolvedKey),"fields");
							var canonical = getDyn(fields,Std.string(fdUid));
							fcfg = isJsonObject(canonical) ? mergeSidecarValue(fcfg,canonical) : cloneJson(fcfg);
							Reflect.deleteField(savedFields,fieldKey);
							Reflect.setField(savedFields,Std.string(fdUid),cloneJson(fcfg));
						}
						var fd = ed.getFieldDef(fdUid);
						fd.visibleWhenFieldUid = resolveFieldUid(ed, getInt(fcfg,"visibleWhenFieldUid"), getDyn(fcfg,"visibleWhenFieldIdentifier"));
						fd.visibleWhenValues = getArray(fcfg,"visibleWhenValues");
						fd.enumValueFilter = getArray(fcfg,"enumValueFilter").map(raw->normalizeEnumFilter(ed,raw));
					}
			}

			if( remapped )
				save();
		}
		catch(err:Dynamic) {
			App.LOG.error('Failed to load fork sidecar "$path": '+Std.string(err));
		}
	}

	function entityIdentifier(uid:Null<Int>) : Null<String> {
		var ed = uid==null ? null : project.defs.getEntityDef(uid);
		return ed==null ? null : ed.identifier;
	}

	function fieldIdentifier(ed:data.def.EntityDef, uid:Null<Int>) : Null<String> {
		var fd = uid==null ? null : ed.getFieldDef(uid);
		return fd==null ? null : fd.identifier;
	}

	function layerIdentifier(uid:Null<Int>) : Null<String> {
		var ld = uid==null ? null : project.defs.getLayerDef(uid);
		return ld==null ? null : ld.identifier;
	}

	function tilesetIdentifier(uid:Null<Int>) : Null<String> {
		var td = uid==null ? null : project.defs.getTilesetDef(uid);
		return td==null ? null : td.identifier;
	}

	function enrichAppearance(ed:data.def.EntityDef, raw:Dynamic) : Dynamic {
		var out = cloneJson(raw);
		var uid = getInt(out,"whenFieldUid");
		Reflect.setField(out,"whenFieldIdentifier",fieldIdentifier(ed,uid));
		var rect = getDyn(out,"tileRect");
		if( rect!=null )
			Reflect.setField(rect,"tilesetIdentifier",tilesetIdentifier(getInt(rect,"tilesetUid")));
		return out;
	}

	function enrichStamp(ed:data.def.EntityDef, raw:Dynamic) : Dynamic {
		var out = cloneJson(raw);
		Reflect.setField(out,"layerIdentifier",layerIdentifier(getInt(out,"layerDefUid")));
		Reflect.setField(out,"whenFieldIdentifier",fieldIdentifier(ed,getInt(out,"whenFieldUid")));
		for(tile in getArray(out,"tiles"))
			Reflect.setField(tile,"tilesetIdentifier",tilesetIdentifier(getInt(tile,"tilesetUid")));
		return out;
	}

	function enrichEnumFilter(ed:data.def.EntityDef, raw:Dynamic) : Dynamic {
		var out = cloneJson(raw);
		Reflect.setField(out,"whenFieldIdentifier",fieldIdentifier(ed,getInt(out,"whenFieldUid")));
		return out;
	}

	public function save() {
		if( project.filePath==null || project.filePath.full==null || project.filePath.full.length==0 )
			return;

		var root : Dynamic = cloneJson(sidecarRoot);
		var entities : Dynamic = getDyn(root,"entities");
		if( !isJsonObject(entities) )
			entities = {};
		for(key in loadedEntityKeys.keys())
			if( project.defs.getEntityDef(Std.parseInt(key))==null )
				Reflect.deleteField(entities,key);
		for(ed in project.defs.entities) {
			var cfg : Dynamic = getDyn(entities,Std.string(ed.uid));
			if( !isJsonObject(cfg) )
				cfg = {};
			var fields : Dynamic = getDyn(cfg,"fields");
			if( !isJsonObject(fields) )
				fields = {};
			var hasFields = Reflect.fields(fields).length>0;
			for(fd in ed.fieldDefs)
				if( fd.visibleWhenFieldUid!=null || fd.visibleWhenValues.length>0 || fd.enumValueFilter.length>0 || Reflect.hasField(fields,Std.string(fd.uid)) ) {
					hasFields = true;
					var filters = fd.enumValueFilter.map(raw->enrichEnumFilter(ed,raw));
					Reflect.setField(fields, Std.string(fd.uid), mergeSidecarValue(getDyn(fields,Std.string(fd.uid)), {
						identifier: fd.identifier,
						visibleWhenFieldUid: fd.visibleWhenFieldUid,
						visibleWhenFieldIdentifier: fieldIdentifier(ed,fd.visibleWhenFieldUid),
						visibleWhenValues: fd.visibleWhenValues,
						enumValueFilter: filters,
					}));
				}

			if( ed.autoChildren.length==0 && ed.autoChainBackRefs.length==0 && ed.appearanceOverrides.length==0 && ed.tileStamps.length==0 && !hasFields && Reflect.fields(cfg).length==0 )
				continue;

			var autoChildren : Array<Dynamic> = [];
			for(ac in ed.autoChildren) {
				var childDef = project.defs.getEntityDef(ac.entityDefUid);
				var presets : Array<Dynamic> = [];
				for(pr in ac.fieldPresets)
					presets.push({
						fieldDefUid: pr.fieldDefUid,
						fieldIdentifier: childDef==null ? null : fieldIdentifier(childDef,pr.fieldDefUid),
						value: pr.value,
					});
				autoChildren.push({
					entityDefUid: ac.entityDefUid,
					entityDefIdentifier: entityIdentifier(ac.entityDefUid),
					offsetX: ac.offsetX,
					offsetY: ac.offsetY,
					count: ac.count,
					spacingX: ac.spacingX,
					spacingY: ac.spacingY,
					linkFieldUid: ac.linkFieldUid,
					linkFieldIdentifier: fieldIdentifier(ed,ac.linkFieldUid),
					fieldPresets: presets,
				});
			}

			cfg = mergeSidecarValue(cfg, {
				identifier: ed.identifier,
				autoChildren: autoChildren,
				appearanceOverrides: ed.appearanceOverrides.map(raw->enrichAppearance(ed,raw)),
				tileStamps: ed.tileStamps.map(raw->enrichStamp(ed,raw)),
				fields: fields,
			});
			if( ed.autoChainBackRefs.length>0 )
				Reflect.setField(cfg,"autoChainBackRefs",mergeSidecarValue(getDyn(cfg,"autoChainBackRefs"),ed.autoChainBackRefs.map(rule->{ chainField:rule.chainField, backField:rule.backField })));
			else
				Reflect.deleteField(cfg,"autoChainBackRefs");
			Reflect.setField(entities, Std.string(ed.uid), cfg);
			loadedEntityKeys.set(Std.string(ed.uid),true);
		}

		Reflect.setField(root,"format",FORMAT);
		Reflect.setField(root,"projectIid",project.iid);
		Reflect.setField(root,"entities",entities);
		try {
			NT.writeFileString(getPath(), haxe.Json.stringify(root,null,"\t"));
			sidecarRoot = cloneJson(root);
		}
		catch(err:Dynamic) {
			App.LOG.error('Failed to save fork sidecar "${getPath()}": '+Std.string(err));
		}
	}

	function getFieldValue(ei:data.inst.EntityInstance, fieldUid:Int) : Dynamic {
		var fd = ei.def.getFieldDef(fieldUid);
		if( fd==null )
			return null;
		var fi = ei.getFieldInstance(fd,true);
		return fi==null ? null : fi.toJson().__value;
	}

	function matchesField(ei:data.inst.EntityInstance, fieldUid:Null<Int>, expected:Dynamic) {
		if( fieldUid==null )
			return true;
		var fd = ei.def.getFieldDef(fieldUid);
		if( fd==null )
			return false;
		return sameValue(getFieldValue(ei,fieldUid), expected);
	}

	public function isFieldVisible(ei:Null<data.inst.EntityInstance>, fd:data.def.FieldDef) {
		if( ei==null || fd.visibleWhenFieldUid==null || fd.visibleWhenValues.length==0 )
			return true;
		if( ei.def.getFieldDef(fd.visibleWhenFieldUid)==null )
			return true;
		var actual = getFieldValue(ei,fd.visibleWhenFieldUid);
		for(expected in fd.visibleWhenValues)
			if( sameValue(actual,expected) )
				return true;
		return false;
	}

	public function isEnumValueAllowed(ei:Null<data.inst.EntityInstance>, fd:data.def.FieldDef, valueId:String) {
		if( ei==null || fd.enumValueFilter.length==0 )
			return true;
		var matchedRule = false;
		for(rule in fd.enumValueFilter) {
			var whenUid = getInt(rule,"whenFieldUid");
			if( matchesField(ei,whenUid,getDyn(rule,"whenValue")) ) {
				matchedRule = true;
				for(allowed in getArray(rule,"allowedEnumValueIds"))
					if( Std.string(allowed)==valueId )
						return true;
			}
		}
		return !matchedRule;
	}

	public function hasValidationError(ei:data.inst.EntityInstance) {
		var shape=DrawableShape.read(ei);
		if(shape!=null && shape.error!=null)return true;
		for(fd in ei.def.fieldDefs)
			if( fd.enumValueFilter.length>0 )
				switch fd.type {
					case F_Enum(_):
						var fi = ei.getFieldInstance(fd,true);
						for(i in 0...fi.getArrayLength()) {
							var v = fi.getEnumValue(i);
							if( v!=null && !isEnumValueAllowed(ei,fd,v) )
								return true;
						}
					case _:
				}
		return false;
	}

	public function getAppearance(ei:data.inst.EntityInstance) : Dynamic {
		for(raw in ei.def.appearanceOverrides)
			if( matchesField(ei,getInt(raw,"whenFieldUid"),getDyn(raw,"whenValue")) )
				return raw;
		return null;
	}

	public function getAppearanceWidth(ei:data.inst.EntityInstance) : Null<Int> {
		return getInt(getAppearance(ei),"width");
	}
	public function hasAppearanceWidthOverride(ed:data.def.EntityDef) {
		for(raw in ed.appearanceOverrides)
			if( getDyn(raw,"width")!=null )
				return true;
		return false;
	}
	public function getAppearanceHeight(ei:data.inst.EntityInstance) : Null<Int> {
		return getInt(getAppearance(ei),"height");
	}
	public function hasAppearanceHeightOverride(ed:data.def.EntityDef) {
		for(raw in ed.appearanceOverrides)
			if( getDyn(raw,"height")!=null )
				return true;
		return false;
	}
	public function getAppearancePivotX(ei:data.inst.EntityInstance) : Null<Float> {
		return getFloat(getAppearance(ei),"pivotX");
	}
	public function getAppearancePivotY(ei:data.inst.EntityInstance) : Null<Float> {
		return getFloat(getAppearance(ei),"pivotY");
	}
	public function getAppearanceTile(ei:data.inst.EntityInstance) : Null<ldtk.Json.TilesetRect> {
		var a = getAppearance(ei);
		return a==null || getDyn(a,"tileRect")==null ? null : cast getDyn(a,"tileRect");
	}
	public function getAppearanceColor(ei:data.inst.EntityInstance) : Null<Int> {
		var a = getAppearance(ei);
		var raw = getDyn(a,"color");
		if( raw==null )
			return null;
		return Type.typeof(raw)==TInt ? cast raw : dn.legacy.Color.hexToInt(Std.string(raw));
	}

	function stampIsActive(ei:data.inst.EntityInstance, stamp:Dynamic) {
		return matchesField(ei,getInt(stamp,"whenFieldUid"),getDyn(stamp,"whenValue"));
	}

	function findStampLayer(ei:data.inst.EntityInstance, stamp:Dynamic) : Null<data.inst.LayerInstance> {
		var uid = getInt(stamp,"layerDefUid");
		if( uid==null )
			return null;
		for(li in ei._li.level.layerInstances)
			if( li.layerDefUid==uid && li.def.type==Tiles )
				return li;
		return null;
	}

	function markGrid(li:data.inst.LayerInstance, cx:Int, cy:Int) {
		if( Editor.exists() && Editor.ME.curLevel==li.level )
			Editor.ME.curLevelTimeline.markGridChange(li,cx,cy);
	}

	function paintStampAt(ei:data.inst.EntityInstance, stamp:Dynamic, px:Int, py:Int, touched:Map<Int,data.inst.LayerInstance>) {
		if(DrawableShape.hasMetadata(ei))return;
		var li = findStampLayer(ei,stamp);
		if( li==null )
			return;
		var grid = li.def.gridSize;
		var baseCx = M.round(px/grid);
		var baseCy = M.round(py/grid);
		for(tile in getArray(stamp,"tiles")) {
			var tileId = getInt(tile,"tileId");
			if( tileId==null )
				continue;
			var tilesetUid = getInt(tile,"tilesetUid",li.getTilesetUid());
			if( tilesetUid!=li.getTilesetUid() ) {
				App.LOG.add("fork", 'Skipped tile stamp: tileset $tilesetUid does not match layer ${li.getTilesetUid()}');
				continue;
			}
			var cx = baseCx + getInt(tile,"dx",0);
			var cy = baseCy + getInt(tile,"dy",0);
			if( !li.isValid(cx,cy) )
				continue;
			markGrid(li,cx,cy);
			li.removeAllGridTiles(cx,cy,false);
			li.addGridTile(cx,cy,tileId,getInt(tile,"flips",0),false,false);
			touched.set(li.layerDefUid,li);
		}
	}

	function eraseStampAt(ei:data.inst.EntityInstance, stamp:Dynamic, px:Int, py:Int, touched:Map<Int,data.inst.LayerInstance>) {
		if(DrawableShape.hasMetadata(ei))return;
		var li = findStampLayer(ei,stamp);
		if( li==null )
			return;
		var grid = li.def.gridSize;
		var baseCx = M.round(px/grid);
		var baseCy = M.round(py/grid);
		for(tile in getArray(stamp,"tiles")) {
			var tileId = getInt(tile,"tileId");
			if( tileId==null )
				continue;
			var cx = baseCx + getInt(tile,"dx",0);
			var cy = baseCy + getInt(tile,"dy",0);
			if( !li.isValid(cx,cy) )
				continue;
			var stack = li.getGridTileStack(cx,cy);
			if( stack.length==1 && stack[0].tileId==tileId && stack[0].flips==getInt(tile,"flips",0) ) {
				markGrid(li,cx,cy);
				li.removeAllGridTiles(cx,cy,false);
				touched.set(li.layerDefUid,li);
			}
		}
	}

	static function touchedToArray(touched:Map<Int,data.inst.LayerInstance>) {
		var all = [];
		for(li in touched)
			all.push(li);
		return all;
	}

	public function paintEntityStamps(ei:data.inst.EntityInstance) : Array<data.inst.LayerInstance> {
		if(DrawableShape.hasMetadata(ei))return [];
		var touched : Map<Int,data.inst.LayerInstance> = new Map();
		for(stamp in ei.def.tileStamps)
			if( stampIsActive(ei,stamp) )
				paintStampAt(ei,stamp,ei.x,ei.y,touched);
		trackEntity(ei);
		return touchedToArray(touched);
	}

	public function eraseEntityStamps(ei:data.inst.EntityInstance) : Array<data.inst.LayerInstance> {
		if(DrawableShape.hasMetadata(ei)) {trackedEntities.remove(ei.iid);return [];}
		var touched : Map<Int,data.inst.LayerInstance> = new Map();
		for(stamp in ei.def.tileStamps)
			if( stampIsActive(ei,stamp) )
				eraseStampAt(ei,stamp,ei.x,ei.y,touched);
		trackedEntities.remove(ei.iid);
		return touchedToArray(touched);
	}

	public function trackEntity(ei:data.inst.EntityInstance) {
		if(DrawableShape.hasMetadata(ei)) {trackedEntities.remove(ei.iid);return;}
		var gates = [];
		for(stamp in ei.def.tileStamps)
			gates.push(stampIsActive(ei,stamp));
		trackedEntities.set(ei.iid, { x:ei.x, y:ei.y, gates:gates });
	}

	public function syncTrackedEntity(ei:data.inst.EntityInstance) : Array<data.inst.LayerInstance> {
		if(DrawableShape.hasMetadata(ei)) {trackedEntities.remove(ei.iid);return [];}
		var old = trackedEntities.get(ei.iid);
		if( old==null ) {
			trackEntity(ei);
			return [];
		}

		var touched : Map<Int,data.inst.LayerInstance> = new Map();
		var oldGates : Array<Bool> = cast old.gates;
		var moved = old.x!=ei.x || old.y!=ei.y;
		for(i in 0...ei.def.tileStamps.length) {
			var stamp = ei.def.tileStamps[i];
			var wasActive = i<oldGates.length ? oldGates[i] : false;
			var isActive = stampIsActive(ei,stamp);
			if( moved ) {
				if( wasActive )
					eraseStampAt(ei,stamp,old.x,old.y,touched);
				if( isActive )
					paintStampAt(ei,stamp,ei.x,ei.y,touched);
			}
			else if( wasActive!=isActive ) {
				if( wasActive )
					eraseStampAt(ei,stamp,ei.x,ei.y,touched);
				else
					paintStampAt(ei,stamp,ei.x,ei.y,touched);
			}
		}
		trackEntity(ei);
		return touchedToArray(touched);
	}

	public function restampLevel(level:data.Level) : Array<data.inst.LayerInstance> {
		var touched : Map<Int,data.inst.LayerInstance> = new Map();
		for(li in level.layerInstances)
			if( li.def.type==Entities )
				for(ei in li.entityInstances)
					if(!DrawableShape.hasMetadata(ei))
						for(stamp in ei.def.tileStamps)
							if( stampIsActive(ei,stamp) )
								paintStampAt(ei,stamp,ei.x,ei.y,touched);
		for(li in level.layerInstances)
			if( li.def.type==Entities )
				for(ei in li.entityInstances)
					trackEntity(ei);
		return touchedToArray(touched);
	}
}
