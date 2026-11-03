'use strict';
const {spawnSync}=require('node:child_process');
const fs=require('node:fs'),path=require('node:path');
const appDir=path.resolve(__dirname,'..'),repo=path.resolve(appDir,'..');
const renderer=path.join(appDir,'assets/js/renderer.js');
function run(command,args,cwd=repo){
 const r=spawnSync(command,args,{cwd,stdio:'inherit',env:process.env});
 if(r.error)throw r.error;
 return r.status==null?1:r.status;
}
let status=1,original=null;
try {
 if(run('haxe',['main.hxml'])!==0)throw Error('Main-process compilation failed');
 if(run('haxe',['renderer.hxml'])!==0)throw Error('Renderer compilation failed');
 original=fs.readFileSync(renderer,'utf8');
 const marker='\tBoot.main();';
 if(original.split(marker).length!==2)throw Error('Cannot find unique renderer bootstrap');
 const expose='\tglobalThis.__ldtk = {classes:$hxClasses,enums:$hxEnums,App:$hxClasses["App"],Editor:$hxClasses["page.Editor"],Project:$hxClasses["data.Project"],Timeline:$hxClasses["LevelTimeline"]};\n';
 fs.writeFileSync(renderer,original.replace(marker,expose+marker));
 status=run(require('electron'),['--no-sandbox','scripts/content-shift-ui-smoke.cjs'],appDir);
}catch(err){console.error(err.stack||err);status=1;}
finally{if(original!==null)fs.writeFileSync(renderer,original);}
process.exit(status);
