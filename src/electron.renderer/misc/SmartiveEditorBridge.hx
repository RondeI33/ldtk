package misc;

import electron.renderer.IpcRenderer;

private typedef ReloadCompletion = {
	var editor : page.Editor;
	var callback : (Bool,Null<String>)->Void;
	var levelMissing : Bool;
}

@:access(page.Editor)
class SmartiveEditorBridge extends dn.Process {
	var currentEditor : Null<page.Editor>;
	var lastProjectPath : Null<String>;
	var projectWatchers : Array<Dynamic> = [];
	var suppressDiskChangesUntil = 0.;
	var reloadInProgress = false;
	var reloadCompletion : Null<ReloadCompletion>;

	public function new() {
		super(App.ME);

		IpcRenderer.on("smartiveManualReload", function(_ev:Dynamic) {
			manualReloadProject();
		});
		IpcRenderer.on("smartiveControlRequest", function(_ev:Dynamic, requestId:Int, kind:String, force:Bool) {
			onControlRequest(requestId,kind,force);
		});
	}

	override function onDispose() {
		closeProjectWatches();
		detachEditor();
		super.onDispose();
	}

	override function update() {
		super.update();

		var ed = page.Editor.ME;
		if( ed!=currentEditor )
			attachEditor(ed);
		else if( ed!=null && ed.project!=null ) {
			var path = ed.project.filePath.full;
			if( path!=lastProjectPath ) {
				suppressDiskChangesUntil = haxe.Timer.stamp()+1.0;
				syncProjectPath(ed);
				refreshProjectWatches(ed);
			}
		}

		if( reloadCompletion!=null && !ui.modal.Progress.hasAny() ) {
			var c = reloadCompletion;
			reloadCompletion = null;
			if( page.Editor.ME!=c.editor || c.editor.destroyed ) {
				reloadInProgress = false;
				c.callback(false,"editor closed during reload");
			}
			else {
				finishSuccessfulReload(c.editor,c.levelMissing,c.callback);
			}
		}
	}

	function attachEditor(ed:Null<page.Editor>) {
		detachEditor();
		currentEditor = ed;
		if( ed==null ) {
			lastProjectPath = null;
			IpcRenderer.invoke("smartiveProjectPath", null);
			return;
		}

		ed.ge.addGlobalListener(onEditorEvent);
		syncProjectPath(ed);
		refreshProjectWatches(ed);
	}

	function detachEditor() {
		closeProjectWatches();
		if( currentEditor!=null && currentEditor.ge!=null ) {
			try currentEditor.ge.removeListener(onEditorEvent) catch(_:Dynamic) {}
		}
		currentEditor = null;
	}

	function onEditorEvent(e:GlobalEvent) {
		switch e {
			case BeforeProjectSaving:
				suppressDiskChangesUntil = haxe.Timer.stamp()+2.0;

			case ProjectSaved:
				suppressDiskChangesUntil = haxe.Timer.stamp()+1.0;
				if( currentEditor!=null ) {
					syncProjectPath(currentEditor);
					refreshProjectWatches(currentEditor);
				}

			case ProjectSelected:
				if( currentEditor!=null )
					syncProjectPath(currentEditor);

			case _:
		}
	}

	function syncProjectPath(ed:page.Editor) {
		var path = ed.project==null ? null : ed.project.filePath.full;
		lastProjectPath = path;
		IpcRenderer.invoke("smartiveProjectPath", path);
	}

	function closeProjectWatches() {
		delayer.cancelById("smartiveDiskChange");
		for(w in projectWatchers)
			try w.close() catch(_:Dynamic) {}
		projectWatchers = [];
	}

	inline function shouldIgnoreDiskChange() {
		return reloadInProgress
			|| ui.ProjectSaver.hasAny()
			|| haxe.Timer.stamp()<suppressDiskChangesUntil;
	}

	function watchDirectory(absDir:String, filter:String->Bool) {
		if( absDir==null || !NT.fileExists(absDir) )
			return;

		try {
			var fs : Dynamic = js.node.Require.require("fs");
			var watcher = fs.watch(absDir, function(_eventType:Dynamic, fileName:Dynamic) {
				if( shouldIgnoreDiskChange() )
					return;
				var name = fileName==null ? null : fileName.toString();
				if( name==null || filter(name) )
					queueProjectDiskChange();
			});
			watcher.on("error", function(err:Dynamic) {
				App.LOG.error('Project FSWatcher failed for $absDir: '+Std.string(err));
			});
			projectWatchers.push(watcher);
		}
		catch(err:Dynamic) {
			App.LOG.error('Could not watch project directory $absDir: '+Std.string(err));
		}
	}

