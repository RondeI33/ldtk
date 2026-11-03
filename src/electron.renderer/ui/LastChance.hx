package ui;

class LastChance extends dn.Process {
	static var CUR : Null<LastChance>;
	var elem : js.jquery.JQuery;

	public function new(str:LocaleString, project:data.Project) {
		super(Editor.ME);

		LastChance.end();
		CUR = this;
		var backup = project.toJson();
		var backupPath = project.filePath.full;
		// LastChance snapshots stock LDtk JSON; capture sidecar-only state by IID.
		var shiftBackup : Map<String,{x:Int,y:Int}> = new Map();
		for(w in project.worlds)
		for(l in w.levels)
			shiftBackup.set(l.iid,{x:l.contentShiftX,y:l.contentShiftY});

		elem = new J("xml#lastChance").clone().children().first();
		elem.appendTo(App.ME.jBody);
		elem.find(".action").text(str);

		elem.find("button").click( function(ev) {
			if( !isActive() )
				return;
			App.LOG.general('Restored project using LastChance ("$str")');
			var restored : data.Project = data.Project.fromJson(backupPath, backup);
			restored.forkConfig.load();
			for(w in restored.worlds)
			for(l in w.levels) {
				var shift = shiftBackup.get(l.iid);
				if( shift!=null ) {
					l.contentShiftX = shift.x;
					l.contentShiftY = shift.y;
				}
			}
			Editor.ME.selectProject(restored);
			App.LOG.general('Restore complete.');
			Editor.ME.resetTools();
			ui.modal.Dialog.closeAll();
			N.msg( L.t._("Canceled action"), '"$str"' );
			hide();
		});

		delayer.addS(hide, 20);
		cd.setF("ignoreFrame",1);

		App.LOG.warning('Last chance for: $str');
		Editor.ME.ge.addGlobalListener(onGlobalEvent);
	}

	function onGlobalEvent(e:GlobalEvent) {
		switch(e) {
			case ViewportChanged(_):
			case LevelSelected(l):
			// Deleting a level is the action LastChance must be able to undo.
			case LevelRemoved(_):
			case LayerInstanceSelected(li):
			case LayerInstanceVisiblityChanged(li):
			case ToolValueSelected:
			case ToolOptionChanged:
			case TilesetDefPixelDataCacheRebuilt(td):

			case _:
				LastChance.end();
		}
	}

	public static function end() {
		if( CUR!=null && CUR.isActive() && !CUR.cd.has("ignoreFrame") ) {
			CUR.hide();
			Editor.ME.ge.emit(LastChanceEnded);
		}
	}

	function isActive() {
		return !destroyed && !cd.has("hiding");
	}

	function hide() {
		if( !isActive() )
			return;

		cd.setS("hiding",Const.INFINITE);
		elem.slideUp(100, function(_) destroy());
	}

	override function onDispose() {
		super.onDispose();

		Editor.ME.ge.removeListener(onGlobalEvent);
		elem.remove();
		elem = null;

		if( CUR==this )
			CUR = null;
	}
}