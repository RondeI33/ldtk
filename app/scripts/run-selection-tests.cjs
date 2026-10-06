'use strict';
const {spawnSync}=require('node:child_process');
const path=require('node:path');
const appDir=path.resolve(__dirname,'..'),repo=path.resolve(appDir,'..');
function run(command,args,cwd=repo){
  const r=spawnSync(command,args,{cwd,stdio:'inherit',env:process.env});
  if(r.error)throw r.error;
  return r.status==null?1:r.status;
}
let status=1;
try{
  if(run('haxe',['main.hxml'])!==0)throw Error('Main-process compilation failed');
  if(run('haxe',['renderer.hxml','-D','selection_drag_tests','--macro',"include('test')"])!==0)throw Error('Instrumented renderer compilation failed');
  const scripts=process.argv.includes('--input-only')
    ? ['scripts/selection-input-smoke.cjs']
    : ['scripts/selection-ui-smoke.cjs','scripts/selection-input-smoke.cjs'];
  status=0;
  for(const script of scripts){
    status=run(require('electron'),['--no-sandbox',script],appDir);
    if(status!==0)break;
  }
}catch(e){
  console.error(e.stack||e);
  status=1;
}finally{
  // Do not leave test-only hooks in a subsequent production build.
  if(run('haxe',['renderer.hxml'])!==0)status=1;
}
process.exit(status);
