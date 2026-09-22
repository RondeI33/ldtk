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
	static inline var FORMAT_VERSION = 1;

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

	public static function exportSelectedLayer(project:data.Project, relSourcePath:String, selectedLayerKey:String) : String {
		if( !isPsdPath(relSourcePath) )
			throw "The selected source is not a PSD file.";
		if( selectedLayerKey==null || selectedLayerKey.length==0 )
			throw "Choose a PSD layer.";

		var absSource = project.makeAbsoluteFilePath(relSourcePath);
		var psd = readPsd(absSource);
		var entries = collectLayers(psd);
		if( entries.length==0 )
			throw "This PSD does not contain any readable layers.";

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

		var selectedRel : Null<String> = null;
		var selectedPath : Null<String> = null;
		for(entry in entries) {
			var rel = exportLayerCanvas(project,psd,entry,base,outDir);
			entry.info.exportRelPath = rel;
			if( entry.info.key==selectedLayerKey ) {
				if( rel==null )
					throw 'PSD layer "${entry.info.path}" has no renderable pixel data.';
				selectedRel = rel;
				selectedPath = entry.info.path;
			}
		}
		if( selectedRel==null )
			throw "The selected PSD layer no longer exists or cannot be rendered.";

		var fs2:Dynamic = js.Syntax.code("require('fs')");
		var stat:Dynamic = fs2.statSync(absSource);
		var json = {
			format: FORMAT_ID,
			version: FORMAT_VERSION,
			sourceRelPath: normalizeRel(relSourcePath),
			documentWidth: intField(psd,"width",0),
			documentHeight: intField(psd,"height",0),
			sourceMtimeMs: stat.mtimeMs,
			layers: [ for(entry in entries) entry.info ],
		};
		fs.writeFileSync(
			path.join(outDir,GENERATED_CONFIG),
			haxe.Json.stringify(json,null,"  "),
			{ encoding:"utf8" }
		);

		App.LOG.fileOp('Imported PSD "$relSourcePath", selected "$selectedPath", exported ${entries.length} indexed layer entries.');
		return selectedRel;
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
			for(layer in layers) {
				if( layer.exportRelPath!=null && normalizeRel(layer.exportRelPath)==wanted )
					return {
						sourceRelPath: source,
						selectedLayerKey: layer.key,
						selectedLayerPath: layer.path,
						documentWidth: docW,
						documentHeight: docH,
						layers: layers,
					};
			}
			return null;
		}
		catch(e:Dynamic) {
			App.LOG.warning("Could not read PSD generated-import metadata: "+Std.string(e));
			return null;
		}
	}

	public static function regenerateGenerated(project:data.Project, relGeneratedPath:String) : Bool {
		var generated = getGeneratedImport(project,relGeneratedPath);
		if( generated==null )
			return false;
		var selected = exportSelectedLayer(project,generated.sourceRelPath,generated.selectedLayerKey);
		return project.makeAbsoluteFilePath(selected)==project.makeAbsoluteFilePath(relGeneratedPath);
	}
}
