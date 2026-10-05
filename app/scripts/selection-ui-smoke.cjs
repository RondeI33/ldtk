'use strict';
const {app}=require('electron');
const fs=require('node:fs'),os=require('node:os'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),tmp=fs.mkdtempSync(path.join(os.tmpdir(),'smartive-selection-'));
const output=path.join(root,'test-results/selection');fs.mkdirSync(output,{recursive:true});
process.chdir(root);app.setPath('userData',tmp);if(app.setAppPath)app.setAppPath(root);else app.getAppPath=()=>root;
process.env.LDTK_SMARTIVE_CONTROL_DIR=path.join(tmp,'control');
app.commandLine.appendSwitch('no-sandbox');app.commandLine.appendSwitch('use-gl','angle');app.commandLine.appendSwitch('use-angle','swiftshader');
let running=false,logs=[];
const timer=setTimeout(()=>{console.error('FAIL: scene-selection regression timed out');app.exit(1);},180000);
const delay=ms=>new Promise(r=>setTimeout(r,ms));
app.on('browser-window-created',(_,win)=>{
  win.webContents.on('console-message',(_,level,message)=>logs.push({level,message}));
  win.webContents.on('did-finish-load',()=>{
    if(!win.webContents.getURL().endsWith('/assets/app.html')||running)return;
    running=true;run(win).catch(async err=>{
      console.error(err.stack||err);
      fs.writeFileSync(path.join(output,'failure.log'),String(err.stack||err)+'\n'+JSON.stringify(logs,null,2));
      try{fs.writeFileSync(path.join(output,'failure.png'),(await win.webContents.capturePage()).toPNG());}catch(_){}
      clearTimeout(timer);app.exit(1);
    });
  });
});
async function run(win) {
  const ev=async code=>{
    const result=await win.webContents.executeJavaScript(`(()=>{try{return {ok:true,value:eval(${JSON.stringify(code)})};}catch(e){return {ok:false,error:String(e.stack||e)};}})()`,true);
    if(!result.ok)throw Error(result.error+'\nExpression: '+code);
    return result.value;
  };
  async function until(code,message) {
    for(let i=0;i<180;i++){if(await ev('!!('+code+')'))return;await delay(40);}
    let state;try{state=await ev('SceneSelectionTests.uiState()');}catch(_){}
    throw Error(message+'; state='+JSON.stringify(state));
  }
  await until('(window.SceneSelectionTests=window.SceneSelectionTests || (typeof exports!=="undefined" && exports.SceneSelectionTests)) && document.querySelector("#page")','Test hooks were not exposed');
  win.setSize(1400,900);win.show();win.focus();win.webContents.setBackgroundThrottling(false);
  await delay(300);
  await ev('SceneSelectionTests.setup('+JSON.stringify(path.join(tmp,'selection.ldtk'))+')');
  await delay(500);win.webContents.focus();
  for(const group of ['matrix','edgeCases','pointCases']) {
    const result=await ev('SceneSelectionTests.'+group+'()');
    console.log('PASS: '+group+' -> '+result.cases+' cumulative cases, '+result.assertions+' assertions');
    await delay(180);
  }
  const result=await ev('SceneSelectionTests.allResults()');
  fs.writeFileSync(path.join(output,'data-cases.json'),JSON.stringify(result,null,2));
  // These runs use real Electron mouse events and the ordinary SelectionTool.
  // The release is not judged by a second implementation of the transfer math.
  const mouseResults=[];
  for(const copy of [false,true]) {
    await ev('SceneSelectionTests.prepareUi('+copy+')');
    await delay(400);require('electron').Menu.setApplicationMenu(null);win.webContents.focus();
    const baseline=await ev('SceneSelectionTests.uiState()');
    const from=await ev('SceneSelectionTests.uiPoint(142,142)');
    const to=await ev('SceneSelectionTests.uiPoint(257,257)');
    const mods=copy?['control','alt']:[];
    if(copy){win.webContents.sendInputEvent({type:'keyDown',keyCode:'Control'});win.webContents.sendInputEvent({type:'keyDown',keyCode:'Alt'});await delay(70);}
    win.webContents.sendInputEvent({type:'mouseMove',x:from.x,y:from.y,modifiers:mods});await delay(100);
    win.webContents.sendInputEvent({type:'mouseDown',x:from.x,y:from.y,button:'left',clickCount:1,modifiers:mods});
    await until('SceneSelectionTests.uiState().running','Ordinary selection drag did not start');
    win.webContents.sendInputEvent({type:'mouseMove',x:to.x,y:to.y,modifiers:mods});
    await until('SceneSelectionTests.uiState().moving && SceneSelectionTests.uiState().ghost','Selection ghost did not appear');
    const ghost=await ev('SceneSelectionTests.uiState()');
    assert.equal(ghost.dx,128,'Displayed X delta differs from expected snapped drag');
    assert.equal(ghost.dy,128,'Displayed Y delta differs from expected snapped drag');
    fs.writeFileSync(path.join(output,copy?'copy-preview.png':'move-preview.png'),(await win.webContents.capturePage()).toPNG());
    win.webContents.sendInputEvent({type:'mouseUp',x:to.x,y:to.y,button:'left',clickCount:1,modifiers:mods});
    if(copy){win.webContents.sendInputEvent({type:'keyUp',keyCode:'Alt'});win.webContents.sendInputEvent({type:'keyUp',keyCode:'Control'});}
    await until('!SceneSelectionTests.uiState().running','Selection drop did not finish');
    const after=await ev('SceneSelectionTests.uiState()');
    assert.equal(after.gridA,1);assert.equal(after.gridB,2);
    assert.equal(after.hole,9,'Empty rectangle space erased an occupied cell');
    assert.equal(after.under,8,'An unselected underlying layer was modified');
    assert.equal(after.entities.length,copy?4:2);
    const moved=after.entities.filter(e=>copy?!baseline.entities.some(old=>old.id===e.id):true);
    assert.deepEqual(moved.map(e=>[e.x,e.y]),[[259,261],[291,261]],'Mouse drop does not match ghost / shifts entities by a tile');
    if(copy)assert.deepEqual(after.entities.filter(e=>baseline.entities.some(old=>old.id===e.id)),baseline.entities,'Copy changed original entities');
    await ev('SceneSelectionTests.undo()');await delay(100);
    const undone=await ev('SceneSelectionTests.uiState()');
    assert.deepEqual(undone.entities,baseline.entities,'One Undo did not restore source entity positions and identity');
    assert.equal(undone.gridA,0);assert.equal(undone.gridB,0);assert.equal(undone.hole,9);assert.equal(undone.under,8);
    await ev('SceneSelectionTests.redo()');await delay(100);
    const redone=await ev('SceneSelectionTests.uiState()');
    assert.deepEqual(redone.entities,after.entities,'Redo did not restore copied/moved entities');
    assert.equal(redone.gridA,1);assert.equal(redone.gridB,2);assert.equal(redone.hole,9);assert.equal(redone.under,8);
    mouseResults.push({copy,passed:true});
    console.log('PASS: actual '+(copy?'Ctrl/Alt copy':'ordinary move')+' -> exact ghost/drop agreement, transparent holes, Undo/Redo');
  }
  fs.writeFileSync(path.join(output,'results.json'),JSON.stringify({data:result,mouse:mouseResults,platform:process.platform,electron:process.versions.electron},null,2));
  console.log('SUCCESS: '+result.cases+' scene-selection cases, '+result.assertions+' assertions, '+mouseResults.length+' real mouse workflows');
  clearTimeout(timer);app.exit(0);
}
require('../assets/main.js');
