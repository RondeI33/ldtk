package display;

import camerapreview.CameraPreviewGeometry;
import camerapreview.CameraPreviewGeometry.CameraPreviewProfile;
import camerapreview.CameraPreviewGeometry.CameraPreviewFrame;

/** Read-only camera framing. Unity owns the telemetry file; LDtk never writes it. */
class GameCameraPreview extends dn.Process {
	public var enabled(default,null) = false;
	public var gridMode(default,null) = true;
	public var useGuideGrid(default,null) = false;
	public var pinned(default,null) = false;
	public var profile(default,null) : Null<CameraPreviewProfile>;
	public var frame(default,null) : Null<CameraPreviewFrame>;
	public var sourceError(default,null) : Null<String>;
	public var sourceStale(default,null) = false;
	public var renderError(default,null) : Null<String>;
	public var drawnGridLines(default,null) = 0;
	public var pointX(default,null) = 0.;
	public var pointY(default,null) = 0.;

	var editor : page.Editor;
	var overlay : h2d.Graphics;
	var label : h2d.Text;
	var jControls : J;
	var currentPath : Null<String>;
	var lastFileSignature : Null<String>;
	var nextPoll = 0.;
	var invalidated = true;
	var lastUiText = "";

	public function new(owner:page.Editor) {
		editor = owner;
		super(owner);
		// Above level/world art, below the existing cursor and ruler UI.
		createRootInLayers(editor.root, Const.DP_MAIN);
		overlay = new h2d.Graphics(root);
		label = new h2d.Text(Assets.getRegularFont(), root);
		label.textColor = 0xb8ceff;
		root.visible = false;
		jControls = App.ME.jPage.find("#cameraPreviewControls");
		jControls.find(".cameraGrid").click(_->setGridMode(true));
		jControls.find(".cameraFree").click(_->setGridMode(false));
		jControls.find(".cameraPin").click(_->setPinned(!pinned));
		jControls.find(".cameraSetup").click(_->showSetup());
		jControls.find(".cameraClose").click(_->editor.setCameraPreview(false));
		jControls.find(".cameraGuideGrid").on("change", _->{
			useGuideGrid = jControls.find(".cameraGuideGrid").prop("checked");
			invalidated = true;
		});
		editor.ge.addGlobalListener(onGlobalEvent);
	}

	public inline function isActive() : Bool {
		return enabled && !editor.worldMode && editor.curLevel!=null;
	}

	public function getSourcePath() : String {
		if( editor.project==null )
			return "";
		var path = editor.project.filePath.full;
		return StringTools.endsWith(path.toLowerCase(), ".ldtk")
			? path.substr(0, path.length-5)+".ldtk-camera.json"
			: path+"-camera.json";
	}

	public function setEnabled(value:Bool) {
		enabled = value;
		resetPoint();
		if( enabled )
			refreshSource(true);
		else {
			root.visible = false;
			frame = null;
		}
		jControls.toggle(enabled);
		invalidated = true;
		updateControls();
	}

	public function setGridMode(value:Bool) {
		gridMode = value;
		invalidated = true;
		updateControls();
	}

	public function setPinned(value:Bool) {
		pinned = value;
		invalidated = true;
		updateControls();
	}

	function resetPoint() {
		pinned = false;
		if( editor.curLevel!=null ) {
			pointX = editor.curLevel.pxWid*0.5;
			pointY = editor.curLevel.pxHei*0.5;
		}
		invalidated = true;
	}

	public function moveTo(m:Coords) {
		if( !isActive() || pinned )
			return;
		pointX = m.worldXf-editor.curLevel.worldX;
		pointY = m.worldYf-editor.curLevel.worldY;
		invalidated = true;
	}

	public function onMouseDown(ev:hxd.Event, m:Coords) {
		if( !isActive() )
			return;
		if( !ev.cancel && ev.button==0 ) {
			moveTo(m);
			setPinned(!pinned);
		}
		ev.cancel = true;
	}

	function onGlobalEvent(event:GlobalEvent) {
		switch event {
			case ProjectSelected:
				// No profile, mode or pinned point may leak between projects.
				currentPath = null;
				lastFileSignature = null;
				profile = null;
				frame = null;
				sourceError = null;
				sourceStale = false;
				gridMode = true;
				useGuideGrid = false;
				resetPoint();
				if( enabled ) refreshSource(true);
			case LevelSelected(_), WorldSelected(_):
				resetPoint();
			case WorldMode(_):
				resetPoint();
			case _:
		}
		invalidated = true;
	}

