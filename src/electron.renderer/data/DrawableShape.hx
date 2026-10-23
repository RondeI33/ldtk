package data;

import data.inst.EntityInstance;
import data.inst.FieldInstance;
import data.def.EntityDef;
import data.def.FieldDef;
import ldtk.Json.FieldType;
import DrawableShapeGeometry;

typedef DrawableShapeState = {
	var cells:Array<Int>;
	var grid:Int;
	var mode:String;
	var preset:String;
	var width:Int;
	var height:Int;
	var error:Null<String>;
	var profile:String;
	var facing:String;
	var thickness:Int;
	var quarterTurns:Int;
	var color:Int;
	var occupied:Map<String,Bool>;
}

/** Version 1 uses only native field definitions/instances; the sidecar enables the UI. */
@:access(data.def.EntityDef)
@:access(data.def.EnumDef)
class DrawableShape {
	public static inline var VERSION=1;
	public static final GENERATED=["ShapeVersion","ShapeMode","ShapeGridSize","ShapeCells","ShapePreset","ShapeThickness","ShapeQuarterTurns"];
	public static final GEOMETRY=["ShapeVersion","ShapeMode","ShapeGridSize","ShapeCells","ShapePreset","ShapeThickness","ShapeQuarterTurns","ShapeFacing"];
	public static final MODES=["Rectangle","Preset","Custom"];
	public static final PROFILES=["SolidBarrier","Spikes","EnergyPool"];
	public static final FACES=["All","Up","Right","Down","Left"];

	public static function isEnabled(ed:EntityDef):Bool return ed!=null && ed._project.forkConfig.hasDrawableShape(ed);
	public static function isGeneratedField(fd:FieldDef):Bool return fd!=null && GENERATED.indexOf(fd.identifier)>=0;
	public static function disable(ed:EntityDef) { if(ed!=null)ed._project.forkConfig.setDrawableShapeEnabled(ed,false); }

	/** Only reserved contract values bypass a project's enum capitalization policy. */
	public static function isContractEnumValue(en:data.def.EnumDef,value:String):Bool {
		if(en==null || value==null)return false;
		var known=MODES.concat(DrawableShapeGeometry.PRESETS).concat(PROFILES).concat(FACES);
		if(known.indexOf(value)<0)return false;
		function values(field:String):Array<String> return switch field {
			case "ShapeMode":MODES;
			case "ShapePreset":DrawableShapeGeometry.PRESETS.concat(["Custom"]);
			case "VisualProfile":PROFILES;
			case "ShapeFacing":FACES;
			case _:[];
		};
		for(name in ["ShapeMode","ShapePreset","VisualProfile","ShapeFacing"])
			if(en.identifier.toLowerCase()==("Drawable"+name).toLowerCase())return values(name).indexOf(value)>=0;
		for(ed in en._project.defs.entities) {
			if(!isEnabled(ed) && (ed.getFieldDef("ShapeVersion")==null || ed.getFieldDef("ShapeCells")==null))continue;
			for(fd in ed.fieldDefs)if(fd.getEnumDefinition()==en && values(fd.identifier).indexOf(value)>=0)return true;
		}
		return false;
	}

	static function enumField(ed:EntityDef,name:String,values:Array<String>):FieldType {
		var p=ed._project, existing=ed.getFieldDef(name);
		if(existing!=null) {
			if(name=="VisualProfile")for(value in values)if(!existing.getEnumDefinition().hasValue(value))existing.getEnumDefinition().addValue(value);
			return existing.type;
		}
		var en:Null<data.def.EnumDef>=null;
		for(candidate in p.defs.enums)if(candidate.identifier.toLowerCase()==("Drawable"+name).toLowerCase()) {en=candidate;break;}
		if(en==null) {en=p.defs.createEnumDef();en.identifier="Drawable"+name;}
		for(value in values)if(!en.hasValue(value))en.addValue(value);
		return F_Enum(en.uid);
	}

