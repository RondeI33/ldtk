package ui;

import data.DrawableShape;
import data.inst.EntityInstance;

/** Small authoring controls; generated arrays never become thousands of field inputs. */
class DrawableShapeEditor {
	public static var placementMode="Select";
	public static var placementPreset="Rectangle";
	static var placementBrush="Paint";
	static var axisPreview:Null<h2d.Graphics>;
	static var previewOwnerIid:Null<String>;
	static var presets=["Rectangle","Strip","LCorner","UShape","Staircase","Diamond","Ring"];
	static var editor(get,never):Editor;
	static inline function get_editor() return Editor.ME;

	static function selected(ed:data.def.EntityDef):Null<EntityInstance> {
		@:privateAccess var all=editor.selectionTool.group.allElements();
		var out:Null<EntityInstance>=null;
		for(ge in all) switch ge {
			case Entity(_,ei): if(out!=null) return null; else out=ei;
			case _:
		}
		return out!=null && out.defUid==ed.uid ? out : null;
	}

	public static function activate(ed:data.def.EntityDef,?ei:EntityInstance,brush="Paint",preset="Rectangle",?configuration:EntityInstance) {
		clearPreview();
		if(!DrawableShape.isEnabled(ed)) return;
		var t=new tool.DrawableShapeTool(ed,ei,brush,preset,configuration);
		var state=ei==null ? null : DrawableShape.read(ei);
		if(state!=null) {t.thickness=state.thickness;t.quarterTurns=state.quarterTurns;}
		editor.setSpecialTool(t);
		editor.clearResizeTool();
	}

	static function selectControl(parent:J,css:String,values:Array<String>,value:String,cb:String->Void):J {
		var j=new J('<select/>').addClass(css).appendTo(parent);
		for(v in values) new J('<option/>').attr("value",v).text(v).appendTo(j);
		j.val(value).change(_->cb(Std.string(j.val())));
		return j;
	}
	static function button(parent:J,label:String,css:String,cb:Void->Void):J
		return new J('<button class="small"/>').text(label).addClass(css).appendTo(parent).click(_->cb());
	static function row(parent:J):J return new J('<div style="display:flex;gap:5px;flex-wrap:wrap;align-items:center;margin:6px 0"/>').appendTo(parent);

	public static function appendDefinition(parent:J,ed:data.def.EntityDef) {
		var box=new J('<section class="drawableShapeDefinition" style="padding:10px 0;border-top:1px solid #535b66"/>').appendTo(parent);
		var enabled=DrawableShape.isEnabled(ed);
		var label=new J('<label/>').appendTo(box);
		var check=new J('<input type="checkbox" class="drawableShapeEnabled"/>').prop("checked",enabled).appendTo(label);
		label.append(" Drawable shape");
		new J('<p class="help"/>').text("Paint one connected object on the entity layer. Its cells and behavior are saved as ordinary LDtk fields. Existing rectangles keep their shape until edited.").appendTo(box);
		check.change(_->{
			if(check.prop("checked")) {
				var error=DrawableShape.enable(ed);
				if(error!=null) {check.prop("checked",false);N.error(error);return;}
			}
			else DrawableShape.disable(ed);
			editor.project.forkConfig.save();
			editor.ge.emit(EntityDefChanged);
		});
	}

	public static function appendPalette(parent:J,ed:data.def.EntityDef) {
		if(ed==null || !DrawableShape.isEnabled(ed)) return;
		var box=new J('<div class="drawableShapePalette" style="padding:8px;border:1px solid #63717f;border-radius:4px;margin-bottom:8px"/>').prependTo(parent);
		box.append('<strong>Drawable shape</strong>');
		var controls=row(box);
		selectControl(controls,"shapePlacementMode",["Select","Rectangle","Preset","Custom"],editor.isSpecialToolActive(tool.DrawableShapeTool) ? placementMode : "Select",v->{
			placementMode=v;
			if(v=="Select") editor.clearSpecialTool();
			else activate(ed,v=="Custom" ? selected(ed) : null,v=="Custom" ? placementBrush : v,placementPreset);
		});
		selectControl(controls,"shapePlacementPreset",presets,placementPreset,v->{placementPreset=v;placementMode="Preset";activate(ed,null,"Preset",v);});
		selectControl(controls,"shapePlacementBrush",["Paint","Erase","Fill"],placementBrush,v->{placementBrush=v;placementMode="Custom";activate(ed,selected(ed),v);});
		button(controls,"New shape","shapeNew",()->{placementMode="Custom";editor.selectionTool.clear();activate(ed,null,"Paint");});
		new J('<p class="help" style="margin:4px 0"/>').text("Drag to paint. Shift fills a rectangle; right-click erases cells. Esc exits. New shape starts a separate owner.").appendTo(box);
		var min=DrawableShapeGeometry.minimum(placementPreset);
		new J('<small/>').text(placementPreset+" minimum: "+min.width+" × "+min.height+" cells").appendTo(box);
	}

