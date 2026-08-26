package misc;

/**
 * Small integration shim for fork-only features. Keeping this isolated avoids
 * invasive changes to upstream LDtk classes and makes future rebases easier.
 */
@:access(data.Project)
@:expose("LdtkForkFeatures")
class ForkFeatures {
	static var installed = false;

	public static function install() {
		if( installed )
			return;
		installed = true;

		// Replace Project.getOrLoadImage at the JS prototype level. The behavior
		// is identical for normal PNG/GIF/JPEG images, while Aseprite sources are
		// represented by PNG render bytes and get a CLI fallback for newer files.
		var cls:Dynamic = data.Project;
		var proto:Dynamic = Reflect.field(cls,"prototype");
		Reflect.setField(proto,"getOrLoadImage", function(relPath:String) {
			var self:data.Project = cast js.Syntax.code("this");
			return getOrLoadImagePatched(self,relPath);
		});
	}

	public static function openAtlasComposer() {
		new ui.modal.dialog.AtlasComposer();
	}

	static function getOrLoadImagePatched(project:data.Project, relPath:String) : Null<data.DataTypes.CachedImage> {
		try {
			if( !project.imageCache.exists(relPath) ) {
				App.LOG.add("cache", 'Caching image $relPath...');
				var absPath = project.makeAbsoluteFilePath(relPath);
				var sourceBytes = NT.readFileBytes(absPath);
				if( sourceBytes==null )
					throw 'Could not read image file: $absPath';

				App.LOG.add("cache", " -> identified as "+dn.Identify.getType(sourceBytes));
				var pixels = dn.ImageDecoder.decodePixels(sourceBytes);
				if( pixels==null && AsepriteTools.isAsepritePath(relPath) ) {
					App.LOG.warning('Native Aseprite decode failed for $relPath; trying the installed Aseprite CLI.');
					pixels = AsepriteTools.decodePixels(absPath);
				}
				if( pixels==null ) {
					App.LOG.error('Failed to decode pixels: $relPath (identified as ${dn.Identify.getType(sourceBytes)}, err=${dn.ImageDecoder.lastError})');
					throw "decodePixels failed";
				}

				App.LOG.add("cache", " -> pixels "+pixels.width+"x"+pixels.height);
				pixels.convert(RGBA);

				// createAtlasHtmlImage() declares data:image/png. A raw .aseprite
				// payload is not displayable by Chromium, so cache a PNG representation
				// while keeping the original .aseprite path as the source of truth.
				var renderBytes = AsepriteTools.isAsepritePath(relPath)
					? pixels.clone().toPNG()
					: sourceBytes;
				var base64 = haxe.crypto.Base64.encode(renderBytes);
				App.LOG.add("cache", " -> base64 "+base64.length);
				var texture = h3d.mat.Texture.fromPixels(pixels);

				project.imageCache.set(relPath,{
					fileName:dn.FilePath.extractFileWithExt(relPath),
					relPath:relPath,
					bytes:renderBytes,
					base64:base64,
					pixels:pixels,
					tex:texture,
				});
			}
			return project.imageCache.get(relPath);
		}
		catch(e:Dynamic) {
			App.LOG.error(e);
			return null;
		}
	}
}
