typedef ShapeResult = {
	var cells:Array<Int>;
	var x:Int;
	var y:Int;
	var width:Int;
	var height:Int;
	var error:Null<String>;
}

/** Pure, deterministic grid geometry shared by authoring and its regression tests. */
class DrawableShapeGeometry {
	public static final PRESETS = ["Rectangle","Strip","LCorner","UShape","Staircase","Diamond","Ring"];
	static inline function key(x:Int,y:Int):String return x+","+y;
	static function failure(message:String):ShapeResult return {cells:[],x:0,y:0,width:0,height:0,error:message};

	public static function normalize(cells:Array<Int>):ShapeResult {
		if( cells==null || cells.length%2!=0 ) return failure("ShapeCells must contain complete integer x/y pairs.");
		if( cells.length==0 ) return {cells:[],x:0,y:0,width:0,height:0,error:null};
		var seen:Map<String,Bool> = new Map();
		var points:Array<{x:Int,y:Int}> = [];
		var minX = cells[0], minY = cells[1], maxX = minX, maxY = minY;
		var i=0;
		while( i<cells.length ) {
			var x=cells[i++], y=cells[i++];
			if( x==null || y==null || !Math.isFinite(x) || !Math.isFinite(y) || x!=Math.floor(x) || y!=Math.floor(y) )
				return failure("ShapeCells contains a non-integer coordinate.");
			if( !seen.exists(key(x,y)) ) { seen.set(key(x,y),true); points.push({x:x,y:y}); }
			if(x<minX) minX=x; if(y<minY) minY=y; if(x>maxX) maxX=x; if(y>maxY) maxY=y;
		}
		points.sort((a,b)-> a.y==b.y ? a.x-b.x : a.y-b.y);
		var out:Array<Int>=[];
		for(p in points) {out.push(p.x-minX);out.push(p.y-minY);}
		return {cells:out,x:minX,y:minY,width:maxX-minX+1,height:maxY-minY+1,error:null};
	}

	public static function occupied(cells:Array<Int>):Map<String,Bool> {
		var out:Map<String,Bool>=new Map(); var i=0;
		while(i+1<cells.length) {out.set(key(cells[i],cells[i+1]),true);i+=2;}
		return out;
	}

	public static function validate(cells:Array<Int>,allowEmpty=false):Null<String> {
		var n=normalize(cells);
		if(n.error!=null) return n.error;
		if(n.cells.length==0) return allowEmpty ? null : "A shape needs at least one occupied cell.";
		var remaining=occupied(n.cells);
		var queue:Array<{x:Int,y:Int}>=[{x:n.cells[0],y:n.cells[1]}];
		remaining.remove(key(queue[0].x,queue[0].y));
		var cursor=0;
		while(cursor<queue.length) {
			var p=queue[cursor++];
			for(d in [{x:1,y:0},{x:-1,y:0},{x:0,y:1},{x:0,y:-1}]) {
				var x=p.x+d.x,y=p.y+d.y;
				if(remaining.remove(key(x,y))) queue.push({x:x,y:y});
			}
		}
		return remaining.iterator().hasNext() ? "The stroke would disconnect the shape. Cells must share an edge; diagonal contact is insufficient." : null;
	}

	/** Enclosed empty components. Euler's cell-complex formula avoids scanning a huge sparse bounding box. */
	public static function holeCount(cells:Array<Int>):Int {
		var n=normalize(cells); if(n.error!=null || n.cells.length==0) return 0;
		var vertices:Map<String,Bool>=new Map(),edges:Map<String,Bool>=new Map();
		var remaining=occupied(n.cells),components=0,i=0;
		while(i<n.cells.length) {
			var x=n.cells[i++],y=n.cells[i++];
			for(dx in 0...2)for(dy in 0...2)vertices.set(key(x+dx,y+dy),true);
			edges.set("h"+key(x,y),true);edges.set("h"+key(x,y+1),true);
			edges.set("v"+key(x,y),true);edges.set("v"+key(x+1,y),true);
			if(!remaining.remove(key(x,y)))continue;
			components++;
			var queue=[{x:x,y:y}],cursor=0;
			while(cursor<queue.length) {
				var p=queue[cursor++];
				// Closed grid squares touch at their vertices. Counting those as one
				// topological component correctly retains holes at diagonal pinches.
				for(dy in -1...2)for(dx in -1...2) {
					var xx=p.x+dx,yy=p.y+dy;
					if(remaining.remove(key(xx,yy)))queue.push({x:xx,y:yy});
				}
			}
		}
		var vertexCount=0,edgeCount=0;
		for(v in vertices)vertexCount++;for(e in edges)edgeCount++;
		return components-vertexCount+edgeCount-Std.int(n.cells.length/2);
	}

	public static function minimum(name:String,thickness=1,quarterTurns=0):{width:Int,height:Int} {
		var t=thickness<1 ? 1 : thickness;
		var w=1,h=1;
		switch name {
			case "LCorner":w=t+1;h=t+1;
			case "UShape":w=t*2+1;h=t+1;
			case "Ring":w=t*2+1;h=t*2+1;
			case "Diamond":w=3;h=3;
			case "Staircase":w=2;h=2;
			case _:
		}
		return quarterTurns%2==0 ? {width:w,height:h} : {width:h,height:w};
	}

