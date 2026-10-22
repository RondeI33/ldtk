import pathpreview.PathPreviewGeometry;
import pathpreview.PathPreviewGeometry.PathPreviewPoint;
import pathpreview.PathPreviewGeometry.PathPreviewMode;

/** Reference vectors supplied by CargoLinePath.cs; deliberately independent of editor setup. */
class PathPreviewGeometryTest {
	static var assertions = 0;
	static var snapshots = 0;
	static var vectors = 0;

	static function assertTrue(value:Bool, message:String) {
		assertions++;
		if( !value )
			throw message;
	}

	static function near(actual:Float, expected:Float, message:String, tolerance:Float=0.0005) {
		assertTrue(Math.isFinite(actual) && Math.abs(actual-expected)<=tolerance,
			message+': expected '+expected+', got '+actual);
	}

	static function points(coordinates:Array<Array<Float>>):Array<PathPreviewPoint> {
		return [for(p in coordinates) {x:p[0],y:p[1]}];
	}

	static function path(coordinates:Array<Array<Float>>, mode:PathPreviewMode, count:Int, width:Float,
		height:Float, gap:Float, evenSpacing:Bool=false, offset:Float=0):PathPreviewGeometry {
		return new PathPreviewGeometry(points(coordinates), {
			mode:mode, blockCount:count, blockWidth:width, blockHeight:height,
			gap:gap, evenSpacing:evenSpacing, startOffset:offset,
		});
	}

	static function metrics(name:String, p:PathPreviewGeometry, expected:Array<Float>, overlap:Bool, isStatic:Bool) {
		vectors++;
		near(p.length,expected[0],name+' length');
		near(p.extent,expected[1],name+' extent');
		near(p.pitch,expected[2],name+' pitch');
		near(p.range,expected[3],name+' range');
		near(p.seamGap,expected[4],name+' seam gap');
		assertTrue(p.overlap==overlap,name+' overlap');
		assertTrue(p.isStatic==isStatic,name+' static');
	}

	static function sample(name:String, p:PathPreviewGeometry, distance:Float, expected:Array<Array<Float>>) {
		snapshots++;
		var blocks = p.sample(distance);
		assertTrue(blocks.length==expected.length,name+' block count');
		for(i in 0...expected.length) {
			var label = name+' d='+distance+' #'+i;
			assertTrue(blocks[i].index==i,label+' index');
			near(blocks[i].distance,expected[i][0],label+' s');
			near(blocks[i].center.x,expected[i][1],label+' center x');
			near(blocks[i].center.y,expected[i][2],label+' center y');
		}
	}

	static function gameVectors() {
		var rectangle:Array<Array<Float>> = [[0,0],[10,0],[10,4],[0,4]];

		var a = path(rectangle,Loop,4,3,1,2);
		assertTrue(a.hasClosingSegment,'Loop adds its missing closing segment');
		metrics('A',a,[28,3,5,0,10],false,false);
		sample('A',a,0,[[0,0,0],[5,5,0],[10,10,0],[15,9,4]]);
		sample('A',a,6.5,[[6.5,6.5,0],[11.5,10,1.5],[16.5,7.5,4],[21.5,2.5,4]]);

		var b = path(rectangle,Loop,7,3,1,2,true);
		metrics('B',b,[28,3,4,0,1],false,false);
		sample('B',b,0,[[0,0,0],[4,4,0],[8,8,0],[12,10,2],[16,8,4],[20,4,4],[24,0,4]]);

		var c = path(rectangle,Loop,2,3,1,2,false,-3);
		metrics('C',c,[28,3,5,0,20],false,false);
		sample('C',c,0,[[25,0,3],[2,2,0]]);

		var d = path([[0,0],[20,0]],Teleport,3,2,1,3);
		metrics('D',d,[20,2,5,0,8],false,false);
		sample('D',d,0,[[0,0,0],[5,5,0],[10,10,0]]);
		sample('D',d,7,[[7,7,0],[12,12,0],[17,17,0]]);
		sample('D',d,13,[[13,13,0],[18,18,0],[3,3,0]]);

		var e = path([[0,0],[8,0]],Teleport,4,3,1,0);
		metrics('E',e,[8,3,3,0,-4],true,false);
		sample('E',e,0,[[0,0,0],[3,3,0],[6,6,0],[1,1,0]]);

		var f = path([[0,0],[0,12]],PingPong,3,3,2,1);
		metrics('F',f,[12,2,3,6,6],false,false);
		sample('F',f,0,[[0,0,0],[3,0,3],[6,0,6]]);
		sample('F',f,4,[[4,0,4],[7,0,7],[10,0,10]]);
		sample('F',f,9,[[3,0,3],[6,0,6],[9,0,9]]);

		var g = path([[0,0],[6,0]],PingPong,3,3,1,1);
		metrics('G',g,[6,3,4,-2,-2],true,true);
		sample('G',g,0,[[0,0,0],[4,4,0],[6,6,0]]);

		var h = path([[0,0],[6,0],[6,0],[6,-5]],Teleport,2,2,1,1,false,1.5);
		metrics('H',h,[11,2,3,0,6],false,false);
		sample('H',h,0,[[1.5,1.5,0],[4.5,4.5,0]]);
		assertTrue(h.vertices.length==3,'H drops the duplicate point');
	}

