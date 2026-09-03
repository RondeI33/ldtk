private typedef PendingControlRequest = {
	var response : Dynamic;
	var timer : haxe.Timer;
}

class SmartiveControlServer {
	static var mainWindow : electron.main.BrowserWindow;
	static var server : Dynamic;
	static var token : String;
	static var port = -1;
	static var controlDir : String;
	static var controlPath : String;
	static var projectPath : Null<String> = null;
	static var nextRequestId = 1;
	static var pending : Map<Int,PendingControlRequest> = new Map();

	static inline var DIR_MODE = 0x1C0; // 0700
	static inline var FILE_MODE = 0x180; // 0600

	public static function start(window:electron.main.BrowserWindow) {
		mainWindow = window;
		if( server!=null ) {
			writeControlFile();
			return;
		}

		var http : Dynamic = js.node.Require.require("http");
		var crypto : Dynamic = js.node.Require.require("crypto");
		var path : Dynamic = js.node.Require.require("path");
		var os : Dynamic = js.node.Require.require("os");
		var envDir : Dynamic = Reflect.field(js.Node.process.env, "LDTK_SMARTIVE_CONTROL_DIR");

		token = crypto.randomBytes(32).toString("hex");
		controlDir = envDir!=null && Std.string(envDir).length>0
			? path.resolve(Std.string(envDir))
			: path.join(os.homedir(), ".ldtk-smartive", "control");
		controlPath = path.join(controlDir, Std.string(js.Node.process.pid)+".json");

		server = http.createServer(function(req:Dynamic, res:Dynamic) {
			handleRequest(req,res);
		});
		server.on("error", function(err:Dynamic) {
			trace("LDTK-Smartive control server error: "+Std.string(err));
		});
		server.listen(0, "127.0.0.1", function() {
			var address : Dynamic = server.address();
			port = address.port;
			writeControlFile();
		});
	}

	public static function setProjectPath(value:Null<String>) {
		var path : Dynamic = js.node.Require.require("path");
		projectPath = value==null || value.length==0 ? null : path.resolve(value);
		writeControlFile();
	}

	static function ensureControlDir() {
		if( controlDir==null )
			return;
		var fs : Dynamic = js.node.Require.require("fs");
		fs.mkdirSync(controlDir, { recursive:true, mode:DIR_MODE });
		try fs.chmodSync(controlDir, DIR_MODE) catch(_:Dynamic) {}
	}

	static function writeControlFile() {
		if( port<=0 || controlPath==null || token==null )
			return;
		try {
			ensureControlDir();
			var fs : Dynamic = js.node.Require.require("fs");
			var json = haxe.Json.stringify({
				pid: js.Node.process.pid,
				port: port,
				token: token,
				projectPath: projectPath,
				version: MacroTools.getAppVersion(),
			});
			fs.writeFileSync(controlPath, json, { encoding:"utf8", mode:FILE_MODE });
			try fs.chmodSync(controlPath, FILE_MODE) catch(_:Dynamic) {}
		}
		catch(err:Dynamic) {
			trace("Failed to write LDTK-Smartive control file: "+Std.string(err));
		}
	}

	static function sendJson(res:Dynamic, status:Int, payload:Dynamic) {
		if( res==null )
			return;
		var body = Std.isOfType(payload,String) ? cast payload : haxe.Json.stringify(payload);
		res.writeHead(status, {
			"Content-Type": "application/json; charset=utf-8",
			"Content-Length": untyped __js__("Buffer.byteLength")(body),
		});
		res.end(body);
	}

	static function requestRenderer(res:Dynamic, kind:String, force:Bool) {
		if( mainWindow==null || mainWindow.isDestroyed() ) {
			sendJson(res, 503, { error:"editor renderer unavailable" });
			return;
		}

		var id = nextRequestId++;
		var timer = haxe.Timer.delay(function() {
			var p = pending.get(id);
			if( p!=null ) {
				pending.remove(id);
				sendJson(p.response, 500, { error:"editor response timeout" });
			}
		}, 29000);
		pending.set(id, { response:res, timer:timer });
		mainWindow.webContents.send("smartiveControlRequest", id, kind, force);
	}

	public static function completeRendererRequest(id:Int, status:Int, json:String) {
		var p = pending.get(id);
		if( p==null )
			return;
		pending.remove(id);
		p.timer.stop();
		if( json==null || json.length==0 )
			json = haxe.Json.stringify({ error:"empty editor response" });
		sendJson(p.response, status, json);
	}

	static function handleRequest(req:Dynamic, res:Dynamic) {
		var headers : Dynamic = req.headers;
		if( headers!=null && Reflect.hasField(headers,"origin") ) {
			sendJson(res, 403, { error:"Origin header is not allowed" });
			return;
		}

		var supplied : Dynamic = headers==null ? null : Reflect.field(headers,"x-ldtk-token");
		if( supplied==null || Std.string(supplied)!=token ) {
			sendJson(res, 403, { error:"invalid or missing X-LDtk-Token" });
			return;
		}

		var method = Std.string(req.method).toUpperCase();
		var requestPath = Std.string(req.url).split("?")[0];
		if( method=="GET" && requestPath=="/status" ) {
			requestRenderer(res,"status",false);
			return;
		}

		if( method=="POST" && requestPath=="/reload" ) {
			var body = "";
			var rejected = false;
			req.on("data", function(chunk:Dynamic) {
				if( rejected )
					return;
				body += chunk.toString();
				if( body.length>65536 ) {
					rejected = true;
					sendJson(res, 413, { error:"request body too large" });
				}
			});
			req.on("end", function() {
				if( rejected )
					return;
				var force = false;
				if( StringTools.trim(body).length>0 ) {
					try {
						var parsed : Dynamic = haxe.Json.parse(body);
						force = Reflect.field(parsed,"force")==true;
					}
					catch(err:Dynamic) {
						sendJson(res, 400, { error:"invalid JSON body" });
						return;
					}
				}
				requestRenderer(res,"reload",force);
			});
			req.on("error", function(err:Dynamic) {
				if( !rejected ) {
					rejected = true;
					sendJson(res, 400, { error:"request read failed" });
				}
			});
			return;
		}

		sendJson(res, 404, { error:"not found" });
	}

	public static function stop() {
		for(p in pending) {
			p.timer.stop();
			try sendJson(p.response, 503, { error:"editor shutting down" }) catch(_:Dynamic) {}
		}
		pending = new Map();

		if( controlPath!=null ) {
			try {
				var fs : Dynamic = js.node.Require.require("fs");
				if( fs.existsSync(controlPath) )
					fs.unlinkSync(controlPath);
			}
			catch(_:Dynamic) {}
		}

		if( server!=null ) {
			try server.close() catch(_:Dynamic) {}
			server = null;
		}
		port = -1;
	}
}
