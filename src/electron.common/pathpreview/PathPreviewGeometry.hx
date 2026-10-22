package pathpreview;

/** All coordinates and distances are in cells. This module has no editor dependencies. */
typedef PathPreviewPoint = {
	var x:Float;
	var y:Float;
}

enum abstract PathPreviewMode(String) from String to String {
	var Loop = "Loop";
	var Teleport = "Teleport";
	var PingPong = "PingPong";
}

typedef PathPreviewOptions = {
	var mode:PathPreviewMode;
	var blockCount:Int;
	var blockWidth:Float;
	var blockHeight:Float;
	var gap:Float;
	var evenSpacing:Bool;
	var startOffset:Float;
}

typedef PathPreviewBlock = {
	var index:Int;
	var distance:Float;
	var center:PathPreviewPoint;
}

/**
 * Editor-only port of the CargoLinePath formulas supplied by the game.
 *
 * Callers convert the entity pivot and Point fields to cell coordinates before constructing
 * the path. Sampling never changes the supplied vertices, options, or any project data.
 */
class PathPreviewGeometry {
	public static inline var EPSILON:Float = 0.0001;

	public var vertices(default,null):Array<PathPreviewPoint> = [];
	public var hasClosingSegment(default,null):Bool = false;
	public var length(default,null):Float = 0;
	public var extent(default,null):Float;
	public var pitch(default,null):Float;
	public var range(default,null):Float;
	public var seamGap(default,null):Float;
	public var count(default,null):Int;
	public var width(default,null):Float;
	public var height(default,null):Float;
	public var mode(default,null):PathPreviewMode;
	public var overlap(default,null):Bool;
	public var isStatic(default,null):Bool;

	var startOffset:Float;
	var segmentLengths:Array<Float> = [];

	public function new(points:Array<PathPreviewPoint>, options:PathPreviewOptions) {
		mode = options.mode;
		count = options.blockCount < 1 ? 1 : options.blockCount;
		width = options.blockWidth;
		height = options.blockHeight;
		startOffset = options.startOffset;

		for(point in points)
			if( vertices.length==0 || !samePoint(vertices[vertices.length-1],point) )
				vertices.push(copyPoint(point));
		// An entity normally supplies V0 even when Path is empty. Keep empty input well-defined.
		if( vertices.length==0 )
			vertices.push({x:0,y:0});

		if( mode==PathPreviewMode.Loop && vertices.length>=2 && !samePoint(vertices[vertices.length-1],vertices[0]) ) {
			vertices.push(copyPoint(vertices[0]));
			hasClosingSegment = true;
		}

		var minX = vertices[0].x;
		var maxX = minX;
		var minY = vertices[0].y;
		var maxY = minY;
		for(i in 0...vertices.length) {
			var point = vertices[i];
			minX = Math.min(minX,point.x);
			maxX = Math.max(maxX,point.x);
			minY = Math.min(minY,point.y);
			maxY = Math.max(maxY,point.y);
			if( i>0 ) {
				var dx = point.x-vertices[i-1].x;
				var dy = point.y-vertices[i-1].y;
				var segmentLength = Math.sqrt(dx*dx+dy*dy);
				segmentLengths.push(segmentLength);
				length += segmentLength;
			}
		}

		extent = maxX-minX >= maxY-minY-EPSILON ? width : height;
		pitch = options.evenSpacing && length>EPSILON ? length/count : extent+Math.max(0,options.gap);
		range = mode==PathPreviewMode.PingPong ? length-(count-1)*pitch : 0;
		seamGap = mode==PathPreviewMode.PingPong ? range : length-(count-1)*pitch-extent;
		overlap = count>1 && (pitch<extent-EPSILON || seamGap < -EPSILON);
		isStatic = length<=EPSILON || (mode==PathPreviewMode.PingPong && range<=EPSILON);
	}

	static inline function copyPoint(point:PathPreviewPoint):PathPreviewPoint {
		return {x:point.x,y:point.y};
	}

	public static inline function samePoint(a:PathPreviewPoint, b:PathPreviewPoint):Bool {
		var dx = a.x-b.x;
		var dy = a.y-b.y;
		return dx*dx+dy*dy <= EPSILON*EPSILON;
	}

	public static inline function clamp(value:Float, min:Float, max:Float):Float {
		return Math.max(min,Math.min(max,value));
	}

	public static function wrap(value:Float, period:Float):Float {
		if( period<=EPSILON )
			return 0;
		// ffloor preserves Float range on all Haxe targets (floor returns a 32-bit Int).
		return value-period*Math.ffloor(value/period);
	}

	/** Distance of a block from V0 after travelling d cells; d=0 is the editor preview. */
	public function distanceFor(index:Int, d:Float=0):Float {
		if( length<=EPSILON )
			return 0;
		if( mode!=PathPreviewMode.PingPong )
			return wrap(startOffset+index*pitch+d,length);

		var base = 0.;
		if( range>EPSILON ) {
			var q = wrap(clamp(startOffset,0,range)+d,2*range);
			// Clamp the epsilon-wide turning boundary so the train cannot overshoot R.
			base = q<=range+EPSILON ? Math.min(q,range) : 2*range-q;
		}
		return clamp(base+index*pitch,0,length);
	}

	/** Sample the polyline, including Loop's closing segment. Returned points are copies. */
	public function pointAt(distance:Float):PathPreviewPoint {
		if( length<=EPSILON || distance<=EPSILON )
			return copyPoint(vertices[0]);
		if( distance>=length-EPSILON )
			return copyPoint(vertices[vertices.length-1]);

		var start = 0.;
		for(i in 0...segmentLengths.length) {
			var segmentLength = segmentLengths[i];
			if( distance<=start+segmentLength+EPSILON ) {
				var t = clamp((distance-start)/segmentLength,0,1);
				var a = vertices[i];
				var b = vertices[i+1];
				return {x:a.x+(b.x-a.x)*t,y:a.y+(b.y-a.y)*t};
			}
			start += segmentLength;
		}
		return copyPoint(vertices[vertices.length-1]);
	}

	public function sample(d:Float=0):Array<PathPreviewBlock> {
		var blocks:Array<PathPreviewBlock> = [];
		for(i in 0...count) {
			var s = distanceFor(i,d);
			blocks.push({index:i,distance:s,center:pointAt(s)});
		}
		return blocks;
	}

	/** The complete PingPong train at b=R, independent of its starting offset. */
	public function endBlocks():Array<PathPreviewBlock> {
		var blocks:Array<PathPreviewBlock> = [];
		if( mode!=PathPreviewMode.PingPong || isStatic )
			return blocks;
		for(i in 0...count) {
			var s = clamp(range+i*pitch,0,length);
			blocks.push({index:i,distance:s,center:pointAt(s)});
		}
		return blocks;
	}
}
