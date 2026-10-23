package ui;

/** Native-dialog HSV control: one hue wheel and a genuine saturation/value square. */
class HueWheelPicker {
	public var isChoosing(default,null) = false;
	public var hue(default,null):Float = 0;
	public var saturation(default,null):Float = 1;
	public var value(default,null):Float = 1;
	public var element(default,null):js.html.DivElement;
	var wheel:js.html.CanvasElement;
	var square:js.html.CanvasElement;
	var wheelImage:js.html.CanvasElement;
	var callback:String->Void;
	static inline var SIZE = 224;
	static inline var SQUARE = 116;
	static inline var CENTER = 112.;
	static inline var RADIUS = 99.;

	public function new() {
		element = js.Browser.document.createDivElement();
		element.className = "hueWheelPicker";
		element.style.cssText = "position:relative;width:224px;height:224px;margin:0 auto;touch-action:none;";
		wheel = js.Browser.document.createCanvasElement();
		wheel.width = SIZE;
		wheel.height = SIZE;
		wheel.className = "hueWheel";
		wheel.tabIndex = 0;
		wheel.setAttribute("role", "slider");
		wheel.setAttribute("aria-label", "Hue wheel");
		wheel.setAttribute("aria-valuemin", "0");
		wheel.setAttribute("aria-valuemax", "359");
		wheel.style.cssText = "display:block;cursor:crosshair;touch-action:none;";
		element.appendChild(wheel);
		square = js.Browser.document.createCanvasElement();
		square.width = SQUARE;
		square.height = SQUARE;
		square.className = "svSquare";
		square.tabIndex = 0;
		square.setAttribute("role", "slider");
		square.setAttribute("aria-label", "Saturation and value square; arrow keys adjust saturation and value");
		square.style.cssText = "position:absolute;left:54px;top:54px;width:116px;height:116px;cursor:crosshair;touch-action:none;outline:1px solid #555;";
		element.appendChild(square);
		wheelImage = js.Browser.document.createCanvasElement();
		wheelImage.width = SIZE;
		wheelImage.height = SIZE;
		var ctx = wheelImage.getContext2d();
		for( i in 0...360 ) {
			ctx.beginPath();
			ctx.strokeStyle = 'hsl($i, 100%, 50%)';
			ctx.lineWidth = 22;
			ctx.arc(CENTER,CENTER,RADIUS,i*Math.PI/180,(i+1.5)*Math.PI/180);
			ctx.stroke();
		}
		bind(wheel,true);
		bind(square,false);
		redraw();
	}

	public function appendTo(parent:js.html.Element) parent.appendChild(element);
	public function onChange(cb:String->Void) callback = cb;
	public function remove() {
		if( element.parentNode!=null ) element.parentNode.removeChild(element);
		callback = null;
	}

	static inline function clamp(v:Float):Float return Math.max(0,Math.min(1,v));
	static inline function wrap(h:Float):Float return ((h%360)+360)%360;

	public static inline function hsvToRgb(h:Float,s:Float,v:Float):Int return HsvColor.hsvToRgb(h,s,v);
	public static inline function rgbToHsv(rgb:Int):{h:Float,s:Float,v:Float} return HsvColor.rgbToHsv(rgb);

	public function setColor(color:Dynamic) {
		var rgb:Null<Int> = Std.isOfType(color,Int) ? cast color : Std.parseInt("0x"+StringTools.replace(Std.string(color),"#",""));
		if( rgb==null ) return;
		var hsv = rgbToHsv(rgb);
		// Grey/black does not reset the user's hue, so raising S/V remains useful.
		if( hsv.s>0 ) hue = hsv.h;
		saturation = hsv.s;
		value = hsv.v;
		changed();
	}

	public function setHsv(h:Float,s:Float,v:Float) {
		hue = wrap(h);
		saturation = clamp(s);
		value = clamp(v);
		changed();
	}

	public function getHexNumber():Int return hsvToRgb(hue,saturation,value);
	public function getHexString():String return "#"+StringTools.hex(getHexNumber(),6);

	function changed() {
		redraw();
		if( callback!=null ) callback(getHexString());
	}

