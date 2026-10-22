package misc;

import data.DataTypes;

private typedef AuthoredRect = {
	var left : Int;
	var right : Int;
	var top : Int;
	var bottom : Int;
}

/**
 * Resolves Smartive appearance rules marked with `whenNeighbour` against an IntGrid layer.
 *
 * The resolver never moves/snaps entities. It only writes the winning rule's normal
 * `whenFieldUid/whenValue` pair into the entity instance. Existing appearanceOverrides then
 * select the sprite/size/pivot/color exactly as before.
 *
 * Supported modes, in priority order:
 * Floor > Ceiling > LeftWall > RightWall > BackgroundWall > Air.
 * Air is an optional fallback and matches only after no physical surface rule matched.
 */
class NeighbourAppearance {
	public static inline var FLOOR = "Floor";
	public static inline var CEILING = "Ceiling";
	public static inline var LEFT_WALL = "LeftWall";
	public static inline var RIGHT_WALL = "RightWall";
	public static inline var BACKGROUND_WALL = "BackgroundWall";
	public static inline var AIR = "Air";

	static var installed = false;
	static var cachedSignatures : Map<String,String> = new Map();
	static var cachedLevelId : Null<Int> = null;

	public static function install() {
		if( installed )
			return;
		installed = true;
		js.Browser.window.setInterval(tick, 90);
	}

	static inline function getDyn(o:Dynamic, field:String) : Dynamic {
		return o==null ? null : Reflect.field(o,field);
	}

	static function getInt(o:Dynamic, field:String, ?fallback:Null<Int>) : Null<Int> {
		var raw = getDyn(o,field);
		if( raw==null )
			return fallback;
		var out = Std.parseInt(Std.string(raw));
		return M.isValidNumber(out) ? out : fallback;
	}

	static inline function sameValue(a:Dynamic, b:Dynamic) {
		return a==null || b==null ? a==b : Std.string(a)==Std.string(b);
	}

	static function modePriority(mode:String) : Int {
		return switch mode {
			case FLOOR: 0;
			case CEILING: 1;
			case LEFT_WALL: 2;
			case RIGHT_WALL: 3;
			case BACKGROUND_WALL: 4;
			case AIR: 5;
			case _: 999;
		}
	}

	static function hasNeighbourRules(ed:data.def.EntityDef) {
		for(rule in ed.appearanceOverrides)
			if( getDyn(rule,"whenNeighbour")!=null )
				return true;
		return false;
	}

	static function getAuthoredRect(ei:data.inst.EntityInstance) : AuthoredRect {
		// Deliberately use authored/base geometry, not appearance-overridden geometry.
		// Otherwise changing the sprite/size could move the neighbour probes and cause a feedback loop.
		var width : Int = ei.customWidth==null ? ei.def.width : ei.customWidth;
		var height : Int = ei.customHeight==null ? ei.def.height : ei.customHeight;
		var left = M.round(ei.x - width*ei.def.pivotX) + ei._li.pxTotalOffsetX;
		var top = M.round(ei.y - height*ei.def.pivotY) + ei._li.pxTotalOffsetY;
		return {
			left: left,
			right: left + width,
			top: top,
			bottom: top + height,
		};
	}

	static function findIntGridLayer(ei:data.inst.EntityInstance, layerDefUid:Null<Int>) : Null<data.inst.LayerInstance> {
		if( layerDefUid==null )
			return null;
		for(li in ei._li.level.layerInstances)
			if( li.layerDefUid==layerDefUid && li.def.type==IntGrid )
				return li;
		return null;
	}

	static inline function toCx(li:data.inst.LayerInstance, levelX:Int) {
		return Std.int(Math.floor((levelX-li.pxTotalOffsetX)/li.def.gridSize));
	}

	static inline function toCy(li:data.inst.LayerInstance, levelY:Int) {
		return Std.int(Math.floor((levelY-li.pxTotalOffsetY)/li.def.gridSize));
	}

	static inline function cellMatches(li:data.inst.LayerInstance, cx:Int, cy:Int, expected:Null<Int>) {
		if( !li.isValid(cx,cy) )
			return false;
		var actual = li.getIntGrid(cx,cy);
		return expected==null || expected<=0 ? actual!=0 : actual==expected;
	}

	static function horizontalProbe(li:data.inst.LayerInstance, left:Int, rightExclusive:Int, y:Int, expected:Null<Int>) {
		if( rightExclusive<=left )
			rightExclusive = left+1;
		var cy = toCy(li,y);
		var c0 = toCx(li,left);
		var c1 = toCx(li,rightExclusive-1);
		for(cx in c0...(c1+1))
			if( cellMatches(li,cx,cy,expected) )
				return true;
		return false;
	}

	static function verticalProbe(li:data.inst.LayerInstance, x:Int, top:Int, bottomExclusive:Int, expected:Null<Int>) {
		if( bottomExclusive<=top )
			bottomExclusive = top+1;
		var cx = toCx(li,x);
		var c0 = toCy(li,top);
		var c1 = toCy(li,bottomExclusive-1);
		for(cy in c0...(c1+1))
			if( cellMatches(li,cx,cy,expected) )
				return true;
		return false;
	}

