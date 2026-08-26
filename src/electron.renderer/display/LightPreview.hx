package display;

typedef LightPreviewLight = {
	var x : Float;
	var y : Float;
	var left : Float;
	var top : Float;
	var width : Float;
	var height : Float;
	var lightType : String;
	var color : Int;
	var intensity : Float;
	var innerRadius : Float;
	var outerRadius : Float;
	var falloff : Float;
	var innerAngle : Float;
	var outerAngle : Float;
	var rotationDeg : Float;
	var shadows : Bool;
	var shadowStrength : Float;
}

typedef LightPreviewCaster = {
	var left : Float;
	var top : Float;
	var right : Float;
	var bottom : Float;
}

/**
	Lightweight active-level lighting preview for the RondeI33 LDtk fork.

	IMPORTANT: this feature intentionally does not add any fork-only project JSON.
	It reads ordinary LDtk Entity fields, so the exact same .ldtk project stays
	editable in stock LDtk. The fork merely interprets conventional Light2D fields
	for authoring preview.
**/
class LightPreview {
	static var _timer : Null<haxe.Timer>;
	static var _editor : Null<page.Editor>;
	static var _root : Null<h2d.Object>;
	static var _ambient : Null<h2d.Graphics>;
	static var _lights : Null<h2d.Graphics>;
	static var _shadows : Null<h2d.Graphics>;
	static var _gizmos : Null<h2d.Graphics>;
	static var _jUi : Null<js.jquery.JQuery>;
	static var _enabled = true;
	static var _mode = 1; // 0=unlit, 1=lit, 2=lit+shadows
	static var _lowRes = true;
	static var _lastSignature : Null<String>;

	static inline var DEFAULT_PIXELS_PER_UNIT = 16.;

	public static function ensure() {
		if( _timer!=null )
			return;
		_timer = new haxe.Timer(50); // max 20 preview checks/sec; redraws are dirty-only
		_timer.run = _tick;
	}

	static function _tick() {
		if( !page.Editor.exists() ) {
			if( _root!=null )
				_root.visible = false;
			if( _jUi!=null )
				_jUi.hide();
			return;
		}

		var ed = page.Editor.ME;
		_ensureRoot(ed);
		_ensureUi(ed);

		if( ed.worldMode || ed.curLevel==null ) {
			_root.visible = false;
			_jUi.hide();
			return;
		}

		_jUi.show();
		_syncRootTransform(ed);
		_root.visible = _enabled && _mode>0;
		if( !_root.visible )
			return;

		var data = _collect(ed);
		var signature = data.signature + '|mode='+_mode+'|low='+_lowRes;
		if( signature==_lastSignature )
			return;
		_lastSignature = signature;
		_render(ed, data.lights, data.casters, data.ambientDarkness);
	}

	static function _ensureRoot(ed:page.Editor) {
		if( _root!=null && _editor==ed )
			return;

		if( _root!=null )
			_root.remove();
		_editor = ed;
		_root = new h2d.Object();
		ed.root.add(_root, Const.DP_MAIN);
		_ambient = new h2d.Graphics(_root);
		_lights = new h2d.Graphics(_root);
		_shadows = new h2d.Graphics(_root);
		_gizmos = new h2d.Graphics(_root);
		_lastSignature = null;
	}

	static function _ensureUi(ed:page.Editor) {
		if( _jUi!=null && _jUi.parents().length>0 )
			return;

		_jUi = new J('<div class="forkLightPreview"/ >');
		_jUi.attr('style', 'position:fixed;right:14px;top:58px;z-index:10000;background:rgba(18,18,22,.92);border:1px solid rgba(255,255,255,.18);border-radius:6px;padding:7px 9px;color:#fff;font:12px sans-serif;box-shadow:0 3px 12px rgba(0,0,0,.35);user-select:none;');
		_jUi.append('<label style="display:block;margin-bottom:5px"><input class="lightingEnabled" type="checkbox" checked> Lighting preview</label>');
		_jUi.append('<div class="modes" style="display:flex;gap:4px"><button data-mode="0">Unlit</button><button data-mode="1">Lit</button><button data-mode="2">Lit + Shadows</button></div>');
		_jUi.append('<label style="display:block;margin-top:5px"><input class="lowRes" type="checkbox" checked> Low-res preview</label>');
		_jUi.append('<div style="opacity:.62;margin-top:3px">Active level only</div>');
		_jUi.appendTo(App.ME.jBody);

		_jUi.find('input.lightingEnabled').change(function(_) {
			_enabled = _jUi.find('input.lightingEnabled').is(':checked');
			_lastSignature = null;
		});
		_jUi.find('input.lowRes').change(function(_) {
			_lowRes = _jUi.find('input.lowRes').is(':checked');
			_lastSignature = null;
		});
		_jUi.find('button[data-mode]').click(function(ev) {
			var v = Std.parseInt(new J(ev.currentTarget).attr('data-mode'));
			if( v!=null )
				_mode = v;
			_updateUiState();
			_lastSignature = null;
		});
		_updateUiState();
	}

