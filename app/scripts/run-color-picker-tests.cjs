'use strict';
const fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const {spawnSync}=require('node:child_process');
const repo=path.resolve(__dirname,'../..');
const dir=fs.mkdtempSync(path.join(os.tmpdir(),'smartive-color-picker-'));
const script=path.join(dir,'color-picker.js');
let status=1;
try {
 const compile=spawnSync('haxe',['-cp','src/electron.common','-cp','tests/color-picker','-main','ColorPickerMathTest','-js',script],{cwd:repo,env:process.env,stdio:'inherit'});
 if(compile.error)throw compile.error;
 if(compile.status!==0)throw Error('Color picker contract compilation failed');
 const test=spawnSync(process.execPath,[script],{cwd:repo,env:process.env,stdio:'inherit'});
 if(test.error)throw test.error;
 status=test.status==null?1:test.status;
} catch(error) {console.error(error.stack||error);} finally {fs.rmSync(dir,{recursive:true,force:true});}
process.exit(status);