	public static function preset(name:String,width:Int,height:Int,thickness=1,quarterTurns=0):ShapeResult {
		if(PRESETS.indexOf(name)<0) return failure("Unknown shape preset: "+name);
		if(thickness<1) return failure("Shape thickness must be at least one grid cell.");
		var minimum=minimum(name,thickness,quarterTurns);
		if(width<minimum.width || height<minimum.height) return failure(name+" needs at least "+minimum.width+" × "+minimum.height+" cells at this thickness and orientation.");
		var q=((quarterTurns%4)+4)%4;
		var w=q%2==0 ? width : height, h=q%2==0 ? height : width;
		var cells:Array<Int>=[];
		for(y in 0...h) for(x in 0...w) {
			var fill=switch name {
				case "Rectangle","Strip":true;
				case "LCorner":x<thickness || y>=h-thickness;
				case "UShape":x<thickness || x>=w-thickness || y>=h-thickness;
				case "Ring":x<thickness || y<thickness || x>=w-thickness || y>=h-thickness;
				case "Staircase":x<Math.ceil((y+1)*w/h);
				case "Diamond":
					var reach=(1-Math.abs((2*y+1-h)/h))*w*0.5;
					Math.abs(x-(w-1)*0.5)<=Math.max(w%2==0 ? 0.5 : 0,reach);
				case _:false;
			};
			if(fill) {cells.push(x);cells.push(y);}
		}
		var result=transform(cells,false,false,q);
		// Diamond rasterization includes extrema deliberately, preserving the requested bounds.
		if(name=="Diamond") {
			var s=occupied(result.cells);
			var cx=Std.int((width-1)/2),cy=Std.int((height-1)/2);
			for(x in 0...width) if(!s.exists(key(x,cy))) {result.cells.push(x);result.cells.push(cy);}
			for(y in 0...height) if(!s.exists(key(cx,y))) {result.cells.push(cx);result.cells.push(y);}
			result=normalize(result.cells);
		}
		result.error=validate(result.cells);
		return result;
	}

	public static function transform(cells:Array<Int>,flipX:Bool,flipY:Bool,quarterTurns=0):ShapeResult {
		var n=normalize(cells);if(n.error!=null || n.cells.length==0)return n;
		var out:Array<Int>=[], q=((quarterTurns%4)+4)%4;
		var i=0;
		while(i<n.cells.length) {
			var x=n.cells[i++],y=n.cells[i++];
			if(flipX)x=n.width-1-x;if(flipY)y=n.height-1-y;
			var xx=x,yy=y;
			switch q {
				case 1:xx=n.height-1-y;yy=x;
				case 2:xx=n.width-1-x;yy=n.height-1-y;
				case 3:xx=y;yy=n.width-1-x;
				case _:
			}
			out.push(xx);out.push(yy);
		}
		return normalize(out);
	}

	/** Insert copies after a selected column/row; negative delta deletes from index. */
	public static function resizeAxis(cells:Array<Int>,axis:String,index:Int,delta:Int):ShapeResult {
		if(axis!="x" && axis!="y")return failure("Choose the X or Y axis.");
		var n=normalize(cells);if(n.error!=null)return n;
		var size=axis=="x" ? n.width : n.height;
		if(index<0 || index>=size || delta<0 && index-delta>size)return failure("The selected row or column is outside the shape.");
		if(delta==0)return n;
		var out:Array<Int>=[],i=0;
		while(i<n.cells.length) {
			var x=n.cells[i++],y=n.cells[i++],v=axis=="x" ? x:y;
			if(delta<0 && v>=index && v<index-delta)continue;
			var shifted=v;
			if(delta>0 && v>index || delta<0 && v>=index-delta)shifted+=delta;
			out.push(axis=="x" ? shifted:x);out.push(axis=="y" ? shifted:y);
			if(delta>0 && v==index)for(j in 1...delta+1) {out.push(axis=="x" ? v+j:x);out.push(axis=="y" ? v+j:y);}
		}
		var result=normalize(out);result.error=validate(result.cells);
		if(result.error==null && holeCount(result.cells)!=holeCount(n.cells))result.error="This resize would open or close a hole. Edit the cells explicitly instead.";
		return result;
	}

	/** Edge-connected supercover interpolation: fast diagonal strokes cannot leave islands. */
	public static function line(x0:Int,y0:Int,x1:Int,y1:Int):Array<Int> {
		var out=[x0,y0],dx=Std.int(Math.abs(x1-x0)),dy=Std.int(Math.abs(y1-y0));
		var sx=x1>x0 ? 1:-1,sy=y1>y0 ? 1:-1,ix=0,iy=0;
		while(ix<dx || iy<dy) {
			if(ix<dx && (iy==dy || (1+2*ix)*dy <= (1+2*iy)*dx)) {x0+=sx;ix++;}
			else {y0+=sy;iy++;}
			out.push(x0);out.push(y0);
		}
		return out;
	}
}
