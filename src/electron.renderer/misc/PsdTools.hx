package misc;

typedef PsdLayerInfo = {
	var key : String;
	var path : String;
	var name : String;
	var depth : Int;
	var isGroup : Bool;
	var selectable : Bool;
	var visible : Bool;
	var opacity : Float;
	var blendMode : String;
	var clipping : Bool;
	var left : Int;
	var top : Int;
	var right : Int;
	var bottom : Int;
	var ?id : Null<Int>;
	var ?kind : String;
	var ?exportRelPath : Null<String>;
	var ?effectiveOpacity : Float;
}

typedef PsdGeneratedImport = {
	var sourceRelPath : String;
	var selectedLayerKeys : Array<String>;
	var selectedLayerPaths : Array<String>;
	var displayRelPath : String;
	var displayLeft : Int;
	var displayTop : Int;
	var displayWidth : Int;
	var displayHeight : Int;
	var documentWidth : Int;
	var documentHeight : Int;
	var layers : Array<PsdLayerInfo>;
	var ?legacy : Bool;
}

class PsdTools {
	static inline var GENERATED_DIR = ".ldtk-psd";
	static inline var GENERATED_CONFIG = "import.json";
	static inline var FORMAT_ID = "ldtk-smartive-psd-import";
	static inline var FORMAT_VERSION = 2;

	static var lib : Dynamic;
	static var canvasInitialized = false;

	public static function isPsdPath(path:Null<String>) : Bool {
		if( path==null )
			return false;
		var ext = dn.FilePath.extractExtension(path);
		return ext!=null && ext.toLowerCase()=="psd";
	}

	static function getLib() : Dynamic {
		if( lib==null )
			lib = js.Syntax.code("require('ag-psd')");

		if( !canvasInitialized ) {
			canvasInitialized = true;
			lib.initializeCanvas(function(w:Int,h:Int) {
				var c:Dynamic = js.Browser.document.createElement("canvas");
				c.width = w;
				c.height = h;
				return c;
			});
		}
		return lib;
	}

	static function readPsd(absPath:String) : Dynamic {
		if( absPath==null || !NT.fileExists(absPath) )
			throw "PSD source file was not found.";

		var fs:Dynamic = js.Syntax.code("require('fs')");
		var bytes:Dynamic = fs.readFileSync(absPath);
		try {
			return getLib().readPsd(bytes, {
				skipCompositeImageData: true,
				skipThumbnail: true,
				logMissingFeatures: false,
			});
		}
		catch(e:Dynamic) {
			throw "Could not decode PSD: "+Std.string(e);
		}
	}

	static inline function intField(obj:Dynamic, name:String, def=0) : Int {
		var v:Dynamic = Reflect.field(obj,name);
		return v==null ? def : Std.int(v);
	}

	static inline function floatField(obj:Dynamic, name:String, def=1.0) : Float {
		var v:Dynamic = Reflect.field(obj,name);
		return v==null ? def : cast v;
	}

	static inline function boolField(obj:Dynamic, name:String, def=false) : Bool {
		var v:Dynamic = Reflect.field(obj,name);
		return v==null ? def : v==true;
	}

	static function layerKind(node:Dynamic, isGroup:Bool) {
		if( isGroup )
			return "group";
		if( Reflect.field(node,"text")!=null )
			return "text";
		if( Reflect.field(node,"placedLayer")!=null )
			return "smartObject";
		if( Reflect.field(node,"adjustment")!=null )
			return "adjustment";
		if( Reflect.field(node,"vectorFill")!=null || Reflect.field(node,"vectorMask")!=null )
			return "vector";
		return "pixel";
	}

