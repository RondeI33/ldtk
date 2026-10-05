package ui;

/** Typed adapter between the isolated template draft and LDtk's field serializers. */
class TemplateEditorBridge {
	public static inline function clone(v:Dynamic):Dynamic return haxe.Json.parse(haxe.Json.stringify(v));
	public static function array(o:Dynamic, k:String):Array<Dynamic> {
		var v = Reflect.field(o,k);
		return v==null ? [] : cast v;
	}
	public static function entity(raw:Dynamic):data.inst.EntityInstance {
		var p = Editor.ME.project;
		var li = Editor.ME.curLevel.getLayerInstance(Std.int(raw.layerDefUid));
		if( li==null || p.defs.getEntityDef(Std.int(raw.json.defUid))==null )
			throw "The entity or layer definition used by this template no longer exists.";
		var json:Dynamic = clone(raw.json);
		json.iid = "template-draft-"+raw.sourceIid;
		json.px = [Std.int(raw.relX),Std.int(raw.relY)];
		return data.inst.EntityInstance.fromJson(p,li,cast json);
	}
	public static function fieldInfo(raw:Dynamic):Array<Dynamic> {
		var ei = entity(raw);
		var out:Array<Dynamic> = [];
		for(fd in ei.def.fieldDefs) {
			var fi = ei.getFieldInstance(fd,true);
			var values:Array<Dynamic> = [];
			var defaults:Array<Bool> = [];
			var full:Dynamic = fi.getFullJsonValue();
			for(i in 0...fi.getArrayLength()) {
				defaults.push(fi.isUsingDefault(i));
				if( fd.type==F_EntityRef ) {
					var refs:Dynamic = null;
					for(r in array(raw,"refs")) if( r.fieldDefUid==fd.uid ) refs=r;
					values.push(refs==null ? null : array(refs,"values")[i]);
				}
				else if( fd.type==F_Point ) {
					var pt:Dynamic = null;
					for(f in array(raw,"points")) if( f.fieldDefUid==fd.uid )
						for(v in array(f,"values")) if( v.idx==i ) pt={x:v.relX,y:v.relY};
					values.push(pt);
				}
				else values.push(fd.isArray ? (cast full:Array<Dynamic>)[i] : full);
			}
			var options:Array<String> = [];
			switch fd.type {
				case F_Enum(uid):
					var ed=ei._project.defs.getEnumDef(uid);
					if(ed!=null) for(v in ed.values) options.push(v.id);
				case _:
			}
			out.push({uid:fd.uid,name:fd.identifier,type:fd.type.getName(),isArray:fd.isArray,
				canBeNull:fd.canBeNull,values:values,defaults:defaults,options:options,
				min:fd.min,max:fd.max,minLength:fd.arrayMinLength,maxLength:fd.arrayMaxLength});
		}
		return out;
	}
	public static function changeField(raw:Dynamic, uid:Int, idx:Int, value:Dynamic, action:String):Void {
		var ei=entity(raw);
		var fd=ei.def.getFieldDef(uid);
		if(fd==null) throw "Field definition no longer exists.";
		var fi=ei.getFieldInstance(fd,true);
		if(action=="add") fi.addArrayValue();
		else if(action=="remove") fi.removeArrayValue(idx);
		else if(action=="reset") fi.parseValue(idx,null);
		else if(fd.type==F_Point) fi.parseValue(idx,"0"+Const.POINT_SEPARATOR+"0");
		else fi.parseValue(idx,value==null ? null : Std.string(value));
		var fjs:Array<Dynamic>=cast raw.json.fieldInstances;
		var replaced=false;
		for(i in 0...fjs.length) if(fjs[i].defUid==uid) { fjs[i]=fi.toJson(); replaced=true; }
		if(!replaced) fjs.push(fi.toJson());
		if(fd.type==F_EntityRef) {
			if(raw.refs==null) raw.refs=[];
			var r:Dynamic=null;
			for(f in array(raw,"refs")) if(f.fieldDefUid==uid) r=f;
			if(r==null) { r={fieldDefUid:uid,values:[]}; (cast raw.refs:Array<Dynamic>).push(r); }
			var values=array(r,"values");
			if(action=="add") values.push(null);
			else if(action=="remove") values.splice(idx,1);
			else values[idx]=action=="reset" ? null : value;
		}
		if(fd.type==F_Point) {
			if(raw.points==null) raw.points=[];
			var f:Dynamic=null;
			for(v in array(raw,"points")) if(v.fieldDefUid==uid) f=v;
			if(f==null) { f={fieldDefUid:uid,values:[]}; (cast raw.points:Array<Dynamic>).push(f); }
			var values=array(f,"values");
			if(action!="add") {
				f.values=values.filter(v->v.idx!=idx);
				if(action=="remove") { for(v in array(f,"values")) if(v.idx>idx) v.idx--; }
				else if(action=="set" && value!=null)
					(cast f.values:Array<Dynamic>).push({idx:idx,relX:value.x,relY:value.y});
			}
		}
	}
	public static function catalog(tpl:Dynamic):Array<Dynamic> {
		var p=Editor.ME.project;
		var used:Map<Int,Bool>=new Map();
		for(r in array(tpl,"entities")) {
			used.set(Std.int(r.layerDefUid),true);
			var ed=p.defs.getEntityDef(Std.int(r.json.defUid));
			if(ed!=null) for(s in ed.tileStamps) if(s.layerDefUid!=null) used.set(Std.int(s.layerDefUid),true);
		}
		for(c in array(tpl,"cells")) used.set(Std.int(c.layerDefUid),true);
		for(ld in p.defs.layers) if(ld.type==AutoLayer && ld.autoSourceLayerDefUid!=null && used.exists(ld.autoSourceLayerDefUid)) used.set(ld.uid,true);
		var out:Array<Dynamic>=[];
		for(ld in p.defs.layers) if(used.exists(ld.uid)) {
			out.push({uid:ld.uid,name:ld.identifier,type:Std.string(ld.type),grid:ld.gridSize,
				source:ld.autoSourceLayerDefUid,order:p.defs.layers.indexOf(ld)});
			used.remove(ld.uid);
		}
		for(uid in used.keys()) out.push({uid:uid,name:"Missing layer #"+uid,type:"Missing",grid:16,source:null,order:999});
		return out;
	}
	public static function entityImage(raw:Dynamic):Dynamic {
		var ei=entity(raw);
		var core=display.EntityRender.renderCore(ei);
		var bounds=core.wrapper.getBounds();
		var left=Math.floor(bounds.xMin)-2, top=Math.floor(bounds.yMin)-2;
		var w=M.imax(1,Math.ceil(bounds.width)+4), h=M.imax(1,Math.ceil(bounds.height)+4);
		// Preview uses the actual renderer, with a bounded texture for oversized entities.
		var scale=M.fmin(1,512/M.imax(w,h));
		var root=new h2d.Object();
		var transform=new h2d.Object(root);
		transform.setScale(scale);
		transform.addChild(core.wrapper);
		core.wrapper.setPosition(-left,-top);
		var tex=new h3d.mat.Texture(M.imax(1,Math.ceil(w*scale)),M.imax(1,Math.ceil(h*scale)),[Target]);
		tex.clear(0);
		root.drawTo(tex);
		var px=tex.capturePixels();
		var url="data:image/png;base64,"+haxe.crypto.Base64.encode(px.toPNG());
		px.dispose(); tex.dispose(); root.removeChildren();
		return {url:url,left:left,top:top,width:w,height:h,entityWidth:ei.width,entityHeight:ei.height,pivotX:ei.pivotX,pivotY:ei.pivotY};
	}
	public static function cellImage(cell:Dynamic):Dynamic {
		var li=Editor.ME.curLevel.getLayerInstance(Std.int(cell.layerDefUid));
		if(li==null) return null;
		if(cell.kind=="intgrid") return {color:C.intToHex(li.def.getIntGridValueColor(Std.int(cell.value)))};
		var td=li.getTilesetDef();
		if(td==null) return null;
		td.getAtlasTile();
		var tiles:Array<Dynamic>=[];
		for(t in array(cell,"tiles")) {
			var j=td.createTileHtmlImageFromTileId(Std.int(t.tileId));
			tiles.push({url:j.attr("src"),flips:t.flips});
		}
		return {tiles:tiles};
	}
}
