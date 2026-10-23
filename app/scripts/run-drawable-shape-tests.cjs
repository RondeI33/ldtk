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
try{
 if(run('haxe',['tests/drawable-shapes.hxml'])!==0)throw Error('Shape geometry regressions failed');
 if(run(process.execPath,['app/scripts/run-color-picker-tests.cjs'])!==0)throw Error('Color picker math regressions failed');
 if(run('haxe',['main.hxml'])!==0)throw Error('Main-process compilation failed');
 if(run('haxe',['renderer.hxml'])!==0)throw Error('Renderer compilation failed');
 original=fs.readFileSync(renderer,'utf8');
 const marker='\tBoot.main();';
 if(original.split(marker).length!==2)throw Error('Cannot locate unique renderer bootstrap');
 const expose='\tglobalThis.__ldtk = {classes:$hxClasses,enums:$hxEnums,App:$hxClasses["App"],Editor:$hxClasses["page.Editor"],Project:$hxClasses["data.Project"],Group:$hxClasses["GenericLevelElementGroup"],Timeline:$hxClasses["LevelTimeline"]};\n';
 fs.writeFileSync(renderer,original.replace(marker,expose+marker));
 status=run(require('electron'),['--no-sandbox','scripts/drawable-shapes-ui-smoke.cjs'],appDir);
}catch(error){console.error(error.stack||error);status=1;}
finally{if(original!==null)fs.writeFileSync(renderer,original);}
process.exit(status);