	static function collectLayers(psd:Dynamic) : Array<{ info:PsdLayerInfo, node:Dynamic }> {
		var out : Array<{ info:PsdLayerInfo, node:Dynamic }> = [];
		var root:Dynamic = Reflect.field(psd,"children");
		if( root==null || !Std.isOfType(root,Array) )
			return out;

		function visit(children:Array<Dynamic>, parents:Array<String>, indexParents:Array<Int>, depth:Int, parentOpacity:Float) {
			for(i in 0...children.length) {
				var node = children[i];
				if( node==null )
					continue;

				var rawName:Dynamic = Reflect.field(node,"name");
				var name = rawName==null || Std.string(rawName).length==0 ? "(unnamed layer)" : Std.string(rawName);
				var names = parents.copy();
				names.push(name);
				var indices = indexParents.copy();
				indices.push(i);

				var childObj:Dynamic = Reflect.field(node,"children");
				var isGroup = childObj!=null && Std.isOfType(childObj,Array);
				var canvas:Dynamic = Reflect.field(node,"canvas");
				var idValue:Dynamic = Reflect.field(node,"id");
				var key = idValue!=null
					? "id:"+Std.string(idValue)
					: "tree:"+indices.join(".");
				var layerPath = names.join("/");
				var selectable = !isGroup && canvas!=null;
				var opacity = M.fclamp(floatField(node,"opacity",1.0),0,1);
				var effectiveOpacity = parentOpacity*opacity;
				var left = intField(node,"left",0);
				var top = intField(node,"top",0);
				var fallbackW = canvas==null ? 0 : Std.int(Reflect.field(canvas,"width"));
				var fallbackH = canvas==null ? 0 : Std.int(Reflect.field(canvas,"height"));
				var right = intField(node,"right",left+fallbackW);
				var bottom = intField(node,"bottom",top+fallbackH);
				if( right<=left && fallbackW>0 ) right = left+fallbackW;
				if( bottom<=top && fallbackH>0 ) bottom = top+fallbackH;

				var info:PsdLayerInfo = {
					key: key,
					path: layerPath,
					name: name,
					depth: depth,
					isGroup: isGroup,
					selectable: selectable,
					visible: !boolField(node,"hidden",false),
					opacity: opacity,
					effectiveOpacity: effectiveOpacity,
					blendMode: Reflect.field(node,"blendMode")==null ? "normal" : Std.string(Reflect.field(node,"blendMode")),
					clipping: boolField(node,"clipping",false),
					left: left,
					top: top,
					right: right,
					bottom: bottom,
					id: idValue==null ? null : Std.int(idValue),
					kind: layerKind(node,isGroup),
					exportRelPath: null,
				};
				out.push({ info:info, node:node });

				if( isGroup )
					visit(cast childObj, names, indices, depth+1, effectiveOpacity);
			}
		}

		visit(cast root, [], [], 0, 1);
		return out;
	}

	public static function listLayers(absSourcePath:String) : Null<Array<PsdLayerInfo>> {
		if( !isPsdPath(absSourcePath) )
			return null;
		try {
			var psd = readPsd(absSourcePath);
			return [ for(v in collectLayers(psd)) v.info ];
		}
		catch(e:Dynamic) {
			App.LOG.error("Could not list PSD layers: "+Std.string(e));
			return null;
		}
	}

	static function normalizeRel(path:String) {
		return path==null ? null : StringTools.replace(path,"\\","/");
	}

	static function sourceDir(project:data.Project, sourceRelPath:String) : String {
		var path:Dynamic = js.Syntax.code("require('path')");
		var sig = haxe.crypto.Md5.encode(normalizeRel(sourceRelPath)).substr(0,12);
		return path.join(project.getProjectDir(), GENERATED_DIR, sig);
	}

	static function configPathForGenerated(project:data.Project, relGeneratedPath:String) : Null<String> {
		if( relGeneratedPath==null )
			return null;
		var normalized = normalizeRel(relGeneratedPath);
		var marker = GENERATED_DIR+"/";
		var at = normalized.indexOf(marker);
		if( at<0 )
			return null;
		var rest = normalized.substr(at+marker.length);
		var slash = rest.indexOf("/");
		if( slash<=0 )
			return null;
		var sourceSig = rest.substr(0,slash);
		var path:Dynamic = js.Syntax.code("require('path')");
		return path.join(project.getProjectDir(), GENERATED_DIR, sourceSig, GENERATED_CONFIG);
	}

	static function canvasToPngBytes(canvas:Dynamic) : Dynamic {
		var dataUrl:String = canvas.toDataURL("image/png");
		var comma = dataUrl.indexOf(",");
		if( comma<0 )
			throw "Could not encode PSD layer PNG.";
		var bufferModule:Dynamic = js.Syntax.code("require('buffer')");
		var Buffer:Dynamic = bufferModule==null ? null : Reflect.field(bufferModule,"Buffer");
		if( Buffer==null || Reflect.field(Buffer,"from")==null )
			throw "Node Buffer API is unavailable in the renderer.";
		return Buffer.from(dataUrl.substr(comma+1), "base64");
	}

