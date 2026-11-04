package display;

import camerapreview.CameraPreviewGeometry;
import camerapreview.CameraPreviewGeometry.CameraPreviewProfile;
import camerapreview.CameraPreviewGeometry.CameraPreviewFrame;

/** Read-only camera framing. Unity owns the telemetry file; LDtk never writes it. */
class GameCameraPreview extends dn.Process {
	public var enabled(default,null) = false;
	public var gridMode(default,null) = false;
	public var useGuideGrid(default,null) = false;
	public var gridOriginAtCamera(default,null) = true;
	public var gridOriginX(default,null) = 0.;
	public var gridOriginY(default,null) = 0.;
	public var gridCellWidth(default,null) = 0.;
	public var gridCellHeight(default,null) = 0.;
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
	var modelBridge : Dynamic;
	var modelSource = "";
	var modelDetail = "";
	var modelDiagnostics = "";
	var lastModel:Dynamic;
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
		jControls.find(".cameraGridOrigin").on("change", _->setGridOriginAtCamera(selected(".cameraGridOrigin")=="camera"));
		var module:Dynamic = js.Syntax.code("require(require('url').fileURLToPath(new URL('js/camera-model-revision2.cjs', document.baseURI)))");
		modelBridge = module.createClient();
		for(selector in [".cameraFacing",".cameraMotion",".cameraLook",".cameraChoice",".cameraZone"])
			jControls.find(selector).on("change", _->{
				invalidated = true;
				updateModeNote();
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
 

	/** Hypothetical settled Joshua/camera state. It never changes any Unity object. */
	function currentModelState():Dynamic {
		var direction=Std.parseInt(selected(".cameraFacing"));
		return {
			direction:direction==null ? 0 : direction,
			motion:selected(".cameraMotion"),
			look:selected(".cameraLook"),
			cameraId:selected(".cameraChoice"),
			zoneId:selected(".cameraZone"),
		};
	}

	function selected(selector:String):String {
		var value:Dynamic=jControls.find(selector).val();
		return value==null ? "" : Std.string(value);
	}

	function hasRevision2():Bool {
		var model=profile==null ? null : profile.unityCameraModel;
		return model!=null && Reflect.field(model,"schemaVersion")==1 && Reflect.field(model,"modelRevision")==2;
	}

	function addOption(selector:String,value:String,label:String) {
		new J('<option/>').attr("value",value).text(label).appendTo(jControls.find(selector));
	}

	function updateModeNote() {
		var model=profile==null ? null : profile.unityCameraModel;
		var note="";
		if( hasRevision2() ) {
			var choice=selected(".cameraChoice");
			var cameras:Dynamic=Reflect.field(model,"cameras");
			if( choice!="" && Std.isOfType(cameras,Array) ) {
				for(camera in (cast cameras:Array<Dynamic>)) {
					if( Std.string(Reflect.field(camera,"id"))==choice || Std.string(Reflect.field(camera,"name"))==choice ) {
						if( Reflect.field(camera,"activation")=="none" )
							note="Preview-only camera: not activated in gameplay";
						var detail=Reflect.field(camera,"note");
						if( detail!=null && Std.string(detail)!="" ) note=Std.string(detail);
						break;
					}
				}
			}
			if( note=="" && selected(".cameraFacing")=="0" ) {
				var rooms:Dynamic=Reflect.field(model,"rooms");
				if( Std.isOfType(rooms,Array) )
					for(room in (cast rooms:Array<Dynamic>))
						if( Reflect.field(room,"neutralFacing")==false ) {
							note="Some camera rooms treat Neutral facing as Right";
							break;
						}
			}
		}
		jControls.find(".cameraModeNote").text(note);
	}

	/** Rebuild per-snapshot mode options without discarding the editor's chosen state. */
	function refreshModelControls() {
		var model=profile==null ? null : profile.unityCameraModel;
		var advanced=hasRevision2();
		jControls.find(".cameraModelControls").toggle(advanced);
		if( model==lastModel ) return;
		lastModel=model;
		if( modelBridge!=null ) modelBridge.clear();
		modelSource=""; modelDetail=""; modelDiagnostics="";
		var chosenCamera=selected(".cameraChoice");
		var chosenZone=selected(".cameraZone");
		jControls.find(".cameraChoice").empty();
		addOption(".cameraChoice","","Default");
		jControls.find(".cameraZone").empty();
		addOption(".cameraZone","","Automatic");
		if( advanced ) {
			var cameras:Dynamic=Reflect.field(model,"cameras");
			if( Std.isOfType(cameras,Array) )
				for(camera in (cast cameras:Array<Dynamic>)) {
					var id=Reflect.field(camera,"id");
					var name=Reflect.field(camera,"name");
					if( id==null || name==null ) continue;
					var label=Std.string(name);
					if( Reflect.field(camera,"activation")=="none" ) label+=" (preview only)";
					addOption(".cameraChoice",Std.string(id),label);
				}
			var zones:Dynamic=Reflect.field(model,"unityZones");
			var seen:Map<String,Bool>=new Map();
			if( Std.isOfType(zones,Array) )
				for(zone in (cast zones:Array<Dynamic>)) {
					var id=Reflect.field(zone,"id");
					if( id==null ) id=Reflect.field(zone,"entityIid");
					if( id==null || seen.exists(Std.string(id)) ) continue;
					seen.set(Std.string(id),true);
					addOption(".cameraZone",Std.string(id),Std.string(Reflect.field(zone,"kind"))+" · "+Std.string(id));
				}
			var rooms:Dynamic=Reflect.field(model,"rooms");
			var supportsLedge=false;
			if( Std.isOfType(rooms,Array) )
				for(room in (cast rooms:Array<Dynamic>)) {
					var look=Reflect.field(room,"look");
					if( look!=null && Reflect.field(look,"ledgePeek")!=null && Reflect.field(look,"ledgePeek")>0 )
						supportsLedge=true;
				}
			jControls.find(".cameraLookWrap").toggle(supportsLedge);
			if( !supportsLedge ) jControls.find(".cameraLook").val("none");
			jControls.find(".cameraChoice").val(chosenCamera);
			if( selected(".cameraChoice")=="" ) jControls.find(".cameraChoice").val("");
			jControls.find(".cameraZone").val(chosenZone);
			if( selected(".cameraZone")=="" ) jControls.find(".cameraZone").val("");
		}
		updateModeNote();
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
		// Inspecting a grid must never require placing a player or consume a stroke.
		if( value ) cancelPlacement();
		gridMode = value;
		invalidated = true;
		updateControls();
	}

	public function setGridOriginAtCamera(value:Bool) {
		if( !editor.canStartCameraPlacement() || placementGesture ) return;
		gridOriginAtCamera = value;
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
				gridOriginAtCamera = true;
				pointsByLevel = new Map();
				activeLevelIid = null;
				firstEnable = true;
				lastModel=null;
				if( modelBridge!=null ) modelBridge.clear();
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
		refreshModelControls();
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
		jControls.find(".cameraGridOptions").toggle(gridMode);
		jControls.find(".cameraGridOrigin").val(gridOriginAtCamera ? "camera" : "level").prop("disabled",useGuideGrid);
		var gridText = number(gridCellWidth)+" × "+number(gridCellHeight)+" px · początek ("+number(gridOriginX)+", "+number(gridOriginY)+")";
		if( gridOriginAtCamera && !useGuideGrid && !pinned && !placementArmed )
			gridText += " · ustaw Joshuę, aby przesunąć siatkę";
		jControls.find(".cameraGridMetrics").text(profile==null || gridCellWidth<=0 ? "" : gridText);
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
		jControls.find(".cameraModelStatus").text(modelSource=="" ? "" : modelSource+" · "+modelDetail);
		jControls.find(".cameraDiagnostics").text(modelDiagnostics);
	}

	static function number(value:Float) : String {
		return Std.string(Math.round(value*100)/100);
	}

	function grid() : { width:Float, height:Float, x:Float, y:Float } {
		var width = !useGuideGrid && frame!=null ? frame.width : profile.width;
		var height = !useGuideGrid && frame!=null ? frame.height : profile.height;
		var x = !useGuideGrid && gridOriginAtCamera && frame!=null ? frame.x : 0.;
		var y = !useGuideGrid && gridOriginAtCamera && frame!=null ? frame.y : 0.;
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

	function drawGrid(g:{width:Float,height:Float,x:Float,y:Float},origin:{x:Float,y:Float},col:Int) {
		var cam = editor.camera;
		var z = cam.adjustedZoom;
		var minX = Math.max(0,-origin.x/z);
		var maxX = Math.min(editor.curLevel.pxWid,(cam.width-origin.x)/z);
		var minY = Math.max(0,-origin.y/z);
		var maxY = Math.min(editor.curLevel.pxHei,(cam.height-origin.y)/z);
		if( maxX<=minX || maxY<=minY ) return;
		var xs = CameraPreviewGeometry.gridAxisLines(g.x,g.width,minX,maxX,z,12*cam.pixelRatio);
		var ys = CameraPreviewGeometry.gridAxisLines(g.y,g.height,minY,maxY,z,12*cam.pixelRatio);
		drawnGridLines = xs.length+ys.length;
		// A dark keyline and bright core remain legible on both light and dark art.
		// Widths are screen pixels, independent of map zoom and Retina scaling.
		for( pass in 0...2 ) {
			overlay.lineStyle((pass==0 ? 4 : 1.5)*cam.pixelRatio,pass==0 ? 0x101724 : col,pass==0 ? 0.85 : 0.95);
			for( xx in xs ) {
				overlay.moveTo(origin.x+xx*z,origin.y+minY*z);
				overlay.lineTo(origin.x+xx*z,origin.y+maxY*z);
			}
			for( yy in ys ) {
				overlay.moveTo(origin.x+minX*z,origin.y+yy*z);
				overlay.lineTo(origin.x+maxX*z,origin.y+yy*z);
			}
		}
	}

	function render() {
		invalidated = false;
		overlay.clear();
		drawnGridLines = 0;
		gridOriginX = gridOriginY = gridCellWidth = gridCellHeight = 0;
		renderError = null;
		root.visible = isActive() && profile!=null && (gridMode || pinned || placementArmed);
		frame = null;
		syncSprite();
		if( !root.visible ) return;
		var cam = editor.camera;
		var z = cam.adjustedZoom;
		var origin = levelOrigin();
		modelSource=""; modelDetail=""; modelDiagnostics="";
		if( (pinned || placementArmed) && hasRevision2() ) {
			try {
				var result:Dynamic=modelBridge.update({
					profile:profile,
					sidecarPath:getSourcePath(),
					levelIid:editor.curLevel.iid,
					point:{x:pointX,y:pointY},
					state:currentModelState(),
					requestEnabled:enabled,
				});
				modelSource=Std.string(Reflect.field(result,"source"));
				modelDetail=Std.string(Reflect.field(result,"status"));
				var diagnostics:Dynamic=Reflect.field(result,"diagnostics");
				if( Std.isOfType(diagnostics,Array) )
					modelDiagnostics=(cast diagnostics:Array<Dynamic>).map(x->Std.string(x)).join("\n");
				var error=Reflect.field(result,"error");
				if( error!=null && Std.string(error)!="" )
					modelDiagnostics=(modelDiagnostics=="" ? "" : modelDiagnostics+"\n")+Std.string(error);
				var suggested=Reflect.field(result,"frame");
				frame=suggested==null
					? CameraPreviewGeometry.frame(pointX,pointY,profile.width,profile.height,false)
					: cast suggested;
			}
			catch(error:Dynamic) {
				modelSource="Dimension-only fallback";
				modelDetail="Camera model could not be evaluated";
				modelDiagnostics=Std.string(error);
				frame=CameraPreviewGeometry.frame(pointX,pointY,profile.width,profile.height,false);
			}
		}
		else if( pinned || placementArmed ) {
			// Original Unity v1 snapshots and v1 static models keep their old path.
			try frame = CameraPreviewGeometry.playerFrame(profile,editor.curLevel.iid,pointX,pointY,
				editor.curLevel.worldX,editor.curLevel.worldY,editor.curLevel.pxWid,editor.curLevel.pxHei)
			catch(error:Dynamic) {
				renderError = "Nie można obliczyć kadru: "+Std.string(error);
				// The level-origin grid needs dimensions only; a missing model mapping
				// must not prevent inspecting or editing an otherwise valid level.
				if( !gridMode || gridOriginAtCamera && !useGuideGrid ) {
					root.visible = false;
					return;
				}
			}
		}
		var g = grid();
		gridOriginX = g.x;
		gridOriginY = g.y;
		gridCellWidth = g.width;
		gridCellHeight = g.height;
		if( gridMode ) {
			try drawGrid(g,origin,sourceStale ? 0xffd080 : 0xa0d8ff)
			catch(error:Dynamic) {
				// Guide metadata and live Unity answers must never crash editing.
				overlay.clear();
				drawnGridLines = 0;
				renderError = "Nie można wyświetlić siatki: "+Std.string(error);
			}
		}
		if( frame==null ) return;
		var x = origin.x+frame.x*z;
		var y = origin.y+frame.y*z;
		var w = frame.width*z;
		var h = frame.height*z;
		overlay.lineStyle(2*cam.pixelRatio,sourceStale ? 0xe8b75b : 0x7faaff,1);
		overlay.drawRect(x,y,w,h);

	}

	public function showSetup() {
		var dialog = new ui.modal.Dialog(null,"cameraPreviewSetup");
		dialog.addTitle(L.untranslated("Connect the Unity camera"),true);
		dialog.addParagraph(L.untranslated("In Unity, install or update the Smartive Unity package, then open <b>Tools &gt; LDTK-Smartive &gt; Camera preview sync</b>."));
		dialog.addParagraph(L.untranslated("Choose this LDtk project and the camera from the active scene. Check the importer Pixels Per Unit, then enable automatic sync or export a snapshot."));
		dialog.addParagraph(L.untranslated("Camera grid works without placing Joshua. Choose the level origin (0, 0), or align it to the camera frame at Joshua's position. Use Place Joshua to set or move the marker; ordinary drawing remains available while inspecting the grid."));
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