	/** Returns an error before changing incompatible user-authored fields. */
	public static function enable(ed:EntityDef):Null<String> {
		if(ed==null)return "Choose an entity definition first.";
		var definitions:Array<{name:String,type:FieldType,array:Bool,initial:String}>=[
			{name:"ShapeVersion",type:F_Int,array:false,initial:"1"},
			{name:"ShapeGridSize",type:F_Int,array:false,initial:"16"},
			{name:"ShapeCells",type:F_Int,array:true,initial:null},
			{name:"ShapeThickness",type:F_Int,array:false,initial:"1"},
			{name:"ShapeQuarterTurns",type:F_Int,array:false,initial:"0"},
			{name:"Color",type:F_Color,array:false,initial:C.intToHex(ed.color)},
		];
		for(spec in definitions) {
			var fd=ed.getFieldDef(spec.name);
			if(fd!=null && (fd.type!=spec.type || fd.isArray!=spec.array))return spec.name+" already exists with an incompatible type.";
		}
		var enums=[{name:"ShapeMode",values:MODES},{name:"ShapePreset",values:DrawableShapeGeometry.PRESETS.concat(["Custom"])},{name:"VisualProfile",values:PROFILES},{name:"ShapeFacing",values:FACES}];
		for(spec in enums) {
			var fd=ed.getFieldDef(spec.name);
			if(fd==null)continue;
			var en=fd.getEnumDefinition();
			if(fd.isArray || en==null)return spec.name+" already exists with an incompatible type.";
			if(spec.name!="VisualProfile")for(value in spec.values)if(!en.hasValue(value))return spec.name+" must include enum value "+value+"; existing enum values were preserved.";
		}
		// All compatibility validation is complete. Register before adding canonical
		// values to an existing VisualProfile enum with a custom project name.
		ed._project.forkConfig.setDrawableShapeEnabled(ed,true);
		for(spec in enums)definitions.push({name:spec.name,type:enumField(ed,spec.name,spec.values),array:false,initial:spec.values[0]});
		for(spec in definitions) {
			var fd=ed.getFieldDef(spec.name),fresh=fd==null;
			if(fresh) {fd=ed.createFieldDef(ed._project,spec.type,spec.name,spec.array);fd.identifier=spec.name;fd.setDefault(spec.initial);}
			if(GENERATED.indexOf(spec.name)>=0) {fd.editorDisplayMode=Hidden;fd.editorShowInWorld=false;}
			if(spec.name=="ShapeCells") {fd.arrayMinLength=null;fd.arrayMaxLength=null;fd.min=null;fd.max=null;}
			if(spec.name=="Color")fd.useForSmartColor=true;
		}
		ed.resizableX=ed.resizableY=true;
		ed.keepAspectRatio=false;
		ed._project.forkConfig.setDrawableShapeEnabled(ed,true);
		return null;
	}

	public static function field(ei:EntityInstance,name:String,create=false):Null<FieldInstance> {
		var fd=ei==null ? null:ei.def.getFieldDef(name);
		return fd==null ? null:ei.getFieldInstance(fd,create);
	}
	public static function value(ei:EntityInstance,name:String,fallback:Dynamic):Dynamic {
		var fi=field(ei,name);return fi==null ? fallback:fi.getFullJsonValue();
	}
	public static function set(ei:EntityInstance,name:String,v:Dynamic):Bool {
		var fi=field(ei,name,true);if(fi==null)return false;
		if(fi.def.isArray) {fi.clearValue();for(item in (cast v:Array<Dynamic>)) {fi.addArrayValue();fi.parseValue(fi.getArrayLength()-1,Std.string(item));}}
		else fi.parseValue(0,v==null ? null:Std.string(v));
		ei.drawableShapeCache=null;
		return true;
	}

	public static function hasMetadata(ei:EntityInstance):Bool {
		if(ei.drawableShapeSourceError!=null)return true;
		var fi=field(ei,"ShapeVersion");
		if(fi!=null && !fi.isUsingDefault(0))return true;
		// Stock LDtk may compact a value back to its default. Explicit cells or
		// another shape field still opt into strict validation, including missing versions.
		for(name in ["ShapeMode","ShapeGridSize","ShapeCells","ShapePreset"]) {
			var other=field(ei,name);
			if(other!=null && (other.def.isArray ? other.getArrayLength()>0:!other.isUsingDefault(0)))return true;
		}
		return false;
	}

