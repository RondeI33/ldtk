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
	/** Optional Unity-authored stationary camera model, never written by the editor. */
	var unityCameraModel:Null<Dynamic>;
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

		var model:Dynamic = Reflect.field(data,"unityCameraModel");
		if( model!=null && (!isObject(model) || !isNumber(Reflect.field(model,"schemaVersion")) || Reflect.field(model,"schemaVersion")!=1) )
			return failure("Unsupported unityCameraModel version (expected 1).");

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
			source:"unity",live:data.live==true,unityCameraModel:model,
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

	static function member(source:Dynamic,key:String):Dynamic {
		return isObject(source) ? Reflect.field(source,key) : null;
	}

	static function finite(source:Dynamic,key:String,fallback:Float):Float {
		var raw = member(source,key);
		if( !isObject(source) || !Reflect.hasField(source,key) ) return fallback;
		if( !isNumber(raw) ) throw "Invalid camera model number: "+key;
		return cast raw;
	}

	static function pickLevel(model:Dynamic,iid:String):Dynamic {
		var levels=member(model,"levels"), found:Dynamic=null;
		if( levels!=null && !Std.isOfType(levels,Array) ) throw "Camera model levels must be an array.";
		if( Std.isOfType(levels,Array) ) {
			for( entry in (cast levels:Array<Dynamic>) ) {
				if( !isObject(entry) ) throw "Invalid camera model level.";
				if( member(entry,"iid")==iid || member(entry,"levelIid")==iid || member(entry,"ldtkLevelIid")==iid ) {
					if( found!=null ) throw "Duplicate camera model level IID: "+iid;
					found=entry;
				}
			}
		}
		var byIid=member(model,"levelsByIid");
		if( byIid!=null && !isObject(byIid) ) throw "Camera model levelsByIid must be an object.";
		var entry=member(byIid,iid);
		if( entry!=null ) {
			if( found!=null || !isObject(entry) ) throw "Ambiguous or invalid camera model level IID: "+iid;
			found=entry;
		}
		if( found==null ) throw "Unity camera model has no supported mapping for level IID "+iid+". Export this level from Unity.";
		return found;
	}

	static function rectOf(value:Dynamic):Dynamic {
		var bounds = member(value,"bounds");
		return bounds==null ? value : bounds;
	}

	static function rectContains(rect:Dynamic,x:Float,y:Float):Bool {
		if( !isObject(rect) ) return false;
		var left=finite(rect,"minX",finite(rect,"x",Math.NaN));
		var top=finite(rect,"minY",finite(rect,"y",Math.NaN));
		var right=finite(rect,"maxX",left+finite(rect,"width",Math.NaN));
		var bottom=finite(rect,"maxY",top+finite(rect,"height",Math.NaN));
		if( !Math.isFinite(left) || !Math.isFinite(top) || !Math.isFinite(right) || !Math.isFinite(bottom) || right<=left || bottom<=top )
			throw "Camera model room/zone has invalid or unsupported bounds.";
		return x>=left && x<=right && y>=top && y<=bottom;
	}

	static function containing(list:Dynamic,x:Float,y:Float):Dynamic {
		if( list==null ) return null;
		if( !Std.isOfType(list,Array) ) throw "Camera model rooms/zones must be arrays.";
		var result:Dynamic=null, priority=Math.NEGATIVE_INFINITY;
		for( item in (cast list:Array<Dynamic>) ) {
			if( !isObject(item) ) throw "Invalid camera room/zone.";
			if( member(item,"enabled")==false ) continue;
			var p=finite(item,"priority",0.);
			if( rectContains(rectOf(item),x,y) && (result==null || p>priority) ) { result=item;priority=p; }
		}
		return result;
	}

	static function rejectUnknownMapping(source:Dynamic) {
		// Never silently treat an unfamiliar Unity-world mapping as LDtk pixels.
		// The original Unity reference fixture is required to implement these shapes.
		for( key in ["coordinateMapping","mapping","worldToLdtk","unityToLdtk","coordinateSystem"] )
			if( member(source,key)!=null ) throw "Unsupported Unity coordinate mapping ("+key+"). Camera reference adapter required; no guessed frame is displayed.";
	}

	/**
	 * Static projection around the player's LDtk-local root, not around an
	 * assumed camera center. Unity +Y is up, LDtk +Y is down. The optional
	 * model is level-IID scoped. Camera damping and blended transitions remain
	 * Unity runtime behaviour, not part of this single-state preview.
	 *
	 * Older schema-1 dimension-only snapshots deliberately fall back to a
	 * player-centered framing rather than pretending to know follow behaviour.
	 */
	public static function playerFrame(profile:CameraPreviewProfile,levelIid:String,playerX:Float,playerY:Float,
		levelWorldX:Float,levelWorldY:Float,levelWidth:Float,levelHeight:Float):CameraPreviewFrame {
		if( !Math.isFinite(playerX) || !Math.isFinite(playerY) || !Math.isFinite(levelWorldX) || !Math.isFinite(levelWorldY) )
			throw "Player or level origin is invalid.";
		var width=profile.width, height=profile.height;
		var cx=playerX, cy=playerY;
		var model=profile.unityCameraModel;
		if( model!=null ) {
			var level=pickLevel(model,levelIid);
			rejectUnknownMapping(model); rejectUnknownMapping(level);
			var camera=member(level,"camera");
			if( camera==null ) camera=member(model,"camera");
			if( camera!=null && !isObject(camera) ) throw "Invalid camera model camera object.";
			if( camera==null && member(level,"rooms")==null && member(level,"zones")==null )
				throw "Unsupported Unity camera model structure; no guessed frame is displayed.";
			var room=containing(member(level,"rooms"),playerX,playerY);
			var zone=containing(member(level,"zones"),playerX,playerY);
			var globalZone=containing(member(model,"zones"),playerX+levelWorldX,playerY+levelWorldY);
			var zoneIsGlobal=globalZone!=null && (zone==null || finite(globalZone,"priority",0.)>finite(zone,"priority",0.));
			if( zoneIsGlobal ) zone=globalZone;
			var zoom=finite(camera,"zoom",1.);
			zoom=finite(room,"zoom",zoom);
			zoom=finite(zone,"zoom",zoom);
			if( zoom<=0 ) throw "Camera model zoom must be positive.";
			var size=finite(zone,"orthographicSize",finite(room,"orthographicSize",finite(camera,"orthographicSize",Math.NaN)));
			if( !Math.isNaN(size) && size<=0 ) throw "Camera model orthographic size must be positive.";
			if( Math.isFinite(size) && size>0 ) {
				height=size*2*profile.pixelsPerUnit;
				width=height*profile.aspect;
			}
			else if( Math.isFinite(zoom) && zoom>0 ) {
				width/=zoom;
				height/=zoom;
			}
			if( !validDimension(width) || !validDimension(height) ) throw "Invalid zoomed camera dimensions.";
			// Named pixel offsets are already in LDtk coordinates. A Unity-unit
			// offset uses its opposite Y sign when mapped into LDtk.
			cx+=finite(camera,"offsetPxX",0.);
			cy+=finite(camera,"offsetPxY",0.);
			var unityOffset=member(camera,"offset");
			if( unityOffset!=null && !isObject(unityOffset) ) throw "Invalid Unity camera offset.";
			cx+=finite(unityOffset,"x",0.)*profile.pixelsPerUnit;
			cy-=finite(unityOffset,"y",0.)*profile.pixelsPerUnit;
			cx+=finite(room,"offsetPxX",0.)+finite(zone,"offsetPxX",0.);
			cy+=finite(room,"offsetPxY",0.)+finite(zone,"offsetPxY",0.);
			var focus=member(zone,"focus");
			if( isObject(focus) ) {
				cx=finite(focus,"x",cx+(zoneIsGlobal ? levelWorldX : 0))-(zoneIsGlobal ? levelWorldX : 0);
				cy=finite(focus,"y",cy+(zoneIsGlobal ? levelWorldY : 0))-(zoneIsGlobal ? levelWorldY : 0);
			}
			// Clamp only to explicitly exported room bounds; old snapshots
			// have no inferred boundaries.
			var bounds=rectOf(room);
			if( isObject(bounds) && rectContains(bounds,playerX,playerY) ) {
				var left=finite(bounds,"minX",finite(bounds,"x",0.));
				var top=finite(bounds,"minY",finite(bounds,"y",0.));
				var right=finite(bounds,"maxX",left+finite(bounds,"width",levelWidth));
				var bottom=finite(bounds,"maxY",top+finite(bounds,"height",levelHeight));
				cx=right-left<width ? (left+right)*0.5 : Math.max(left+width*0.5,Math.min(right-width*0.5,cx));
				cy=bottom-top<height ? (top+bottom)*0.5 : Math.max(top+height*0.5,Math.min(bottom-height*0.5,cy));
			}
		}
		return frame(cx,cy,width,height,false);
	}
}
