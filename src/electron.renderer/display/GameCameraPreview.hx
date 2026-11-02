package display;

import camerapreview.CameraPreviewGeometry;
import camerapreview.CameraPreviewGeometry.CameraPreviewProfile;
import camerapreview.CameraPreviewGeometry.CameraPreviewFrame;

/** Read-only camera framing. Unity owns the telemetry file; LDtk never writes it. */
class GameCameraPreview extends dn.Process {
	public var enabled(default,null) = false;
	public var gridMode(default,null) = false;
	public var useGuideGrid(default,null) = false;
	public var pinned(default,null) = false;
	/** Explicit placement action. Switching levels never arms this automatically. */
	public var placementArmed(default,null) = false;
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
	var jControls : J;
	var jSprite : J;
	// The supplied Joshua artwork is a fixed, non-interactive authoring marker.
	// No sprite importer, prefab calibration or per-session appearance settings.
	var spriteWidth = 32.;
	var spriteHeight = 44.;
	var currentPath : Null<String>;
	var lastFileSignature : Null<String>;
	var nextPoll = 0.;
	var invalidated = true;
	var lastUiText = "";
	var pointsByLevel : Map<String,{x:Float,y:Float,pinned:Bool}> = new Map();
	var activeLevelIid : Null<String>;
	var firstEnable = true;
	var lastTransform = "";
	var placementGesture = false;
	public var state(get,never):String;
	function get_state():String return !enabled ? "off" : placementArmed ? "placing" : pinned ? "locked" : "idle";

	public function new(owner:page.Editor) {
		editor = owner;
		super(owner);
		// Above level/world art, below the existing cursor and ruler UI.
		createRootInLayers(editor.root, Const.DP_MAIN);
		overlay = new h2d.Graphics(root);
		root.visible = false;
		jControls = App.ME.jPage.find("#cameraPreviewControls");
		jSprite = new J('<img class="cameraJoshuaSprite" alt="" aria-hidden="true"/>');
		jSprite.attr("src","img/joshua-idle-preview.png").attr("draggable","false");
		jSprite.appendTo(App.ME.jPage);
		jSprite.hide();
		var img:Dynamic = js.Browser.document.querySelector(".cameraJoshuaSprite");
		img.addEventListener("load",function(_:Dynamic) {
			spriteWidth=img.naturalWidth;
			spriteHeight=img.naturalHeight;
			invalidated=true;
		});
		jControls.find(".cameraGrid").click(_->setGridMode(true));
		jControls.find(".cameraFree").click(_->setGridMode(false));
		jControls.find(".cameraPin").click(_->{
			if( placementArmed ) cancelPlacement();
			else setPinned(false);
		});
		jControls.find(".cameraSetup").click(_->showSetup());
		jControls.find(".cameraClose").click(_->editor.setCameraPreview(false));
		jControls.find(".cameraGuideGrid").on("change", _->{
			useGuideGrid = jControls.find(".cameraGuideGrid").prop("checked");
			invalidated = true;
		});
		editor.ge.addGlobalListener(onGlobalEvent);
	}

	public inline function isActive() : Bool {
		return enabled && editor.curLevel!=null;
	}

	public inline function isPlacing() : Bool {
		return isActive() && !editor.worldMode && placementArmed;
	}

 
	/** Editor-level position projected through the actual visible level or world camera. */
	function levelOrigin() : {x:Float,y:Float} {
		if( editor.worldMode ) {
			var z=editor.camera.adjustedZoom;
			return {
				x:editor.worldRender.root.x+editor.curLevel.worldX*z,
				y:editor.worldRender.root.y+editor.curLevel.worldY*z
			};
		}
		return {x:editor.levelRender.root.x,y:editor.levelRender.root.y};
	}

	/** DOM sprite is nearest-neighbour, receives no pointer input, and stays anchored in World view. */
	function syncSprite() {
		var visible = isActive() && (pinned || placementArmed);
		jSprite.toggle(visible);
		if( !visible ) return;
		var ppu=profile==null ? 16. : profile.pixelsPerUnit;
		var z=editor.camera.adjustedZoom;
		var ratio=editor.camera.pixelRatio;
		var w=spriteWidth*ppu/16*z/ratio;
		var h=spriteHeight*ppu/16*z/ratio;
		if( !Math.isFinite(w) || !Math.isFinite(h) || w<0.001 || h<0.001 || w>16000 || h>16000 ) {
			jSprite.hide();
			return;
		}
		// Keep the Joshua marker readable when zoomed out to the entire world.
		if( editor.worldMode && h<16 ) {
			w*=16/h;
			h=16;
		}
		var o=levelOrigin();
		var canvas:Dynamic=js.Browser.document.getElementById("webgl");
		var bounds:Dynamic=canvas.getBoundingClientRect();
		var x=bounds.left+(o.x+pointX*z)/ratio-w*0.5;
		var y=bounds.top+(o.y+pointY*z)/ratio-h;
		if( x+w<bounds.left || x>bounds.right || y+h<bounds.top || y>bounds.bottom ) {
			jSprite.hide();
			return;
		}
		jSprite.css("left",Std.string(x)+"px");
		jSprite.css("top",Std.string(y)+"px");
		jSprite.css("width",Std.string(w)+"px");
		jSprite.css("height",Std.string(h)+"px");
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
		if( enabled ) {
			selectLevelAnchor(editor.curLevel);
			// Initial opening retains the original one-click Joshua placement flow.
			// Later toggles, level switches and World View navigation never re-arm it.
			if( firstEnable && !pinned && !editor.worldMode )
				setPinned(false);
			firstEnable = false;
			refreshSource(true);
		}
		else {
			cancelPlacement();
			root.visible = false;
			frame = null;
			jSprite.hide();
		}
		jControls.toggle(enabled);
		invalidated = true;
		updateControls();
	}

