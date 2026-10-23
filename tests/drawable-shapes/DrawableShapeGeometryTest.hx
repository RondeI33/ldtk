import DrawableShapeGeometry as G;

class DrawableShapeGeometryTest {
	static var checks=0;
	static function check(ok:Bool,message:String) {checks++;if(!ok)throw message;}
	static function equal(a:Dynamic,b:Dynamic,message:String) check(haxe.Json.stringify(a)==haxe.Json.stringify(b),message+"; "+haxe.Json.stringify(a));
	static function referenceHoles(cells:Array<Int>):Int {
		var solid=G.occupied(cells),seen:Map<String,Bool>=new Map(),holes=0;
		for(y in -1...4)for(x in -1...4) {
			if(solid.exists(x+","+y)||seen.exists(x+","+y))continue;
			var queue=[{x:x,y:y}],cursor=0,outside=false;seen.set(x+","+y,true);
			while(cursor<queue.length) {var p=queue[cursor++];if(p.x==-1||p.y==-1||p.x==3||p.y==3)outside=true;
				for(d in [{x:1,y:0},{x:-1,y:0},{x:0,y:1},{x:0,y:-1}]) {var xx=p.x+d.x,yy=p.y+d.y,k=xx+","+yy;
					if(xx>=-1&&yy>=-1&&xx<=3&&yy<=3&&!solid.exists(k)&&!seen.exists(k)) {seen.set(k,true);queue.push({x:xx,y:yy});}
				}
			}
			if(!outside)holes++;
		}
		return holes;
	}
	static function main() {
		var l=[0,0,0,1,0,2,1,2,2,2];
		check(G.validate(l)==null,"L is connected");
		check(G.validate([0,0,1,1])!=null,"Diagonal-only contact rejected");
		check(G.validate([0,0,1])!=null,"Odd payload rejected");
		check(G.validate([])!=null,"Empty custom shape rejected");
		check(G.validate([],true)==null,"Empty stroke candidate may delete its owner");
		var n=G.normalize([2,3,-1,0,2,3,1,3]);
		equal(n.cells,[0,0,2,3,3,3],"Normalize unique sorted coordinates");
		check(n.x==-1 && n.y==0 && n.width==4 && n.height==4,"Normalize retains original minimum for atomic position updates");
		check(G.validate([0,0,1,0,2,0])==null,"One-cell bridge accepted");
		check(G.validate([0,0,2,0])!=null,"Disconnected erase rejected");
		for(name in G.PRESETS)for(q in 0...4) {
			var m=G.minimum(name,1,q);
			for(dim in [{w:m.width,h:m.height},{w:23,h:7},{w:7,h:23}]) {
				var p=G.preset(name,dim.w,dim.h,1,q);
				check(p.error==null,name+" valid at "+dim.w+"x"+dim.h+" q="+q+": "+p.error);
				check(p.width==dim.w && p.height==dim.h,name+" bounds honor both axes");
				check(G.validate(p.cells)==null,name+" connected at all tested sizes");
				check(G.holeCount(p.cells)==(name=="Ring" ? 1:0),name+" expected holes");
			}
			if(m.width>1)check(G.preset(name,m.width-1,m.height,1,q).error!=null,name+" minimum width enforced");
			if(m.height>1)check(G.preset(name,m.width,m.height-1,1,q).error!=null,name+" minimum height enforced");
		}
		var ring=G.preset("Ring",5,5).cells;
		check(!G.occupied(ring).exists("2,2"),"Ring center is genuinely empty");
		check(G.preset("Ring",4,4,2).error!=null,"Thick ring cannot collapse into rectangle");
		check(G.preset("UShape",4,5,2).error!=null,"Thick U cannot collapse into rectangle");
		var wider=G.resizeAxis(ring,"x",2,3);
		check(wider.error==null && wider.width==8 && G.holeCount(wider.cells)==1,"Ring interior extension preserves hole");
		var closed=G.resizeAxis(ring,"x",1,-3);
		check(closed.error!=null,"Shrink that destroys hole rejected");
		var bridged=[0,0,1,0,2,0,0,1,2,1,0,2,2,2];
		check(G.resizeAxis(bridged,"y",0,-1).error!=null,"Shrink that removes bridge rejected");
		var mirrored=G.transform(l,true,false);
		equal(mirrored.cells,[2,0,2,1,0,2,1,2,2,2],"Mirror transforms all cells");
		equal(G.transform(mirrored.cells,true,false).cells,l,"Double mirror identity");
		var rotated=l;
		for(i in 0...4)rotated=G.transform(rotated,false,false,1).cells;
		equal(rotated,l,"Four quarter turns identity");
		for(x in -13...14)for(y in -8...9) {
			var line=G.line(0,0,x,y);
			check(G.validate(line)==null,"Interpolated stroke connected");
			check(line[line.length-2]==x && line[line.length-1]==y,"Interpolated stroke reaches pointer");
		}
		var large=G.preset("Rectangle",101,57);
		check(large.cells.length==11514 && G.validate(large.cells)==null,"No arbitrary small shape array limit");
		for(mask in 0...512) {
			var cells:Array<Int>=[];for(i in 0...9)if(mask&(1<<i)!=0){cells.push(i%3);cells.push(Std.int(i/3));}
			check(G.holeCount(cells)==referenceHoles(cells),"Linear hole count agrees with independent flood-fill for mask "+mask);
		}
		Sys.println("Drawable shape geometry: "+checks+" checks passed.");
	}
}
