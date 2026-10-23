package ui;

import data.def.FieldDef;
import data.inst.EntityInstance;
import data.MultiEntityEdit;

/** Contextual inspector for a homogeneous entity selection. No shortcut changes. */
class MultiEntityInstanceEditor extends dn.Process {
	public static var CURRENT : Null<MultiEntityInstanceEditor>;
	var owner : Editor;
	var entities : Array<EntityInstance>;
	var jWindow : J;
	var jFields : J;
	var jError : J;
	var invalidated = false;
	var applying = false;

	static function collect(elements:Array<Null<GenericLevelElement>>) : Array<EntityInstance> {
		var out : Array<EntityInstance> = [];
		for(ge in elements)
			switch ge {
				case Entity(_,ei):
					if( out.indexOf(ei)<0 ) out.push(ei);
				case _:
			}
		return out;
	}

	public static function sync(elements:Array<Null<GenericLevelElement>>) {
		var selected = collect(elements);
		if( !MultiEntityEdit.isValid(selected) ) {
			closeExisting();
			return;
		}
		if( isOpen() && CURRENT.entities.length==selected.length ) {
			var same = true;
			for(ei in selected)
				if( CURRENT.entities.indexOf(ei)<0 ) same=false;
			if( same ) return;
		}
		closeExisting();
		EntityInstanceEditor.closeExisting();
		CURRENT = new MultiEntityInstanceEditor(selected);
	}

	public static inline function isOpen() return CURRENT!=null && !CURRENT.destroyed;
	public static function closeExisting() {
		if( isOpen() ) {
			CURRENT.jWindow.remove();
			CURRENT.destroy();
		}
		CURRENT = null;
	}

	function new(selected:Array<EntityInstance>) {
		super(Editor.ME);
		owner = Editor.ME;
		entities = selected.copy();
		jWindow = new J('<div class="entityInstanceEditor multiEntityInstanceEditor"/>');
		jWindow.css({width:"390px", maxWidth:"45vw"});
		App.ME.jPage.append(jWindow);
		var wrap = new J('<div class="entityInstanceWrapper"/>').appendTo(jWindow);
		var props = new J('<div class="propsWrapper"/>').appendTo(wrap);
		var header = new J('<header/>').appendTo(props);
		new J('<div class="id"/>').text(entities[0].def.identifier+" ("+entities.length+" selected)").appendTo(header);
		var close = new J('<button class="small gray" title="Clear selection">×</button>').appendTo(header);
		close.click(_->owner.selectionTool.clear());
		new J('<p class="multiEditHint"/>')
			.text("Editing all selected entities. — means different values. Only the edited field changes.")
			.css({fontSize:"12px",lineHeight:"1.5",opacity:"0.85",margin:"10px 0"}).appendTo(props);
		jError = new J('<div class="warning multiEditError" role="alert"/>').hide().appendTo(props);
		jFields = new J('<dl class="form fieldInstanceEditor multiFields"/>').appendTo(wrap);
		owner.ge.addGlobalListener(onGlobalEvent);
		render();
	}

	override function onDispose() {
		owner.ge.removeListener(onGlobalEvent);
		jWindow.remove();
		if( CURRENT==this ) CURRENT=null;
		super.onDispose();
	}

	override function onResize() {
		super.onResize();
		if( jWindow==null ) return;
		jWindow.css({
			left:(js.Browser.window.innerWidth-jWindow.outerWidth())+"px",
			top:Math.max(42,(js.Browser.window.innerHeight-jWindow.outerHeight())*0.5)+"px",
		});
	}

	function onGlobalEvent(ev:GlobalEvent) {
		if( destroyed || applying ) return;
		switch ev {
			case ProjectSelected, LevelSelected(_), WorldSelected(_),
				LayerInstancesRestoredFromHistory(_), LevelRestoredFromHistory(_):
				closeExisting();
			case EntityInstanceRemoved(ei):
				if( entities.indexOf(ei)>=0 ) closeExisting();
			case EntityFieldInstanceChanged(ei,_), EntityInstanceChanged(ei):
				if( entities.indexOf(ei)>=0 ) invalidated=true;
			case EntityDefChanged, FieldDefChanged(_), FieldDefRemoved(_), FieldDefSorted,
				EnumDefChanged, EnumDefRemoved, EnumDefSorted, EnumDefValueRemoved,
				ProjectSettingsChanged:
				invalidated=true;
			case _:
		}
	}

	override function update() {
		super.update();
		if( destroyed ) return;
		if( !MultiEntityEdit.isValid(entities) ) { closeExisting(); return; }
		var moving = owner.selectionTool.isRunning();
		jWindow.toggleClass("faded",moving);
		jFields.css("pointer-events",moving ? "none" : "auto");
		if( invalidated && !moving ) { invalidated=false; render(); }
	}