	static function _updateUiState() {
		if( _jUi==null )
			return;
		_jUi.find('button[data-mode]').css('opacity', '0.55');
		_jUi.find('button[data-mode="'+_mode+'"]').css('opacity', '1');
	}

	static function _syncRootTransform(ed:page.Editor) {
		var z = ed.camera.adjustedZoom;
		_root.setScale(z);
		_root.x = M.round( ed.camera.width*0.5 - ed.camera.levelX*z );
		_root.y = M.round( ed.camera.height*0.5 - ed.camera.levelY*z );
	}

	static inline function _norm(s:String) : String {
		return ~/[^a-z0-9]/g.replace(s.toLowerCase(), '');
	}

	static function _fields(ei:data.inst.EntityInstance) : Map<String,Dynamic> {
		var out : Map<String,Dynamic> = new Map();
		for(fd in ei.def.fieldDefs) {
			var fi = ei.getFieldInstance(fd, true);
			out.set(_norm(fd.identifier), fi.getFullJsonValue());
		}
		return out;
	}

	static function _field(fields:Map<String,Dynamic>, names:Array<String>) : Dynamic {
		for(name in names) {
			var key = _norm(name);
			if( fields.exists(key) )
				return fields.get(key);
		}
		return null;
	}

	static function _asFloat(v:Dynamic, fallback:Float) : Float {
		if( v==null )
			return fallback;
		var parsed = Std.parseFloat(Std.string(v));
		return Math.isNaN(parsed) ? fallback : parsed;
	}

	static function _asBool(v:Dynamic, fallback:Bool) : Bool {
		if( v==null )
			return fallback;
		if( Std.isOfType(v, Bool) )
			return v;
		var s = Std.string(v).toLowerCase();
		if( s=='true' || s=='1' || s=='yes' || s=='on' ) return true;
		if( s=='false' || s=='0' || s=='no' || s=='off' ) return false;
		return fallback;
	}

	static function _asColor(v:Dynamic, fallback:Int) : Int {
		if( v==null )
			return fallback;
		if( Std.isOfType(v, Int) )
			return v;
		var s = Std.string(v);
		try return dn.legacy.Color.hexToInt(s) catch(_:Dynamic) return fallback;
	}

	static function _isSettings(ei:data.inst.EntityInstance, fields:Map<String,Dynamic>) : Bool {
		var id = _norm(ei.def.identifier);
		return id.indexOf('lightpreviewsettings')>=0
			|| id.indexOf('ldtglightsettings')>=0
			|| fields.exists('ldtkpixelsperunityunit');
	}

	static function _isLight(ei:data.inst.EntityInstance, fields:Map<String,Dynamic>) : Bool {
		var id = _norm(ei.def.identifier);
		if( id.indexOf('settings')>=0 )
			return false;
		return id=='light'
			|| id.indexOf('light2d')>=0
			|| id.indexOf('unitylight')>=0
			|| fields.exists('lighttype')
			|| fields.exists('unitylighttype');
	}

	static function _isCaster(ei:data.inst.EntityInstance, fields:Map<String,Dynamic>) : Bool {
		var id = _norm(ei.def.identifier);
		return id.indexOf('shadowcaster')>=0
			|| _asBool(_field(fields, ['CastsLightShadow','CastsShadows','ShadowCaster','CastShadows']), false);
	}

	static function _entityLevelX(ed:page.Editor, ei:data.inst.EntityInstance) : Float {
		var li = ei._li;
		return ed.camera.getParallaxOffsetX(li) + ei.x*li.def.getScale();
	}

	static function _entityLevelY(ed:page.Editor, ei:data.inst.EntityInstance) : Float {
		var li = ei._li;
		return ed.camera.getParallaxOffsetY(li) + ei.y*li.def.getScale();
	}

	static function _directPxOrUnits(fields:Map<String,Dynamic>, pxNames:Array<String>, unitNames:Array<String>, ppu:Float, fallback:Float) : Float {
		var px = _field(fields, pxNames);
		if( px!=null )
			return _asFloat(px, fallback);
		var units = _field(fields, unitNames);
		if( units!=null )
			return _asFloat(units, fallback/ppu)*ppu;
		return fallback;
	}

