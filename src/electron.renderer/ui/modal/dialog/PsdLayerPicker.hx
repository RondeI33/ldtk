package ui.modal.dialog;

/**
 * Single-layer picker for PSD imports. Group rows are preserved visually so the
 * Photoshop hierarchy remains understandable, but only renderable leaf layers
 * can be chosen as LDtk's visible atlas.
 */
class PsdLayerPicker extends ui.Modal {
	var allLayers : Array<Dynamic>;
	var selectedKey : Null<String>;
	var jRows : js.jquery.JQuery;
	var jImport : js.jquery.JQuery;
	var onImport : String->Void;

	public function new(sourceRelPath:String, layers:Array<Dynamic>, onImport:String->Void) {
		super();
		this.allLayers = layers.copy();
		this.onImport = onImport;
		addClass("psdLayerPicker");
		setAnchor(MA_Centered);

		for(layer in allLayers)
			if( layer.selectable==true && layer.visible==true ) {
				selectedKey = Std.string(layer.key);
				break;
			}
		if( selectedKey==null )
			for(layer in allLayers)
				if( layer.selectable==true ) {
					selectedKey = Std.string(layer.key);
					break;
				}

		jContent.append('<h2><span class="icon layer"></span> Choose PSD layer</h2>');

		var jHelp = new J('<p class="help"></p>');
		jHelp.text("Choose the Photoshop layer that LDtk should display as this spritesheet. All readable PSD layers are still exported and indexed for future external importers (for example normal/emission material maps). The PSD source is never modified.");
		jHelp.appendTo(jContent);

		var jSource = new J('<p class="sub" style="margin-bottom:10px"></p>');
		jSource.text("Source: "+sourceRelPath);
		jSource.appendTo(jContent);

		jRows = new J('<div style="min-width:460px; max-height:440px; overflow:auto; border-top:1px solid rgba(255,255,255,.08); border-bottom:1px solid rgba(255,255,255,.08)"></div>');
		jRows.appendTo(jContent);

		var radioName = "psdLayer_"+Std.random(999999);
		for(layer in allLayers) {
			var depth:Int = layer.depth==null ? 0 : Std.int(layer.depth);
			var isGroup = layer.isGroup==true;
			var selectable = layer.selectable==true;
			var layerKey = Std.string(layer.key);
			var layerName = Std.string(layer.name);
			var layerPath = Std.string(layer.path);

			var jRow = new J('<label style="display:flex; align-items:center; gap:8px; padding:7px 8px"></label>');
			jRow.css("padding-left",(8+depth*18)+"px");
			jRow.appendTo(jRows);

			if( isGroup ) {
				jRow.css("font-weight","bold");
				jRow.append('<span class="icon layer"></span>');
			}
			else {
				var jRadio = new J('<input type="radio"/>');
				jRadio.attr("name",radioName);
				jRadio.prop("disabled",!selectable);
				jRadio.prop("checked",selectable && selectedKey==layerKey);
				jRadio.appendTo(jRow);
				if( selectable ) {
					jRow.css("cursor","pointer");
					jRadio.change(_->{
						if( jRadio.prop("checked")==true ) {
							selectedKey = layerKey;
							updateState();
						}
					});
				}
			}

			var jName = new J('<span style="flex:1; min-width:0"></span>');
			jName.text(layerName);
			jName.appendTo(jRow);

			if( !isGroup ) {
				var meta = [];
				if( layer.visible!=true ) meta.push("hidden");
				if( layer.kind!=null && Std.string(layer.kind)!="pixel" ) meta.push(Std.string(layer.kind));
				if( layer.opacity!=null && Math.abs((cast layer.opacity:Float)-1.0)>0.001 )
					meta.push(Std.int((cast layer.opacity:Float)*100)+"%");
				if( layer.blendMode!=null && Std.string(layer.blendMode)!="normal" )
					meta.push(Std.string(layer.blendMode));
				if( !selectable ) meta.push("no bitmap");

				if( meta.length>0 ) {
					var jMeta = new J('<span class="sub"></span>');
					jMeta.text(meta.join(" · "));
					jMeta.appendTo(jRow);
				}
			}

			ui.Tip.attach(jRow,layerPath);
		}

		var jActions = new J('<div class="buttons" style="margin-top:14px; display:flex; gap:8px"></div>');
		jActions.appendTo(jContent);
		jImport = new J('<button class="positive"><span class="icon layer"></span> Import PSD layer</button>');
		jImport.appendTo(jActions);
		var jCancel = new J('<button class="gray">Cancel</button>');
		jCancel.appendTo(jActions);

		jCancel.click(_->close());
		jImport.click(_->{
			if( selectedKey==null )
				return;
			var picked = selectedKey;
			close();
			onImport(picked);
		});

		updateState();
		JsTools.parseComponents(jContent);
	}

	function updateState() {
		if( jImport==null )
			return;
		jImport.prop("disabled",selectedKey==null);
		if( selectedKey==null )
			jImport.text("No renderable PSD layer found");
	}
}