	/** Poll only the small camera file, never reload the edited project. */
	public function refreshSource(force=false) {
		var path = getSourcePath();
		if( path!=currentPath ) {
			currentPath = path;
			lastFileSignature = null;
			profile = null;
			frame = null;
			sourceStale = false;
			force = true;
		}
		nextPoll = haxe.Timer.stamp()+0.5;
		try {
			var fs : Dynamic = js.node.Require.require("fs");
			if( path=="" || !fs.existsSync(path) ) {
				profile = null;
				lastFileSignature = null;
				sourceError = "Waiting for Unity camera. Open Camera preview sync in Unity to connect this project.";
			}
			else {
				var stat : Dynamic = fs.statSync(path);
				var signature = Std.string(stat.mtimeMs)+":"+Std.string(stat.ctimeMs)+":"+Std.string(stat.ino)+":"+Std.string(stat.size);
				if( force || signature!=lastFileSignature ) {
					lastFileSignature = signature;
					if( stat.size>65536 ) {
						profile = null;
						sourceError = "Camera file exceeds the 64 KB limit.";
					}
					else {
						var result = CameraPreviewGeometry.parse(fs.readFileSync(path,"utf8"));
						profile = result.profile;
						sourceError = result.error;
					}
				}
			}
		}
		catch(_:Dynamic) {
			profile = null;
			lastFileSignature = null;
			sourceError = "Cannot read the Unity camera file. It will be retried automatically.";
		}
		sourceStale = false;
		if( profile!=null && profile.live ) {
			var timestamp = js.lib.Date.parse(profile.updatedAtUtc);
			var age = js.lib.Date.now()-timestamp;
			sourceStale = Math.isNaN(timestamp) || age>15000 || age< -5000;
		}
		invalidated = true;
		updateControls();
	}

	function updateControls() {
		jControls.find(".cameraGrid").toggleClass("active",gridMode).attr("aria-pressed",Std.string(gridMode));
		jControls.find(".cameraFree").toggleClass("active",!gridMode).attr("aria-pressed",Std.string(!gridMode));
		jControls.find(".cameraPin").toggleClass("active",pinned).attr("aria-pressed",Std.string(pinned));
		jControls.find(".cameraPin .label").text(pinned ? "Pinned" : "Follow");
		jControls.find(".guideOption").toggle(gridMode);
		jControls.find(".cameraGuideGrid").prop("checked",useGuideGrid);
		var text = sourceError;
		if( editor.worldMode )
			text = "Camera preview is paused in World view. Open a level to continue.";
		else if( profile!=null ) {
			var state = profile.live ? (sourceStale ? "Sync paused · last Unity snapshot" : "Unity camera synced") : "Unity camera snapshot";
			text = state+" · "+profile.sceneName+" / "+profile.cameraName+" · "+number(profile.width)+" × "+number(profile.height)+" px";
		}
		if( !editor.worldMode && renderError!=null ) text = renderError;
		if( text!=lastUiText ) {
			jControls.find(".cameraSource").text(text==null ? "Waiting for Unity camera" : text);
			lastUiText = text;
		}
		jControls.toggleClass("unavailable",profile==null || sourceStale || renderError!=null);
		var stamp = profile==null ? Math.NaN : js.lib.Date.parse(profile.updatedAtUtc);
		jControls.find(".cameraTimestamp")
			.text(Math.isNaN(stamp) ? "" : "Updated "+new js.lib.Date(stamp).toLocaleTimeString())
			.attr("title",profile==null ? "" : profile.updatedAtUtc);
		jControls.find(".cameraPin").prop("disabled",profile==null || editor.worldMode);
	}

	static function number(value:Float) : String {
		return Std.string(Math.round(value*100)/100);
	}

	function grid() : { width:Float, height:Float, x:Float, y:Float } {
		var width = profile.width;
		var height = profile.height;
		var x = 0.;
		var y = 0.;
		var li = editor.curLayerInstance;
		if( useGuideGrid && li!=null ) {
			var scale = li.def.getScale();
			if( li.def.guideGridWid>1 ) {
				width = li.def.guideGridWid*scale;
				x = li.pxTotalOffsetX*scale+editor.camera.getParallaxOffsetX(li);
			}
			if( li.def.guideGridHei>1 ) {
				height = li.def.guideGridHei*scale;
				y = li.pxTotalOffsetY*scale+editor.camera.getParallaxOffsetY(li);
			}
		}
		return { width:width, height:height, x:x, y:y };
	}

