'use strict';
const {app}=require('electron');
const fs=require('node:fs'),os=require('node:os'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
const tmp=fs.mkdtempSync(path.join(os.tmpdir(),'smartive-selection-input-'));
const output=path.join(root,'test-results/selection');
fs.mkdirSync(output,{recursive:true});
process.chdir(root);
app.setPath('userData',tmp);
if(app.setAppPath)app.setAppPath(root);else app.getAppPath=()=>root;
process.env.LDTK_SMARTIVE_CONTROL_DIR=path.join(tmp,'control');
app.commandLine.appendSwitch('no-sandbox');
app.commandLine.appendSwitch('use-gl','angle');
app.commandLine.appendSwitch('use-angle','swiftshader');
let running=false,variants=0;
const passed=[];
const timer=setTimeout(()=>{console.error('FAIL: selection input regression timed out');app.exit(1);},240000);
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
function key(cell){return `${cell.layer}:${cell.cx}:${cell.cy}`;}
function canonical(cells){return [...cells].sort((a,b)=>key(a).localeCompare(key(b)));}
function expectedGrid(before,selected,dx,dy,isCopy){
  // Independent sparse-overlay oracle. Read all source values BEFORE deleting
  // anything; empty cells are absent and can never erase a destination cell.
  const world=new Map(before.map(c=>[key(c),structuredClone(c)]));
  const payload=selected.map(c=>({cell:c,value:world.get(key(c))})).filter(p=>p.value);
  if(!isCopy)for(const p of payload)world.delete(key(p.cell));
  for(const {cell,value} of payload){
    const next=structuredClone(value);
    next.cx+=dx*16/cell.grid;
    next.cy+=dy*16/cell.grid;
    assert(Number.isInteger(next.cx)&&Number.isInteger(next.cy),'Invalid oracle grid delta');
    world.set(key(next),next);
  }
  return canonical([...world.values()]);
}
app.on('browser-window-created',(_,win)=>{
  win.webContents.on('did-finish-load',()=>{
    if(running||!win.webContents.getURL().endsWith('/assets/app.html'))return;
    running=true;
    run(win).catch(async err=>{
      console.error(err.stack||err);
      fs.writeFileSync(path.join(output,'input-failure.json'),JSON.stringify({error:String(err.stack||err),passed,variants},null,2));
      try{fs.writeFileSync(path.join(output,'input-failure.png'),(await win.webContents.capturePage()).toPNG());}catch(_){}
      clearTimeout(timer);app.exit(1);
    });
  });
});
async function run(win){
  const ev=async code=>{
    const result=await win.webContents.executeJavaScript(`(()=>{try{return {ok:true,value:(${code})};}catch(e){return {ok:false,error:String(e&&e.stack||e)};}})()`,true);
    if(!result||!result.ok)throw Error(`Renderer failed: ${code}\n${result&&result.error}`);
    return result.value;
  };
  async function until(code,label){for(let i=0;i<200;i++){if(await ev(code))return;await delay(40);}throw Error(label);}
  const pass=label=>{passed.push(label);console.log('PASS: '+label);};
  await until('(window.SelectionDragTestHooks=window.SelectionDragTestHooks||(typeof exports!=="undefined"&&exports.SelectionDragTestHooks)) && (window.SelectionInputTestHooks=window.SelectionInputTestHooks||(typeof exports!=="undefined"&&exports.SelectionInputTestHooks)) && !!document.querySelector("#page")','Selection test hooks unavailable');
  await delay(700);
  win.setSize(1400,900);win.show();win.focus();win.webContents.setBackgroundThrottling(false);
  await ev(`SelectionDragTestHooks.setup(${JSON.stringify(path.join(tmp,'input.ldtk'))})`);
  await until('SelectionDragTestHooks.ready()','Fixture editor unavailable');
  await delay(180);
  await ev('SelectionInputTestHooks.configure()');

  // These are real SelectionTool handlers, not direct commitDragSnapshot calls.
  // Run them first so the pre-fix baseline fails with a precise regression.
  for(const selected of [true,false])for(const copy of [false,true]){
    await ev('SelectionDragTestHooks.prepare(5,1,false)');
    const result=await ev(`SelectionInputTestHooks.marquee(${selected},${copy})`);
    assert.equal(result.moving,false,'MARQUEE_STARTED_MOVE: a selection rectangle entered move mode');
    assert.equal(result.cut,false,'MARQUEE_CUT_SOURCE: rectangle selection cut the source');
    assert.deepEqual(result.during,result.before,'Marquee changed map data before mouse-up');
    assert.deepEqual(result.after,result.before,'Marquee changed map data on mouse-up');
  }
  pass('Four marquee/modifier variants never start a move or temporarily cut source data');
  await ev('SelectionDragTestHooks.prepare(5,1,false)');
  const empty=await ev('SelectionInputTestHooks.emptyDrag()');
  assert.equal(empty.moving,false,'Empty drag entered move mode');
  assert.deepEqual(empty.after,empty.before,'Empty drag mutated map data');
  pass('Dragging empty space is a no-op');

  for(const horizontal of [true,false])for(const offset of [16,17,23,31]){
    await ev('SelectionDragTestHooks.prepare(5,1,false)');
    const result=await ev(`SelectionInputTestHooks.offsetBoundary(${horizontal},${offset})`);
    assert.equal(result.selected,false,`OFFSET_SELECTED_CELL_ZERO: ${horizontal?'X':'Y'} offset ${offset}`);
  }
  pass('Eight offset-layer boundaries do not select a row or column outside the rectangle');

  for(const copy of [true,false])for(const [dx,dy] of [[5,1],[5,-2],[-2,3],[-2,-2]]){
    await ev(`SelectionDragTestHooks.prepare(${dx},${dy},false)`);
    const before=await ev('SelectionInputTestHooks.grids()');
    const cells=await ev('SelectionInputTestHooks.selectedCells()');
    const result=await ev(`SelectionInputTestHooks.mouseDrag(${copy},33,33,${(2+dx)*16+15},${(2+dy)*16+15})`);
    assert.equal(result.moving,true,'Real input handlers did not start the move');
    assert.equal(result.preview.visible,true,'First movement event did not show the ghost');
    assert.equal(result.preview.x,32+dx*16,'Input ghost X drift');
    assert.equal(result.preview.y,32+dy*16,'Input ghost Y drift');
    assert.equal(result.running,false,'Selection tool remained running after release');
    assert.deepEqual(canonical(await ev('SelectionInputTestHooks.grids()')),expectedGrid(before,cells,dx,dy,copy),'Real input path differs from sparse-overlay oracle');
    variants++;
  }
  pass('Eight real mouse-handler move/copy cases match preview and preserve every unrelated cell');
  await ev('SelectionInputTestHooks.configure()');

  const offsets=[[1,1],[1,15],[8,8],[15,1],[15,15]];
  for(const copy of [true,false])for(const dx of [-2,-1,0,1,5])for(const dy of [-2,-1,0,1,3])for(const grab of offsets)for(const drop of offsets){
    await ev(`SelectionDragTestHooks.prepare(${dx},${dy},false)`);
    const before=await ev('SelectionInputTestHooks.grids()');
    const cells=await ev('SelectionInputTestHooks.selectedCells()');
    const result=await ev(`SelectionDragTestHooks.drag(${copy},${32+grab[0]},${32+grab[1]},${32+dx*16+drop[0]},${32+dy*16+drop[1]},false)`);
    assert.equal(result.ghost.x,32+dx*16,'All-direction ghost X drift');
    assert.equal(result.ghost.y,32+dy*16,'All-direction ghost Y drift');
    assert.deepEqual(canonical(await ev('SelectionInputTestHooks.grids()')),expectedGrid(before,cells,dx,dy,copy),`Whole-grid mismatch: copy=${copy} delta=${dx},${dy} grab=${grab} drop=${drop}`);
    variants++;
  }
  pass('1,250 whole-grid cases cover left/up/right/down, zero delta, overlap and sub-cell grab/release positions');

  const coarseOffsets=[[1,1],[1,31],[31,1],[31,31]];
  for(const copy of [true,false])for(const dx of [-2,0,2,4])for(const dy of [-2,0,2,4])for(const grab of coarseOffsets)for(const drop of coarseOffsets){
    await ev(`SelectionDragTestHooks.prepare(${dx},${dy},true)`);
    const before=await ev('SelectionInputTestHooks.grids()');
    const cells=await ev('SelectionInputTestHooks.selectedCells()');
    const result=await ev(`SelectionDragTestHooks.drag(${copy},${32+grab[0]},${32+grab[1]},${32+dx*16+drop[0]},${32+dy*16+drop[1]},false)`);
    assert.equal(result.ghost.x,32+dx*16,'Mixed-grid ghost X drift');
    assert.equal(result.ghost.y,32+dy*16,'Mixed-grid ghost Y drift');
    assert.deepEqual(canonical(await ev('SelectionInputTestHooks.grids()')),expectedGrid(before,cells,dx,dy,copy),'Mixed 16/32 grid sparse-overlay mismatch');
    variants++;
  }
  pass('512 mixed 16px/32px cases preserve relative alignment and transparent holes');

  await ev('SelectionDragTestHooks.prepare(5,4,false)');
  const initial=await ev('SelectionInputTestHooks.grids()');
  for(let i=0;i<50;i++){
    await ev('SelectionDragTestHooks.drag(false,33,33,127,111,false)');
    await ev('SelectionDragTestHooks.drag(false,113,97,47,47,false)');
    assert.deepEqual(await ev('SelectionInputTestHooks.grids()'),initial,`Accumulated drift after round trip ${i+1}`);
    variants+=2;
  }
  pass('100 consecutive moves return to the exact original grid state without accumulated drift');
  fs.writeFileSync(path.join(output,'input-results.json'),JSON.stringify({passed,variantChecks:variants,platform:process.platform,electron:process.versions.electron},null,2));
  console.log(`SUCCESS: ${variants} additional selection transfers and ${passed.length} grouped input regressions`);
  clearTimeout(timer);app.exit(0);
}
require('../assets/main.js');
