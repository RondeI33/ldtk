package display;

import data.DrawableShape.DrawableShapeState;

typedef DrawableShapeEdge = { var x:Int; var y:Int; var face:String; }
typedef DrawableShapeSurface = { var x:Int; var y:Int; var width:Int; }
typedef DrawableShapeRenderStats = {
	var cellCount:Int;
	var cells:Array<Int>;
	var exposedEdges:Array<DrawableShapeEdge>;
	var spikeFaces:Array<DrawableShapeEdge>;
	var surfaceSpans:Array<DrawableShapeSurface>;
	var innerCorners:Int;
	var outerCorners:Int;
	var profile:String;
	var color:Int;
	var error:Null<String>;
}

/** Entity-owned retained graphics. Called only when EntityRender's core is invalidated. */
class DrawableShapeRender {
	static inline function key(x:Int,y:Int):String return x+":"+y;

	/** g's origin is the occupied bounding box top-left. No map tiles are modified. */
	public static function draw(g:h2d.Graphics,state:DrawableShapeState,?ei:data.inst.EntityInstance,?ed:data.def.EntityDef,?tint:Int):DrawableShapeRenderStats {
		g.clear();
		g.removeChildren();
		var color:Int = tint==null ? state.color : tint;
		if( state.error!=null ) color = 0xff4545;
		var stats:DrawableShapeRenderStats = {
			cellCount:Std.int(state.cells.length/2), cells:state.cells.copy(),
			exposedEdges:[],spikeFaces:[],surfaceSpans:[],innerCorners:0,outerCorners:0,
			profile:state.profile,color:color,error:state.error,
		};
		Reflect.setField(g,"drawableShapeStats",stats);
		var grid = state.grid>0 ? state.grid : 16;
		if( state.cells.length==0 ) {
			// Invalid versioned data is diagnostic only; never present a filled collider.
			var width = Math.max(grid,state.width>0 ? state.width*grid : ei==null ? grid : ei.width);
			var height = Math.max(grid,state.height>0 ? state.height*grid : ei==null ? grid : ei.height);
			g.lineStyle(2,0xff4545);
			g.drawRect(0,0,width,height);
			g.moveTo(0,0);g.lineTo(width,height);
			g.moveTo(width,0);g.lineTo(0,height);
			var label = new h2d.Text(Assets.getRegularFont(),g);
			label.text = "Invalid drawable shape";
			label.textColor = 0xff4545;
			label.y = -label.textHeight-2;
			return stats;
		}
		var occupied:Map<String,Bool> = new Map();
		var vertices:Map<String,{x:Int,y:Int}> = new Map();
		for( i in 0...stats.cellCount ) {
			var cx=state.cells[i*2],cy=state.cells[i*2+1];
			occupied.set(key(cx,cy),true);
			for( oy in 0...2 ) for( ox in 0...2 ) vertices.set(key(cx+ox,cy+oy),{x:cx+ox,y:cy+oy});
		}
		inline function has(x:Int,y:Int):Bool return occupied.exists(key(x,y));
		var pool = state.profile=="EnergyPool";
		var spikes = state.profile=="Spikes";
		var body = C.toBlack(color,pool ? 0.25 : spikes ? 0.55 : 0.30);
		var highlight = C.toWhite(color,0.60);
		var shadow = C.toBlack(color,0.65);
		var line = Math.max(1,Math.min(2,grid/8));

		// Repeated procedural body artwork is a fallback for definitions without a tile.
		// Pattern density is in pixels, so resizing adds cells instead of stretching art.
		g.lineStyle(0);
		for( i in 0...stats.cellCount ) {
			var cx=state.cells[i*2],cy=state.cells[i*2+1];
			var x=cx*grid,y=cy*grid;
			g.beginFill(body,pool ? 0.72 : 1);
			g.drawRect(x,y,grid,grid);
			g.endFill();
			if( pool && grid>=4 ) {
				g.beginFill(color,0.45);
				g.drawRect(x+grid*0.25,y+grid*0.6,Math.max(1,grid*0.4),1);
				g.endFill();
			}
			else if( !pool && grid>=4 ) {
				g.beginFill(color,0.32);
				g.drawRect(x+Math.max(1,grid/4),y+Math.max(1,grid/4),Math.max(1,grid/8),Math.max(1,grid/8));
				g.endFill();
			}
			if( !has(cx,cy-1) ) stats.exposedEdges.push({x:cx,y:cy,face:"Up"});
			if( !has(cx+1,cy) ) stats.exposedEdges.push({x:cx,y:cy,face:"Right"});
			if( !has(cx,cy+1) ) stats.exposedEdges.push({x:cx,y:cy,face:"Down"});
			if( !has(cx-1,cy) ) stats.exposedEdges.push({x:cx,y:cy,face:"Left"});
		}

		// Reuse a project's chosen tile as body artwork, clipped per occupied cell.
		// One batched tile group retains the original texel density even on huge masks.
		if( ed==null && ei!=null ) ed=ei.def;
		var rect = ei==null ? ed==null ? null : ed.getDefaultTile() : ei.getSmartTile();
		if( rect!=null && ed!=null && state.error==null ) {
			var td = (ei==null ? Editor.ME.project : ei._project).defs.getTilesetDef(rect.tilesetUid);
			if( td!=null ) {
				var tile = td.getTileRect(rect);
				var tw=Std.int(tile.width),th=Std.int(tile.height);
				if( tw>0 && th>0 ) {
					var tiles = new h2d.TileGroup(td.getAtlasTile(),g);
					tiles.setDefaultColor(color,ed.tileOpacity);
					for( i in 0...stats.cellCount ) {
						var x=state.cells[i*2]*grid,y=state.cells[i*2+1]*grid;
						var oy=0;
						while( oy<grid ) {
							var sy=(y+oy)%th,ph=Std.int(Math.min(th-sy,grid-oy));
							var ox=0;
							while( ox<grid ) {
								var sx=(x+ox)%tw,pw=Std.int(Math.min(tw-sx,grid-ox));
								tiles.add(x+ox,y+oy,tile.sub(sx,sy,pw,ph));
								ox+=pw;
							}
							oy+=ph;
						}
					}
				}
			}
		}
		var edges = new h2d.Graphics(g);
		for( edge in stats.exposedEdges ) {
			var x=edge.x*grid,y=edge.y*grid;
			var face=edge.face;
			var damaging = spikes && (state.facing=="All" || state.facing==face);
			if( damaging ) stats.spikeFaces.push(edge);
			edges.lineStyle(line,face=="Up" || face=="Left" ? highlight : color,pool ? 0.8 : 1);
			switch face {
				case "Up": edges.moveTo(x,y+line/2);edges.lineTo(x+grid,y+line/2);
				case "Right": edges.moveTo(x+grid-line/2,y);edges.lineTo(x+grid-line/2,y+grid);
				case "Down": edges.moveTo(x,y+grid-line/2);edges.lineTo(x+grid,y+grid-line/2);
				case "Left": edges.moveTo(x+line/2,y);edges.lineTo(x+line/2,y+grid);
			}
			if( damaging ) {
				// Teeth point toward the exposed face and stay within the occupied mask.
				var count = Std.int(Math.max(1,Math.ceil(grid/8)));
				var pitch=grid/count,depth=Math.min(6,grid*0.45);
				edges.lineStyle(1,shadow);
				for( t in 0...count ) {
					var a=t*pitch,b=(t+1)*pitch,mid=(a+b)*0.5;
					edges.beginFill(highlight);
					switch face {
						case "Up": edges.moveTo(x+a,y+depth);edges.lineTo(x+mid,y);edges.lineTo(x+b,y+depth);edges.lineTo(x+a,y+depth);
						case "Down": edges.moveTo(x+a,y+grid-depth);edges.lineTo(x+mid,y+grid);edges.lineTo(x+b,y+grid-depth);edges.lineTo(x+a,y+grid-depth);
						case "Left": edges.moveTo(x+depth,y+a);edges.lineTo(x,y+mid);edges.lineTo(x+depth,y+b);edges.lineTo(x+depth,y+a);
						case "Right": edges.moveTo(x+grid-depth,y+a);edges.lineTo(x+grid,y+mid);edges.lineTo(x+grid-depth,y+b);edges.lineTo(x+grid-depth,y+a);
					}
					edges.endFill();
				}
			}
			// Ends of a surface get a cap only where the neighbouring surface ends.
			if( pool && face=="Up" ) {
				if( !has(edge.x-1,edge.y) || has(edge.x-1,edge.y-1) ) {
					var length=1;
					while( has(edge.x+length,edge.y) && !has(edge.x+length,edge.y-1) ) length++;
					stats.surfaceSpans.push({x:edge.x,y:edge.y,width:length});
				}
				edges.lineStyle(0);
				edges.beginFill(highlight,0.9);
				edges.drawRect(x,y,grid,Math.min(2,grid));
				edges.endFill();
				if( grid>2 ) {
					edges.beginFill(color,0.8);
					edges.drawRect(x,y+2,grid,Math.min(2,grid-2));
					edges.endFill();
				}
			}
		}
		// Corner joints follow occupied quadrants, including concave inner corners.
		for( vertex in vertices ) {
			var quadrants = [has(vertex.x-1,vertex.y-1),has(vertex.x,vertex.y-1),has(vertex.x-1,vertex.y),has(vertex.x,vertex.y)];
			var count=0;
			for( occupied in quadrants ) if( occupied ) count++;
			if( count!=1 && count!=3 ) continue;
			if( count==1 ) stats.outerCorners++; else stats.innerCorners++;
			if( pool ) continue;
			for( q in 0...4 ) if( quadrants[q] ) {
				var x=vertex.x*grid+(q%2==0 ? -line : 0);
				var y=vertex.y*grid+(q<2 ? -line : 0);
				edges.lineStyle(0);edges.beginFill(count==1 ? highlight : color);
				edges.drawRect(x,y,line,line);edges.endFill();
			}
		}
		return stats;
	}
}
