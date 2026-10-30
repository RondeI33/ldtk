package camerapreview;

typedef CameraPreviewProfile = {
	var width:Float;
	var height:Float;
	var orthographicSize:Float;
	var aspect:Float;
	var pixelsPerUnit:Float;
	var sceneName:String;
	var scenePath:String;
	var cameraName:String;
	var updatedAtUtc:String;
	var source:String;
	var live:Bool;
}

typedef CameraPreviewParseResult = {
	var profile:Null<CameraPreviewProfile>;
	var error:Null<String>;
}

typedef CameraPreviewFrame = {
	var x:Float;
	var y:Float;
	var width:Float;
	var height:Float;
	var centerX:Float;
	var centerY:Float;
	/** Integral floats preserve cell indices outside the signed 32-bit range. */
	var column:Null<Float>;
	var row:Null<Float>;
}

/** Pure projection/placement calculations: no editor state or project writes. */
class CameraPreviewGeometry {
	public static inline var SCHEMA_VERSION = 1;
	public static inline var MAX_DIMENSION = 10000000.;

	static function failure(message:String):CameraPreviewParseResult {
		return {profile:null,error:message};
	}

	static function isNumber(value:Dynamic):Bool {
		return switch Type.typeof(value) {
			case TInt, TFloat: Math.isFinite(cast value);
			case _: false;
		};
	}

	static function isObject(value:Dynamic):Bool {
		return value!=null && Reflect.isObject(value)
			&& !Std.isOfType(value,Array) && !Std.isOfType(value,String);
	}

	static function stringOrEmpty(value:Dynamic):String {
		return value==null ? "" : cast value;
	}

	/**
	 * Read a Unity snapshot without coercing strings, booleans, or missing values
	 * into camera dimensions. A bad/incomplete write is a result, not an exception.
	 */
	public static function parse(raw:String):CameraPreviewParseResult {
		if( raw==null || StringTools.trim(raw).length==0 )
			return failure("Unity camera snapshot is empty.");
		var data:Dynamic;
		try data = haxe.Json.parse(raw)
		catch(_:Dynamic) return failure("Unity camera snapshot is not valid JSON.");
		if( !isObject(data) )
			return failure("Unity camera snapshot must be a JSON object.");

		if( !isNumber(data.schemaVersion) || data.schemaVersion!=SCHEMA_VERSION )
			return failure("Unsupported Unity camera snapshot version (expected 1).");
		if( !Std.isOfType(data.source,String) || data.source!="unity" )
			return failure("Camera snapshot source must be Unity.");
		if( !Std.isOfType(data.valid,Bool) )
			return failure("Unity camera snapshot is missing its valid flag.");
		if( data.valid==false ) {
			if( Std.isOfType(data.error,String) && StringTools.trim(data.error).length>0 )
				return failure(data.error);
			return failure("The active Unity scene has no supported camera snapshot.");
		}
		if( !Std.isOfType(data.orthographic,Bool) )
			return failure("Unity camera snapshot is missing its orthographic flag.");
		if( data.orthographic==false )
			return failure("Camera preview requires an orthographic Unity camera.");

		for(key in ["orthographicSize","aspect","pixelsPerUnit"]) {
			var value = Reflect.field(data,key);
			if( !isNumber(value) || (cast value:Float)<=0 )
				return failure("Unity camera "+key+" must be a finite positive number.");
		}
		for(key in ["sceneName","scenePath","cameraName","updatedAtUtc","error"])
			if( Reflect.hasField(data,key) && !Std.isOfType(Reflect.field(data,key),String) )
				return failure("Unity camera "+key+" must be a string.");
		if( Reflect.hasField(data,"live") && !Std.isOfType(data.live,Bool) )
			return failure("Unity camera live flag must be a boolean.");

		var size:Float = data.orthographicSize;
		var aspect:Float = data.aspect;
		var ppu:Float = data.pixelsPerUnit;
		var height = size*ppu*2;
		var width = height*aspect;
		if( !validDimension(width) || !validDimension(height) )
			return failure("Unity camera dimensions must be greater than zero and at most 10,000,000 level pixels.");

		return {error:null,profile:{
			width:width,height:height,orthographicSize:size,aspect:aspect,pixelsPerUnit:ppu,
			sceneName:stringOrEmpty(data.sceneName),scenePath:stringOrEmpty(data.scenePath),
			cameraName:stringOrEmpty(data.cameraName),updatedAtUtc:stringOrEmpty(data.updatedAtUtc),
			source:"unity",live:data.live==true,
		}};
	}

	static inline function validDimension(value:Float):Bool {
		return Math.isFinite(value) && value>0 && value<=MAX_DIMENSION;
	}

	/**
	 * Free mode centers the frame at the exact level point. Grid mode uses the
	 * containing cell's center, with a top-left grid origin and independent steps.
	 * A frame may extend outside the room: its projection is never cropped/clamped.
	 */
	public static function frame(pointX:Float,pointY:Float,width:Float,height:Float,gridMode:Bool,
		?gridWidth:Float,?gridHeight:Float,?originX:Float,?originY:Float):CameraPreviewFrame {
		if( !Math.isFinite(pointX) || !Math.isFinite(pointY) )
			throw "Camera preview point must be finite.";
		if( !validDimension(width) || !validDimension(height) )
			throw "Camera preview dimensions are invalid.";
		var centerX = pointX;
		var centerY = pointY;
		var column:Null<Float> = null;
		var row:Null<Float> = null;
		if( gridMode ) {
			var stepX:Float = gridWidth==null ? width : gridWidth;
			var stepY:Float = gridHeight==null ? height : gridHeight;
			var left:Float = originX==null ? 0 : originX;
			var top:Float = originY==null ? 0 : originY;
			if( !validDimension(stepX) || !validDimension(stepY) )
				throw "Camera preview grid dimensions are invalid.";
			if( !Math.isFinite(left) || !Math.isFinite(top) )
				throw "Camera preview grid origin must be finite.";
			column = Math.ffloor((pointX-left)/stepX);
			row = Math.ffloor((pointY-top)/stepY);
			centerX = left+(column+0.5)*stepX;
			centerY = top+(row+0.5)*stepY;
			if( !Math.isFinite(column) || !Math.isFinite(row) || !Math.isFinite(centerX) || !Math.isFinite(centerY) )
				throw "Camera preview grid coordinates exceed the supported numeric range.";
		}
		var x = centerX-width*0.5;
		var y = centerY-height*0.5;
		if( !Math.isFinite(x) || !Math.isFinite(y) )
			throw "Camera preview frame exceeds the supported numeric range.";
		return {x:x,y:y,width:width,height:height,centerX:centerX,centerY:centerY,column:column,row:row};
	}
}