	static function exportLayerCanvas(
		project:data.Project,
		psd:Dynamic,
		entry:{ info:PsdLayerInfo, node:Dynamic },
		baseName:String,
		outDir:String
	) : Null<String> {
		if( !entry.info.selectable )
			return null;

		var srcCanvas:Dynamic = Reflect.field(entry.node,"canvas");
		if( srcCanvas==null )
			return null;

		var path:Dynamic = js.Syntax.code("require('path')");
		var fs:Dynamic = js.Syntax.code("require('fs')");
		var layerSig = haxe.crypto.Md5.encode(entry.info.key+"|"+entry.info.path).substr(0,12);
		var layerDir:String = path.join(outDir,"layers",layerSig);
		fs.mkdirSync(layerDir,{ recursive:true });
		var absOut:String = path.join(layerDir,baseName+".png");

		var full:Dynamic = js.Browser.document.createElement("canvas");
		full.width = intField(psd,"width",1);
		full.height = intField(psd,"height",1);
		var ctx:Dynamic = full.getContext("2d");
		ctx.clearRect(0,0,full.width,full.height);
		ctx.globalAlpha = 1;
		ctx.globalCompositeOperation = "source-over";
		ctx.drawImage(srcCanvas,entry.info.left,entry.info.top);
		fs.writeFileSync(absOut,canvasToPngBytes(full));
		return project.makeRelativeFilePath(absOut);
	}


	static function canvasBlendMode(psdBlend:String) : String {
		return switch psdBlend {
			case "multiply": "multiply";
			case "screen": "screen";
			case "overlay": "overlay";
			case "darken": "darken";
			case "lighten": "lighten";
			case "color dodge": "color-dodge";
			case "color burn": "color-burn";
			case "hard light": "hard-light";
			case "soft light": "soft-light";
			case "difference": "difference";
			case "exclusion": "exclusion";
			case "hue": "hue";
			case "saturation": "saturation";
			case "color": "color";
			case "luminosity": "luminosity";
			case _: "source-over";
		}
	}


	static function readExistingVariants(configPath:String) : Array<Dynamic> {
		if( configPath==null || !NT.fileExists(configPath) )
			return [];
		try {
			var raw:Dynamic = haxe.Json.parse(NT.readFileString(configPath));
			if( Reflect.field(raw,"format")!=FORMAT_ID )
				return [];
			var variants:Dynamic = Reflect.field(raw,"variants");
			return variants!=null && Std.isOfType(variants,Array) ? cast variants : [];
		}
		catch(_:Dynamic) {
			return [];
		}
	}


