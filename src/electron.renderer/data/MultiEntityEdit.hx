package data;

import data.inst.EntityInstance;
import data.inst.FieldInstance;
import data.def.FieldDef;

/**
 * A multi-edit changes only the explicitly edited field/index. Values are parsed
 * into detached candidates before any live data changes, then saved together.
 */
@:keep
@:access(data.inst.FieldInstance)
class MultiEntityEdit {
	public static function isValid(entities:Array<EntityInstance>) : Bool {
		if( entities==null || entities.length<2 || !Editor.exists() )
			return false;
		var p = Editor.ME.project;
		var first = entities[0];
		if( first==null || first.def==null )
			return false;
		var seen = new Map<String,Bool>();
		for(ei in entities) {
			if( ei==null || ei._project!=p || ei.defUid!=first.defUid
				|| ei._li==null || ei._li.level!=Editor.ME.curLevel
				|| ei._li.level.getLayerInstance(ei._li.layerDefUid)!=ei._li
				|| !ei._li.containsEntity(ei) || seen.exists(ei.iid) )
				return false;
			seen.set(ei.iid,true);
		}
		return true;
	}

	static function requireField(entities:Array<EntityInstance>, uid:Int) : FieldDef {
		if( !isValid(entities) )
			throw "The selection changed. Select entities of one type in the current level.";
		var fd = entities[0].def.getFieldDef(uid);
		if( fd==null )
			throw "This field no longer exists.";
		for(ei in entities)
			if( !ei._project.forkConfig.isFieldVisible(ei,fd) )
				throw "This field is not available on every selected entity.";
		// Many-to-one symmetric links can overwrite one another's back-links.
		// Never silently break them while editing several entities.
		if( fd.type==F_EntityRef && fd.symmetricalRef )
			throw "Symmetrical references must be edited individually.";
		return fd;
	}

	public static function getValue(ei:EntityInstance, fd:FieldDef, idx:Int) : Dynamic {
		var fi = ei.getFieldInstance(fd,true);
		return fi.getJsonValue(idx);
	}

	public static function isMixed(entities:Array<EntityInstance>, fd:FieldDef, idx:Int) : Bool {
		var first = haxe.Json.stringify(getValue(entities[0],fd,idx));
		for(ei in entities)
			if( haxe.Json.stringify(getValue(ei,fd,idx))!=first )
				return true;
		return false;
	}

	public static function commonLength(entities:Array<EntityInstance>, fd:FieldDef) : Int {
		var n = entities[0].getFieldInstance(fd,true).getArrayLength();
		for(ei in entities)
			n = M.imin(n,ei.getFieldInstance(fd,true).getArrayLength());
		return n;
	}

	public static function hasMixedLengths(entities:Array<EntityInstance>, fd:FieldDef) : Bool {
		var n = entities[0].getFieldInstance(fd,true).getArrayLength();
		for(ei in entities)
			if( ei.getFieldInstance(fd,true).getArrayLength()!=n )
				return true;
		return false;
	}

	public static function canReference(entities:Array<EntityInstance>, fd:FieldDef, target:EntityInstance, idx:Int) : Bool {
		if( target==null || target._li==null || !target._li.containsEntity(target) )
			return false;
		for(ei in entities) {
			if( target==ei || !fd.acceptsEntityRefTo(ei,target.def,target._li.level) )
				return false;
			var fi = ei.getFieldInstance(fd,true);
			// Preserve the native rule against duplicate references in an array.
			for(i in 0...fi.getArrayLength())
				if( i!=idx && fi.getEntityRefIid(i)==target.iid )
					return false;
		}
		return true;
	}

