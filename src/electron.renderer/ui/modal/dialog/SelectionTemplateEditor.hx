package ui.modal.dialog;

/** A normal LDtk modal. All editing is confined to a JSON snapshot. */
class SelectionTemplateEditor extends ui.modal.Dialog {
	var view:Dynamic;
	public function new(tpl:Dynamic) {
		super("selectionTemplateEditor");
		addTitle(L.t._("Edit template"),true);
		jWrapper.css({width:"min(1100px, 94vw)",maxWidth:"94vw"});
		jContent.css({maxHeight:"80vh",overflow:"auto"});
		jContent.find(">h2").css({margin:"0 0 10px",padding:"8px",fontSize:"16px",minHeight:"32px"});
		var host=new J('<div class="template-editor-host"/>');
		host.appendTo(jContent);
		var module:Dynamic=js.Node.require(JsTools.getAssetsDir()+"/js/selection-template-editor.js");
		view=module.mount(host.get(0),{
			template:ui.TemplateEditorBridge.clone(tpl),
			layers:ui.TemplateEditorBridge.catalog(tpl),
			inspect:ui.TemplateEditorBridge.fieldInfo,
			changeField:ui.TemplateEditorBridge.changeField,
			entityImage:ui.TemplateEditorBridge.entityImage,
			cellImage:ui.TemplateEditorBridge.cellImage,
		});
		addButton(L.t._("Save template"),"saveTemplate",()->{
			try {
				var draft:Dynamic=view.getDraft();
				if(data.SelectionTemplates.put(project,draft)) {
					data.SelectionTemplates.refreshUi(editor);
					N.quick("Template updated — save the LDtk project to persist it");
					close();
				}
			}
			catch(e:Dynamic) view.showError(Std.string(e));
		});
		addCancel();
	}
	override function onDispose() {
		if(view!=null) view.dispose();
		view=null;
		super.onDispose();
	}
}
