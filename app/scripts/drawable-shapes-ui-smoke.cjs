'use strict';
const {app}=require('electron');
const fs=require('node:fs'),os=require('node:os'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),tmp=fs.mkdtempSync(path.join(os.tmpdir(),'smartive-drawable-shapes-'));
const output=path.join(root,'test-results/drawable-shapes');fs.mkdirSync(output,{recursive:true});
process.chdir(root);app.setPath('userData',tmp);if(app.setAppPath)app.setAppPath(root);else app.getAppPath=()=>root;
process.env.LDTK_SMARTIVE_CONTROL_DIR=path.join(tmp,'control');app.commandLine.appendSwitch('no-sandbox');
if(process.platform==='linux'){app.commandLine.appendSwitch('use-gl','angle');app.commandLine.appendSwitch('use-angle','swiftshader');}
const timer=setTimeout(()=>{console.error('FAIL: drawable-shape regressions timed out');app.exit(1);},process.platform==='darwin'?420000:300000);
const passed=[],delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));let running=false;
app.on('browser-window-created',(_,win)=>win.webContents.on('did-finish-load',()=>{
 if(!win.webContents.getURL().endsWith('/assets/app.html')||running)return;running=true;
 run(win).catch(async error=>{console.error(error.stack||error);try{fs.writeFileSync(path.join(output,'failure.png'),(await win.webContents.capturePage()).toPNG());}catch(_){}
  fs.writeFileSync(path.join(output,'results.json'),JSON.stringify({status:'failed',passed,error:String(error.stack||error)},null,2));clearTimeout(timer);app.exit(1);});
}));
async function run(win){
 const ev=async code=>{
  try{new Function('return ('+code+')');}catch(error){throw Error('Invalid regression expression: '+code+'\n'+error.stack);}
  const result=await win.webContents.executeJavaScript(`(()=>{try{return {ok:true,value:(${code})};}catch(e){return {ok:false,error:String(e&&e.stack||e)};}})()`,true);
  if(!result?.ok)throw Error('Renderer expression failed: '+code+'\n'+result?.error);return result.value;
 };
 const until=async(code,label=code)=>{for(let i=0;i<250;i++){if(await ev(code))return true;await delay(30);}throw Error('Timed out waiting for '+label);};
 const frame=()=>win.webContents.executeJavaScript('new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(()=>resolve(true))))',true);
 await until('!!(globalThis.__ldtk && __ldtk.App.ME && document.querySelector("#page"))','editor bootstrap');
 await delay(650);win.setSize(1400,900);win.show();win.focus();win.webContents.setBackgroundThrottling(false);
 await win.webContents.executeJavaScript(fs.readFileSync(path.join(__dirname,'drawable-shape-fixture.js'),'utf8'),true);
 const call=(name,...args)=>ev(`shapeFixture.${name}(${args.map(x=>JSON.stringify(x)).join(',')})`);
 const pass=async message=>{assert.equal(await ev('__ldtk.App.ME.curPageProcess.__class__.__name__'),'page.Editor','Editor crashed');assert.equal((await call('state')).sentinel,1,'Untouched map layer changed');passed.push(message);console.log('PASS: '+message);};
 await call('setup',path.join(tmp,'shapes.ldtk'));await frame();
 for(const name of await call('runCore'))await pass(name);
 for(const name of await call('runStyleCases',tmp))await pass(name);
 await call('setup',path.join(tmp,'external-shapes.ldtk'),{offsets:true});await frame();
 const exportDirectory=process.env.LDTK_DRAWABLE_EXPORT_DIR||path.join(output,'example');
 assert.equal(await call('exportExamples',exportDirectory),4);
 const project=JSON.parse(fs.readFileSync(path.join(exportDirectory,'drawable-shapes.ldtk'),'utf8'));
 assert.equal(project.externalLevels,true);assert(project.levels.every(l=>l.externalRelPath&&l.layerInstances===null));
 const fixtures=JSON.parse(fs.readFileSync(path.join(exportDirectory,'drawable-shapes-v1-export.json'),'utf8'));
 assert(fixtures.fixtures.every(f=>f.worldOrigin[0]!==0&&f.layerOffset[0]!==0&&f.layerOffset[1]!==0));
 await pass('External-level example and Unity export fixtures use native fields with nonzero world origins and layer offsets');
 await call('beginExternalLoad',path.join(exportDirectory,'drawable-shapes.ldtk'));
 await until('shapeFixture.externalResult !== null || shapeFixture.externalError !== null','native external-level project loader');
 assert.equal(await ev('shapeFixture.externalError'),null);
 const reopened=await ev('shapeFixture.externalResult');
 for(const fixture of fixtures.fixtures){
  const entity=reopened.find(e=>e.iid===fixture.entity.iid);assert(entity,'External loader lost an entity IID');
  assert.equal(entity.error,null);assert.deepEqual(entity.fields,Object.fromEntries(fixture.entity.fieldInstances.map(f=>[f.__identifier,f.__value])));
  assert.deepEqual(entity.shape,entity.fields.ShapeCells);assert.deepEqual(entity.offset,fixture.layerOffset);assert.deepEqual(entity.world,fixture.worldOrigin);
 }
 await pass('The native project loader reopens external levels with complete masks, behavior, colors, IIDs, world origins and layer offsets');
 await require('./drawable-shapes-native-tests.cjs')({win,ev,call,delay,pass,frame,until,tmp,output});
 await require('./drawable-shapes-extra-tests.cjs')({win,ev,call,delay,pass,frame,until,tmp,output});
 await require('./drawable-shapes-clipboard-tests.cjs')({win,ev,call,delay,pass,frame,until,tmp,output});
 fs.writeFileSync(path.join(output,'results.json'),JSON.stringify({status:'passed',passed,platform:process.platform,electron:process.versions.electron},null,2));
 fs.writeFileSync(path.join(output,'success.png'),(await win.webContents.capturePage()).toPNG());
 console.log('SUCCESS: '+passed.length+' drawable-shape scenarios passed');clearTimeout(timer);app.exit(0);
}
require('../assets/main.js');