	static function edgeCases() {
		var eps = PathPreviewGeometry.EPSILON;
		near(PathPreviewGeometry.wrap(-3,28),25,'negative offset wrapping');
		near(PathPreviewGeometry.wrap(28,28),0,'exact seam wrapping');
		near(PathPreviewGeometry.wrap(1,eps),0,'epsilon period');
		near(PathPreviewGeometry.wrap(1e12+3,10),3,'large travelled distance does not overflow Int');

		var single = path([[3.5,-2.5]],Teleport,0,3,1,-4,true,12);
		assertTrue(single.count==1,'block count is at least one');
		assertTrue(single.isStatic && !single.overlap,'one stationary block has no train overlap');
		near(single.pitch,3,'negative gap clamps to zero');
		near(single.sample()[0].center.x,3.5,'empty Path stays at the entity pivot x');
		near(single.sample()[0].center.y,-2.5,'empty Path stays at the entity pivot y');
		near(single.distanceFor(0,25),0,'zero length ignores travelled distance');

		var duplicates = path([[0,0],[eps/2,0],[0,0]],Loop,2,3,1,0);
		assertTrue(duplicates.vertices.length==1 && duplicates.isStatic,'epsilon duplicates collapse to one vertex');
		assertTrue(duplicates.overlap,'coincident train blocks overlap');
		var outsideEpsilon = path([[0,0],[eps*2,0]],Teleport,1,1,1,0);
		assertTrue(!outsideEpsilon.isStatic,'segments beyond epsilon survive');

		var touching = path([[0,0],[6-eps/2,0]],Teleport,2,3,1,0);
		assertTrue(!touching.overlap,'sub-epsilon negative seam is not flagged');
		var overlapping = path([[0,0],[6-eps*2,0]],Teleport,2,3,1,0);
		assertTrue(overlapping.overlap,'seam below negative epsilon is flagged');
		var tightEven = path([[0,0],[6-eps/2,0]],Teleport,2,3,1,0,true);
		assertTrue(!tightEven.overlap,'sub-epsilon pitch shortfall is not flagged');
		var overlapEven = path([[0,0],[6-eps*4,0]],Teleport,2,3,1,0,true);
		assertTrue(overlapEven.overlap,'pitch shortfall beyond epsilon is flagged');

		var exactFit = path([[0,0],[8,0]],PingPong,3,3,1,1);
		assertTrue(exactFit.isStatic && !exactFit.overlap,'zero travel range fits but cannot move');
		assertTrue(exactFit.endBlocks().length==0,'static train has no ghost');
		var almostFit = path([[0,0],[8+eps/2,0]],PingPong,3,3,1,1);
		assertTrue(almostFit.isStatic,'sub-epsilon travel range is static');

		var offset = path([[0,0],[0,12]],PingPong,3,3,2,1,false,100);
		near(offset.distanceFor(0),6,'PingPong clamps positive StartOffset to R');
		near(offset.distanceFor(0,3),3,'PingPong turns around from clamped offset');
		var negativeOffset = path([[0,0],[0,12]],PingPong,3,3,2,1,false,-100);
		near(negativeOffset.distanceFor(0),0,'PingPong clamps negative StartOffset to zero');
		near(negativeOffset.distanceFor(0,-3),3,'PingPong supports negative travelled distance');
		var ghosts = negativeOffset.endBlocks();
		assertTrue(ghosts.length==3,'ghost includes the whole train');
		for(i in 0...ghosts.length) {
			near(ghosts[i].distance,6+i*3,'ghost distance #'+i);
			near(ghosts[i].center.x,0,'vertical ghost x #'+i);
			near(ghosts[i].center.y,6+i*3,'vertical ghost y #'+i);
		}

		var diagonal = path([[0,0],[3,4]],Teleport,2,2,1,1,false,2.5);
		near(diagonal.length,5,'diagonal uses Euclidean length');
		near(diagonal.sample()[0].center.x,1.5,'diagonal interpolation x');
		near(diagonal.sample()[0].center.y,2,'diagonal interpolation y');
		near(diagonal.extent,1,'vertical-dominant path uses block height');
		var equalAxes = path([[0,0],[4,4]],Teleport,1,3,1,0);
		near(equalAxes.extent,3,'axis tie uses block width');

		var original = points([[0,0],[2,0],[2,0]]);
		var snapshot = haxe.Json.stringify(original);
		var copied = new PathPreviewGeometry(original, {
			mode:Loop,blockCount:2,blockWidth:1,blockHeight:1,gap:0,evenSpacing:false,startOffset:0,
		});
		copied.sample(4);
		copied.pointAt(1);
		copied.endBlocks();
		assertTrue(haxe.Json.stringify(original)==snapshot,'construction and sampling never mutate input vertices');
		var sampled = copied.pointAt(0);
		sampled.x = 99;
		near(copied.vertices[0].x,0,'returned samples do not alias source vertices');
		var closed = path([[0,0],[2,0],[0,0]],Loop,1,1,1,0);
		near(closed.length,4,'already closed Loop is not extended');
		assertTrue(closed.vertices.length==3,'already closed Loop has no zero-length closing segment');
		assertTrue(!closed.hasClosingSegment,'already closed Loop needs no extra rendered segment');
		assertTrue(closed.endBlocks().length==0,'Loop has no PingPong ghost');
	}

	static function main() {
		gameVectors();
		edgeCases();
		Sys.println('PASS: path preview geometry ('+vectors+' game vectors, '+snapshots
			+' reference snapshots, epsilon/degenerate cases, '+assertions+' assertions)');
	}
}
