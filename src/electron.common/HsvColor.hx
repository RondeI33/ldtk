package;

/** One RGB/HSV conversion contract for every native Color picker control. */
class HsvColor {
	static inline function clamp(v:Float):Float return Math.max(0,Math.min(1,v));
	static inline function wrap(h:Float):Float return ((h%360)+360)%360;

	public static function hsvToRgb(h:Float,s:Float,v:Float):Int {
		h = wrap(h)/60;
		s = clamp(s);
		v = clamp(v);
		var c = v*s;
		var x = c*(1-Math.abs(h%2-1));
		var m = v-c;
		var r:Float=0, g:Float=0, b:Float=0;
		if( h<1 ) { r=c;g=x; }
		else if( h<2 ) { r=x;g=c; }
		else if( h<3 ) { g=c;b=x; }
		else if( h<4 ) { g=x;b=c; }
		else if( h<5 ) { r=x;b=c; }
		else { r=c;b=x; }
		return (Math.round((r+m)*255)<<16) | (Math.round((g+m)*255)<<8) | Math.round((b+m)*255);
	}

	public static function rgbToHsv(rgb:Int):{h:Float,s:Float,v:Float} {
		var r = ((rgb>>16)&255)/255.;
		var g = ((rgb>>8)&255)/255.;
		var b = (rgb&255)/255.;
		var max = Math.max(r,Math.max(g,b));
		var min = Math.min(r,Math.min(g,b));
		var delta = max-min;
		var h = delta==0 ? 0. : max==r ? (g-b)/delta : max==g ? (b-r)/delta+2 : (r-g)/delta+4;
		return {h:wrap(h*60),s:max==0 ? 0 : delta/max,v:max};
	}

}