	function runEdit(edit:Void->Bool) {
		if( destroyed || CURRENT!=this || owner.selectionTool.isRunning() ) return;
		applying=true;
		try {
			edit();
			jError.hide().text("");
			render();
		}
		catch(e:Dynamic) {
			jError.text(Std.string(e)).show();
		}
		applying=false;
	}

	function set(fd:FieldDef, idx:Int, raw:Null<String>)
		runEdit(()->MultiEntityEdit.setValue(entities,fd.uid,idx,raw));

	function render() {
		if( !MultiEntityEdit.isValid(entities) ) { closeExisting(); return; }
		var scroll = jWindow.find(".entityInstanceWrapper").scrollTop();
		jFields.empty();
		var visibleCount = 0;
		for(fd in entities[0].def.fieldDefs) {
			if( data.DrawableShape.isEnabled(entities[0].def) && data.DrawableShape.isGeneratedField(fd) ) continue;
			var visible = true;
			for(ei in entities)
				if( !owner.project.forkConfig.isFieldVisible(ei,fd) ) visible=false;
			if( !visible ) continue;
			visibleCount++;
			var label = new J('<dt/>').appendTo(jFields);
			new J('<label/>').text(fd.identifier).appendTo(label);
			if( fd.doc!=null ) label.attr("title",fd.doc);
			var row = new J('<dd/>').attr("data-multi-field",fd.uid).appendTo(jFields);

			if( fd.type==F_EntityRef && fd.symmetricalRef ) {
				new J('<span class="multiUnsupported"/>')
					.text("Symmetrical references: edit individually.").appendTo(row);
				continue;
			}
			if( fd.isArray ) {
				var mixed = MultiEntityEdit.hasMixedLengths(entities,fd);
				var count = MultiEntityEdit.commonLength(entities,fd);
				var sizeRow = new J('<div class="multiArraySize"/>').appendTo(row);
				new J('<label/>').text("Size ").appendTo(sizeRow);
				var sizeInput = new J('<input type="text" class="multiSize"/>')
					.attr("placeholder",mixed ? "—" : "0")
					.attr("aria-label",fd.identifier+" array size")
					.css("width","65px").val(mixed ? "" : Std.string(count)).appendTo(sizeRow);
				sizeInput.change(_->{
					var raw = StringTools.trim(sizeInput.val());
					if( raw=="" && mixed ) return;
					runEdit(()->{
						if( !~/^[0-9]+$/.match(raw) || raw.length>5 ) throw "Enter a valid array size.";
						return MultiEntityEdit.resizeArray(entities,fd.uid,Std.parseInt(raw));
					});
				});
				if( mixed )
					new J('<p class="multiArrayHint"/>').text("— Different sizes; showing shared indices only.")
						.css({fontSize:"11px",opacity:"0.8"}).appendTo(row);
				for(idx in 0...count) {
					var item = new J('<div class="multiArrayItem"/>').css("margin-top","6px").appendTo(row);
					new J('<span/>').text("["+idx+"] ").appendTo(item);
					addInput(fd,idx,item);
				}
			}
			else
				addInput(fd,0,row);
		}
		if( visibleCount==0 )
			new J('<p/>').text("No common editable fields.").appendTo(jFields);
		jWindow.find(".entityInstanceWrapper").scrollTop(scroll);
		onResize();
	}