	static function _buildLight(ed:page.Editor, ei:data.inst.EntityInstance, fields:Map<String,Dynamic>, ppu:Float) : Null<LightPreviewLight> {
		if( !_asBool(_field(fields, ['Enabled','LightEnabled']), true) )
			return null;
		if( !_asBool(_field(fields, ['PreviewEnabled','LightingPreviewEnabled']), true) )
			return null;

		var scale = ei._li.def.getScale();
		var x = _entityLevelX(ed, ei);
		var y = _entityLevelY(ed, ei);
		var fallbackRadius = M.fmax(4, M.fmax(ei.width, ei.height)*0.5*scale);
		var outer = _directPxOrUnits(fields,
			['OuterRadiusPx','RadiusPx','PointLightOuterRadiusPx'],
			['OuterRadius','Radius','PointLightOuterRadius'],
			ppu, fallbackRadius
		);
		if( outer<=0 )
			outer = fallbackRadius;
		var inner = _directPxOrUnits(fields,
			['InnerRadiusPx','PointLightInnerRadiusPx'],
			['InnerRadius','PointLightInnerRadius'],
			ppu, 0
		);
		inner = M.fclamp(inner, 0, outer);

		var intensity = M.fmax(0, _asFloat(_field(fields, ['Intensity','LightIntensity']), 1));
		if( intensity<=0 )
			return null;

		var rawType = _field(fields, ['LightType','UnityLightType','Type']);
		var lightType = rawType==null ? 'Point' : Std.string(rawType);
		var fallbackColor = ei.getSmartColor(false);
		var color = _asColor(_field(fields, ['Color','LightColor']), fallbackColor);
		var falloff = M.fclamp(_asFloat(_field(fields, ['Falloff','FalloffIntensity','FalloffStrength']), 0.5), 0, 1);
		var outerAngle = M.fclamp(_asFloat(_field(fields, ['OuterAngle','PointLightOuterAngle','SpotOuterAngle']), 360), 0.1, 360);
		var innerAngle = M.fclamp(_asFloat(_field(fields, ['InnerAngle','PointLightInnerAngle','SpotInnerAngle']), outerAngle), 0, outerAngle);
		var rotation = _asFloat(_field(fields, ['RotationDeg','Rotation','Angle','DirectionDeg']), 0);
		var shadows = _asBool(_field(fields, ['ShadowsEnabled','ShadowEnabled','Shadows']), false);
		var shadowStrength = M.fclamp(_asFloat(_field(fields, ['ShadowIntensity','ShadowStrength']), 1), 0, 1);

		return {
			x: x,
			y: y,
			left: x - ei.width*ei.def.pivotX*scale,
			top: y - ei.height*ei.def.pivotY*scale,
			width: ei.width*scale,
			height: ei.height*scale,
			lightType: lightType,
			color: color,
			intensity: intensity,
			innerRadius: inner,
			outerRadius: outer,
			falloff: falloff,
			innerAngle: innerAngle,
			outerAngle: outerAngle,
			rotationDeg: rotation,
			shadows: shadows,
			shadowStrength: shadowStrength,
		};
	}

	static function _buildCaster(ed:page.Editor, ei:data.inst.EntityInstance) : LightPreviewCaster {
		var scale = ei._li.def.getScale();
		var x = _entityLevelX(ed, ei);
		var y = _entityLevelY(ed, ei);
		var left = x - ei.width*ei.def.pivotX*scale;
		var top = y - ei.height*ei.def.pivotY*scale;
		return {
			left: left,
			top: top,
			right: left + ei.width*scale,
			bottom: top + ei.height*scale,
		};
	}