	static function areaProbe(li:data.inst.LayerInstance, r:AuthoredRect, expected:Null<Int>) {
		var right = r.right<=r.left ? r.left+1 : r.right;
		var bottom = r.bottom<=r.top ? r.top+1 : r.bottom;
		var cx0 = toCx(li,r.left);
		var cx1 = toCx(li,right-1);
		var cy0 = toCy(li,r.top);
		var cy1 = toCy(li,bottom-1);
		for(cy in cy0...(cy1+1))
		for(cx in cx0...(cx1+1))
			if( cellMatches(li,cx,cy,expected) )
				return true;
		return false;
	}

	static function neighbourMatches(ei:data.inst.EntityInstance, rule:Dynamic) {
		var mode = Std.string(getDyn(rule,"whenNeighbour"));
		if( mode==AIR )
			return true;

		var li = findIntGridLayer(ei,getInt(rule,"neighbourLayerDefUid"));
		if( li==null )
			return false;
		var expected = getInt(rule,"neighbourIntGridValue");
		var r = getAuthoredRect(ei);

		return switch mode {
			case FLOOR:
				horizontalProbe(li,r.left,r.right,r.bottom,expected);
			case CEILING:
				horizontalProbe(li,r.left,r.right,r.top-1,expected);
			case LEFT_WALL:
				verticalProbe(li,r.left-1,r.top,r.bottom,expected);
			case RIGHT_WALL:
				verticalProbe(li,r.right,r.top,r.bottom,expected);
			case BACKGROUND_WALL:
				areaProbe(li,r,expected);
			case _:
				false;
		}
	}

	static function resolveRule(ei:data.inst.EntityInstance, rules:Array<Dynamic>) : Dynamic {
		var best : Dynamic = null;
		var bestPriority = 999;
		for(rule in rules) {
			var mode = Std.string(getDyn(rule,"whenNeighbour"));
			var priority = modePriority(mode);
			if( priority<bestPriority && neighbourMatches(ei,rule) ) {
				best = rule;
				bestPriority = priority;
			}
		}
		return best;
	}

	static function applyRuleValue(ei:data.inst.EntityInstance, fieldUid:Int, rule:Dynamic) {
		if( rule==null )
			return false;
		var fd = ei.def.getFieldDef(fieldUid);
		if( fd==null || fd.isArray )
			return false;
		var fi = ei.getFieldInstance(fd,true);
		var desired = getDyn(rule,"whenValue");
		var current = fi.toJson().__value;
		if( sameValue(current,desired) )
			return false;
		fi.parseValue(0, desired==null ? null : Std.string(desired));
		return true;
	}

	static function syncEntity(ei:data.inst.EntityInstance) : String {
		var groups : Map<Int,Array<Dynamic>> = new Map();
		for(rule in ei.def.appearanceOverrides) {
			if( getDyn(rule,"whenNeighbour")==null )
				continue;
			var fieldUid = getInt(rule,"whenFieldUid");
			if( fieldUid==null )
				continue;
			var fd = ei.def.getFieldDef(fieldUid);
			if( fd==null || fd.isArray )
				continue;
			if( !groups.exists(fieldUid) )
				groups.set(fieldUid,[]);
			groups.get(fieldUid).push(rule);
		}

		var fieldUids : Array<Int> = [];
		for(uid in groups.keys())
			fieldUids.push(uid);
		fieldUids.sort(function(a,b) return a-b);

		var signature : Array<String> = [];
		var changed = false;
		for(fieldUid in fieldUids) {
			var rule = resolveRule(ei,groups.get(fieldUid));
			var idx = rule==null ? -1 : ei.def.appearanceOverrides.indexOf(rule);
			signature.push(fieldUid+":"+idx);
			if( applyRuleValue(ei,fieldUid,rule) )
				changed = true;
		}

		if( changed && Editor.exists() )
			Editor.ME.needSaving = true;
		return signature.join("|");
	}

	static function tick() {
		if( !Editor.exists() || Editor.ME.project==null || Editor.ME.curLevel==null ) {
			cachedSignatures = new Map();
			cachedLevelId = null;
			return;
		}

		var editor = Editor.ME;
		if( cachedLevelId!=editor.curLevelId ) {
			cachedLevelId = editor.curLevelId;
			cachedSignatures = new Map();
		}

		var next : Map<String,String> = new Map();
		for(li in editor.curLevel.layerInstances) {
			if( li.def.type!=Entities )
				continue;
			for(ei in li.entityInstances) {
				if( !hasNeighbourRules(ei.def) )
					continue;
				var signature = syncEntity(ei);
				next.set(ei.iid,signature);
				var previous = cachedSignatures.get(ei.iid);
				if( previous==null || previous!=signature )
					editor.levelRender.invalidateLayer(li);
			}
		}
		cachedSignatures = next;
	}
}
