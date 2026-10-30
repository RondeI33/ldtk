import camerapreview.CameraPreviewGeometry;
import camerapreview.CameraPreviewGeometry.CameraPreviewFrame;

class CameraPreviewGeometryTest {
	static var assertions = 0;
	static var vectors = 0;

	static function check(value:Bool,message:String) {
		assertions++;
		if( !value )
			throw message;
	}

	static function near(value:Float,expected:Float,message:String,tolerance=0.000001) {
		check(Math.isFinite(value) && Math.abs(value-expected)<=tolerance,message+": expected "+expected+", got "+value);
	}

	static function snapshot():Dynamic {
		return {schemaVersion:1,source:"unity",valid:true,orthographic:true,
			orthographicSize:5.625,aspect:16/9,pixelsPerUnit:16};
	}

	static function rejected(raw:String,name:String,?contains:String) {
		vectors++;
		var result = CameraPreviewGeometry.parse(raw);
		check(result.profile==null,name+" must not produce a profile");
		check(result.error!=null && result.error.length>0,name+" must explain the rejection");
		if( contains!=null )
			check(result.error.indexOf(contains)>=0,name+" rejection should mention "+contains+", got "+result.error);
	}

	static function badField(key:String,value:Dynamic,name:String) {
		var data:Dynamic = snapshot();
		Reflect.setField(data,key,value);
		rejected(haxe.Json.stringify(data),name);
	}

