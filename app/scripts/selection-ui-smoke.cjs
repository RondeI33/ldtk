'use strict';
const {app}=require('electron');
const fs=require('fs'),os=require('os'),path=require('path'),assert=require('assert');
const root=path.resolve(__dirname,'..'),tmp=fs.mkdtempSync(path.join(os.tmpdir(),'smartive-selection-'));
const output=path.join(root,'test-results/selection');fs.mkdirSync(output,{recursive:true});
process.chdir(root);app.setPath('userData',tmp);if(app.setAppPath)app.setAppPath(root);else app.getAppPath=()=>root;
process.env.LDTK_SMARTIVE_CONTROL_DIR=path.join(tmp,'control');
app.commandLine.appendSwitch('no-sandbox');app.commandLine.appendSwitch('use-gl','angle');app.commandLine.appendSwitch('use-angle','swiftshader');
const timer=setTimeout(()=>{console.error('FAIL: selection UI regression timed out');app.exit(1);},90000);
let running=false,passed=[],checks=0;
const delay=ms=>new Promise(r=>setTimeout(r,ms));
app.on('browser-window-created',(_,win)=>{
  win.webContents.on('did-finish-load',()=>{
    if(!win.webContents.getURL().endsWith('/assets/app.html')||running)return;
    running=true;run(win).catch(async err=>{
      console.error(err.stack||err);
      try{fs.writeFileSync(path.join(output,'failure.png'),(await win.webContents.capturePage()).toPNG());}catch(_){}
      clearTimeout(timer);app.exit(1);
    });
  });
});
function expectTile(stack,id){
  assert(Array.isArray(stack));
  assert.strictEqual(stack.length,1);
  assert.strictEqual(stack[0].tileId,id);
}
function expectSource(state,present){
  if(present){
    expectTile(state.source.a22,10);expectTile(state.source.a42,20);expectTile(state.source.b23,30);assert.strictEqual(state.source.i24,2);
  }else{
    assert.deepStrictEqual(state.source.a22,[]);assert.deepStrictEqual(state.source.a42,[]);assert.deepStrictEqual(state.source.b23,[]);assert.strictEqual(state.source.i24,0);
  }
}
function expectDestination(state){
  expectTile(state.dest.a22,10);expectTile(state.dest.a42,20);expectTile(state.dest.b23,30);assert.strictEqual(state.dest.i24,2);
}
function expectSentinels(state){
  expectTile(state.sentinels.a,90);expectTile(state.sentinels.b,91);assert.strictEqual(state.sentinels.i,1);
}
function expectEntities(state,isCopy,dx,dy){
  const src={x:32,y:80,px:3,py:5};
  const dst={x:32+dx*16,y:80+dy*16,px:3+dx,py:5+dy};
  assert.strictEqual(state.entities.length,isCopy?2:1);
  const has=(v,e)=>v.some(x=>x.x===e.x&&x.y===e.y&&x.points.some(p=>p.cx===e.px&&p.cy===e.py));
  if(isCopy)assert(has(state.entities,src),'Source entity/point missing after copy');
  assert(has(state.entities,dst),'Destination entity/point is not on snapped delta');
}
async function run(win){
  win.webContents.on('console-message',(_event,level,message,line,sourceId)=>{
    console.log('[renderer console]',level,message,sourceId+':'+line);
  });
  const ev=async code=>{
    const wrapped=`(()=>{try{return {ok:true,value:(${code})};}catch(e){return {ok:false,error:String(e&&e.stack||e)};}})()`;
    let result;
    try{
      result=await win.webContents.executeJavaScript(wrapped,true);
    }catch(e){
      throw Error('executeJavaScript IPC failure for expression:\n'+code+'\n'+String(e&&e.stack||e));
    }
    if(!result || !result.ok)
      throw Error('Renderer expression failed:\n'+code+'\n'+String(result&&result.error||result));
    return result.value;
  };
  async function until(code,message){for(let i=0;i<200;i++){if(await ev(`!!(${code})`))return;await delay(40);}throw Error(message);}
  const pass=m=>{passed.push(m);console.log('PASS: '+m);};
  await until('(window.SelectionDragTestHooks=window.SelectionDragTestHooks || (typeof exports!=="undefined" && exports.SelectionDragTestHooks)) && document.querySelector("#page")','Selection test hooks unavailable');
  // Let the normal app boot finish before replacing Home with the isolated
  // regression Editor. Otherwise late startup can replace the fixture page.
  await delay(700);
  win.setSize(1400,900);win.show();win.focus();win.webContents.setBackgroundThrottling(false);
  await ev(`SelectionDragTestHooks.setup(${JSON.stringify(path.join(tmp,'selection.ldtk'))})`);
  await until('SelectionDragTestHooks.ready()','Editor did not finish loading the selection regression project');
  await delay(180);

  // Real history transaction: grab near the top-left edge and release near the
  // bottom-right edge of another cell. Raw pixel deltas would round to +1 tile.
  await ev('SelectionDragTestHooks.prepare(5,1,false)');
  const beforeHistory=await ev('SelectionDragTestHooks.state()');
  await ev('SelectionDragTestHooks.drag(true,33,33,127,63,true)');
  let state=await ev('SelectionDragTestHooks.state()');
  expectSource(state,true);expectDestination(state);expectSentinels(state);expectEntities(state,true,5,1);
  await ev('SelectionDragTestHooks.undo()');await delay(160);
  state=await ev('SelectionDragTestHooks.state()');
  assert.deepStrictEqual(state,beforeHistory,'Undo did not restore exact pre-copy state');
  await ev('SelectionDragTestHooks.redo()');await delay(160);
  state=await ev('SelectionDragTestHooks.state()');
  expectSource(state,true);expectDestination(state);expectSentinels(state);expectEntities(state,true,5,1);
  pass('Copy uses one history operation and Undo/Redo preserves empty-space sentinels');

  // Move cancellation must restore the temporarily cut source byte-for-byte.
  await ev('SelectionDragTestHooks.prepare(6,2,false)');
  const beforeCancel=await ev('SelectionDragTestHooks.state()');
  await ev('SelectionDragTestHooks.startAndCancel(false)');
  state=await ev('SelectionDragTestHooks.state()');
  assert.deepStrictEqual(state,beforeCancel,'Cancelling a move did not restore source selection');
  pass('Cancelled move restores the cut source without touching destination data');

  const deltasX=[5,6,7],deltasY=[0,1,2];
  const offsets=[[1,1],[1,15],[8,8],[15,1],[15,15]];
  for(const isCopy of [true,false]){
    for(const dx of deltasX)for(const dy of deltasY)for(const grab of offsets)for(const drop of offsets){
      await ev(`SelectionDragTestHooks.prepare(${dx},${dy},false)`);
      const ox=2*16+grab[0],oy=2*16+grab[1];
      const tx=(2+dx)*16+drop[0],ty=(2+dy)*16+drop[1];
      const result=await ev(`SelectionDragTestHooks.drag(${isCopy},${ox},${oy},${tx},${ty},false)`);
      state=await ev('SelectionDragTestHooks.state()');
      expectSource(state,isCopy);
      expectDestination(state);
      expectSentinels(state);
      expectEntities(state,isCopy,dx,dy);
      assert.strictEqual(result.ghost.x,32+dx*16,'Ghost X did not match snapped destination');
      assert.strictEqual(result.ghost.y,32+dy*16,'Ghost Y did not match snapped destination');
      checks++;
    }
  }
  pass(`${checks} copy/move variants keep preview and drop on identical snapped cells`);
  pass('Empty cells stay transparent on selected and unrelated grid layers in every matrix variant');

  const transferData=s=>({
    a22:s.a22,a32:s.a32,a42:s.a42,a62:s.a62,
    b22:s.b22,b32:s.b32,b42:s.b42,b62:s.b62,
  });

  // Ctrl+Alt+Up moves the exact selected tile stacks to the previous compatible
  // layer in the actual LDtk layer-list order. Empty rectangle cells stay transparent.
  await ev('SelectionDragTestHooks.prepareLayerTransfer(false,false,false)');
  const beforeLayerDown=await ev('SelectionDragTestHooks.layerTransferState()');
  assert.strictEqual(await ev('SelectionDragTestHooks.layerTransferShortcut(1)'),true,'Ctrl+Alt+Down was not handled');
  let transfer=await ev('SelectionDragTestHooks.layerTransferState()');
  assert.deepStrictEqual(transfer.a22,[]);
  assert.deepStrictEqual(transfer.a42,[]);
  assert.deepStrictEqual(transfer.b22,[{tileId:10,flips:0},{tileId:11,flips:1}]);
  assert.deepStrictEqual(transfer.b42,[{tileId:20,flips:2}]);
  expectTile(transfer.a62,66);
  expectTile(transfer.b32,88);
  assert.strictEqual(transfer.active,'Tiles_B');
  assert.deepStrictEqual(transfer.selectionLayers,['Tiles_B']);
  await ev('SelectionDragTestHooks.undo()');await delay(160);
  transfer=await ev('SelectionDragTestHooks.layerTransferState()');
  assert.deepStrictEqual(transferData(transfer),transferData(beforeLayerDown),'Undo did not restore cross-layer tile transfer');
  await ev('SelectionDragTestHooks.redo()');await delay(160);
  transfer=await ev('SelectionDragTestHooks.layerTransferState()');
  assert.deepStrictEqual(transfer.b22,[{tileId:10,flips:0},{tileId:11,flips:1}]);
  assert.deepStrictEqual(transfer.b42,[{tileId:20,flips:2}]);
  expectTile(transfer.b32,88);
  pass('Ctrl+Alt+Up transfers selected tile stacks atomically and Undo/Redo restores both layers');

  // Down uses the same path in reverse.
  await ev('SelectionDragTestHooks.prepareLayerTransfer(false,true,false)');
  assert.strictEqual(await ev('SelectionDragTestHooks.layerTransferShortcut(-1)'),true,'Ctrl+Alt+Up was not handled');
  transfer=await ev('SelectionDragTestHooks.layerTransferState()');
  assert.deepStrictEqual(transfer.a22,[{tileId:10,flips:0},{tileId:11,flips:1}]);
  assert.deepStrictEqual(transfer.a42,[{tileId:20,flips:2}]);
  expectTile(transfer.a32,88);
  assert.strictEqual(transfer.active,'Tiles_A');
  assert.deepStrictEqual(transfer.selectionLayers,['Tiles_A']);
  pass('Ctrl+Alt+Down transfers the selection to the next compatible same-tileset layer');

  // Occupied destinations must reject the entire transfer. No source cell may
  // be removed when even one target cell is blocked.
  await ev('SelectionDragTestHooks.prepareLayerTransfer(true,false,false)');
  const blockedBefore=await ev('SelectionDragTestHooks.layerTransferState()');
  assert.strictEqual(await ev('SelectionDragTestHooks.layerTransfer(-1)'),false,'Blocked destination unexpectedly accepted transfer');
  const blockedAfter=await ev('SelectionDragTestHooks.layerTransferState()');
  assert.deepStrictEqual(blockedAfter,blockedBefore,'Blocked transfer partially mutated source/destination');
  pass('Occupied target cells reject the whole transfer without data loss');

  // Mixed-layer/non-Tiles selections are unsupported by design and must be
  // harmless no-ops rather than partial moves or crashes.
  await ev('SelectionDragTestHooks.prepareLayerTransfer(false,false,true)');
  const mixedBefore=await ev('SelectionDragTestHooks.layerTransferState()');
  assert.strictEqual(await ev('SelectionDragTestHooks.layerTransfer(1)'),false,'Mixed-layer selection unexpectedly transferred');
  assert.deepStrictEqual(await ev('SelectionDragTestHooks.layerTransferState()'),mixedBefore,'Mixed-layer rejection changed data');
  await ev('SelectionDragTestHooks.prepareIntGridLayerTransfer()');
  assert.strictEqual(await ev('SelectionDragTestHooks.layerTransfer(1)'),false,'IntGrid selection unexpectedly transferred as Tiles');
  pass('Mixed-layer and non-Tiles selections reject safely');

  // BigTiles deliberately uses the same tileset with a different 32px grid.
  // Moving up from Tiles_B scans to it and must reject without distortion.
  await ev('SelectionDragTestHooks.prepareLayerTransfer(false,true,false)');
  const gridBefore=await ev('SelectionDragTestHooks.layerTransferState()');
  assert.strictEqual(await ev('SelectionDragTestHooks.layerTransfer(-1)'),false,'Different-grid same-tileset layer unexpectedly accepted transfer');
  assert.deepStrictEqual(await ev('SelectionDragTestHooks.layerTransferState()'),gridBefore,'Different-grid rejection changed data');
  pass('Same tileset with incompatible grid size is rejected safely');

  fs.writeFileSync(path.join(output,'results.json'),JSON.stringify({passed,variantChecks:checks,platform:process.platform,electron:process.versions.electron},null,2));
  console.log(`SUCCESS: ${checks} matrix variants + ${passed.length} grouped selection scenarios passed`);
  clearTimeout(timer);app.exit(0);
}
require('../assets/main.js');