	function refreshProjectWatches(ed:page.Editor) {
		closeProjectWatches();
		if( ed==null || ed.project==null || ed.project.isBackup() )
			return;

		var path : Dynamic = js.node.Require.require("path");
		var project = ed.project;
		var projectFile = path.basename(project.filePath.full);
		var sidecarFile = path.basename(project.forkConfig.getPath());
		watchDirectory(project.filePath.directory, function(name:String) {
			return name==projectFile || name==sidecarFile;
		});

		if( project.externalLevels ) {
			var levelDir = project.getAbsExternalFilesDir();
			var ext = "."+Const.LEVEL_EXTENSION.toLowerCase();
			watchDirectory(levelDir, function(name:String) {
				return StringTools.endsWith(name.toLowerCase(), ext);
			});
		}
	}

	function queueProjectDiskChange() {
		delayer.cancelById("smartiveDiskChange");
		delayer.addS("smartiveDiskChange", function() {
			if( shouldIgnoreDiskChange() || currentEditor==null || currentEditor.project==null )
				return;
			showDiskChangeBanner(currentEditor);
		}, 0.3);
	}

	function showDiskChangeBanner(ed:page.Editor) {
		var wrapper = new J('<div class="smartiveDiskChange"/>');
		var text = new J('<span/>');
		text.text(
			ed.needSaving
				? "Project files changed on disk while the editor has unsaved changes. Saving now could overwrite the external changes."
				: "Project files changed on disk."
		);
		text.appendTo(wrapper);

		var actions = new J('<span class="actions"/>');
		actions.appendTo(wrapper);
		var reload = new J('<button>Reload</button>');
		reload.appendTo(actions);
		reload.click(function(_) {
			ed.setPermanentNotification("smartiveDiskChange");
			manualReloadProject();
		});
		var ignore = new J('<button class="gray">Ignore</button>');
		ignore.appendTo(actions);
		ignore.click(function(_) {
			ed.setPermanentNotification("smartiveDiskChange");
		});

		ed.setPermanentNotification("smartiveDiskChange",wrapper);
	}

	function manualReloadProject() {
		var ed = page.Editor.ME;
		if( ed==null || ed.project==null || reloadInProgress )
			return;

		if( !ed.needSaving ) {
			reloadProject(ed,function(_,_) {});
			return;
		}

		var dialog = new ui.modal.Dialog(null,"smartiveReloadProject");
		dialog.jContent.text("The project has unsaved changes. What do you want to do before reloading it from disk?");
		dialog.addButton("Save and reload","save",function() {
			dialog.close();
			ed.onSave(false,null,function() {
				if( page.Editor.ME==ed && !ed.needSaving )
					reloadProject(ed,function(_,_) {});
			});
		});
		dialog.addButton("Discard and reload","warning",function() {
			dialog.close();
			reloadProject(ed,function(_,_) {});
		});
		var cancel = dialog.addButton("Cancel","cancel",function() {
			dialog.close();
		});
		cancel.focus();
	}

	function onControlRequest(requestId:Int, kind:String, force:Bool) {
		var ed = page.Editor.ME;
		switch kind {
			case "status":
				reply(requestId,200,{
					ok: true,
					projectPath: ed==null || ed.project==null ? null : ed.project.filePath.full,
					unsavedChanges: ed==null ? false : ed.needSaving,
					version: Const.getAppVersionStr(),
				});

			case "reload":
				if( ed==null || ed.project==null ) {
					reply(requestId,409,{ error:"no project open" });
					return;
				}
				var path = ed.project.filePath.full;
				if( ed.needSaving && !force ) {
					reply(requestId,200,{
						ok: true,
						reloaded: false,
						refused: "unsavedChanges",
						projectPath: path,
					});
					return;
				}
				if( reloadInProgress ) {
					reply(requestId,409,{ error:"reload already in progress" });
					return;
				}
				reloadProject(ed,function(ok:Bool,err:Null<String>) {
					if( ok )
						reply(requestId,200,{ ok:true, reloaded:true, projectPath:ed.project.filePath.full });
					else
						reply(requestId,500,{ error:err==null ? "reload failed" : err });
				});

			case _:
				reply(requestId,400,{ error:"unknown editor control request" });
		}
	}

	function reply(requestId:Int, status:Int, payload:Dynamic) {
		IpcRenderer.invoke("smartiveControlResponse", requestId, status, haxe.Json.stringify(payload));
	}