	static function parseVectors() {
		var parsed = CameraPreviewGeometry.parse(haxe.Json.stringify(snapshot()));
		check(parsed.error==null && parsed.profile!=null,"Minimal valid snapshot resolves");
		near(parsed.profile.width,320,"Unity half-height converts to width");
		near(parsed.profile.height,180,"Unity half-height converts to height");
		near(parsed.profile.orthographicSize,5.625,"Original orthographic size retained");
		near(parsed.profile.aspect,16/9,"Original aspect retained");
		near(parsed.profile.pixelsPerUnit,16,"Original pixel density retained");
		check(parsed.profile.source=="unity","Source retained");
		check(parsed.profile.sceneName=="" && parsed.profile.scenePath=="" && parsed.profile.cameraName=="" && parsed.profile.updatedAtUtc=="","Optional metadata defaults to empty strings");
		check(!parsed.profile.live,"A manual snapshot is the default");

		var data:Dynamic = snapshot();
		data.sceneName="Badania Łódź";data.scenePath="Assets/Scenes/04_research.unity";
		data.cameraName="Main Camera";data.updatedAtUtc="2026-10-30T12:00:00.0000000Z";data.live=true;
		data.futureData={keep:[1,2,3]};data.error="";
		var before = haxe.Json.stringify(data);
		parsed = CameraPreviewGeometry.parse(before);
		check(parsed.error==null && parsed.profile.live,"Live export with additional metadata resolves");
		check(parsed.profile.sceneName==data.sceneName && parsed.profile.scenePath==data.scenePath && parsed.profile.cameraName==data.cameraName,"Unicode/path metadata remains exact");
		check(parsed.profile.updatedAtUtc==data.updatedAtUtc,"UTC timestamp remains exact");
		check(haxe.Json.stringify(data)==before,"Reading a profile does not mutate caller data");

		for(vector in [
			{size:5.625,aspect:9/16,ppu:16.,w:101.25,h:180.},
			{size:5.625,aspect:21/9,ppu:16.,w:420.,h:180.},
			{size:2.75,aspect:4/3,ppu:24.,w:176.,h:132.},
			{size:8.,aspect:1.6,ppu:32.,w:819.2,h:512.},
			{size:0.125,aspect:1.,ppu:4.,w:1.,h:1.},
			{size:5000000.,aspect:1.,ppu:1.,w:10000000.,h:10000000.},
			{size:2000000.,aspect:2.5,ppu:1.,w:10000000.,h:4000000.}
		]) {
			vectors++;
			data=snapshot();data.orthographicSize=vector.size;data.aspect=vector.aspect;data.pixelsPerUnit=vector.ppu;
			parsed=CameraPreviewGeometry.parse(haxe.Json.stringify(data));
			check(parsed.profile!=null && parsed.error==null,"Projection vector "+vectors+" resolves");
			near(parsed.profile.width,vector.w,"Projection vector width");
			near(parsed.profile.height,vector.h,"Projection vector height");
		}

		for(raw in [null,""," \n\t ","{","{\"valid\":","null","true","0","\"unity\"","[]","[{\"schemaVersion\":1}]"])
			rejected(raw,"Malformed/primitive payload "+Std.string(raw));
		for(key in ["schemaVersion","source","valid","orthographic","orthographicSize","aspect","pixelsPerUnit"]) {
			data=snapshot();Reflect.deleteField(data,key);
			rejected(haxe.Json.stringify(data),"Missing "+key);
			badField(key,null,"Null "+key);
		}
		for(value in ([2,0,-1,1.5,"1",true,[],{}]:Array<Dynamic>))
			badField("schemaVersion",value,"Invalid schema version "+Std.string(value));
		for(value in (["Unity","manual",1,true,[],{}]:Array<Dynamic>))
			badField("source",value,"Invalid source "+Std.string(value));
		for(key in ["valid","orthographic","live"])
			for(value in (["true",1,0,[],{}]:Array<Dynamic>))
				badField(key,value,"Non-boolean "+key);
		badField("live",null,"Null live flag");
		badField("orthographic",false,"Perspective camera rejected");
		for(key in ["orthographicSize","aspect","pixelsPerUnit"])
			for(value in ([0,-0.001,-10,"16",true,false,[],[16],{value:16}]:Array<Dynamic>))
				badField(key,value,"Invalid positive numeric "+key+": "+Std.string(value));
		for(key in ["sceneName","scenePath","cameraName","updatedAtUtc","error"])
			for(value in ([null,1,true,[],{}]:Array<Dynamic>))
				badField(key,value,"Invalid string metadata "+key);
		for(key in ["orthographicSize","aspect","pixelsPerUnit"]) {
			data=snapshot();Reflect.setField(data,key,123456789);
			var raw=haxe.Json.stringify(data);
			for(value in ["1e999","-1e999","NaN","Infinity","-Infinity"])
				rejected(StringTools.replace(raw,"123456789",value),"Non-finite "+key+" "+value);
		}
		badField("orthographicSize",5000001,"Oversized height");
		badField("aspect",1e10,"Oversized width");
		badField("pixelsPerUnit",1e308,"Overflowing dimension");
		data=snapshot();data.orthographicSize=1e-300;data.pixelsPerUnit=1e-300;
		rejected(haxe.Json.stringify(data),"Underflowing height");
		data=snapshot();data.orthographicSize=1e-300;data.aspect=1e-300;
		rejected(haxe.Json.stringify(data),"Underflowing width");

		data=snapshot();data.valid=false;data.error="Active scene has no camera.";
		rejected(haxe.Json.stringify(data),"Unity invalidation","Active scene has no camera.");
		data={schemaVersion:1,source:"unity",valid:false,error:"Camera is tilted."};
		rejected(haxe.Json.stringify(data),"Minimal invalidation","Camera is tilted.");
		data.error="";rejected(haxe.Json.stringify(data),"Invalidation without reason");
		data.error=17;rejected(haxe.Json.stringify(data),"Invalidation with malformed reason");
	}

	static function assertFrame(actual:CameraPreviewFrame,expected:Array<Float>,column:Null<Float>,row:Null<Float>,name:String) {
		vectors++;
		near(actual.x,expected[0],name+" left");near(actual.y,expected[1],name+" top");
		near(actual.width,expected[2],name+" width");near(actual.height,expected[3],name+" height");
		near(actual.centerX,expected[0]+expected[2]*0.5,name+" center x");
		near(actual.centerY,expected[1]+expected[3]*0.5,name+" center y");
		check(actual.column==column && actual.row==row,name+" cell indices");
	}

	static function expectThrow(action:()->Void,name:String) {
		var thrown=false;
		try action() catch(_:Dynamic) thrown=true;
		check(thrown,name+" must reject invalid frame input");
	}