	public static function commit(ei:EntityInstance,action:Void->Null<String>):Bool {
		var error=action();
		if(error!=null) {N.error("Shape unchanged: "+error);return false;}
		editor.curLevelTimeline.markEntityChange(ei);
		editor.curLevelTimeline.saveLayerState(ei._li);
		editor.ge.emit(EntityInstanceChanged(ei));
		editor.levelRender.invalidateLayer(ei._li);
		editor.selectionTool.invalidateRender();
		editor.invalidateResizeTool();
		return true;
	}

	/** Resize uses rows/columns for custom shapes, and regeneration for presets. */
	public static function resize(ei:EntityInstance,w:Int,h:Int,fromLeft=false,fromTop=false):Null<String> {
		var s=DrawableShape.read(ei);
		if(s==null) return "Enter Draw Shape to convert this legacy rectangle first.";
		if(s.error!=null) return s.error;
		var cells=s.cells.copy(),error:Null<String>=null;
		var originX=ei.left,originY=ei.top;
		if(w<1 || h<1) return "A shape must occupy at least one row and column.";
		if(s.mode=="Custom") {
			var dx=w-s.width,dy=h-s.height;
			if(dx!=0) {
				var result=DrawableShapeGeometry.resizeAxis(cells,"x",fromLeft ? 0 : dx>0 ? s.width-1 : w,dx);
				if(result.error!=null) return result.error;
				originX+=result.x*s.grid;originY+=result.y*s.grid;
				cells=result.cells;
			}
			if(dy!=0) {
				var result=DrawableShapeGeometry.resizeAxis(cells,"y",fromTop ? 0 : dy>0 ? s.height-1 : h,dy);
				if(result.error!=null) return result.error;
				originX+=result.x*s.grid;originY+=result.y*s.grid;
				cells=result.cells;
			}
		}
		else {
			var result=DrawableShapeGeometry.preset(s.mode=="Rectangle" ? "Rectangle" : s.preset,w,h,s.thickness,s.quarterTurns);
			if(result.error!=null) return result.error;
			cells=result.cells;
		}
		if(fromLeft) originX-=(w-s.width)*s.grid;
		if(fromTop) originY-=(h-s.height)*s.grid;
		return DrawableShape.applyCells(ei,cells,s.grid,originX,originY,s.mode,s.preset);
	}

	static function number(parent:J,label:String,value:Int,css:String):J {
		var wrap=new J('<label/>').text(label+" ").appendTo(parent);
		return new J('<input type="number" step="1" style="width:62px"/>').addClass(css).val(value).appendTo(wrap);
	}

