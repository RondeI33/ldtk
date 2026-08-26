package misc;

/**
 * Fallback Aseprite loader used when the native heaps-aseprite decoder cannot
 * decode a newer .aseprite/.ase file. The original source file remains the
 * LDtk asset path; this helper only exports a temporary PNG for decoding.
 */
class AsepriteTools {
	static var cachedExecutable : Null<String>;
	static var executableLookupDone = false;

	public static function isAsepritePath(path:Null<String>) : Bool {
		if( path==null )
			return false;
		var ext = dn.FilePath.extractExtension(path);
		if( ext==null )
			return false;
		ext = ext.toLowerCase();
		return ext=="aseprite" || ext=="ase";
	}

	static function canRun(exe:String) : Bool {
		if( exe==null || exe.length==0 )
			return false;
		try {
			var cp:Dynamic = js.Syntax.code("require('child_process')");
			cp.execFileSync(exe, ["--version"], { stdio:"ignore", windowsHide:true });
			return true;
		}
		catch(_:Dynamic) {
			return false;
		}
	}

	public static function findExecutable() : Null<String> {
		if( executableLookupDone )
			return cachedExecutable;
		executableLookupDone = true;

		var candidates : Array<String> = ["aseprite", "Aseprite"];
		var env:Dynamic = js.Syntax.code("process.env");
		var path:Dynamic = js.Syntax.code("require('path')");

		if( NT.isWindows() ) {
			var pf:String = env.ProgramFiles;
			var pf86:String = env["ProgramFiles(x86)"];
			var local:String = env.LOCALAPPDATA;
			if( pf!=null ) candidates.push(path.join(pf, "Aseprite", "Aseprite.exe"));
			if( pf86!=null ) candidates.push(path.join(pf86, "Aseprite", "Aseprite.exe"));
			if( local!=null ) {
				candidates.push(path.join(local, "Programs", "Aseprite", "Aseprite.exe"));
				candidates.push(path.join(local, "Aseprite", "Aseprite.exe"));
			}
		}
		else if( NT.isMacOs() ) {
			candidates.push("/Applications/Aseprite.app/Contents/MacOS/aseprite");
			candidates.push("/Applications/Aseprite.app/Contents/MacOS/Aseprite");
		}
		else {
			candidates.push("/usr/bin/aseprite");
			candidates.push("/usr/local/bin/aseprite");
		}

		for(exe in candidates)
			if( canRun(exe) ) {
				cachedExecutable = exe;
				App.LOG.fileOp('Using Aseprite CLI fallback: $exe');
				return exe;
			}

		return null;
	}

	/**
	 * Export an Aseprite document to a temporary PNG and decode that PNG into
	 * Heaps pixels. Returns null if Aseprite is not installed or export fails.
	 */
	public static function decodePixels(absSourcePath:String) : Null<hxd.Pixels> {
		if( !isAsepritePath(absSourcePath) )
			return null;

		var exe = findExecutable();
		if( exe==null ) {
			App.LOG.warning("Native Aseprite decode failed and no Aseprite CLI executable was found.");
			return null;
		}

		var os:Dynamic = js.Syntax.code("require('os')");
		var path:Dynamic = js.Syntax.code("require('path')");
		var cp:Dynamic = js.Syntax.code("require('child_process')");
		var tmp = path.join(os.tmpdir(), 'ldtk-aseprite-${Date.now().getTime()}-${Std.random(999999)}.png');

		try {
			// --sheet also supports animated Aseprite documents. For a normal
			// tileset document this produces the expected single flattened image.
			cp.execFileSync(exe, [
				"-b", absSourcePath,
				"--sheet", tmp,
				"--sheet-type", "horizontal",
			], { stdio:"pipe", windowsHide:true });

			if( !NT.fileExists(tmp) ) {
				App.LOG.error("Aseprite CLI did not create the temporary PNG.");
				return null;
			}

			var pngBytes = NT.readFileBytes(tmp);
			var pixels = dn.ImageDecoder.decodePixels(pngBytes);
			if( pixels==null ) {
				App.LOG.error("Aseprite CLI created a PNG, but LDtk could not decode it.");
				return null;
			}
			pixels.convert(RGBA);
			return pixels;
		}
		catch(e:Dynamic) {
			App.LOG.error("Aseprite CLI fallback failed: "+Std.string(e));
			return null;
		}
		finally {
			if( NT.fileExists(tmp) )
				NT.removeFile(tmp);
		}
	}
}