	static function _collect(ed:page.Editor) : { signature:String, lights:Array<LightPreviewLight>, casters:Array<LightPreviewCaster>, ambientDarkness:Float } {
		var all : Array<{ ei:data.inst.EntityInstance, fields:Map<String,Dynamic> }> = [];
		var signature = new StringBuf();
		var ppu = DEFAULT_PIXELS_PER_UNIT;
		var ambientDarkness = 0.;

		for(li in ed.curLevel.layerInstances) {
			if( li.def.type!=Entities )
				continue;
			for(ei in li.entityInstances) {
				var fields = _fields(ei);
				all.push({ ei:ei, fields:fields });
				signature.add(ei.iid);
				signature.add('@'+ei.x+','+ei.y+','+ei.width+','+ei.height+'=');
				try signature.add(haxe.Json.stringify(ei.toSimplifiedJson())) catch(_:Dynamic) signature.add(ei.toString());
				signature.add(';');
				if( _isSettings(ei, fields) ) {
					ppu = M.fmax(0.001, _asFloat(_field(fields, ['LDtkPixelsPerUnityUnit','PixelsPerUnit','PreviewPixelsPerUnit']), ppu));
					ambientDarkness = M.fclamp(_asFloat(_field(fields, ['PreviewAmbientDarkness','AmbientDarkness']), ambientDarkness), 0, 0.8);
				}
			}
		}

		var lights : Array<LightPreviewLight> = [];
		var casters : Array<LightPreviewCaster> = [];
		for(item in all) {
			if( _isLight(item.ei, item.fields) ) {
				var l = _buildLight(ed, item.ei, item.fields, ppu);
				if( l!=null )
					lights.push(l);
			}
			if( _isCaster(item.ei, item.fields) )
				casters.push(_buildCaster(ed, item.ei));
		}
		return {
			signature: signature.toString()+'|ppu='+ppu+'|amb='+ambientDarkness,
			lights: lights,
			casters: casters,
			ambientDarkness: ambientDarkness,
		};
	}

	static inline function _isGlobal(light:LightPreviewLight) : Bool {
		return _norm(light.lightType).indexOf('global')>=0;
	}

	static inline function _isFreeform(light:LightPreviewLight) : Bool {
		return _norm(light.lightType).indexOf('freeform')>=0;
	}

	static inline function _isSprite(light:LightPreviewLight) : Bool {
		return _norm(light.lightType).indexOf('sprite')>=0;
	}

	static function _visibleInCamera(ed:page.Editor, light:LightPreviewLight) : Bool {
		if( _isGlobal(light) )
			return true;
		var halfW = ed.camera.width*0.5/ed.camera.adjustedZoom;
		var halfH = ed.camera.height*0.5/ed.camera.adjustedZoom;
		var l = ed.camera.levelX-halfW;
		var r = ed.camera.levelX+halfW;
		var t = ed.camera.levelY-halfH;
		var b = ed.camera.levelY+halfH;
		return !( light.x+light.outerRadius<l || light.x-light.outerRadius>r || light.y+light.outerRadius<t || light.y-light.outerRadius>b );
	}

	static function _drawSector(g:h2d.Graphics, x:Float, y:Float, radius:Float, startDeg:Float, sweepDeg:Float, color:Int, alpha:Float, segments:Int) {
		if( radius<=0 || alpha<=0 )
			return;
		g.beginFill(color, M.fclamp(alpha,0,1));
		g.moveTo(x,y);
		for(i in 0...segments+1) {
			var a = (startDeg + sweepDeg*i/segments) * Math.PI/180;
			g.lineTo(x + Math.cos(a)*radius, y + Math.sin(a)*radius);
		}
		g.lineTo(x,y);
		g.endFill();
	}

	static function _drawPointLight(g:h2d.Graphics, light:LightPreviewLight) {
		var rings = _lowRes ? 10 : 26;
		var maxAlpha = M.fclamp(0.10 + light.intensity*0.13, 0.04, 0.72);
		var fallExp = 0.55 + light.falloff*2.2;
		var fullCircle = light.outerAngle>=359.9;
		for(i in 0...rings) {
			var ratio = 1 - i/rings;
			var radius = light.innerRadius + (light.outerRadius-light.innerRadius)*ratio;
			if( light.innerRadius<=0 )
				radius = light.outerRadius*ratio;
			var centerWeight = Math.pow(1-ratio, fallExp);
			var alpha = maxAlpha * (0.025 + centerWeight*0.14);
			if( fullCircle ) {
				g.beginFill(light.color, alpha);
				g.drawCircle(light.x, light.y, radius);
				g.endFill();
			}
			else {
				var start = light.rotationDeg - light.outerAngle*0.5;
				_drawSector(g, light.x, light.y, radius, start, light.outerAngle, light.color, alpha, _lowRes?12:28);
			}
		}
		if( light.innerRadius>0 ) {
			var a = maxAlpha*0.24;
			if( fullCircle ) {
				g.beginFill(light.color, a);
				g.drawCircle(light.x, light.y, light.innerRadius);
				g.endFill();
			}
			else {
				var start = light.rotationDeg - light.innerAngle*0.5;
				_drawSector(g, light.x, light.y, light.innerRadius, start, light.innerAngle, light.color, a, _lowRes?10:24);
			}
		}
	}