	public function setGridMode(value:Bool) {
		if( !editor.canStartCameraPlacement() || placementGesture ) return;
		gridMode = value;
		invalidated = true;
		updateControls();
	}

	public function setPinned(value:Bool) {
		if( !isActive() || editor.worldMode ) return;
		if( !value && (!editor.canStartCameraPlacement() || placementGesture) ) return;
		if( value ) {
			pinned = true;
			placementArmed = false;
			rememberPoint();
		}
		else {
			// Repositioning is explicit, never triggered by selecting another level.
			pinned = false;
			placementArmed = true;
		}
		invalidated = true;
		updateControls();
	}

	/** Abandon an unfinished placement without losing an earlier committed anchor. */
	function cancelPlacement() {
		if( !placementArmed ) return;
		placementArmed = false;
		var saved = activeLevelIid==null ? null : pointsByLevel.get(activeLevelIid);
		pinned = saved!=null && saved.pinned;
		if( pinned ) {
			pointX = saved.x;
			pointY = saved.y;
		}
		else if( editor.curLevel!=null ) {
			pointX = editor.curLevel.pxWid*0.5;
			pointY = editor.curLevel.pxHei*0.5;
		}
		invalidated = true;
		updateControls();
	}

	function resetPoint() {
		placementGesture = false;
		pinned = false;
		placementArmed = false;
		pointX = editor.curLevel==null ? 0. : editor.curLevel.pxWid*0.5;
		pointY = editor.curLevel==null ? 0. : editor.curLevel.pxHei*0.5;
		invalidated = true;
	}

	function rememberPoint() {
		// Cursor movement is only a temporary placement preview; never store it.
		if( pinned && activeLevelIid!=null )
			pointsByLevel.set(activeLevelIid,{x:pointX,y:pointY,pinned:true});
	}

	function selectLevelAnchor(level:data.Level) {
		var iid = level==null ? null : level.iid;
		if( iid==activeLevelIid ) return;
		rememberPoint();
		activeLevelIid=iid;
		placementGesture=false;
		placementArmed=false;
		var saved = iid==null ? null : pointsByLevel.get(iid);
		if( saved!=null ) {
			pointX=saved.x;
			pointY=saved.y;
			pinned=saved.pinned;
		}
		else {
			pinned=false;
			pointX=level==null ? 0. : level.pxWid*0.5;
			pointY=level==null ? 0. : level.pxHei*0.5;
		}
		invalidated=true;
	}

	public function moveTo(m:Coords) {
		if( !isPlacing() )
			return;
		pointX = m.worldXf-editor.curLevel.worldX;
		pointY = m.worldYf-editor.curLevel.worldY;
		invalidated = true;
	}

	public function onMouseDown(ev:hxd.Event, m:Coords) {
		if( !isPlacing() || ev.cancel || ev.button!=0 ) return;
		moveTo(m);
		setPinned(true);
		placementGesture = true;
		ev.cancel = true;
	}

	public inline function isPlacementGesture():Bool return placementGesture;

	public function endPlacementGesture():Bool {
		var consumed=placementGesture;
		placementGesture=false;
		return consumed;
	}

