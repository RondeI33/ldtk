package misc;

/**
 * Resolves Smartive entity surface/attachment appearance from a nearby IntGrid layer.
 *
 * The visual rules themselves remain ordinary ForkConfig appearanceOverrides. Managed
 * rules carry a `smartiveNeighbour` object that describes which IntGrid layer to sample
 * and which probe (Floor/Ceiling/LeftWall/RightWall/BackgroundWall) the rule represents.
 * The resolver writes the detected surface into the configured normal LDtk field, so the
 * regular appearance override pipeline can select the matching sprite without any special
 * renderer path.
 *
 * IMPORTANT: this class never moves or snaps entities. It only resolves appearance.
 */
class NeighbourAppearanceRuntime {
	public static inline var META_FIELD = "smartiveNeighbour";
	public static inline var BACKGROUND = "BackgroundWall";
	public static inline var LEFT = "LeftWall";
	public static inline var RIGHT = "RightWall";
	public static inline var CEILING = "Ceiling";
	public static inline var FLOOR = "Floor";

	static var installed = false;
	static var ticking = false;

	public static function install() {
		if( installed )
			return;
		installed = true;
		js.Browser.window.setInterval(tick, 120);
	}

	static inline function getDyn(o:Dynamic, field:String) : Dynamic {
		return o==null ? null : Reflect.field(o, field);
	}

	static function getInt(o:Dynamic, field:String, ?fallback:Null<Int>) : Null<Int> {
		var raw = getDyn(o, field);
		if( raw==null )
			return fallback;
		var out = Std.parseInt(Std.string(raw));
		return M.isValidNumber(out) ? out : fallback;
	}

	static function getArray(o:Dynamic, field:String) : Array<Dynamic> {
		var raw = getDyn(o, field);
		return raw==null || !Std.isOfType(raw, Array) ? [] : cast raw;
	}

	static function getManagedRules(ed:data.def.EntityDef) : Array<Dynamic> {
		var out : Array<Dynamic> = [];
		for(rule in ed.appearanceOverrides)
			if( getDyn(rule, META_FIELD)!=null )
				out.push(rule);
		return out;
	}

	static function findIntGridLayer(level:data.Level, cfg:Dynamic) : Null<data.inst.LayerInstance> {
		var uid = getInt(cfg, "layerDefUid");
		var identifier = getDyn(cfg, "layerIdentifier");
		for(li in level.layerInstances) {
			if( li.def.type!=IntGrid )
				continue;
			if( uid!=null && li.layerDefUid==uid )
				return li;
			if( identifier!=null && li.def.identifier==Std.string(identifier) )
				return li;
		}
		return null;
	}

	static function isSolid(li:data.inst.LayerInstance, cx:Int, cy:Int, solidValues:Array<Dynamic>) {
		if( li==null || !li.isValid(cx,cy) )
			return false;
		var value = li.getIntGrid(cx,cy);
		if( value<=0 )
			return false;
		// Empty list means: every non-zero IntGrid value counts as a surface.
		if( solidValues.length==0 )
			return true;
		for(raw in solidValues) {
			var v = Std.parseInt(Std.string(raw));
			if( M.isValidNumber(v) && v==value )
				return true;
		}
		return false;
	}

	static function horizontalScore(li:data.inst.LayerInstance, y:Int, leftLevel:Int, rightLevelExclusive:Int, solidValues:Array<Dynamic>) {
		var x0 = li.levelToLayerCx(leftLevel);
		var x1 = li.levelToLayerCx(M.imax(leftLevel, rightLevelExclusive-1));
		if( x1<x0 ) {
			var tmp = x0;
			x0 = x1;
			x1 = tmp;
		}
		var score = 0;
		for(cx in x0...(x1+1))
			if( isSolid(li,cx,y,solidValues) )
				score++;
		return score;
	}

	static function verticalScore(li:data.inst.LayerInstance, x:Int, topLevel:Int, bottomLevelExclusive:Int, solidValues:Array<Dynamic>) {
		var y0 = li.levelToLayerCy(topLevel);
		var y1 = li.levelToLayerCy(M.imax(topLevel, bottomLevelExclusive-1));
		if( y1<y0 ) {
			var tmp = y0;
			y0 = y1;
			y1 = tmp;
		}
		var score = 0;
		for(cy in y0...(y1+1))
			if( isSolid(li,x,cy,solidValues) )
				score++;
		return score;
	}