	function reloadProject(ed:page.Editor, callback:(Bool,Null<String>)->Void) {
		if( reloadInProgress ) {
			callback(false,"reload already in progress");
			return;
		}

		reloadInProgress = true;
		suppressDiskChangesUntil = haxe.Timer.stamp()+30.0;
		ed.setPermanentNotification("smartiveDiskChange");

		var filePath = ed.project.filePath.full;
		var oldWorldIid = ed.curWorldIid;
		var oldLevelIid = ed.curLevel==null ? null : ed.curLevel.iid;
		var oldLayerDefUid = ed.curLayerDefUid;
		var oldWorldMode = ed.worldMode;
		var oldWorldDepth = ed.curWorldDepth;
		var cameraX = ed.camera.worldX;
		var cameraY = ed.camera.worldY;
		var cameraZoom = ed.camera.adjustedZoom;

		new ui.ProjectLoader(
			filePath,
			function(p:data.Project) {
				if( page.Editor.ME!=ed || ed.destroyed ) {
					reloadInProgress = false;
					callback(false,"editor closed during reload");
					return;
				}

				try {
					// Close UI that may retain references into the old project before swapping models.
					ui.Modal.closeAll();
					ed.clearSpecialTool();
					ed.clearResizeTool();
					ed.selectionTool.clear();

					// selectProject is the normal project initialization path: tidy, tilesets/pixel caches,
					// auto-layer caches and file watchers are rebuilt here. It also resets level timelines.
					ed.selectProject(p);

					var levelMissing = false;
					var targetLevel = oldLevelIid==null ? null : p.getLevelAnywhere(null,oldLevelIid);
					if( targetLevel!=null ) {
						if( ed.curWorld!=targetLevel._world )
							ed.selectWorld(targetLevel._world,false);
						ed.selectLevel(targetLevel,false);
					}
					else if( oldLevelIid!=null ) {
						levelMissing = true;
						var oldWorld = p.getWorldIid(oldWorldIid);
						if( oldWorld!=null && oldWorld.levels.length>0 && ed.curWorld!=oldWorld )
							ed.selectWorld(oldWorld,false);
					}

					var layerDef = p.defs.getLayerDef(oldLayerDefUid);
					if( layerDef!=null && ed.curLevel!=null ) {
						var li = ed.curLevel.getLayerInstance(layerDef);
						if( li!=null )
							ed.selectLayerInstance(li,false);
					}

					if( ed.curWorld!=null ) {
						var minDepth = ed.curWorld.getLowestLevelDepth();
						var maxDepth = ed.curWorld.getHighestLevelDepth();
						if( oldWorldDepth>=minDepth && oldWorldDepth<=maxDepth )
							ed.selectWorldDepth(oldWorldDepth);
					}
					if( ed.worldMode!=oldWorldMode )
						ed.setWorldMode(oldWorldMode);

					ed.camera.cancelAllAutoMovements();
					ed.camera.setWorldPos(cameraX,cameraY);
					ed.camera.setZoom(cameraZoom);
					ed.camera.cancelAllAutoMovements();

					// Existing layer-tool instances are intentionally kept alive: their active palette
					// tile/entity selection remains intact when the same layer definition still exists.
					reloadCompletion = {
						editor: ed,
						callback: callback,
						levelMissing: levelMissing,
					};
				}
				catch(err:Dynamic) {
					reloadInProgress = false;
					suppressDiskChangesUntil = haxe.Timer.stamp()+1.0;
					callback(false,"Failed to activate reloaded project: "+Std.string(err));
				}
			},
			function(err:ui.LoadingError) {
				reloadInProgress = false;
				suppressDiskChangesUntil = haxe.Timer.stamp()+1.0;
				callback(false,loadingErrorToString(err));
			},
			true
		);
	}

	function finishSuccessfulReload(ed:page.Editor, levelMissing:Bool, callback:(Bool,Null<String>)->Void) {
		reloadInProgress = false;
		suppressDiskChangesUntil = haxe.Timer.stamp()+1.0;
		ed.setPermanentNotification("smartiveDiskChange");
		syncProjectPath(ed);
		refreshProjectWatches(ed);
		if( levelMissing )
			N.quick("Previously selected level no longer exists; opened the first available level.");
		N.success("Project reloaded from disk");
		callback(true,null);
	}

	static function loadingErrorToString(err:ui.LoadingError) {
		return switch err {
			case ProjectNotFound: "project file not found";
			case ExternalDirMissing(relPath): 'external level directory missing: $relPath';
			case FileRead(msg): "project file read failed: "+msg;
			case JsonParse(msg): "project JSON parse failed: "+msg;
			case ProjectInit(msg): "project initialization failed: "+msg;
			case UnsupportedWinNetDrive: "unsupported Windows network drive";
		}
	}
}