	static function frameVectors() {
		assertFrame(CameraPreviewGeometry.frame(123.25,79.5,320,180,false),[-36.75,-10.5,320,180],null,null,"Free point keeps fractional coordinates");
		assertFrame(CameraPreviewGeometry.frame(0,0,320,180,false),[-160,-90,320,180],null,null,"Free frame extends beyond room origin");
		assertFrame(CameraPreviewGeometry.frame(-30.5,-20.75,320,180,false),[-190.5,-110.75,320,180],null,null,"Negative free point");
		assertFrame(CameraPreviewGeometry.frame(1024,768,320,180,false),[864,678,320,180],null,null,"Free frame does not clamp to a room edge");
		assertFrame(CameraPreviewGeometry.frame(319.999,179.999,320,180,true),[0,0,320,180],0,0,"Last point in origin cell");
		assertFrame(CameraPreviewGeometry.frame(320,180,320,180,true),[320,180,320,180],1,1,"Exact positive boundary uses following cell");
		assertFrame(CameraPreviewGeometry.frame(0,0,320,180,true),[0,0,320,180],0,0,"Grid origin");
		assertFrame(CameraPreviewGeometry.frame(-0.0001,-0.0001,320,180,true),[-320,-180,320,180],-1,-1,"Just before origin uses negative cell");
		assertFrame(CameraPreviewGeometry.frame(-320,-180,320,180,true),[-320,-180,320,180],-1,-1,"Exact negative boundary");
		assertFrame(CameraPreviewGeometry.frame(-320.0001,-180.0001,320,180,true),[-640,-360,320,180],-2,-2,"Just before negative boundary");
		assertFrame(CameraPreviewGeometry.frame(50,70,320,180,true,64,48),[-128,-18,320,180],0,1,"Guide cell independent of viewport size");
		assertFrame(CameraPreviewGeometry.frame(50,70,320,180,true,64),[-128,0,320,180],0,0,"Only guide width specified");
		assertFrame(CameraPreviewGeometry.frame(50,70,320,180,true,null,48),[0,-18,320,180],0,1,"Only guide height specified");
		assertFrame(CameraPreviewGeometry.frame(10,-20,320,180,true,null,null,10,-20),[10,-20,320,180],0,0,"Nonzero grid origin");
		assertFrame(CameraPreviewGeometry.frame(9.999,-20.001,320,180,true,null,null,10,-20),[-310,-200,320,180],-1,-1,"Negative cells relative to offset origin");
		assertFrame(CameraPreviewGeometry.frame(79,25,20,10,true,32,16,5,-2),[75,17,20,10],2,1,"Offset guide grid centers full projection");
		assertFrame(CameraPreviewGeometry.frame(0.3,0.4,0.5,0.25,true),[0,0.25,0.5,0.25],0,1,"Subpixel grid dimensions");
		assertFrame(CameraPreviewGeometry.frame(1e12+8,-1e12+4,16,8,true),[1e12,-1e12,16,8],62500000000.,-125000000000.,"Cell indices outside signed 32-bit range");
		assertFrame(CameraPreviewGeometry.frame(23.5,-9.25,320,180,false,0,Math.NaN,Math.POSITIVE_INFINITY,Math.NaN),[-136.5,-99.25,320,180],null,null,"Free mode ignores inactive grid parameters");

		for(point in [Math.NaN,Math.POSITIVE_INFINITY,Math.NEGATIVE_INFINITY]) {
			expectThrow(()->CameraPreviewGeometry.frame(point,0,320,180,false),"Invalid point X");
			expectThrow(()->CameraPreviewGeometry.frame(0,point,320,180,false),"Invalid point Y");
			expectThrow(()->CameraPreviewGeometry.frame(0,0,320,180,true,null,null,point,0),"Invalid origin X");
			expectThrow(()->CameraPreviewGeometry.frame(0,0,320,180,true,null,null,0,point),"Invalid origin Y");
		}
		for(size in [0.,-1.,Math.NaN,Math.POSITIVE_INFINITY,10000001.]) {
			expectThrow(()->CameraPreviewGeometry.frame(0,0,size,180,false),"Invalid width");
			expectThrow(()->CameraPreviewGeometry.frame(0,0,320,size,false),"Invalid height");
			expectThrow(()->CameraPreviewGeometry.frame(0,0,320,180,true,size,16),"Invalid grid width");
			expectThrow(()->CameraPreviewGeometry.frame(0,0,320,180,true,16,size),"Invalid grid height");
		}
		expectThrow(()->CameraPreviewGeometry.frame(1e300,0,320,180,true,1e-300,16),"Grid index overflow");
		expectThrow(()->CameraPreviewGeometry.frame(1e308,0,320,180,true,16,16,-1e308,0),"Relative coordinate overflow");

		// Every point in a camera cell must produce the same frame, across the origin
		// and with viewport dimensions deliberately different from guide-grid steps.
		for(x in -12...13)
			for(y in -9...10) {
				var stepX=23.5,stepY=14.25,originX=7.25,originY=-3.5;
				var a=CameraPreviewGeometry.frame(originX+x*stepX+0.01,originY+y*stepY+0.01,320,180,true,stepX,stepY,originX,originY);
				var b=CameraPreviewGeometry.frame(originX+(x+1)*stepX-0.01,originY+(y+1)*stepY-0.01,320,180,true,stepX,stepY,originX,originY);
				check(a.column==x && a.row==y && b.column==x && b.row==y,"Stable containing cell "+x+","+y);
				near(a.x,b.x,"Frame X remains constant within cell");near(a.y,b.y,"Frame Y remains constant within cell");
				near(a.centerX,originX+(x+0.5)*stepX,"Guide center X");near(a.centerY,originY+(y+0.5)*stepY,"Guide center Y");
				var free=CameraPreviewGeometry.frame(a.centerX,a.centerY,320,180,false);
				near(free.x,a.x,"Free and snapped frame agree at cell center X");near(free.y,a.y,"Free and snapped frame agree at cell center Y");
			}
	}


