package data;

import pathpreview.PathPreviewGeometry;
import pathpreview.PathPreviewGeometry.PathPreviewMode;
import pathpreview.PathPreviewGeometry.PathPreviewPoint;

typedef ResolvedPathPreview = {
	var geometry : PathPreviewGeometry;
	var unitPx : Float;
	var blockColor : Int;
	var overlapColor : Int;
	var pathField : data.def.FieldDef;
}

/** Logical layer pixels from selection ghosts; never written back to the instance. */
typedef PathPreviewOverrides = {
	var ?pivotPx : PathPreviewPoint;
	var ?pointPx : Map<Int,PathPreviewPoint>;
	var ?pathPx : Array<PathPreviewPoint>;
}

/** Converts the sidecar and existing instance values into a read-only drawing description. */
class PathPreviewConfig {
	static function get(raw:Dynamic, key:String) : Dynamic {
		return raw==null ? null : Reflect.field(raw,key);
	}

	static function number(value:Dynamic, fallback:Float) : Float {
		if( value==null )
			return fallback;
		var v = Std.parseFloat(Std.string(value));
		return Math.isFinite(v) ? v : fallback;
	}

	static function field(ei:data.inst.EntityInstance, binding:Dynamic) : Null<data.def.FieldDef> {
		if( binding==null )
			return null;
		var uid = Std.parseInt(Std.string(get(binding,"fieldUid")));
		var fd = uid==null ? null : ei.def.getFieldDef(uid);
		if( fd!=null )
			return fd;
		var id = get(binding,"fieldIdentifier");
		if( Std.isOfType(id,String) )
			for(candidate in ei.def.fieldDefs)
				if( candidate.identifier==id )
					return candidate;
		return null;
	}

	static function value(ei:data.inst.EntityInstance, binding:Dynamic) : Dynamic {
		var fd = field(ei,binding);
		if( fd==null || fd.isArray )
			return null;
		// false is essential: rendering must not create serialized field instances.
		var fi = ei.getFieldInstance(fd,false);
		return fi==null ? fd.getDefault() : fi.getFullJsonValue();
	}

	static function color(raw:Dynamic, fallback:Int) : Int {
		if( !Std.isOfType(raw,String) || !~/^#[0-9a-fA-F]{6}$/.match(raw) )
			return fallback;
		return Std.parseInt("0x"+Std.string(raw).substr(1));
	}

	static function modeValue(binding:Dynamic, key:String, fallback:String) : String {
		var v = get(binding,key);
		return Std.isOfType(v,String) ? cast v : fallback;
	}

	public static function resolve(ei:data.inst.EntityInstance, raw:Dynamic, ?overrides:PathPreviewOverrides) : Null<ResolvedPathPreview> {
		var pathField = field(ei,get(raw,"path"));
		if( pathField==null || pathField.type!=F_Point || !pathField.isArray || ei._li==null )
			return null;

		var unitPx = number(get(raw,"unitPx"),ei._li.def.gridSize);
		if( unitPx<=0 )
			unitPx = ei._li.def.gridSize;
		var pivot = overrides==null || overrides.pivotPx==null ? {x:ei.x*1.0,y:ei.y*1.0} : overrides.pivotPx;
		var points : Array<PathPreviewPoint> = [{x:pivot.x/unitPx,y:pivot.y/unitPx}];
		var fi = ei.getFieldInstance(pathField,false);
		if( overrides!=null && overrides.pathPx!=null )
			for(point in overrides.pathPx)
				points.push({x:point.x/unitPx,y:point.y/unitPx});
		else if( fi!=null )
			for(i in 0...fi.getArrayLength()) {
				var moved = overrides==null || overrides.pointPx==null ? null : overrides.pointPx.get(i);
				if( moved!=null ) {
					points.push({x:moved.x/unitPx,y:moved.y/unitPx});
					continue;
				}
				var pt = fi.getPointGrid(i);
				if( pt!=null )
					points.push({
						x:(pt.cx+0.5)*ei._li.def.gridSize/unitPx,
						y:(pt.cy+0.5)*ei._li.def.gridSize/unitPx,
					});
			}

		var modeBinding = get(raw,"mode");
		var selectedMode = value(ei,modeBinding);
		var mode : PathPreviewMode = Loop;
		if( selectedMode==modeValue(modeBinding,"teleportValue","Teleport") )
			mode = Teleport;
		else if( selectedMode==modeValue(modeBinding,"pingPongValue","PingPong") )
			mode = PingPong;

		return {
			geometry: new PathPreviewGeometry(points, {
				mode:mode,
				blockCount:Std.int(Math.max(1,number(value(ei,get(raw,"blockCount")),1))),
				blockWidth:Math.max(0,number(value(ei,get(raw,"blockWidth")),1)),
				blockHeight:Math.max(0,number(value(ei,get(raw,"blockHeight")),1)),
				gap:number(value(ei,get(raw,"gap")),0),
				evenSpacing:value(ei,get(raw,"evenSpacing"))==true,
				startOffset:number(value(ei,get(raw,"startOffset")),0),
			}),
			unitPx:unitPx,
			blockColor:color(get(raw,"blockColor"),ei.def.color),
			overlapColor:color(get(raw,"overlapColor"),0xff3030),
			pathField:pathField,
		};
	}
}
