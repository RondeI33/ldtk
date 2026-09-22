package ui.modal.dialog;

/**
 * Multi-layer picker for PSD imports. Group rows are preserved visually so the
 * Photoshop hierarchy remains understandable. Selected renderable leaf layers
 * are flattened into one cropped LDtk atlas, while every PSD layer remains
 * exported/indexed separately for future external importers.
 */
class PsdLayerPicker extends ui.Modal {
	var allLayers : Array<Dynamic>;
	var selected : Map<String,Bool> = new Map();
	var jRows : js.jquery.JQuery;
	var jImport : js.jquery.JQuery;
	var onImport : Array<String>->Void;

	public function new(sourceRelPath:String, layers:Array<Dynamic>, onImport:Array<String>->Void) {
		super();
		this.allLayers = layers.copy();
		this.onImport = onImport;
		addClass("psdLayerPicker");
		setAnchor(MA_Centered);

		jContent.append('<h2><span class="icon layer"></span> Choose PSD layers</h2>');

		var jHelp = new J('<p class="help"></p>');
		jHelp.text(
			"Choose one or more Photoshop layers to flatten into the LDtk spritesheet. "+
			"All readable PSD layers are still exported and indexed separately for future importers "+
			"(for example color/normal/emission maps). The PSD source is never modified."
		);
		jHelp.appendTo(jContent);

		var jSource = new J('<p class="sub" style="margin-bottom:10px"></p>');
		jSource.text("Source: "+sourceRelPath);
		jSource.appendTo(jContent);

		var jTopActions = new J('<div style="display:flex; gap:6px; margin-bottom:8px"></div>');
		jTopActions.appendTo(jContent);
		var jAll = new J('<button class="gray">Select all</button>');
		var jNone = new J('<button class="gray">Select none</button>');
		jAll.appendTo(jTopActions);
		jNone.appendTo(jTopActions);

		jRows = new J('<div style="min-width:480px; max-height:440px; overflow:auto; border-top:1px solid rgba(255,255,255,.08); border-bottom:1px solid rgba(255,255,255,.08)"></div>');
		jRows.appendTo(jContent);

		for(layer in allLayers) {
			var depth:Int = layer.depth==null ? 0 : Std.int(layer.depth);
			var isGroup = layer.isGroup==true;
			var selectable = layer.selectable==true;
			var layerKey = Std.string(layer.key);
			var layerName = Std.string(layer.name);
			var layerPath = Std.string(layer.path);

			if( selectable )
				selected.set(layerKey,layer.visible==true);

			var jRow = new J('<label style="display:flex; align-items:center; gap:8px; padding:7px 8px"></label>');
			jRow.css("padding-left",(8+depth*18)+"px");
			jRow.appendTo(jRows);

			if( isGroup ) {
				jRow.css("font-weight","bold");
				jRow.append('<span class="icon layer"></span>');
			}
			else {
				var jCheck = new J('<input type="checkbox"/>');
				jCheck.prop("disabled",!selectable);
				jCheck.prop("checked",selectable && selected.get(layerKey)==true);
				jCheck.appendTo(jRow);
				if( selectable ) {
					jRow.css("cursor","pointer");
					jCheck.change(_->{
						selected.set(layerKey,jCheck.prop("checked")==true);
						updateState();
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
		jImport = new J('<button class="positive"><span class="icon layer"></span> Import selected PSD layers</button>');
		jImport.appendTo(jActions);
		var jCancel = new J('<button class="gray">Cancel</button>');
		jCancel.appendTo(jActions);

		jAll.click(_->setAll(true));
		jNone.click(_->setAll(false));
		jCancel.click(_->close());
		jImport.click(_->{
			var picked = getSelectedLayers();
			if( picked.length==0 )
				return;
			close();
			onImport(picked);
		});

		updateState();
		JsTools.parseComponents(jContent);
	}


	function setAll(v:Bool) {
		for(layer in allLayers)
			if( layer.selectable==true )
				selected.set(Std.string(layer.key),v);
		jRows.find('input[type="checkbox"]:not(:disabled)').prop("checked",v);
		updateState();
	}


	function getSelectedLayers() : Array<String> {
		var out : Array<String> = [];
		for(layer in allLayers)
			if( layer.selectable==true ) {
				var key = Std.string(layer.key);
				if( selected.exists(key) && selected.get(key)==true )
					out.push(key);
			}
		return out;
	}


	function updateState() {
		if( jImport==null )
			return;
		var n = getSelectedLayers().length;
		jImport.prop("disabled",n<=0);
		jImport.text(
			n<=0
				? "Choose at least one PSD layer"
				: 'Import $n PSD layer${n==1 ? "" : "s"}'
		);
	}
}