	function addInput(fd:FieldDef, idx:Int, row:J) {
		var fi = entities[0].getFieldInstance(fd,true);
		var mixed = MultiEntityEdit.isMixed(entities,fd,idx);
		var id = "multi_field_"+fd.uid+"_"+idx;
		row.attr("data-mixed",mixed ? "true" : "false");
		if( mixed ) row.attr("title","Different values (—). A new value applies to all "+entities.length+" selected entities.");

		switch fd.type {
			case F_Bool:
				var input = new J('<input type="checkbox" class="multiValue"/>')
					.attr("id",id).attr("aria-label",fd.identifier).appendTo(row);
				input.prop("checked",mixed ? false : fi.getBool(idx));
				input.prop("indeterminate",mixed);
				if( mixed ) new J('<span class="mixedValue"/>').text(" — ").appendTo(row);
				input.change(_->set(fd,idx,input.prop("checked") ? "true" : "false"));
			case F_Enum(uid):
				var select = new J('<select class="multiValue"/>').attr("id",id).appendTo(row);
				var initial = mixed ? "__mixed__" : fi.getEnumValue(idx);
				if( mixed ) new J('<option value="__mixed__" disabled/>').text("—").appendTo(select);
				if( fd.canBeNull ) new J('<option value="__null__"/>').text("(default / null)").appendTo(select);
				for(v in fd.getEnumDefinition().values) {
					var allowed = true;
					for(ei in entities)
						if( !owner.project.forkConfig.isEnumValueAllowed(ei,fd,v.id) ) allowed=false;
					if( allowed )
						new J('<option/>').attr("value",v.id).text(v.id).appendTo(select);
				}
				select.val(initial==null ? "__null__" : initial);
				select.change(_->{
					var v = select.val();
					if( v!="__mixed__" ) set(fd,idx,v=="__null__" ? null : v);
				});
			case F_EntityRef:
				// A dropdown preserves the multi-selection, unlike a scene pick
				// which can switch levels or replace the selection mid-transaction.
				var select = new J('<select class="multiValue"/>').attr("id",id).appendTo(row);
				if( mixed ) new J('<option value="__mixed__" disabled/>').text("—").appendTo(select);
				if( fd.canBeNull ) new J('<option value="__null__"/>').text("(none)").appendTo(select);
				for(w in owner.project.worlds)
				for(l in w.levels)
				for(li in l.layerInstances)
				for(target in li.entityInstances)
					if( MultiEntityEdit.canReference(entities,fd,target,idx) )
						new J('<option/>').attr("value",target.iid)
							.text(target.def.identifier+" @"+target.x+","+target.y+" · "+l.identifier).appendTo(select);
				var value = fi.getEntityRefIid(idx);
				select.val(mixed ? "__mixed__" : value==null ? "__null__" : value);
				select.change(_->{
					var v = select.val();
					if( v!=null && v!="__mixed__" ) set(fd,idx,v=="__null__" ? null : v);
				});
			case F_Tile:
				if( mixed ) new J('<span class="mixedValue"/>').text("— ").appendTo(row);
				var td = owner.project.defs.getTilesetDef(fd.tilesetUid);
				if( td==null || !td.isAtlasLoaded() )
					new J('<span/>').text("Tileset unavailable").appendTo(row);
				else
					JsTools.createTileRectPicker(fd.tilesetUid,mixed ? null : fi.getTileRectObj(idx),r->{
						if( r!=null ) set(fd,idx,'${r.x},${r.y},${r.w},${r.h}');
					}).attr("id",id).appendTo(row);
			case _:
				var display : String = switch fd.type {
					case F_String, F_Text: fi.getString(idx);
					case F_Path: fi.getFilePath(idx);
					case F_Point: fi.getPointStr(idx);
					case F_Color: fi.getColorAsHexStr(idx);
					case _: Std.string(MultiEntityEdit.getValue(entities[0],fd,idx));
				}
				if( display==null || display=="null" && fd.type!=F_String && fd.type!=F_Text ) display="";
				var initial = mixed ? "" : display;
				var input = new J(fd.type==F_Text ? '<textarea class="multiValue"/>' : '<input type="text" class="multiValue"/>')
					.attr("id",id).attr("aria-label",fd.identifier)
					.attr("placeholder",mixed ? "—" : "(default / null)")
					.val(initial).appendTo(row);
				if( fd.type==F_Text ) input.attr("rows",3);
				if( fd.type==F_Point ) input.attr("title","Grid coordinates: x,y");
				var typed = false;
				input.on("input",_->typed=true);
				input.change(_->{
					var v:String = input.val();
					// The placeholder is presentation only. Blur/no-op never sets
					// all targets to null, zero, false, or the first entity's value.
					if( !typed && v==initial ) return;
					if( mixed && v=="" && !typed ) return;
					typed=false;
					set(fd,idx,v);
				});
				input.on("keydown",ev->{
					if( ev.keyCode==27 ) {
						ev.preventDefault(); ev.stopPropagation();
						typed=false; input.val(initial); input.blur();
					}
					else if( ev.keyCode==13 && fd.type!=F_Text ) {
						ev.preventDefault(); input.change();
					}
				});
				if( fd.type==F_Color ) {
					var color = new J('<input type="color" class="multiColor"/>')
						.attr("aria-label",fd.identifier+" color picker")
						.val(mixed ? "#808080" : display).css({width:"28px",padding:"0"}).appendTo(row);
					color.change(_->set(fd,idx,color.val()));
				}
				if( fd.type==F_Path ) {
					var browse = new J('<button class="small gray">…</button>').appendTo(row);
					browse.click(_->dn.js.ElectronDialogs.openFile(fd.acceptFileTypes,owner.project.getProjectDir(),path->{
						set(fd,idx,owner.project.makeRelativeFilePath(path));
					}));
				}
		}
		var reset = new J('<button class="transparent small multiReset" title="Reset this value to its default on all selected entities">↶</button>')
			.attr("aria-label","Reset "+fd.identifier).appendTo(row);
		reset.click(_->set(fd,idx,null));
	}
}
