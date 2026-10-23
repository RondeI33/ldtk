import HsvColor;

/** RGB/HSV contract shared by wheel, square, numeric inputs and native Color export. */
class ColorPickerMathTest {
	static var assertions=0;
	static function equal(actual:Int,expected:Int,message:String) {
		assertions++;
		if( actual!=expected ) throw message+": expected "+StringTools.hex(expected,6)+", got "+StringTools.hex(actual,6);
	}
	static function main() {
		for( entry in [
			{h:0.,rgb:0xff0000},{h:60.,rgb:0xffff00},{h:120.,rgb:0x00ff00},
			{h:180.,rgb:0x00ffff},{h:240.,rgb:0x0000ff},{h:300.,rgb:0xff00ff},
			{h:360.,rgb:0xff0000},{h:-60.,rgb:0xff00ff},{h:720.,rgb:0xff0000},
		] ) equal(HsvColor.hsvToRgb(entry.h,1,1),entry.rgb,"Hue wheel primary/secondary angle");
		for( hue in [0.,60.,120.,180.,240.,300.,359.9] ) {
			equal(HsvColor.hsvToRgb(hue,0,1),0xffffff,"SV square upper-left is white");
			equal(HsvColor.hsvToRgb(hue,0,0),0x000000,"SV square lower-left is black");
			equal(HsvColor.hsvToRgb(hue,1,0),0x000000,"SV square lower-right is black");
		}
		for( r in [0,17,64,128,200,255] ) for( g in [0,17,64,128,200,255] ) for( b in [0,17,64,128,200,255] ) {
			var rgb=(r<<16)|(g<<8)|b;
			var hsv=HsvColor.rgbToHsv(rgb);
			equal(HsvColor.hsvToRgb(hsv.h,hsv.s,hsv.v),rgb,"Hex/RGB round trip");
		}
		for( gray in 0...256 ) {
			var hsv=HsvColor.rgbToHsv((gray<<16)|(gray<<8)|gray);
			equal(Math.round(hsv.s*100),0,"Grayscale saturation is zero");
			equal(Math.round(hsv.v*255),gray,"Grayscale value");
		}
		equal(HsvColor.hsvToRgb(0,2,2),0xff0000,"SV upper clamp");
		equal(HsvColor.hsvToRgb(0,-1,-1),0x000000,"SV lower clamp");
		trace("PASS: "+assertions+" hue wheel and SV square color-contract assertions");
	}
}
