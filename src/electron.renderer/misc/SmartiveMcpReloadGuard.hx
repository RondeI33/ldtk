package misc;

import electron.renderer.IpcRenderer;

/**
 * Owns MCP-facing editor control requests.
 *
 * The wire contract still accepts the historical `force` boolean, but remote callers are never
 * allowed to silently discard dirty editor state. If the project has unsaved changes, the user
 * must explicitly choose Save and reload, Discard and reload, or Cancel in the editor UI.
 */
class SmartiveMcpReloadGuard {
	var bridge : Dynamic;

	public function new(bridge:Dynamic) {
		this.bridge = bridge;

		// SmartiveEditorBridge installs the default handler first. Replace only this control-request
		// listener; its project-path syncing, reload implementation and file watchers stay active.
		var ipc : Dynamic = js.node.Require.require("electron").ipcRenderer;
		ipc.removeAllListeners("smartiveControlRequest");
		IpcRenderer.on("smartiveControlRequest", function(_ev:Dynamic, requestId:Int, kind:String, _force:Bool) {
			onControlRequest(requestId,kind);
		});
	}

	function reply(requestId:Int, status:Int, payload:Dynamic) {
		IpcRenderer.invoke("smartiveControlResponse", requestId, status, haxe.Json.stringify(payload));
	}

	function refusedUnsaved(requestId:Int, path:String) {
		reply(requestId,200,{
			ok: true,
			reloaded: false,
			refused: "unsavedChanges",
			projectPath: path,
		});
	}

	function performReload(requestId:Int, ed:page.Editor) {
		untyped bridge.reloadProject(ed,function(ok:Bool,err:Null<String>) {
			if( ok )
				reply(requestId,200,{ ok:true, reloaded:true, projectPath:ed.project.filePath.full });
			else
				reply(requestId,500,{ error:err==null ? "reload failed" : err });
		});
	}

	function confirmDirtyReload(requestId:Int, ed:page.Editor) {
		var path = ed.project.filePath.full;
		var dialog = new ui.modal.Dialog(null,"smartiveReloadProject");
		dialog.jContent.text("An external tool requested a project reload, but the editor has unsaved changes. What do you want to do?");

		dialog.addButton("Save and reload","save",function() {
			dialog.close();
			ed.onSave(false,null,function() {
				if( page.Editor.ME!=ed || ed.destroyed ) {
					reply(requestId,409,{ error:"no project open" });
					return;
				}
				if( ed.needSaving ) {
					refusedUnsaved(requestId,path);
					return;
				}
				performReload(requestId,ed);
			});
		});

		dialog.addButton("Discard and reload","warning",function() {
			dialog.close();
			if( page.Editor.ME!=ed || ed.destroyed )
				reply(requestId,409,{ error:"no project open" });
			else
				performReload(requestId,ed);
		});

		var cancel = dialog.addButton("Cancel","cancel",function() {
			dialog.close();
			refusedUnsaved(requestId,path);
		});
		cancel.focus();
	}

	function onControlRequest(requestId:Int, kind:String) {
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

				if( ed.needSaving )
					confirmDirtyReload(requestId,ed);
				else
					performReload(requestId,ed);

			case _:
				reply(requestId,400,{ error:"unknown editor control request" });
		}
	}
}