	static function playerModelVectors() {
		var legacy = CameraPreviewGeometry.parse(haxe.Json.stringify(snapshot()));
		check(legacy.profile!=null && legacy.profile.unityCameraModel==null,"Older snapshots stay dimensions-only");
		assertFrame(CameraPreviewGeometry.playerFrame(legacy.profile,"room-a",20,30,0,0,640,400),
			[-140,-60,320,180],null,null,"Legacy projection centers on player only");
		var invalid:Dynamic=snapshot();
		invalid.unityCameraModel={schemaVersion:2};
		rejected(haxe.Json.stringify(invalid),"Unknown nested camera model version","unityCameraModel");
		var newer:Dynamic=snapshot();
		newer.unityCameraModel={
			schemaVersion:1,
			levels:[{
				iid:"room-a",
				camera:{offset:{x:1.5,y:-0.5}},
				rooms:[{x:0,y:0,width:640,height:400}],
				zones:[{x:100,y:100,width:200,height:150,zoom:2}]
			}]
		};
		var parsed=CameraPreviewGeometry.parse(haxe.Json.stringify(newer));
		check(parsed.error==null && parsed.profile.unityCameraModel!=null,"Nested Unity model preserved for solver");
		assertFrame(CameraPreviewGeometry.playerFrame(parsed.profile,"room-a",20,40,1024,80,640,400),
			[0,0,320,180],null,null,"Room boundary clamps camera, nonzero level world origin");
		assertFrame(CameraPreviewGeometry.playerFrame(parsed.profile,"room-a",200,150,1024,80,640,400),
			[144,113,160,90],null,null,"Zone zoom and Unity-to-LDtk Y-offset around player");
		assertFrame(CameraPreviewGeometry.playerFrame(parsed.profile,"other-room",20,40,1024,80,640,400),
			[-140,-50,320,180],null,null,"Unknown level IID cannot borrow another room");
		newer.unityCameraModel.levels[0].zones=[{x:100,y:100,width:200,height:150,orthographicSize:3}];
		parsed=CameraPreviewGeometry.parse(haxe.Json.stringify(newer));
		var f=CameraPreviewGeometry.playerFrame(parsed.profile,"room-a",200,150,1024,80,640,400);
		near(f.width,96*16/9,"Zone orthographic size overrides preview width");
		near(f.height,96,"Zone orthographic size overrides preview height");
		near(f.centerX,224,"Zone zoom does not replace player X with camera center");
		near(f.centerY,158,"LDtk downwards Y uses inverted Unity camera offset");
		for(value in [Math.NaN,Math.POSITIVE_INFINITY,Math.NEGATIVE_INFINITY])
			expectThrow(()->CameraPreviewGeometry.playerFrame(parsed.profile,"room-a",value,10,0,0,640,400),
				"Invalid player position rejected");
	}

	static function main() {
		parseVectors();
		frameVectors();
		playerModelVectors();
		Sys.println("PASS: camera preview geometry: "+vectors+" explicit vectors, "+assertions+" assertions including 475 grid-cell sweeps");
	}
}