	static function signature(ei:EntityInstance):String {
		var sig=ei.width+":"+ei.height+":"+ei.drawableShapeSourceError;
		for(name in GEOMETRY.concat(["Color","VisualProfile"])) {
			var fi=field(ei,name);
			if(fi==null) {sig+=":missing";continue;}
			sig+=":"+fi.revision+":"+Std.string(fi.def.type)+":"+fi.def.isArray+":"+fi.def.min+":"+fi.def.max;
			// Native default edits do not change the instance revision. Track only
			// scalar defaults; large cell arrays stay on the cheap revision path.
			if(!fi.def.isArray && fi.isUsingDefault(0))sig+=":"+Std.string(fi.def.getDefault());
		}
		return sig;
	}

	public static function read(ei:EntityInstance):Null<DrawableShapeState> {
		if(ei==null || !hasMetadata(ei))return null;
		var sig=signature(ei);
		if(ei.drawableShapeCache!=null && ei.drawableShapeSignature==sig)return ei.drawableShapeCache;
		try {
		var grid:Int=value(ei,"ShapeGridSize",0);
		var mode:String=value(ei,"ShapeMode",""),preset:String=value(ei,"ShapePreset","");
		var cells:Array<Int>=cast value(ei,"ShapeCells",[]);
		var s:DrawableShapeState={cells:[],grid:grid,mode:mode,preset:preset,width:0,height:0,error:ei.drawableShapeSourceError==null ? null:ei.drawableShapeSourceError,
			profile:value(ei,"VisualProfile","SolidBarrier"),facing:value(ei,"ShapeFacing","All"),
			thickness:value(ei,"ShapeThickness",1),quarterTurns:value(ei,"ShapeQuarterTurns",0),
			color:ei.def.color,occupied:new Map()};
		var color=field(ei,"Color");if(color!=null && color.def.type==F_Color)s.color=color.getColorAsInt(0);
		function error(message:String) {if(s.error==null)s.error=message;}
		if(value(ei,"ShapeVersion",0)!=VERSION)error("Unsupported ShapeVersion; expected version 1.");
		if(grid<=0 || grid!=Math.floor(grid))error("ShapeGridSize must be a positive integer.");
		if(MODES.indexOf(mode)<0)error("ShapeMode must be Rectangle, Preset, or Custom.");
		if(DrawableShapeGeometry.PRESETS.indexOf(preset)<0 && preset!="Custom")error("Unknown ShapePreset.");
		// Existing project profile enum values remain valid. Unknown visual styles
		// use the solid body preview while preserving their runtime profile value.
		if(FACES.indexOf(s.facing)<0)error("ShapeFacing must be All, Up, Right, Down, or Left.");
		if(s.thickness<1 || s.thickness!=Math.floor(s.thickness) || s.quarterTurns<0 || s.quarterTurns>3 || s.quarterTurns!=Math.floor(s.quarterTurns))error("Invalid shape thickness or quarter-turn orientation.");
		if(grid>0) {
			s.width=Std.int(ei.width/grid);s.height=Std.int(ei.height/grid);
			if(ei.width<=0 || ei.height<=0 || ei.width%grid!=0 || ei.height%grid!=0)error("Shape bounds must be positive whole grid cells.");
		}
		if(s.error==null && mode=="Rectangle") {
			s.cells=DrawableShapeGeometry.preset("Rectangle",s.width,s.height).cells;
			if(cells.length>0 && haxe.Json.stringify(cells)!=haxe.Json.stringify(s.cells))error("Rectangle cells disagree with the entity bounds.");
		}
		else if(s.error==null) {
			var n=DrawableShapeGeometry.normalize(cells);
			if(n.error!=null)error(n.error);
			else if(n.x!=0 || n.y!=0 || haxe.Json.stringify(cells)!=haxe.Json.stringify(n.cells))error("ShapeCells must be unique, normalized, and sorted by Y then X.");
			else if(n.width!=s.width || n.height!=s.height)error("ShapeCells do not match the entity bounding box.");
			else {var invalid=DrawableShapeGeometry.validate(cells);if(invalid!=null)error(invalid);else s.cells=cells.copy();}
		}
		if(s.error!=null)s.cells=[];
		s.occupied=DrawableShapeGeometry.occupied(s.cells);
		ei.drawableShapeSignature=sig;ei.drawableShapeCache=s;
		return s;
		}
		catch(error:Dynamic) {
			var s:DrawableShapeState={cells:[],grid:ei._li==null ? 16:ei._li.def.gridSize,mode:"Custom",preset:"Custom",width:0,height:0,
				error:"Malformed native shape fields: "+Std.string(error),profile:"SolidBarrier",facing:"All",thickness:1,quarterTurns:0,color:ei.def.color,occupied:new Map()};
			ei.drawableShapeSignature=sig;ei.drawableShapeCache=s;
			return s;
		}
	}