	static function detectProbe(ei:data.inst.EntityInstance, li:data.inst.LayerInstance, solidValues:Array<Dynamic>) : String {
		// Use authored/resized bounds, not an appearance override size. This prevents the
		// selected variant from feeding back into the neighbour test itself.
		var width : Int = ei.customWidth!=null ? cast ei.customWidth : ei.def.width;
		var height : Int = ei.customHeight!=null ? cast ei.customHeight : ei.def.height;
		var left = M.round(ei.x - width*ei.def.pivotX) + ei._li.pxTotalOffsetX;
		var top = M.round(ei.y - height*ei.def.pivotY) + ei._li.pxTotalOffsetY;
		var right = left + width;
		var bottom = top + height;

		var floorScore = horizontalScore(li, li.levelToLayerCy(bottom), left, right, solidValues);
		var ceilingScore = horizontalScore(li, li.levelToLayerCy(top-1), left, right, solidValues);
		var leftScore = verticalScore(li, li.levelToLayerCx(left-1), top, bottom, solidValues);
		var rightScore = verticalScore(li, li.levelToLayerCx(right), top, bottom, solidValues);

		var best = 0;
		var probe = BACKGROUND;
		// Deterministic ties: floor > ceiling > left > right. Otherwise the side with the
		// largest amount of actual IntGrid contact wins.
		if( floorScore>best ) { best = floorScore; probe = FLOOR; }
		if( ceilingScore>best ) { best = ceilingScore; probe = CEILING; }
		if( leftScore>best ) { best = leftScore; probe = LEFT; }
		if( rightScore>best ) { best = rightScore; probe = RIGHT; }
		return probe;
	}

	static function valueForProbe(rules:Array<Dynamic>, probe:String) : Null<String> {
		for(rule in rules) {
			var cfg = getDyn(rule, META_FIELD);
			if( cfg!=null && Std.string(getDyn(cfg,"probe"))==probe ) {
				var v = getDyn(rule,"whenValue");
				return v==null ? null : Std.string(v);
			}
		}
		return null;
	}

	static function updateEntity(ei:data.inst.EntityInstance) {
		var rules = getManagedRules(ei.def);
		if( rules.length==0 )
			return;

		var first = rules[0];
		var fieldUid = getInt(first,"whenFieldUid");
		if( fieldUid==null )
			return;
		var fd = ei.def.getFieldDef(fieldUid);
		if( fd==null || fd.isArray )
			return;
		switch fd.type {
			case F_Enum(_), F_String:
			case _:
				return;
		}

		var cfg = getDyn(first, META_FIELD);
		var sampleLayer = findIntGridLayer(ei._li.level,cfg);
		if( sampleLayer==null )
			return;
		var probe = detectProbe(ei,sampleLayer,getArray(cfg,"solidValues"));
		var resolved = valueForProbe(rules,probe);
		if( resolved==null )
			resolved = valueForProbe(rules,BACKGROUND);
		if( resolved==null )
			return;

		var fi = ei.getFieldInstance(fd,true);
		if( fi==null )
			return;
		var current = fi.toJson().__value;
		if( current!=null && Std.string(current)==resolved )
			return;

		fi.parseValue(0,resolved);
		if( Editor.exists() && Editor.ME.project==ei._project ) {
			Editor.ME.needSaving = true;
			Editor.ME.levelRender.invalidateLayer(ei._li);
			Editor.ME.ge.emit(EntityFieldInstanceChanged(ei,fi));
		}
	}

	static function tick() {
		if( ticking || !Editor.exists() || Editor.ME.project==null || Editor.ME.curLevel==null )
			return;
		ticking = true;
		try {
			var level = Editor.ME.curLevel;
			for(li in level.layerInstances)
				if( li.def.type==Entities )
					for(ei in li.entityInstances)
						updateEntity(ei);
		}
		catch(err:Dynamic) {
			App.LOG.error("Smartive neighbour appearance resolver failed: "+Std.string(err));
		}
		ticking = false;
	}
}
