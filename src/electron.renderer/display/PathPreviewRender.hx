package display;

import data.PathPreviewConfig.ResolvedPathPreview;
import pathpreview.PathPreviewGeometry;
import pathpreview.PathPreviewGeometry.PathPreviewBlock;
import pathpreview.PathPreviewGeometry.PathPreviewMode;
import pathpreview.PathPreviewGeometry.PathPreviewPoint;

/** Drawing only: no interactive objects, generated entities, tiles, or field writes. */
class PathPreviewRender extends h2d.Object {
	/** A selection drag replaces the source preview with its transient geometry. */
	public static var suppressedEntities:Map<String,Bool> = new Map();
	public static inline function isSuppressed(ei:data.inst.EntityInstance):Bool {
		return suppressedEntities.exists(ei.iid);
	}

	var graphics:h2d.Graphics;
	var labels:h2d.Object;
	var instance:data.inst.EntityInstance;
	var config:ResolvedPathPreview;
	var zoomScale:Float;
	public var geometry(default,null):Null<PathPreviewGeometry>;
	public var drawnBlockCount(default,null) = 0;
	public var drawnGhostCount(default,null) = 0;
	public var drawnGapCount(default,null) = 0;
	public var gapValues(default,null):Array<Float> = [];
	public var drawnColor(default,null) = 0;
	public var warning(default,null) = "";
	public var modeCue(default,null) = "";

	public function new(parent:h2d.Object) {
		super(parent);
		graphics = new h2d.Graphics(this);
		labels = new h2d.Object(this);
	}

	static function number(value:Float):String {
		var rounded = Math.round(value*1000)/1000;
		return Std.string(rounded==0 ? 0 : rounded);
	}

	inline function local(point:PathPreviewPoint):PathPreviewPoint {
		return {
			x:point.x*config.unitPx-instance.x+instance._li.pxTotalOffsetX,
			y:point.y*config.unitPx-instance.y+instance._li.pxTotalOffsetY,
		};
	}

	function label(text:String, x:Float, y:Float, color:Int, centered=true, alpha=1.) {
		var tf = new h2d.Text(Assets.getRegularFont(), labels);
		tf.text = text;
		tf.textColor = color;
		tf.alpha = alpha;
		tf.setScale(zoomScale);
		tf.filter = new h2d.filter.Outline(1,0x10151b,0.9);
		tf.x = x-(centered ? tf.textWidth*tf.scaleX*0.5 : 0);
		tf.y = y-tf.textHeight*tf.scaleY*0.5;
	}

	function block(block:PathPreviewBlock, ghost:Bool) {
		var center = local(block.center);
		var width = geometry.width*config.unitPx;
		var height = geometry.height*config.unitPx;
		graphics.lineStyle(zoomScale,drawnColor,ghost ? 0.3 : 1);
		if( !ghost )
			graphics.beginFill(drawnColor,0.35);
		graphics.drawRect(center.x-width*0.5,center.y-height*0.5,width,height);
		graphics.endFill();
		if( ghost )
			drawnGhostCount++;
		else {
			drawnBlockCount++;
			if( geometry.width>=2-PathPreviewGeometry.EPSILON )
				label(Std.string(block.index),center.x,center.y,0xffffff);
		}
	}

	function dimensionPoint(distance:Float):PathPreviewPoint {
		var s = geometry.mode==PathPreviewMode.Loop
			? PathPreviewGeometry.wrap(distance,geometry.length)
			: PathPreviewGeometry.clamp(distance,0,geometry.length);
		return local(geometry.pointAt(s));
	}

	/** Dimension follows the polyline through corners, splitting at Loop's origin. */
	function gap(from:Float, to:Float, value:Float, seam=false) {
		var lo = Math.min(from,to);
		var hi = Math.max(from,to);
		var spans:Array<{from:Float,to:Float}> = [];
		var mid:Float;
		if( geometry.mode==PathPreviewMode.Loop ) {
			// Oversized overlapping blocks can extend more than one lap past an endpoint.
			// Drawing the same closed path repeatedly adds nothing; keep the full numeric value.
			var length = Math.min(hi-lo,geometry.length);
			var start = PathPreviewGeometry.wrap(lo,geometry.length);
			var end = start+length;
			spans.push({from:start,to:Math.min(end,geometry.length)});
			if( end>geometry.length+PathPreviewGeometry.EPSILON )
				spans.push({from:0,to:end-geometry.length});
			mid = PathPreviewGeometry.wrap(start+length*0.5,geometry.length);
		}
		else {
			lo = PathPreviewGeometry.clamp(lo,0,geometry.length);
			hi = PathPreviewGeometry.clamp(hi,0,geometry.length);
			spans.push({from:lo,to:hi});
			mid = (lo+hi)*0.5;
		}
		var before = dimensionPoint(mid-0.01);
		var after = dimensionPoint(mid+0.01);
		var angle = Math.atan2(after.y-before.y,after.x-before.x);
		var nx = Math.sin(angle);
		var ny = -Math.cos(angle);
		// Move the dimension just outside the axis-aligned block on this segment.
		var offset = (Math.abs(nx)*geometry.width+Math.abs(ny)*geometry.height)*config.unitPx*0.5+5*zoomScale;
		graphics.lineStyle(zoomScale,drawnColor,0.8);
		for(span in spans) {
			var points:Array<PathPreviewPoint> = [local(geometry.pointAt(span.from))];
			var distance = 0.;
			for(i in 1...geometry.vertices.length) {
				var a = geometry.vertices[i-1];
				var b = geometry.vertices[i];
				distance += Math.sqrt((b.x-a.x)*(b.x-a.x)+(b.y-a.y)*(b.y-a.y));
				if( distance>span.from+PathPreviewGeometry.EPSILON && distance<span.to-PathPreviewGeometry.EPSILON )
					points.push(local(b));
			}
			points.push(local(geometry.pointAt(span.to)));
			for(i in 0...points.length) {
				var p = points[i];
				if( i==0 ) graphics.moveTo(p.x+nx*offset,p.y+ny*offset);
				else graphics.lineTo(p.x+nx*offset,p.y+ny*offset);
			}
		}
		for(p in [local(geometry.pointAt(spans[0].from)),local(geometry.pointAt(spans[spans.length-1].to))]) {
			graphics.moveTo(p.x+nx*(offset-3*zoomScale),p.y+ny*(offset-3*zoomScale));
			graphics.lineTo(p.x+nx*(offset+3*zoomScale),p.y+ny*(offset+3*zoomScale));
		}
		var center = dimensionPoint(mid);
		label((seam ? "seam " : "")+number(value),center.x+nx*(offset+8*zoomScale),center.y+ny*(offset+8*zoomScale),drawnColor);
		gapValues.push(value);
		drawnGapCount++;
	}

