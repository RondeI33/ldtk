package misc;

/**
 * Hooks LDtk's existing image file dialog so layered source formats can expose
 * their layer picker before the normal image-picker callback receives a PNG.
 *
 * Aseprite keeps its existing CLI-based selective flattening flow.
 * PSD uses PsdTools: one chosen layer becomes the LDtk atlas while all readable
 * layer exports + metadata are preserved under .ldtk-psd for future importers.
 */
class AsepriteImportInterceptor {
	static var installed = false;

	public static function install() {
		if( installed )
			return;
		installed = true;

		var originalOpenFile:Dynamic = untyped dn.js.ElectronDialogs.openFile;
		untyped dn.js.ElectronDialogs.openFile = function(extensions:Array<String>, initialPath:String, onPick:Dynamic) {
			var acceptsAseprite = extensions!=null && (extensions.contains(".aseprite") || extensions.contains(".ase"));
			var acceptsPsd = extensions!=null && extensions.contains(".psd");
			if( !acceptsAseprite && !acceptsPsd ) {
				originalOpenFile(extensions, initialPath, onPick);
				return;
			}

			originalOpenFile(extensions, initialPath, function(absPath:String) {
				if( absPath==null ) {
					onPick(absPath);
					return;
				}

				var project = try Editor.ME.project catch(_) null;
				if( project==null ) {
					onPick(absPath);
					return;
				}

				if( AsepriteTools.isAsepritePath(absPath) ) {
					var layers = AsepriteTools.listLayers(absPath);
					if( layers==null || layers.length==0 ) {
						new ui.modal.dialog.Warning(Lang.untranslated(
							"LDtk could not read the Aseprite layer list. Layer-selective importing requires the Aseprite application/CLI to be installed and accessible."
						));
						return;
					}

					var relSourcePath = project.makeRelativeFilePath(absPath);
					new ui.modal.dialog.AsepriteLayerPicker(relSourcePath, layers, selectedLayers->{
						try {
							var generatedRelPath = AsepriteTools.exportSelectedLayers(project, relSourcePath, selectedLayers);
							var generatedAbsPath = project.makeAbsoluteFilePath(generatedRelPath);
							onPick(generatedAbsPath);

							App.ME.settings.storeUiDir(
								project,
								"PickImage",
								dn.FilePath.extractDirectoryWithoutSlash(absPath,true)
							);
							N.success('Imported ${selectedLayers.length} Aseprite layer${selectedLayers.length==1 ? "" : "s"}.');
						}
						catch(e:Dynamic) {
							App.LOG.error(e);
							new ui.modal.dialog.Warning(Lang.untranslated("Aseprite layer import failed:\n\n"+Std.string(e)));
						}
					});
					return;
				}

				if( PsdTools.isPsdPath(absPath) ) {
					var layers = PsdTools.listLayers(absPath);
					if( layers==null || layers.length==0 ) {
						new ui.modal.dialog.Warning(Lang.untranslated(
							"LDtk could not read this PSD or it contains no readable layers. PSD import currently supports the formats that ag-psd can decode."
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
							"This PSD contains no renderable leaf layer that LDtk can use as a spritesheet."
						));
						return;
					}

					var relSourcePath = project.makeRelativeFilePath(absPath);
					new ui.modal.dialog.PsdLayerPicker(relSourcePath, cast layers, selectedLayerKeys->{
						try {
							var generatedRelPath = PsdTools.exportSelectedLayers(project, relSourcePath, selectedLayerKeys);
							var generatedAbsPath = project.makeAbsoluteFilePath(generatedRelPath);
							onPick(generatedAbsPath);

							App.ME.settings.storeUiDir(
								project,
								"PickImage",
								dn.FilePath.extractDirectoryWithoutSlash(absPath,true)
							);

							var imported = PsdTools.getGeneratedImport(project,generatedRelPath);
							var n = imported==null ? selectedLayerKeys.length : imported.selectedLayerKeys.length;
							N.success('Imported $n PSD layer${n==1 ? "" : "s"} into one cropped LDtk atlas. All PSD layers remain preserved for external importers.');
						}
						catch(e:Dynamic) {
							App.LOG.error(e);
							new ui.modal.dialog.Warning(Lang.untranslated("PSD layer import failed:\n\n"+Std.string(e)));
						}
					});
					return;
				}

				onPick(absPath);
			});
		};
	}
}