	static function _drawBoxLight(g:h2d.Graphics, light:LightPreviewLight) {
		var rings = _lowRes ? 6 : 14;
		var maxAlpha = M.fclamp(0.10 + light.intensity*0.12, 0.04, 0.62);
		for(i in 0...rings) {
			var t = i/rings;
			var pad = light.outerRadius*(1-t);
			var alpha = maxAlpha*(0.025 + t*0.08);
			g.beginFill(light.color, alpha);
			g.drawRect(light.left-pad, light.top-pad, light.width+pad*2, light.height+pad*2);
			g.endFill();
		}
		g.beginFill(light.color, maxAlpha*0.18);
		g.drawRect(light.left, light.top, light.width, light.height);
		g.endFill();
	}

	static function _drawGlobalLight(ed:page.Editor, g:h2d.Graphics, light:LightPreviewLight) {
		var alpha = M.fclamp(light.intensity*0.18, 0, 0.7);
		g.beginFill(light.color, alpha);
		g.drawRect(0,0,ed.curLevel.pxWid,ed.curLevel.pxHei);
		g.endFill();
	}

	static function _drawShadowForCaster(g:h2d.Graphics, light:LightPreviewLight, c:LightPreviewCaster) {
		var cx = (c.left+c.right)*0.5;
		var cy = (c.top+c.bottom)*0.5;
		var dx = cx-light.x;
		var dy = cy-light.y;
		var dist = Math.sqrt(dx*dx+dy*dy);
		if( dist<=0.001 || dist>light.outerRadius )
			return;
		var ax = dx/dist;
		var ay = dy/dist;
		var px = -ay;
		var py = ax;
		var corners = [
			{x:c.left,y:c.top}, {x:c.right,y:c.top},
			{x:c.right,y:c.bottom}, {x:c.left,y:c.bottom},
		];
		var minP = 1e20;
		var maxP = -1e20;
		var a = corners[0];
		var b = corners[0];
		for(p in corners) {
			var proj = (p.x-cx)*px + (p.y-cy)*py;
			if( proj<minP ) { minP=proj; a=p; }
			if( proj>maxP ) { maxP=proj; b=p; }
		}
		var ext = light.outerRadius*1.8;
		var alpha = M.fclamp(0.12 + light.shadowStrength*0.35, 0.08, 0.55);
		g.beginFill(0x000000, alpha);
		g.moveTo(a.x,a.y);
		g.lineTo(b.x,b.y);
		g.lineTo(b.x+ax*ext,b.y+ay*ext);
		g.lineTo(a.x+ax*ext,a.y+ay*ext);
		g.lineTo(a.x,a.y);
		g.endFill();
	}

	static function _drawGizmo(g:h2d.Graphics, light:LightPreviewLight) {
		if( _isGlobal(light) )
			return;
		g.lineStyle(1, light.color, 0.38);
		if( _isFreeform(light) || _isSprite(light) )
			g.drawRect(light.left, light.top, light.width, light.height);
		else {
			g.drawCircle(light.x, light.y, light.outerRadius);
			if( light.innerRadius>0 )
				g.drawCircle(light.x, light.y, light.innerRadius);
			if( light.outerAngle<359.9 ) {
				for(sign in [-1,1]) {
					var a = (light.rotationDeg + sign*light.outerAngle*0.5)*Math.PI/180;
					g.moveTo(light.x, light.y);
					g.lineTo(light.x+Math.cos(a)*light.outerRadius, light.y+Math.sin(a)*light.outerRadius);
				}
			}
		}
	}

	static function _render(ed:page.Editor, lights:Array<LightPreviewLight>, casters:Array<LightPreviewCaster>, ambientDarkness:Float) {
		_ambient.clear();
		_lights.clear();
		_shadows.clear();
		_gizmos.clear();

		if( ambientDarkness>0 ) {
			_ambient.beginFill(0x000000, ambientDarkness);
			_ambient.drawRect(0,0,ed.curLevel.pxWid,ed.curLevel.pxHei);
			_ambient.endFill();
		}

		for(light in lights) {
			if( !_visibleInCamera(ed, light) )
				continue;
			if( _isGlobal(light) )
				_drawGlobalLight(ed, _lights, light);
			else if( _isFreeform(light) || _isSprite(light) )
				_drawBoxLight(_lights, light);
			else
				_drawPointLight(_lights, light);

			if( _mode==2 && light.shadows && !_isGlobal(light) )
				for(c in casters)
					_drawShadowForCaster(_shadows, light, c);
			_drawGizmo(_gizmos, light);
		}
	}
}
