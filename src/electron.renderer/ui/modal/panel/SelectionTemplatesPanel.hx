package ui.modal.panel;

class SelectionTemplatesPanel extends ui.modal.Panel {
	public function new() {
		super(true);
		loadTemplate("selectionTemplatesPanel","selectionTemplatesPanel");
		linkToButton("#selectionTemplatesTab");
		allowCanvasInteraction();
		data.SelectionTemplates.attachPanel(jContent.find(".selectionTemplatesBody"));
	}

	override function onDispose() {
		data.SelectionTemplates.detachPanel();
		super.onDispose();
	}

	override function onGlobalEvent(e:GlobalEvent) {
		super.onGlobalEvent(e);
		switch e {
			case ProjectSelected, LevelSelected(_):
				close();
			case _:
		}
	}
}