	function render() {
		invalidated = false;
		overlay.clear();
		drawnGridLines = 0;
		renderError = null;
		root.visible = isActive() && profile!=null;
		frame = null;
		if( !root.visible ) return;
		var cam = editor.camera;
		var z = cam.adjustedZoom;
		var levelRoot = editor.levelRender.root;
		var g = grid();
		try frame = CameraPreviewGeometry.frame(pointX,pointY,profile.width,profile.height,gridMode,g.width,g.height,g.x,g.y)
		catch(_:Dynamic) {
			root.visible = false;
			renderError = "Camera or guide-grid dimensions cannot be displayed. Check the Unity scale and layer guide grid.";
			return;
		}
		var x = levelRoot.x+frame.x*z;
		var y = levelRoot.y+frame.y*z;
		var w = frame.width*z;
		var h = frame.height*z;
		var screenW = cam.width;
		var screenH = cam.height;
		var left = Math.max(0,Math.min(screenW,x));
		var right = Math.max(0,Math.min(screenW,x+w));
		var top = Math.max(0,Math.min(screenH,y));
		var bottom = Math.max(0,Math.min(screenH,y+h));
		overlay.beginFill(0x080c14,0.76);
		overlay.drawRect(0,0,screenW,top);
		overlay.drawRect(0,bottom,screenW,screenH-bottom);
		overlay.drawRect(0,top,left,bottom-top);
		overlay.drawRect(right,top,screenW-right,bottom-top);
		overlay.endFill();

		var col = sourceStale ? 0xe8b75b : 0x7faaff;
		if( gridMode ) {
			overlay.lineStyle(cam.pixelRatio,col,0.22);
			var minX = Math.max(0,-levelRoot.x/z);
			var maxX = Math.min(editor.curLevel.pxWid,(screenW-levelRoot.x)/z);
			var minY = Math.max(0,-levelRoot.y/z);
			var maxY = Math.min(editor.curLevel.pxHei,(screenH-levelRoot.y)/z);
			// Pixel-density and iteration caps keep pathological/huge maps cheap.
			if( maxX>minX && maxY>minY ) {
				if( g.width*z>=12*cam.pixelRatio ) {
					var xx = g.x+Math.ceil((minX-g.x)/g.width)*g.width;
					var count = 0;
					while( xx<=maxX && count++<200 ) {
						overlay.moveTo(levelRoot.x+xx*z,levelRoot.y+minY*z);
						overlay.lineTo(levelRoot.x+xx*z,levelRoot.y+maxY*z);
						xx += g.width;
						drawnGridLines++;
					}
				}
				if( g.height*z>=12*cam.pixelRatio ) {
					var yy = g.y+Math.ceil((minY-g.y)/g.height)*g.height;
					var count = 0;
					while( yy<=maxY && count++<200 ) {
						overlay.moveTo(levelRoot.x+minX*z,levelRoot.y+yy*z);
						overlay.lineTo(levelRoot.x+maxX*z,levelRoot.y+yy*z);
						yy += g.height;
						drawnGridLines++;
					}
				}
			}
		}
		overlay.lineStyle(2*cam.pixelRatio,col,1);
		overlay.drawRect(x,y,w,h);
		overlay.lineStyle(cam.pixelRatio,col,0.65);
		var cross = 5*cam.pixelRatio;
		overlay.moveTo(x+w/2-cross,y+h/2);
		overlay.lineTo(x+w/2+cross,y+h/2);
		overlay.moveTo(x+w/2,y+h/2-cross);
		overlay.lineTo(x+w/2,y+h/2+cross);
		label.text = (pinned ? "PINNED · " : "")+(gridMode ? "Camera cell "+frame.column+", "+frame.row : "Camera center "+number(frame.centerX)+", "+number(frame.centerY));
		label.textColor = col;
		label.setScale(cam.pixelRatio);
		label.x = Math.max(8*cam.pixelRatio,Math.min(screenW-label.textWidth*cam.pixelRatio-8*cam.pixelRatio,x));
		label.y = Math.max(8*cam.pixelRatio,Math.min(screenH-24*cam.pixelRatio,y-22*cam.pixelRatio));
	}

	public function showSetup() {
		var dialog = new ui.modal.Dialog(null,"cameraPreviewSetup");
		dialog.addTitle(L.untranslated("Connect the Unity camera"),true);
		dialog.addParagraph(L.untranslated("In Unity, install or update the Smartive Unity package, then open <b>Tools &gt; LDTK-Smartive &gt; Camera preview sync</b>."));
		dialog.addParagraph(L.untranslated("Choose this LDtk project and the camera from the active scene. Check the importer Pixels Per Unit, then enable automatic sync or export a snapshot."));
		dialog.addParagraph(L.untranslated("The camera frame uses Unity's orthographic size, aspect ratio and importer scale. Grid mode uses camera-sized cells; the optional layer guide grid changes their spacing. Free point mode follows the mouse. Click to pin or release the frame. Escape closes the preview."));
		dialog.addParagraph(L.untranslated("This previews the camera framing of the LDtk artwork. Camera follow, room constraints, Unity-only objects, lighting and post-processing run in Unity."));
		new J('<p class="cameraFilePath"/>').text(getSourcePath()).appendTo(dialog.jContent);
		dialog.addButton("Copy Unity package URL",null,()->{
			electron.Clipboard.writeText("https://github.com/RondeI33/ldtk.git?path=/unity/com.rondei33.ldtk-smartive-unity-icons#master");
			N.quick("Unity package URL copied");
		});
		dialog.addButton("Refresh camera",null,()->{ refreshSource(true); dialog.close(); });
		dialog.addClose();
	}

	override function onResize() {
		super.onResize();
		invalidated = true;
	}

	override function postUpdate() {
		super.postUpdate();
		if( enabled && haxe.Timer.stamp()>=nextPoll )
			refreshSource();
		if( invalidated ) {
			render();
			updateControls();
		}
	}

	override function onDispose() {
		if( editor.ge!=null ) editor.ge.removeListener(onGlobalEvent);
		jControls.find("*").off();
		jControls.hide();
		super.onDispose();
	}
}
