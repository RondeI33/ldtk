package ui.modal.dialog;

/**
 * Lets the user choose which saved Selection Templates to clone from another
 * LDtk project's template companion. Imported templates remain staged until
 * the current project is saved.
 */
class SelectionTemplateImportPicker extends ui.Modal {
	var sourceProjectPath:String;
	var templates:Array<Dynamic>;
	var selected:Map<String,Bool> = new Map();
	var jRows:js.jquery.JQuery;
	var jImport:js.jquery.JQuery;
	var onImport:Array<String>->Void;

	public function new(sourceProjectPath:String, templates:Array<Dynamic>, onImport:Array<String>->Void) {
		super();
		this.sourceProjectPath=sourceProjectPath;
		this.templates=templates.copy();
		this.onImport=onImport;
		addClass("selectionTemplateImportPicker");
		setAnchor(MA_Centered);

		jContent.append('<h2><span class="icon copy"></span> Import Selection Templates</h2>');

		var help=new J('<p class="help"></p>');
		help.text("Choose which saved templates to clone into this project. Imported templates get new template IDs and are not written to disk until you save the current LDtk project.");
		help.appendTo(jContent);

		var source=new J('<p class="sub" style="margin-bottom:10px"></p>');
		source.text("Source: "+sourceProjectPath);
		source.appendTo(jContent);

		var top=new J('<div style="display:flex;gap:6px;margin-bottom:8px"></div>');
		top.appendTo(jContent);
		var all=new J('<button class="gray">Select all</button>');
		var none=new J('<button class="gray">Select none</button>');
		all.appendTo(top);
		none.appendTo(top);

		jRows=new J('<div style="min-width:480px;max-height:440px;overflow:auto;border-top:1px solid rgba(255,255,255,.08);border-bottom:1px solid rgba(255,255,255,.08)"></div>');
		jRows.appendTo(jContent);

		for(tpl in this.templates) {
			var id=Std.string(Reflect.field(tpl,"id"));
			if( id==null || id=="null" || id.length==0 )
				id='legacy-'+this.templates.indexOf(tpl);
			selected.set(id,true);

			var row=new J('<label style="display:flex;align-items:center;gap:8px;padding:8px;cursor:pointer"></label>');
			row.appendTo(jRows);

			var check=new J('<input type="checkbox" checked="checked"/>');
			check.attr("data-template-id",id);
			check.appendTo(row);

			var body=new J('<span style="flex:1;min-width:0"></span>');
			body.appendTo(row);
			var name=new J('<strong style="display:block"></strong>');
			name.text(Reflect.field(tpl,"name")==null ? "Unnamed template" : Std.string(Reflect.field(tpl,"name")));
			name.appendTo(body);

			var entities:Dynamic=Reflect.field(tpl,"entities");
			var cells:Dynamic=Reflect.field(tpl,"cells");
			var entityCount=entities==null ? 0 : (cast entities:Array<Dynamic>).length;
			var cellCount=cells==null ? 0 : (cast cells:Array<Dynamic>).length;
			var meta=new J('<span class="sub"></span>');
			meta.text(entityCount+" entities · "+cellCount+" grid cells");
			meta.appendTo(body);

			var capturedId=id;
			check.change(_->{
				selected.set(capturedId,check.prop("checked")==true);
				updateState();
			});
		}

		var actions=new J('<div class="buttons" style="margin-top:14px;display:flex;gap:8px"></div>');
		actions.appendTo(jContent);
		jImport=new J('<button class="positive"><span class="icon copy"></span> Import selected templates</button>');
		jImport.appendTo(actions);
		var cancel=new J('<button class="gray">Cancel</button>');
		cancel.appendTo(actions);

		all.click(_->setAll(true));
		none.click(_->setAll(false));
		cancel.click(_->close());
		jImport.click(_->{
			var ids=getSelectedIds();
			if( ids.length==0 )
				return;
			close();
			onImport(ids);
		});

		updateState();
		JsTools.parseComponents(jContent);
	}

	function setAll(v:Bool) {
		for(k in selected.keys())
			selected.set(k,v);
		jRows.find('input[type="checkbox"]').prop("checked",v);
		updateState();
	}

	function getSelectedIds():Array<String> {
		var out:Array<String>=[];
		for(tpl in templates) {
			var id=Std.string(Reflect.field(tpl,"id"));
			if( id==null || id=="null" || id.length==0 )
				id='legacy-'+templates.indexOf(tpl);
			if( selected.exists(id) && selected.get(id)==true )
				out.push(id);
		}
		return out;
	}

	function updateState() {
		if( jImport==null )
			return;
		var n=getSelectedIds().length;
		jImport.prop("disabled",n<=0);
		jImport.text(n<=0 ? "Choose at least one template" : "Import "+n+" selected template"+(n==1 ? "" : "s"));
	}
}