	static function validateRaw(entities:Array<EntityInstance>, fd:FieldDef, idx:Int, raw:Null<String>) {
		if( raw==null )
			return; // An explicit Reset, never the visual mixed-value marker.
		switch fd.type {
			case F_Int, F_Float:
				var text = StringTools.trim(raw);
				var valid = fd.type==F_Int
					? ~/^[+-]?[0-9]+$/.match(text)
					: ~/^[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?$/.match(text);
				var n = Std.parseFloat(text);
				if( !valid || !Math.isFinite(n)
					|| fd.type==F_Int && (n< -2147483648. || n>2147483647.) )
					throw "Enter a valid number.";
				if( fd.min!=null && n<fd.min || fd.max!=null && n>fd.max )
					throw "Value is outside this field's allowed range.";
			case F_Bool:
				if( raw!="true" && raw!="false" )
					throw "Choose true or false.";
			case F_Color:
				if( !~/^#[0-9a-fA-F]{6}$/.match(raw) )
					throw "Enter a color in #RRGGBB format.";
			case F_Enum(uid):
				if( !fd.getEnumDefinition().hasValue(raw) )
					throw "Choose a valid enum value.";
				for(ei in entities)
					if( !ei._project.forkConfig.isEnumValueAllowed(ei,fd,raw) )
						throw "This enum value is not allowed for every selected entity.";
			case F_Point:
				if( !~/^-?[0-9]+,-?[0-9]+$/.match(raw) )
					throw "Enter grid coordinates as x,y.";
			case F_EntityRef:
				var target = Editor.ME.project.getEntityInstanceByIid(raw);
				if( !canReference(entities,fd,target,idx) )
					throw "This reference is not valid for every selected entity.";
			case F_Tile:
				if( !~/^[0-9]+,[0-9]+,[0-9]+,[0-9]+$/.match(raw) )
					throw "Choose a tile rectangle.";
				var td = Editor.ME.project.defs.getTilesetDef(fd.tilesetUid);
				var v = raw.split(",").map(s->Std.parseInt(s));
				if( td==null || v[2]<=0 || v[3]<=0 || v[0]+v[2]>td.pxWid || v[1]+v[3]>td.pxHei )
					throw "Tile rectangle is outside the tileset.";
			case F_String, F_Text, F_Path:
		}
	}

	static function copyField(fi:FieldInstance) : FieldInstance {
		return FieldInstance.fromJson(fi._project,haxe.Json.parse(haxe.Json.stringify(fi.toJson())));
	}

	public static function setValue(entities:Array<EntityInstance>, uid:Int, idx:Int, raw:Null<String>) : Bool {
		var fd = requireField(entities,uid);
		if( idx<0 || idx>=commonLength(entities,fd) )
			throw "This array index does not exist on every selected entity.";
		validateRaw(entities,fd,idx,raw);
		var candidates : Array<FieldInstance> = [];
		for(ei in entities) {
			var fi = copyField(ei.getFieldInstance(fd,true));
			fi.parseValue(idx,raw);
			candidates.push(fi);
		}
		return commit(entities,fd,candidates);
	}

	public static function resizeArray(entities:Array<EntityInstance>, uid:Int, size:Int) : Bool {
		var fd = requireField(entities,uid);
		if( !fd.isArray || size<0 || size>10000
			|| fd.arrayMinLength!=null && size<fd.arrayMinLength
			|| fd.arrayMaxLength!=null && size>fd.arrayMaxLength )
			throw "Array size is outside the allowed range.";
		var candidates : Array<FieldInstance> = [];
		for(ei in entities) {
			var fi = copyField(ei.getFieldInstance(fd,true));
			while( fi.getArrayLength()>size ) fi.removeLastArrayValue();
			while( fi.getArrayLength()<size ) fi.addArrayValue();
			candidates.push(fi);
		}
		return commit(entities,fd,candidates);
	}

	static function commit(entities:Array<EntityInstance>, fd:FieldDef, candidates:Array<FieldInstance>) : Bool {
		var editor = Editor.ME;
		var p = editor.project;
		var changed : Array<EntityInstance> = [];
		for(i in 0...entities.length)
			if( haxe.Json.stringify(entities[i].getFieldInstance(fd,true).toJson().realEditorValues)
				!=haxe.Json.stringify(candidates[i].toJson().realEditorValues) )
				changed.push(entities[i]);
		if( changed.length==0 )
			return false; // Do not consume Undo or truncate Redo on a no-op.

		// Establish history and stamp baselines BEFORE the first mutation.
		var timeline = editor.ensureLevelTimeline(editor.curLevel);
		for(ei in changed) {
			timeline.markEntityChange(ei);
			p.forkConfig.trackEntity(ei);
		}
		for(i in 0...entities.length)
			if( changed.indexOf(entities[i])>=0 )
				entities[i].fieldInstances.set(fd.uid,candidates[i]);

		if( fd.type==F_EntityRef )
			p.initEntityIidsCache(); // Rebuild both directions; retain unrelated links.

		var layers : Array<data.inst.LayerInstance> = [];
		for(ei in changed) {
			if( layers.indexOf(ei._li)<0 ) layers.push(ei._li);
			for(li in p.forkConfig.syncTrackedEntity(ei))
				if( layers.indexOf(li)<0 ) layers.push(li);
			timeline.markEntityChange(ei);
		}
		for(li in layers) {
			editor.invalidateLevelCache(li.level);
			editor.levelRender.invalidateLayer(li);
		}
		timeline.saveLayerStates(layers); // One transaction across all affected layers.
		editor.needSaving = true;
		editor.selectionTool.invalidateRender();
		for(ei in changed)
			editor.ge.emit(EntityFieldInstanceChanged(ei,ei.getFieldInstance(fd,true)));
		return true;
	}
}