	public static function exportSelectedLayers(project:data.Project, relSourcePath:String, selectedLayerKeys:Array<String>) : String {
		if( !isPsdPath(relSourcePath) )
			throw "The selected source is not a PSD file.";
		if( selectedLayerKeys==null || selectedLayerKeys.length==0 )
			throw "Choose at least one PSD layer.";

		var absSource = project.makeAbsoluteFilePath(relSourcePath);
		var psd = readPsd(absSource);
		var entries = collectLayers(psd);
		if( entries.length==0 )
			throw "This PSD does not contain any readable layers.";

		var selectedMap : Map<String,Bool> = new Map();
		for(key in selectedLayerKeys)
			if( key!=null && key.length>0 )
				selectedMap.set(key,true);

		var selectedEntries : Array<{ info:PsdLayerInfo, node:Dynamic }> = [];
		for(entry in entries)
			if( entry.info.selectable && selectedMap.exists(entry.info.key) )
				selectedEntries.push(entry);

		if( selectedEntries.length==0 )
			throw "The selected PSD layers no longer exist or contain no renderable pixel data.";

		var path:Dynamic = js.Syntax.code("require('path')");
		var fs:Dynamic = js.Syntax.code("require('fs')");
		var outDir = sourceDir(project,relSourcePath);
		var layersDir:String = path.join(outDir,"layers");
		fs.mkdirSync(outDir,{ recursive:true });
		if( fs.existsSync(layersDir) )
			fs.rmSync(layersDir,{ recursive:true, force:true });
		fs.mkdirSync(layersDir,{ recursive:true });

		var base = dn.FilePath.extractFileName(relSourcePath);
		if( base==null || base.length==0 )
			base = "photoshop";
		base = ~/[^A-Za-z0-9_-]+/g.replace(base,"_");

		// Preserve every renderable PSD leaf as a full-document PNG for future
		// Unity/external importers. These are NOT used as the LDtk atlas.
		for(entry in entries)
			entry.info.exportRelPath = exportLayerCanvas(project,psd,entry,base,outDir);

		var docW = intField(psd,"width",0);
		var docH = intField(psd,"height",0);

		// Crop LDtk's display atlas to the union of selected layers. The old
		// full-document atlas kept PSD document offsets as transparent margins,
		// which shifted the LDtk grid and produced visible gaps between tiles.
		var cropLeft = docW;
		var cropTop = docH;
		var cropRight = 0;
		var cropBottom = 0;
		for(entry in selectedEntries) {
			var srcCanvas:Dynamic = Reflect.field(entry.node,"canvas");
			if( srcCanvas==null )
				continue;

			var left = M.imax(0,entry.info.left);
			var top = M.imax(0,entry.info.top);
			var right = M.imin(docW,entry.info.right);
			var bottom = M.imin(docH,entry.info.bottom);
			if( right<=left )
				right = M.imin(docW,left+Std.int(Reflect.field(srcCanvas,"width")));
			if( bottom<=top )
				bottom = M.imin(docH,top+Std.int(Reflect.field(srcCanvas,"height")));

			cropLeft = M.imin(cropLeft,left);
			cropTop = M.imin(cropTop,top);
			cropRight = M.imax(cropRight,right);
			cropBottom = M.imax(cropBottom,bottom);
		}

		var cropW = cropRight-cropLeft;
		var cropH = cropBottom-cropTop;
		if( cropW<=0 || cropH<=0 )
			throw "Selected PSD layers have empty or invalid bounds.";

		var display:Dynamic = js.Browser.document.createElement("canvas");
		display.width = cropW;
		display.height = cropH;
		var ctx:Dynamic = display.getContext("2d");
		if( ctx==null )
			throw "Could not create PSD display canvas.";
		ctx.clearRect(0,0,cropW,cropH);
		ctx.imageSmoothingEnabled = false;

		// ag-psd returns Photoshop children in top-to-bottom order. Paint
		// bottom-to-top so multiple selected layers flatten like the PSD stack.
		var i = selectedEntries.length-1;
		while( i>=0 ) {
			var entry = selectedEntries[i--];
			var srcCanvas:Dynamic = Reflect.field(entry.node,"canvas");
			if( srcCanvas==null )
				continue;

			ctx.save();
			ctx.globalAlpha = entry.info.effectiveOpacity==null
				? M.fclamp(entry.info.opacity,0,1)
				: M.fclamp(entry.info.effectiveOpacity,0,1);
			ctx.globalCompositeOperation = canvasBlendMode(entry.info.blendMode);
			ctx.drawImage(
				srcCanvas,
				entry.info.left-cropLeft,
				entry.info.top-cropTop
			);
			ctx.restore();
		}

		var normalizedKeys = [ for(entry in selectedEntries) entry.info.key ];
		var selectedPaths = [ for(entry in selectedEntries) entry.info.path ];
		var sigKeys = normalizedKeys.copy();
		sigKeys.sort(Reflect.compare);
		var selectionSig = haxe.crypto.Md5.encode(sigKeys.join("|")).substr(0,12);
		var displayDir:String = path.join(outDir,"display",selectionSig);
		fs.mkdirSync(displayDir,{ recursive:true });
		var absDisplay:String = path.join(displayDir,base+".png");
		fs.writeFileSync(absDisplay,canvasToPngBytes(display));
		var displayRel = project.makeRelativeFilePath(absDisplay);

		var configPath:String = path.join(outDir,GENERATED_CONFIG);
		var variants = readExistingVariants(configPath);
		var keptVariants : Array<Dynamic> = [];
		for(v in variants) {
			var rel:Dynamic = Reflect.field(v,"displayRelPath");
			if( rel==null || normalizeRel(Std.string(rel))!=normalizeRel(displayRel) )
				keptVariants.push(v);
		}
		keptVariants.push({
			selectedLayerKeys: normalizedKeys,
			selectedLayerPaths: selectedPaths,
			displayRelPath: displayRel,
			displayCrop: {
				left: cropLeft,
				top: cropTop,
				right: cropRight,
				bottom: cropBottom,
				width: cropW,
				height: cropH,
			},
		});

		var stat:Dynamic = fs.statSync(absSource);
		var json = {
			format: FORMAT_ID,
			version: FORMAT_VERSION,
			sourceRelPath: normalizeRel(relSourcePath),
			documentWidth: docW,
			documentHeight: docH,
			sourceMtimeMs: stat.mtimeMs,
			layers: [ for(entry in entries) entry.info ],
			variants: keptVariants,
		};
		fs.writeFileSync(
			configPath,
			haxe.Json.stringify(json,null,"  "),
			{ encoding:"utf8" }
		);

		App.LOG.fileOp(
			'Imported PSD "$relSourcePath", selected ${normalizedKeys.length} layer(s), '+
			'LDtk atlas=$cropW x $cropH from crop $cropLeft,$cropTop, exported ${entries.length} indexed layer entries.'
		);
		return displayRel;
	}