	function link(a:PathPreviewPoint, b:PathPreviewPoint, dashed=false) {
		var from = local(a);
		var to = local(b);
		FieldInstanceRender.renderRefLink(graphics,config.blockColor,from.x,from.y,to.x,to.y,1,
			dashed ? ldtk.Json.FieldLinkStyle.DashedLine : config.pathField.editorLinkStyle,
			FieldInstanceRender.LinkEndingStyle.Full);
	}

	public function render(ei:data.inst.EntityInstance, resolved:ResolvedPathPreview, includePath=false) {
		graphics.clear();
		labels.removeChildren();
		drawnBlockCount = drawnGhostCount = drawnGapCount = 0;
		gapValues = [];
		warning = modeCue = "";
		geometry = resolved==null ? null : resolved.geometry;
		if( geometry==null ) {
			visible = false;
			return;
		}
		instance = ei;
		config = resolved;
		zoomScale = 1/Editor.ME.camera.adjustedZoom;
		visible = includePath || !isSuppressed(ei);
		drawnColor = geometry.overlap ? config.overlapColor : config.blockColor;

		var vertices = geometry.vertices;
		if( includePath )
			for(i in 1...vertices.length)
				link(vertices[i-1],vertices[i]);

		if( geometry.mode==PathPreviewMode.Loop && vertices.length>1 ) {
			modeCue = "loop";
			// Stock PointPath leaves this segment open; PointPathLoop already draws it.
			if( !includePath && geometry.hasClosingSegment && config.pathField.editorDisplayMode!=ldtk.Json.FieldDisplayMode.PointPathLoop )
				link(vertices[vertices.length-2],vertices[vertices.length-1]);
		}
		else if( geometry.mode==PathPreviewMode.Teleport ) {
			modeCue = "teleport";
			var a = vertices[vertices.length-1];
			var b = vertices[0];
			if( !PathPreviewGeometry.samePoint(a,b) )
				link(a,b,true);
			var start = local(b);
			graphics.lineStyle(zoomScale,config.blockColor,0.9);
			graphics.drawCircle(start.x,start.y,5*zoomScale);
			graphics.moveTo(start.x-2*zoomScale,start.y-7*zoomScale);
			graphics.lineTo(start.x+2*zoomScale,start.y-5*zoomScale);
			graphics.lineTo(start.x-2*zoomScale,start.y-3*zoomScale);
			var end = local(a);
			label("seam "+number(geometry.seamGap),(start.x+end.x)*0.5,(start.y+end.y)*0.5+14*zoomScale,drawnColor);
		}

		if( geometry.mode==PathPreviewMode.PingPong ) {
			modeCue = geometry.isStatic ? "does not fit" : "pingpong";
			for(ghost in geometry.endBlocks())
				block(ghost,true);
		}

		var blocks = geometry.sample();
		for(current in blocks)
			block(current,false);
		if( blocks.length>1 && geometry.length>PathPreviewGeometry.EPSILON ) {
			blocks.sort((a,b)->a.distance<b.distance ? -1 : a.distance>b.distance ? 1 : a.index-b.index);
			for(i in 0...blocks.length-1) {
				var current = blocks[i];
				var next = blocks[i+1];
				gap(current.distance+geometry.extent*0.5,next.distance-geometry.extent*0.5,
					next.distance-current.distance-geometry.extent,current.index==geometry.count-1 && next.index==0);
			}
			if( geometry.mode==PathPreviewMode.Loop ) {
				var last = blocks[blocks.length-1];
				var first = blocks[0];
				gap(last.distance+geometry.extent*0.5,first.distance+geometry.length-geometry.extent*0.5,
					first.distance+geometry.length-last.distance-geometry.extent,last.index==geometry.count-1 && first.index==0);
			}
		}

		var warnings:Array<String> = [];
		if( geometry.overlap ) {
			if( geometry.pitch<geometry.extent-PathPreviewGeometry.EPSILON )
				warnings.push("overlap: pitch "+number(geometry.pitch)+" < block "+number(geometry.extent));
			if( geometry.seamGap < -PathPreviewGeometry.EPSILON )
				warnings.push("overlap: seam "+number(geometry.seamGap));
		}
		if( geometry.mode==PathPreviewMode.PingPong && geometry.isStatic )
			warnings.push("does not fit");
		warning = warnings.join("; ");
		if( warning.length>0 ) {
			var pivot = local(vertices[0]);
			label(warning,pivot.x+8*zoomScale,pivot.y+geometry.height*config.unitPx*0.5+26*zoomScale,
				geometry.overlap ? config.overlapColor : config.blockColor,false);
		}
	}
}
