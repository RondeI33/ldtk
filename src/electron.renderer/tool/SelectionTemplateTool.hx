package tool;

class SelectionTemplateTool extends Tool<Int> {
	var tpl : Dynamic;
	var ghost : h2d.Graphics;
	var flipX = false;
	var flipY = false;
	var placedOnRelease = false;

	public function new(tpl:Dynamic) {
		super();
		var module:Dynamic=js.Node.require(JsTools.getAssetsDir()+"/js/selection-template-editor.js");
		this.tpl = module.materialize(tpl,ui.TemplateEditorBridge.catalog(tpl));
		canUseOutOfBounds = false;
		ghost = new h2d.Graphics();
		editor.levelRender.root.add(ghost, Const.DP_UI);
	}

	override function onDispose() {
		super.onDispose();
		if( ghost!=null )
			ghost.remove();
		ghost = null;
	}

	// SelectionTemplates.place records all affected layers as one transaction.
	override function saveToHistory() {}

	override function getDefaultValue() return 1;
	override public function canEdit() return true;

	inline function field(o:Dynamic, name:String) : Dynamic
		return o==null ? null : Reflect.field(o,name);

	function arr(o:Dynamic, name:String) : Array<Dynamic> {
		var v = field(o,name);
		return v==null ? [] : cast v;
	}

	function intVal(v:Dynamic, fallback=0) : Int {
		if( v==null )
			return fallback;
		var i = Std.parseInt(Std.string(v));
		return M.isValidNumber(i) ? i : fallback;
	}

	override function customCursor(ev:hxd.Event, m:Coords) {
		ghost.clear();
		var width = intVal(field(tpl,"width"),1);
		var height = intVal(field(tpl,"height"),1);

		ghost.lineStyle(1,0x66ccff,0.9);
		ghost.beginFill(0x66ccff,0.05);
		ghost.drawRect(m.levelX,m.levelY,width,height);
		ghost.endFill();

		for(cell in arr(tpl,"cells")) {
			var grid = intVal(field(cell,"gridSize"),16);
			var rx = intVal(field(cell,"relX"));
			var ry = intVal(field(cell,"relY"));
			if( flipX ) rx = width-rx-grid;
			if( flipY ) ry = height-ry-grid;
			ghost.beginFill(0xffcc00,0.24);
			ghost.drawRect(m.levelX+rx,m.levelY+ry,grid,grid);
			ghost.endFill();
		}

		for(ent in arr(tpl,"entities")) {
			var rx = intVal(field(ent,"relX"));
			var ry = intVal(field(ent,"relY"));
			if( flipX ) rx = width-rx;
			if( flipY ) ry = height-ry;
			var json = field(ent,"json");
			var ew = intVal(field(json,"width"),16);
			var eh = intVal(field(json,"height"),16);
			ghost.beginFill(0x66ccff,0.22);
			ghost.drawRect(m.levelX+rx-ew*0.5,m.levelY+ry-eh*0.5,ew,eh);
			ghost.endFill();
		}

		ev.cancel = true;
	}

	override function useAt(m:Coords, isOnStop:Bool) : Bool {
		if( !isOnStop )
			return false;
		placedOnRelease = data.SelectionTemplates.place(editor,tpl,Std.int(m.levelX),Std.int(m.levelY),flipX,flipY);
		return placedOnRelease;
	}

	override function stopUsing(m:Coords) {
		placedOnRelease = false;
		super.stopUsing(m);

		// A successful placement becomes a normal multi-layer selection
		// immediately, so the next drag moves the placed template as a group
		// instead of stamping another copy.
		if( placedOnRelease )
			editor.clearSpecialTool();
	}

	override function onAppCommand(cmd:AppCommand) {
		super.onAppCommand(cmd);
		switch cmd {
			case C_FlipX:
				flipX = !flipX;
			case C_FlipY:
				flipY = !flipY;
			case _:
		}
	}

	override function onKeyPress(keyId:Int) {
		super.onKeyPress(keyId);
		if( keyId==K.ESCAPE )
			editor.clearSpecialTool();
	}
}
