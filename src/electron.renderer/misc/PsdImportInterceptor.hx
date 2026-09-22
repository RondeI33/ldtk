package misc;

/**
 * Hooks LDtk's image dialog so choosing a .psd opens the PSD layer picker.
 * LDtk receives the generated PNG path, while PsdTools keeps the PSD source
 * plus every layer export/metadata for future external importers.
 */
class PsdImportInterceptor {
	static var installed = false;

	public static function install() {
		if( installed )
			return;
		installed = true;

		var originalOpenFile:Dynamic = untyped dn.js.ElectronDialogs.openFile;
		untyped dn.js.ElectronDialogs.openFile = function(extensions:Array<String>, initialPath:String, onPick:Dynamic) {
			var acceptsPsd = extensions!=null && extensions.contains(".psd");
			if( !acceptsPsd ) {
				originalOpenFile(extensions,initialPath,onPick);
				return;
			}

			originalOpenFile(extensions,initialPath,function(absPath:String) {
				if( absPath==null || !PsdTools.isPsdPath(absPath) ) {
					onPick(absPath);
					return;
				}

				var project = try Editor.ME.project catch(_) null;
				if( project==null ) {
					onPick(absPath);
					return;
				}

				var layers = PsdTools.listLayers(absPath);
				if( layers==null || layers.length==0 ) {
					new ui.modal.dialog.Warning(Lang.untranslated(
						"LDtk could not read any PSD layers. Make sure this is a standard Photoshop PSD with readable 8-bit layer bitmap data."
					));
					return;
				}

				var hasSelectable = false;
				for(layer in layers)
					if( layer.selectable ) {
						hasSelectable = true;
						break;
					}
				if( !hasSelectable ) {
					new ui.modal.dialog.Warning(Lang.untranslated(
						"The PSD layer tree was read, but no layer contains renderable bitmap data."
					));
					return;
				}

				var relSourcePath = project.makeRelativeFilePath(absPath);
				new ui.modal.dialog.PsdLayerPicker(relSourcePath,cast layers,selectedLayerKey->{
					try {
						var generatedRelPath = PsdTools.exportSelectedLayer(project,relSourcePath,selectedLayerKey);
						var generatedAbsPath = project.makeAbsoluteFilePath(generatedRelPath);
						onPick(generatedAbsPath);

						// Keep the next file dialog in the artist source directory, not
						// inside the generated .ldtk-psd cache.
						App.ME.settings.storeUiDir(
							project,
							"PickImage",
							dn.FilePath.extractDirectoryWithoutSlash(absPath,true)
						);

						var imported = PsdTools.getGeneratedImport(project,generatedRelPath);
						var displayName = imported==null ? "PSD layer" : imported.selectedLayerPath;
						N.success('Imported PSD layer: $displayName');
					}
					catch(e:Dynamic) {
						App.LOG.error(e);
						new ui.modal.dialog.Warning(Lang.untranslated("PSD layer import failed:\n\n"+Std.string(e)));
					}
				});
			});
		};
	}
}