	function bind(canvas:js.html.CanvasElement,isWheel:Bool) {
		function update(ev:js.html.PointerEvent) {
			var bounds = canvas.getBoundingClientRect();
			var x = (ev.clientX-bounds.left)/bounds.width;
			var y = (ev.clientY-bounds.top)/bounds.height;
			if( isWheel ) setHsv(Math.atan2(y-0.5,x-0.5)*180/Math.PI,saturation,value);
			else setHsv(hue,x,1-y);
		}
		canvas.addEventListener("pointerdown",(ev:js.html.PointerEvent)->{
			if( ev.button!=0 ) return;
			if( isWheel ) {
				var bounds = canvas.getBoundingClientRect();
				var dx = (ev.clientX-bounds.left)/bounds.width-0.5;
				var dy = (ev.clientY-bounds.top)/bounds.height-0.5;
				if( Math.sqrt(dx*dx+dy*dy)<0.37 ) return;
			}
			ev.preventDefault();
			ev.stopPropagation();
			canvas.focus();
			isChoosing = true;
			canvas.setPointerCapture(ev.pointerId);
			update(ev);
		});
		canvas.addEventListener("pointermove",(ev:js.html.PointerEvent)->{
			if( isChoosing && canvas.hasPointerCapture(ev.pointerId) ) {
				ev.preventDefault();
				update(ev);
			}
		});
		canvas.addEventListener("pointerup",(ev:js.html.PointerEvent)->{
			if( canvas.hasPointerCapture(ev.pointerId) ) {
				update(ev);
				canvas.releasePointerCapture(ev.pointerId);
			}
			isChoosing = false;
		});
		canvas.addEventListener("pointercancel",(ev:js.html.PointerEvent)->{
			if( canvas.hasPointerCapture(ev.pointerId) ) canvas.releasePointerCapture(ev.pointerId);
			isChoosing = false;
		});
		canvas.addEventListener("keydown",(ev:js.html.KeyboardEvent)->{
			if( ev.key!="ArrowLeft" && ev.key!="ArrowRight" && ev.key!="ArrowUp" && ev.key!="ArrowDown" ) return;
			ev.preventDefault();
			ev.stopPropagation();
			isChoosing = true;
			var sign = ev.key=="ArrowLeft" || ev.key=="ArrowDown" ? -1 : 1;
			var step = ev.shiftKey ? 0.1 : 0.01;
			if( isWheel ) setHsv(hue+sign*(ev.shiftKey ? 10 : 1),saturation,value);
			else if( ev.key=="ArrowLeft" || ev.key=="ArrowRight" ) setHsv(hue,saturation+sign*step,value);
			else setHsv(hue,saturation,value+sign*step);
			isChoosing = false;
		});
	}

	function marker(ctx:js.html.CanvasRenderingContext2D,x:Float,y:Float,radius:Float) {
		ctx.beginPath();ctx.arc(x,y,radius,0,Math.PI*2);
		ctx.lineWidth=3;ctx.strokeStyle="#111111";ctx.stroke();
		ctx.lineWidth=1;ctx.strokeStyle="#ffffff";ctx.stroke();
	}

	function redraw() {
		var ctx = wheel.getContext2d();
		ctx.clearRect(0,0,SIZE,SIZE);
		ctx.drawImage(wheelImage,0,0);
		marker(ctx,CENTER+Math.cos(hue*Math.PI/180)*RADIUS,CENTER+Math.sin(hue*Math.PI/180)*RADIUS,5);
		wheel.setAttribute("aria-valuenow",Std.string(Math.round(hue)));
		wheel.setAttribute("aria-valuetext",'Hue ${Math.round(hue)} degrees');
		ctx = square.getContext2d();
		ctx.clearRect(0,0,SQUARE,SQUARE);
		ctx.fillStyle = "#"+StringTools.hex(hsvToRgb(hue,1,1),6);
		ctx.fillRect(0,0,SQUARE,SQUARE);
		var white = ctx.createLinearGradient(0,0,SQUARE,0);
		white.addColorStop(0,"rgba(255,255,255,1)");
		white.addColorStop(1,"rgba(255,255,255,0)");
		ctx.fillStyle = white;
		ctx.fillRect(0,0,SQUARE,SQUARE);
		var black = ctx.createLinearGradient(0,0,0,SQUARE);
		black.addColorStop(0,"rgba(0,0,0,0)");
		black.addColorStop(1,"rgba(0,0,0,1)");
		ctx.fillStyle = black;
		ctx.fillRect(0,0,SQUARE,SQUARE);
		marker(ctx,saturation*(SQUARE-1),(1-value)*(SQUARE-1),4);
		square.setAttribute("aria-valuetext",'Saturation ${Math.round(saturation*100)}%, value ${Math.round(value*100)}%');
	}
}