	public static function getGeneratedImport(project:data.Project, relGeneratedPath:String) : Null<PsdGeneratedImport> {
		var cfgPath = configPathForGenerated(project,relGeneratedPath);
		if( cfgPath==null || !NT.fileExists(cfgPath) )
			return null;

		try {
			var raw:Dynamic = haxe.Json.parse(NT.readFileString(cfgPath));
			if( Reflect.field(raw,"format")!=FORMAT_ID )
				return null;

			var sourceValue:Dynamic = Reflect.field(raw,"sourceRelPath");
			if( sourceValue==null )
				return null;
			var source = Std.string(sourceValue);
			var docW = intField(raw,"documentWidth",0);
			var docH = intField(raw,"documentHeight",0);
			var rawLayers:Dynamic = Reflect.field(raw,"layers");
			if( rawLayers==null || !Std.isOfType(rawLayers,Array) )
				return null;

			var layers:Array<PsdLayerInfo> = cast rawLayers;
			var wanted = normalizeRel(relGeneratedPath);

			var rawVariants:Dynamic = Reflect.field(raw,"variants");
			if( rawVariants!=null && Std.isOfType(rawVariants,Array) )
				for(v in (cast rawVariants:Array<Dynamic>)) {
					var rel:Dynamic = Reflect.field(v,"displayRelPath");
					if( rel==null || normalizeRel(Std.string(rel))!=wanted )
						continue;

					var keys:Array<String> = [];
					var rawKeys:Dynamic = Reflect.field(v,"selectedLayerKeys");
					if( rawKeys!=null && Std.isOfType(rawKeys,Array) )
						for(k in (cast rawKeys:Array<Dynamic>))
							if( k!=null ) keys.push(Std.string(k));

					var paths:Array<String> = [];
					var rawPaths:Dynamic = Reflect.field(v,"selectedLayerPaths");
					if( rawPaths!=null && Std.isOfType(rawPaths,Array) )
						for(p in (cast rawPaths:Array<Dynamic>))
							if( p!=null ) paths.push(Std.string(p));

					var crop:Dynamic = Reflect.field(v,"displayCrop");
					return {
						sourceRelPath: source,
						selectedLayerKeys: keys,
						selectedLayerPaths: paths,
						displayRelPath: Std.string(rel),
						displayLeft: intField(crop,"left",0),
						displayTop: intField(crop,"top",0),
						displayWidth: intField(crop,"width",docW),
						displayHeight: intField(crop,"height",docH),
						documentWidth: docW,
						documentHeight: docH,
						layers: layers,
						legacy: false,
					};
				}

			// Compatibility with 1.0.14/1.0.15 projects that still reference a
			// single full-document layer export directly.
			for(layer in layers)
				if( layer.exportRelPath!=null && normalizeRel(layer.exportRelPath)==wanted )
					return {
						sourceRelPath: source,
						selectedLayerKeys: [layer.key],
						selectedLayerPaths: [layer.path],
						displayRelPath: relGeneratedPath,
						displayLeft: 0,
						displayTop: 0,
						displayWidth: docW,
						displayHeight: docH,
						documentWidth: docW,
						documentHeight: docH,
						layers: layers,
						legacy: true,
					};

			return null;
		}
		catch(e:Dynamic) {
			App.LOG.warning("Could not read PSD generated-import metadata: "+Std.string(e));
			return null;
		}
	}


	public static function regenerateGenerated(project:data.Project, relGeneratedPath:String) : Bool {
		var generated = getGeneratedImport(project,relGeneratedPath);
		if( generated==null || generated.selectedLayerKeys.length==0 )
			return false;

		var display = exportSelectedLayers(project,generated.sourceRelPath,generated.selectedLayerKeys);

		if( generated.legacy==true )
			return NT.fileExists(project.makeAbsoluteFilePath(relGeneratedPath));

		return project.makeAbsoluteFilePath(display)==project.makeAbsoluteFilePath(relGeneratedPath);
	}

}