	public static function appendInspector(parent:J,ei:EntityInstance) {
		if(!DrawableShape.isEnabled(ei.def)) return;
		var s=DrawableShape.read(ei),grid=s==null ? ei._li.def.gridSize : s.grid;
		var box=new J('<div class="drawableShapeInspector" style="padding:9px;border:1px solid #63717f;margin:8px 0"/>').appendTo(parent);
		box.append('<strong>Shape</strong>');
		if(s!=null && s.error!=null) new J('<p class="error"/>').text(s.error).appendTo(box);
		var buttons=row(box);
		button(buttons,"Select / move","shapeSelect",()->editor.clearSpecialTool());
		for(b in ["Paint","Erase","Fill"]) {
			var brush=b;
			button(buttons,b,"shape"+b,()->{placementMode="Custom";activate(ei.def,ei,brush);});
		}
		button(buttons,"Save configuration","shapeSaveConfig",()->{editor.clearSpecialTool();editor.selectionTool.select([Entity(ei._li,ei)]);editor.selectionTool.saveSelectionAsTemplate();});
		new J('<small/>').text(s==null ? "Legacy rectangle · edit to create shape fields" : s.mode+" · "+Std.int(s.cells.length/2)+" cells · "+grid+" px grid").appendTo(box);
		var params=row(box);
		var preset=selectControl(params,"shapePreset",presets,s==null || s.preset=="Custom" ? "Rectangle" : s.preset,_ -> {});
		var width=number(params,"X",M.imax(1,Std.int(ei.width/grid)),"shapeWidth");
		var height=number(params,"Y",M.imax(1,Std.int(ei.height/grid)),"shapeHeight");
		var thickness=number(params,"Thickness",s==null ? 1 : s.thickness,"shapeThickness");
		width.attr("min",1);height.attr("min",1);thickness.attr("min",1);
		var rotation=selectControl(params,"shapeRotation",["0","90","180","270"],Std.string(s==null ? 0 : s.quarterTurns*90),_ -> {});
		var info=new J('<small class="shapeMinimum"/>').appendTo(box);
		function updateMinimum() {
			var t=Std.parseInt(thickness.val()); if(t==null || t<1) t=1;
			var min=DrawableShapeGeometry.minimum(preset.val(),t,Std.int(Std.parseInt(rotation.val())/90));
			info.text(preset.val()+" minimum: "+min.width+" × "+min.height+" cells. Apply preset replaces the silhouette.");
		}
		var previewStatus=new J('<small class="shapeParameterPreview"/>').appendTo(box);
		// Resizing a custom mask keeps that mask. Only an explicit preset/parameter
		// choice switches this pending preview to deliberate silhouette replacement.
		var presetPreview=s==null || s.mode!="Custom";
		function showParameterPreview() {
			clearPreview();updateMinimum();
			var w=Std.parseInt(width.val()),h=Std.parseInt(height.val()),t=Std.parseInt(thickness.val()),q=Std.parseInt(rotation.val());
			if(w==null || h==null || t==null || q==null) {previewStatus.text("Preview: enter whole cell dimensions.");return;}
			var json=ei.toJson(ei._li);
			json.iid="shape-preview-"+ei.iid;
			var draft=EntityInstance.fromJson(ei._project,ei._li,json);
			var error=presetPreview
				? DrawableShape.applyPreset(draft,preset.val(),w,h,t,Std.int(q/90))
				: resize(draft,w,h);
			var state=DrawableShape.read(draft);
			if(state==null) state={cells:[],grid:grid,mode:"Preset",preset:preset.val(),width:w,height:h,error:error,
				profile:DrawableShape.value(ei,"VisualProfile","SolidBarrier"),facing:DrawableShape.value(ei,"ShapeFacing","All"),
				thickness:t,quarterTurns:Std.int(q/90),color:ei.getSmartColor(false),occupied:new Map()};
			if(error!=null) {
				state={cells:[],grid:grid,mode:state.mode,preset:state.preset,width:w,height:h,error:error,
					profile:state.profile,facing:state.facing,thickness:t,quarterTurns:Std.int(q/90),color:state.color,occupied:new Map()};
			}
			showShapePreview(ei,state,error==null ? draft.left : ei.left,error==null ? draft.top : ei.top);
			previewStatus.text(error!=null ? "Shape unchanged: "+error : presetPreview
				? "Preview only · Apply preset replaces the silhouette."
				: "Preview only · Resize X / Y keeps the custom silhouette and valid topology.");
		}
		preset.change(_->{presetPreview=true;showParameterPreview();});
		thickness.on("input change",_->{presetPreview=true;showParameterPreview();});
		rotation.change(_->{presetPreview=true;showParameterPreview();});
		width.on("input change",_->showParameterPreview());height.on("input change",_->showParameterPreview());
		updateMinimum();
		button(params,"Cancel preview","shapeParameterCancel",()->{clearPreview();previewStatus.text("");});
		button(params,"Apply preset","shapeApplyPreset",()->{
			clearPreview();
			var w=Std.parseInt(width.val()),h=Std.parseInt(height.val()),t=Std.parseInt(thickness.val()),q=Std.parseInt(rotation.val());
			if(w==null || h==null || t==null || q==null) {N.error("Enter whole cell dimensions.");return;}
			commit(ei,()->DrawableShape.applyPreset(ei,preset.val(),w,h,t,Std.int(q/90)));
		});
		if(s!=null && s.error==null) {
			button(params,"Resize X / Y","shapeResize",()->{
				clearPreview();
				var w=Std.parseInt(width.val()),h=Std.parseInt(height.val());
				if(w==null || h==null) return;
				commit(ei,()->resize(ei,w,h));
			});
			var transforms=row(box);
			button(transforms,"Mirror X","shapeMirrorX",()->commit(ei,()->DrawableShape.transform(ei,true,false)));
			button(transforms,"Mirror Y","shapeMirrorY",()->commit(ei,()->DrawableShape.transform(ei,false,true)));
			button(transforms,"Rotate 90°","shapeRotate",()->commit(ei,()->DrawableShape.transform(ei,false,false,1)));
			var extension=row(box);
			var axis=selectControl(extension,"shapeAxis",["X","Y"],"X",_ -> {});
			var index=number(extension,"At column / row",0,"shapeAxisIndex").attr("min",0);
			var delta=number(extension,"Count (+ / −)",1,"shapeAxisDelta");
			var status=new J('<small class="shapeAxisStatus"/>').appendTo(box);
			function candidate() {
				var n=Std.parseInt(index.val()),d=Std.parseInt(delta.val());
				return DrawableShapeGeometry.resizeAxis(s.cells,Std.string(axis.val()).toLowerCase(),n==null ? -1 : n,d==null ? 0 : d);
			}
			function showPreview() {
				clearPreview();
				var result=candidate();status.text(result.error==null ? "Preview: "+result.width+" × "+result.height+"; click Apply rows / columns to keep it." : result.error);
				var draft:Dynamic={cells:result.cells.length>0 ? result.cells : s.cells,grid:s.grid,mode:"Custom",preset:"Custom",width:result.width,height:result.height,
					error:result.error,profile:s.profile,facing:s.facing,thickness:s.thickness,quarterTurns:s.quarterTurns,color:s.color};
				showShapePreview(ei,cast draft,ei.left+result.x*s.grid,ei.top+result.y*s.grid);
			}
			axis.change(_->showPreview());index.on("input",_->showPreview());delta.on("input",_->showPreview());
			button(extension,"Preview","shapeAxisPreview",showPreview);
			button(extension,"Apply rows / columns","shapeAxisApply",()->{
				var result=candidate();clearPreview();
				if(result.error!=null) {N.error(result.error);return;}
				commit(ei,()->DrawableShape.applyCells(ei,result.cells,s.grid,ei.left+result.x*s.grid,ei.top+result.y*s.grid));
			});
			button(extension,"Cancel preview","shapeAxisCancel",clearPreview);
		}
	}

	static function showShapePreview(ei:EntityInstance,state:data.DrawableShape.DrawableShapeState,left:Int,top:Int) {
		clearPreview();
		axisPreview=new h2d.Graphics();editor.levelRender.root.add(axisPreview,Const.DP_UI);
		axisPreview.setScale(ei._li.def.getScale());
		axisPreview.setPosition(ei._li.pxParallaxX+left*ei._li.def.getScale(),ei._li.pxParallaxY+top*ei._li.def.getScale());
		display.DrawableShapeRender.draw(axisPreview,state,ei,ei.def);
		axisPreview.alpha=0.85;
		previewOwnerIid=ei.iid;display.EntityRender.suppressedShapes.set(ei.iid,true);
		editor.selectionTool.invalidateRender();
		App.ME.requestCpu();
	}

	public static function clearPreview() {
		var hadPreview=axisPreview!=null || previewOwnerIid!=null;
		if(axisPreview!=null) axisPreview.remove();axisPreview=null;
		if(previewOwnerIid!=null) display.EntityRender.suppressedShapes.remove(previewOwnerIid);
		previewOwnerIid=null;
		if(hadPreview && editor!=null) editor.selectionTool.invalidateRender();
		if(App.ME!=null) App.ME.requestCpu();
	}
}