	public static function applyCells(ei:EntityInstance,cells:Array<Int>,grid:Int,?originX:Int,?originY:Int,mode="Custom",preset="Custom"):Null<String> {
		if(ei==null)return "Choose an entity instance first.";
		if(!isEnabled(ei.def))return "Enable Drawable shape for this entity definition first.";
		if(grid<=0)return "ShapeGridSize must be positive.";
		if(MODES.indexOf(mode)<0)return "Invalid shape mode.";
		var n=DrawableShapeGeometry.normalize(cells),invalid=DrawableShapeGeometry.validate(cells);
		if(invalid!=null)return invalid;
		if(mode=="Rectangle" && n.cells.length!=n.width*n.height*2)return "Rectangle mode requires a filled rectangle.";
		var x=originX==null ? ei.left:originX,y=originY==null ? ei.top:originY;
		var newWidth=n.width*grid,newHeight=n.height*grid;
		var left=x+n.x*grid,top=y+n.y*grid;
		function position(origin:Int,size:Int,pivot:Float):Null<Int> {
			var candidate=origin+M.round(size*pivot);
			if(M.round(candidate-size*pivot)==origin)return candidate;
			// LDtk rounds half pixels away from zero. An adjacent integer anchor
			// normally represents the exact origin; some zero-origin ties cannot.
			for(offset in [-1,1])if(M.round(candidate+offset-size*pivot)==origin)return candidate+offset;
			return null;
		}
		var px=position(left,newWidth,ei.def.pivotX),py=position(top,newHeight,ei.def.pivotY);
		if(px==null || py==null)return "This grid, pivot and origin cannot preserve exact pixel positions. Move the shape one pixel or choose a compatible pivot.";
		ei.drawableShapeSourceError=null;
		// Keep every surviving cell in world space, including fractional-pivot rounding.
		ei.customWidth=newWidth;ei.customHeight=newHeight;
		ei.x=px;ei.y=py;
		set(ei,"ShapeVersion",VERSION);set(ei,"ShapeGridSize",grid);set(ei,"ShapeMode",mode);set(ei,"ShapePreset",preset);
		set(ei,"ShapeCells",mode=="Rectangle" ? []:n.cells);
		if(mode=="Custom")set(ei,"ShapeQuarterTurns",0);
		return null;
	}

	public static function applyPreset(ei:EntityInstance,preset:String,width:Int,height:Int,thickness=1,quarterTurns=0):Null<String> {
		var n=DrawableShapeGeometry.preset(preset,width,height,thickness,quarterTurns);
		if(n.error!=null)return n.error;
		var previous=read(ei),grid=previous==null ? ei._li.def.gridSize:previous.grid;
		var err=applyCells(ei,n.cells,grid,ei.left,ei.top,preset=="Rectangle" ? "Rectangle":"Preset",preset);
		if(err!=null)return err;
		set(ei,"ShapeThickness",thickness);set(ei,"ShapeQuarterTurns",((quarterTurns%4)+4)%4);
		if(preset=="Strip" && value(ei,"ShapeFacing","All")=="All")set(ei,"ShapeFacing","Up");
		return null;
	}

