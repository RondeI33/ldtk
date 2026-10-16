'use strict';
const {spawnSync}=require('node:child_process');
const fs=require('node:fs'),path=require('node:path');
const appDir=path.resolve(__dirname,'..'),repo=path.resolve(appDir,'..');
const renderer=path.join(appDir,'assets/js/renderer.js');
function run(command,args,cwd=repo){
  const result=spawnSync(command,args,{cwd,stdio:'inherit',env:process.env});
  if(result.error)throw result.error;
  return result.status==null?1:result.status;
}
let status=1,original=null;
try{
  if(run('haxe',['main.hxml'])!==0)throw Error('Main-process compilation failed');
  if(run('haxe',['renderer.hxml'])!==0)throw Error('Renderer compilation failed');
  original=fs.readFileSync(renderer,'utf8');
  const marker='\tBoot.main();';
  if(original.split(marker).length!==2)throw Error('Cannot locate unique renderer bootstrap');
  // Expose the compiler registries in this temporary test build only. No
  // production method is replaced: assertions exercise freshly compiled Haxe.
  const expose='\tglobalThis.__ldtk = {classes:$hxClasses,enums:$hxEnums,App:$hxClasses["App"],Editor:$hxClasses["page.Editor"],Project:$hxClasses["data.Project"],Timeline:$hxClasses["LevelTimeline"],Group:$hxClasses["GenericLevelElementGroup"],EntityTool:$hxClasses["tool.lt.EntityTool"],SelectionTool:$hxClasses["tool.SelectionTool"],Tool:$hxClasses["Tool"]};\n';
  fs.writeFileSync(renderer,original.replace(marker,expose+marker));
  status=run(require('electron'),['--no-sandbox','scripts/entity-multi-ui-smoke.cjs'],appDir);
}catch(error){
  console.error(error.stack||error);
  status=1;
}finally{
  if(original!==null)fs.writeFileSync(renderer,original);
}
process.exit(status);