	function onGlobalEvent(event:GlobalEvent) {
		switch event {
			case ProjectSelected:
				// Persist only for the open project; never leak anchors into a new one.
				currentPath = null;
				lastFileSignature = null;
				profile = null;
				frame = null;
				sourceError = null;
				sourceStale = false;
				gridMode = false;
				useGuideGrid = false;
				pointsByLevel = new Map();
				activeLevelIid = null;
				firstEnable = true;
				resetPoint();
				if( enabled ) refreshSource(true);
			case LevelSelected(level):
				// Zoom-triggered re-selection of the same level must not reset Joshua.
				selectLevelAnchor(level);
			case WorldSelected(_):
				// Preview geometry is re-projected below; do not discard placement.
			case WorldMode(active):
				// World navigation must never leave Joshua stuck to the cursor.
				if( active ) cancelPlacement();
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
					if( stat.size>4*1024*1024 ) {
						profile = null;
						sourceError = "Camera file exceeds the 4 MiB preview limit.";
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
		jControls.find(".cameraPin").toggle(enabled).attr("aria-pressed",Std.string(placementArmed));
		jControls.find(".cameraPin .label").text(placementArmed ? "Anuluj" : pinned ? "Przestaw Joshuę" : "Ustaw Joshuę");
		jControls.find(".guideOption").toggle(gridMode);
		jControls.find(".cameraGuideGrid").prop("checked",useGuideGrid);
		var text=sourceError;
		if( profile!=null ) {
			text=number(profile.width)+" × "+number(profile.height)+" px"
				+(profile.unityCameraModel==null ? " · tylko wymiary" : " · model Unity (niezweryfikowany)");
			if( sourceStale ) text+=" · snapshot";
		}
		if( renderError!=null ) text=renderError;
		if( text!=lastUiText ) {
			jControls.find(".cameraSource").text(text==null ? "Brak danych kamery z Unity" : text);
			lastUiText=text;
		}
		jControls.toggleClass("unavailable",profile==null || sourceStale || renderError!=null);
		// Placement of an editor-only marker need not wait for Unity sync.
		jControls.find(".cameraPin").prop("disabled",editor.worldMode);
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
		root.visible = isActive() && profile!=null && (pinned || placementArmed);
		frame = null;
		syncSprite();
		if( !root.visible ) return;
		var cam = editor.camera;
		var z = cam.adjustedZoom;
		var origin = levelOrigin();
		var g = grid();
		// Switching the grid never changes what the camera sees at Joshua's position.
		try frame = CameraPreviewGeometry.playerFrame(profile,editor.curLevel.iid,pointX,pointY,
			editor.curLevel.worldX,editor.curLevel.worldY,editor.curLevel.pxWid,editor.curLevel.pxHei)
		catch(error:Dynamic) {
			root.visible = false;
			renderError = "Nie można obliczyć kadru: "+Std.string(error);
			return;
		}
		var x = origin.x+frame.x*z;
		var y = origin.y+frame.y*z;
		var w = frame.width*z;
		var h = frame.height*z;
		var screenW = cam.width;
		var screenH = cam.height;
		var col = sourceStale ? 0xe8b75b : 0x7faaff;
		if( gridMode ) {
			// Default guide cells radiate from the actual camera frame, not a snapped origin.
			if( !useGuideGrid ) { g.width=frame.width; g.height=frame.height; g.x=frame.x; g.y=frame.y; }
			overlay.lineStyle(cam.pixelRatio,col,0.22);
			var minX = Math.max(0,-origin.x/z);
			var maxX = Math.min(editor.curLevel.pxWid,(screenW-origin.x)/z);
			var minY = Math.max(0,-origin.y/z);
			var maxY = Math.min(editor.curLevel.pxHei,(screenH-origin.y)/z);
			// Pixel-density and iteration caps keep pathological/huge maps cheap.
			if( maxX>minX && maxY>minY ) {
				if( g.width*z>=12*cam.pixelRatio ) {
					var xx = g.x+Math.ceil((minX-g.x)/g.width)*g.width;
					var count = 0;
					while( xx<=maxX && count++<200 ) {
						overlay.moveTo(origin.x+xx*z,origin.y+minY*z);
						overlay.lineTo(origin.x+xx*z,origin.y+maxY*z);
						xx += g.width;
						drawnGridLines++;
					}
				}
				if( g.height*z>=12*cam.pixelRatio ) {
					var yy = g.y+Math.ceil((minY-g.y)/g.height)*g.height;
					var count = 0;
					while( yy<=maxY && count++<200 ) {
						overlay.moveTo(origin.x+minX*z,origin.y+yy*z);
						overlay.lineTo(origin.x+maxX*z,origin.y+yy*z);
						yy += g.height;
						drawnGridLines++;
					}
				}
			}
		}
		overlay.lineStyle(2*cam.pixelRatio,col,1);
		overlay.drawRect(x,y,w,h);

	}

	public function showSetup() {
		var dialog = new ui.modal.Dialog(null,"cameraPreviewSetup");
		dialog.addTitle(L.untranslated("Connect the Unity camera"),true);
		dialog.addParagraph(L.untranslated("In Unity, install or update the Smartive Unity package, then open <b>Tools &gt; LDTK-Smartive &gt; Camera preview sync</b>."));
		dialog.addParagraph(L.untranslated("Choose this LDtk project and the camera from the active scene. Check the importer Pixels Per Unit, then enable automatic sync or export a snapshot."));
		dialog.addParagraph(L.untranslated("Click the level to place Joshua. The border shows the camera view at his position; camera grid only changes the grid display. The normal editor tools remain usable after placement."));
		dialog.addParagraph(L.untranslated("Camera framing comes from the Unity snapshot. Runtime damping and transitions are not simulated. The Joshua marker is editor-only and does not change the level file."));
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
		if( isActive() ) {
			var o=levelOrigin();
			var transform=o.x+":"+o.y+":"+editor.worldMode+":"+editor.camera.adjustedZoom+":"+editor.camera.pixelRatio;
			if( transform!=lastTransform ) {lastTransform=transform;invalidated=true;}
		}
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
		jSprite.remove();
		jControls.hide();
		super.onDispose();
	}
}