	public static function transform(ei:EntityInstance,flipX:Bool,flipY:Bool,quarterTurns=0):Null<String> {
		var s=read(ei);if(s==null)return null;if(s.error!=null)return s.error;
		var n=DrawableShapeGeometry.transform(s.cells,flipX,flipY,quarterTurns);
		var face=s.facing;
		if(flipX)face=face=="Left" ? "Right":face=="Right" ? "Left":face;
		if(flipY)face=face=="Up" ? "Down":face=="Down" ? "Up":face;
		var directions=["Up","Right","Down","Left"],idx=directions.indexOf(face),q=((quarterTurns%4)+4)%4;
		if(idx>=0)face=directions[(idx+q)%4];
		var err=applyCells(ei,n.cells,s.grid,ei.left,ei.top);
		if(err==null)set(ei,"ShapeFacing",face);
		return err;
	}

	/** Apply compatible behaviour only. Neither identity nor authored cells are replaced. */
	public static function applyConfiguration(target:EntityInstance,source:EntityInstance):Null<String> {
		if(target==null || source==null || target.defUid!=source.defUid)return "Settings can only be applied to the same drawable entity type.";
		var shape=read(target);if(!isEnabled(target.def) || shape!=null && shape.error!=null)return "The target must have valid drawable geometry.";
		for(fd in source.def.fieldDefs) {
			if(GENERATED.indexOf(fd.identifier)>=0)continue;
			// References belong to the placed owner and its surrounding level, not
			// to a reusable behavior profile. Keep them (and their reverse cache).
			if(fd.type==F_EntityRef || fd.type==F_Point)continue;
			var fi=source.getFieldInstance(fd,false);if(fi==null)continue;
			target.fieldInstances.set(fd.uid,FieldInstance.fromJson(target._project,fi.toJson()));
		}
		target.drawableShapeCache=null;
		return null;
	}

	public static function hitTest(ei:EntityInstance,x:Float,y:Float,outline=2.):Null<Bool> {
		var s=read(ei);if(s==null)return null;
		if(s.error!=null)return x>=ei.left-outline && x<=ei.right+outline && y>=ei.top-outline && y<=ei.bottom+outline
			&& (Math.abs(x-ei.left)<outline || Math.abs(x-ei.right)<outline || Math.abs(y-ei.top)<outline || Math.abs(y-ei.bottom)<outline);
		var lx=x-ei.left,ly=y-ei.top,cx=Std.int(Math.floor(lx/s.grid)),cy=Std.int(Math.floor(ly/s.grid));
		if(s.occupied.exists(cx+","+cy))return true;
		// Only the actual exposed outline gets padding; a hollow bounding box never swallows a click.
		for(dy in -1...2)for(dx in -1...2) {
			var xx=cx+dx,yy=cy+dy;if(!s.occupied.exists(xx+","+yy))continue;
			var left=xx*s.grid,top=yy*s.grid;
			if(lx>=left-outline && lx<=left+s.grid+outline && ly>=top-outline && ly<=top+s.grid+outline)return true;
		}
		return false;
	}

	/** Retain a visible error if an imported file's public values disagree with native values. */
	public static function validateImported(ei:EntityInstance,json:ldtk.Json.EntityInstanceJson) {
		var declared=hasMetadata(ei);
		// Public non-legacy geometry also requires validation when damaged or
		// compacted native values would otherwise look like untouched defaults.
		for(fieldJson in JsonTools.readArray(json.fieldInstances))if(!declared) {
			if(fieldJson.__identifier=="ShapeCells" && Std.isOfType(fieldJson.__value,Array) && (cast fieldJson.__value:Array<Dynamic>).length>0)declared=true;
			if(fieldJson.__identifier=="ShapeMode" && fieldJson.__value!="Rectangle")declared=true;
			if(fieldJson.__identifier=="ShapePreset" && fieldJson.__value!="Rectangle")declared=true;
		}
		if(!declared)return;
		try {
		for(fieldJson in JsonTools.readArray(json.fieldInstances))if(GEOMETRY.indexOf(fieldJson.__identifier)>=0) {
			var fi=field(ei,fieldJson.__identifier);
			if(fi!=null && haxe.Json.stringify(fieldJson.__value)!=haxe.Json.stringify(fi.getFullJsonValue())) {
				ei.drawableShapeSourceError="Imported "+fieldJson.__identifier+" disagrees with its native editor values.";
				return;
			}
		}
		}
		catch(error:Dynamic)ei.drawableShapeSourceError="Malformed native shape field values: "+Std.string(error);
	}
}
