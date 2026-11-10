'use strict';
const {app,nativeImage}=require('electron');
const fs=require('fs'),os=require('os'),path=require('path'),assert=require('assert');
const root=path.resolve(__dirname,'..'),tmp=fs.mkdtempSync(path.join(os.tmpdir(),'smartive-selection-'));
const output=path.join(root,'test-results/selection');fs.mkdirSync(output,{recursive:true});
process.chdir(root);app.setPath('userData',tmp);if(app.setAppPath)app.setAppPath(root);else app.getAppPath=()=>root;
process.env.LDTK_SMARTIVE_CONTROL_DIR=path.join(tmp,'control');
app.commandLine.appendSwitch('no-sandbox');app.commandLine.appendSwitch('use-gl','angle');app.commandLine.appendSwitch('use-angle','swiftshader');
let running=false,passed=[],checks=0,flipChecks=0,rotationChecks=0,currentCase='boot';
// Flip and rotation cases use real editor-frame/history waits, not sleeps.
// Keep individual frame deadlines unchanged while allowing the full suite to
// complete, including native pixels, keyboard guards and disk round-trips.
const timer=setTimeout(()=>{
  const progress={passed,variantChecks:checks,flipChecks,rotationChecks,currentCase,platform:process.platform,electron:process.versions.electron};
  fs.writeFileSync(path.join(output,'timeout.json'),JSON.stringify(progress,null,2));
  console.error(`FAIL: selection UI regression timed out at ${currentCase} (${checks} matrix variants, ${flipChecks} flip cases, ${rotationChecks} rotation cases completed)`);
  app.exit(1);
},360000);
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
function expectedFlipState(before,kind,axes,isCopy=false,dx=0,dy=0){
  const result=JSON.parse(JSON.stringify(before));
  const flipX=[...axes].filter(a=>a==='x').length%2===1;
  const flipY=[...axes].filter(a=>a==='y').length%2===1;
  const flipBits=(flipX?1:0)|(flipY?2:0);
  const selected={
    tilesA:kind==='tiles'||kind==='mixed'?[[2,2],[4,2],[2,4]]:[],
    tilesB:kind==='mixed'?[[4,4],[2,3]]:[],
    ints:kind==='intgrid'||kind==='mixed'?[[2,2],[4,2],[2,4]]:[],
  };
  for(const [layer,positions] of Object.entries(selected)){
    const isSelected=c=>positions.some(([x,y])=>c.cx===x&&c.cy===y);
    const original=before[layer].filter(isSelected);
    result[layer]=before[layer].filter(c=>isCopy||!isSelected(c));
    for(const cell of original){
      const copy=JSON.parse(JSON.stringify(cell));
      copy.cx=(flipX?6-cell.cx:cell.cx)+dx;
      copy.cy=(flipY?6-cell.cy:cell.cy)+dy;
      if(copy.tiles)for(const tile of copy.tiles)tile.flips^=flipBits;
      result[layer].push(copy);
    }
    result[layer].sort((a,b)=>a.cy-b.cy||a.cx-b.cx);
  }
  result.autoTiles=result.ints.map(c=>({cx:c.cx,cy:c.cy,tileId:69+c.value,flips:0}));
  return result;
}

// An independent cell/pixel oracle. These eight orientations describe transpose
// followed by screen-space X/Y reflection; it never calls the production helper.
const cwOrientation=[5,7,4,6,1,3,0,2],ccwOrientation=[6,4,7,5,2,0,3,1];
const clone=value=>JSON.parse(JSON.stringify(value));
function transformPoint(x,y,width,height,command){
  switch(command){
    case 'r':return {x:height-1-y,y:x,width:height,height:width};
    case 'l':return {x:y,y:width-1-x,width:height,height:width};
    case 'x':return {x:width-1-x,y,width,height};
    case 'y':return {x,y:height-1-y,width,height};
    default:throw Error('Unknown test transform '+command);
  }
}
function withoutEntityIds(value){
  const result=clone(value);
  for(const list of [result.entities,result.shapes])for(const item of list)delete item.iid;
  return result;
}
function expectedRotationState(before,kind,commands,isCopy=false,dx=0,dy=0){
  const result=clone(before);
  const selected={
    tilesA:kind==='tiles'||kind==='mixed'?[[2,2],[4,2],[2,3]]:[],
    tilesB:kind==='mixed'?[[4,3],[4,2]]:[],
    ints:kind==='intgrid'||kind==='mixed'?[[2,2],[4,2],[2,3]]:[],
  };
  for(const [layer,positions] of Object.entries(selected)){
    const isSelected=c=>positions.some(([x,y])=>c.cx===x&&c.cy===y);
    const original=before.grid[layer].filter(isSelected);
    result.grid[layer]=before.grid[layer].filter(c=>isCopy||!isSelected(c));
    for(const cell of original){
      const copy=clone(cell);
      let p={x:cell.cx-2,y:cell.cy-2,width:3,height:2};
      for(const command of commands){
        p=transformPoint(p.x,p.y,p.width,p.height,command);
        if(copy.tiles)for(const tile of copy.tiles){
          tile.flips=command==='r'?cwOrientation[tile.flips]
            :command==='l'?ccwOrientation[tile.flips]:tile.flips^(command==='x'?1:2);
        }
      }
      copy.cx=2+p.x+dx;copy.cy=2+p.y+dy;
      result.grid[layer].push(copy);
    }
    result.grid[layer].sort((a,b)=>a.cy-b.cy||a.cx-b.cx);
  }
  result.grid.autoTiles=result.grid.ints.map(c=>({cx:c.cx,cy:c.cy,tileId:69+c.value,flips:0}));
  if(dx||dy){
    result.entities=isCopy?clone(before.entities):[];
    for(const item of before.entities){
      const copy=clone(item);copy.x+=dx*16;copy.y+=dy*16;
      // Only the first point is selected; the second must remain authored.
      copy.points[0].cx+=dx;copy.points[0].cy+=dy;
      result.entities.push(copy);
    }
    result.entities.sort((a,b)=>a.x-b.x||a.y-b.y);
  }
  if(kind==='shapes'){
    result.shapes=isCopy?clone(before.shapes):[];
    for(const original of before.shapes){
      const shape=clone(original);
      let cells=[];
      for(let i=0;i<shape.cells.length;i+=2)cells.push({x:shape.cells[i],y:shape.cells[i+1]});
      let width=shape.width/16,height=shape.height/16;
      for(const command of commands){
        cells=cells.map(c=>transformPoint(c.x,c.y,width,height,command));
        if(command==='r'||command==='l'){
          [width,height]=[height,width];
          const facing=['Up','Right','Down','Left'];
          shape.facing=facing[(facing.indexOf(shape.facing)+(command==='r'?1:3))%4];
        }else if(command==='x')shape.facing=({Left:'Right',Right:'Left'})[shape.facing]||shape.facing;
        else shape.facing=({Up:'Down',Down:'Up'})[shape.facing]||shape.facing;
      }
      cells.sort((a,b)=>a.y-b.y||a.x-b.x);
      shape.cells=cells.flatMap(c=>[c.x,c.y]);shape.width=width*16;shape.height=height*16;
      shape.x+=dx*16;shape.y+=dy*16;shape.left+=dx*16;shape.top+=dy*16;
      result.shapes.push(shape);
    }
    result.shapes.sort((a,b)=>a.x-b.x||a.y-b.y);
  }
  return withoutEntityIds(result);
}

function writeRotationAtlas(file){
  // Every tile has four asymmetric opaque quadrants. Native screenshots can
  // prove the tile artwork rotated, independently of positions and flip bits.
  const width=160,height=160,pixels=Buffer.alloc(width*height*4);
  const colors=[[235,40,50],[25,210,70],[35,85,235],[245,210,35]];
  for(let y=0;y<height;y++)for(let x=0;x<width;x++){
    const [r,g,b]=colors[(y%16>=8?2:0)+(x%16>=8?1:0)],i=(y*width+x)*4;
    pixels[i]=b;pixels[i+1]=g;pixels[i+2]=r;pixels[i+3]=255;
  }
  fs.writeFileSync(file,nativeImage.createFromBitmap(pixels,{width,height}).toPNG());
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
  // Timeline undo/redo emits LayerInstancesRestoredFromHistory at the end of an
  // editor frame, where SelectionTool clears stale selections. A wall-clock
  // sleep can finish before that event under CI load and incorrectly clear a
  // selection created for the NEXT scenario. Await the frame boundary instead.
  const editorFrame=()=>win.webContents.executeJavaScript(`new Promise((resolve,reject)=>{
    const timer=setTimeout(()=>reject(Error('Editor frame did not complete')),8000);
    // This older instrumented selection bundle exposes SelectionDragTestHooks,
    // not the __ldtk class registry used by newer point tests. Two renderer
    // animation frames advance Heaps' deferred end-of-frame event queue.
    requestAnimationFrame(()=>requestAnimationFrame(()=>{
      clearTimeout(timer);resolve(true);
    }));
  })`,true);
  const settleHistory=async()=>{await editorFrame();await editorFrame();};
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
  currentCase='copy history and cancellation';
  await ev('SelectionDragTestHooks.prepare(5,1,false)');
  const beforeHistory=await ev('SelectionDragTestHooks.state()');
  await ev('SelectionDragTestHooks.drag(true,33,33,127,63,true)');
  let state=await ev('SelectionDragTestHooks.state()');
  expectSource(state,true);expectDestination(state);expectSentinels(state);expectEntities(state,true,5,1);
  await ev('SelectionDragTestHooks.undo()');await settleHistory();
  state=await ev('SelectionDragTestHooks.state()');
  assert.deepStrictEqual(state,beforeHistory,'Undo did not restore exact pre-copy state');
  await ev('SelectionDragTestHooks.redo()');await settleHistory();
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
  currentCase='450 copy/move matrix';
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
  currentCase='layer transfer and editor-frame stress';

  // Ctrl+Alt+Up moves the exact selected tile stacks to the previous compatible
  // layer in the actual LDtk layer-list order. Empty rectangle cells stay transparent.
  await ev('SelectionDragTestHooks.prepareLayerTransfer(false,false,false)');
  const beforeLayerDown=await ev('SelectionDragTestHooks.layerTransferState()');
  assert.strictEqual(await ev('SelectionDragTestHooks.layerTransferShortcut(-1)'),true,'Ctrl+Alt+Up was not handled');
  let transfer=await ev('SelectionDragTestHooks.layerTransferState()');
  assert.deepStrictEqual(transfer.a22,[]);
  assert.deepStrictEqual(transfer.a42,[]);
  assert.deepStrictEqual(transfer.b22,[{tileId:10,flips:0},{tileId:11,flips:1}]);
  assert.deepStrictEqual(transfer.b42,[{tileId:20,flips:2}]);
  expectTile(transfer.a62,66);
  expectTile(transfer.b32,88);
  assert.strictEqual(transfer.active,'Tiles_B');
  assert.deepStrictEqual(transfer.selectionLayers,['Tiles_B']);
  await ev('SelectionDragTestHooks.undo()');await settleHistory();
  transfer=await ev('SelectionDragTestHooks.layerTransferState()');
  assert.deepStrictEqual(transferData(transfer),transferData(beforeLayerDown),'Undo did not restore cross-layer tile transfer');
  await ev('SelectionDragTestHooks.redo()');await settleHistory();
  transfer=await ev('SelectionDragTestHooks.layerTransferState()');
  assert.deepStrictEqual(transfer.b22,[{tileId:10,flips:0},{tileId:11,flips:1}]);
  assert.deepStrictEqual(transfer.b42,[{tileId:20,flips:2}]);
  expectTile(transfer.b32,88);
  pass('Ctrl+Alt+Up transfers selected tile stacks atomically and Undo/Redo restores both layers');

  // Down uses the same path in reverse.
  await ev('SelectionDragTestHooks.prepareLayerTransfer(false,true,false)');
  await editorFrame();
  assert.deepStrictEqual((await ev('SelectionDragTestHooks.layerTransferState()')).selectionLayers,['Tiles_B'],
    'A deferred history event cleared the new source selection before the Down transfer');
  assert.strictEqual(await ev('SelectionDragTestHooks.layerTransferShortcut(1)'),true,'Ctrl+Alt+Down was not handled');
  transfer=await ev('SelectionDragTestHooks.layerTransferState()');
  assert.deepStrictEqual(transfer.a22,[{tileId:10,flips:0},{tileId:11,flips:1}]);
  assert.deepStrictEqual(transfer.a42,[{tileId:20,flips:2}]);
  expectTile(transfer.a32,88);
  assert.strictEqual(transfer.active,'Tiles_A');
  assert.deepStrictEqual(transfer.selectionLayers,['Tiles_A']);
  await editorFrame();
  assert.deepStrictEqual((await ev('SelectionDragTestHooks.layerTransferState()')).selectionLayers,['Tiles_A'],
    'The completed Down transfer lost its selection on the next editor frame');
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
  assert.strictEqual(await ev('SelectionDragTestHooks.layerTransfer(-1)'),false,'Mixed-layer selection unexpectedly transferred');
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

  // Exercise both directions repeatedly across real editor frames. In addition
  // to asserting tile ownership, ensure the selection survives the frame AFTER
  // each transfer, rather than accepting only a synchronous transient state.
  for(let i=0;i<16;i++){
    await editorFrame();
    const fromB=i%2===1, source=fromB?'Tiles_B':'Tiles_A', target=fromB?'Tiles_A':'Tiles_B';
    await ev(`SelectionDragTestHooks.prepareLayerTransfer(false,${fromB},false)`);
    await editorFrame();
    let current=await ev('SelectionDragTestHooks.layerTransferState()');
    assert.deepStrictEqual(current.selectionLayers,[source],
      `Iteration ${i}: selection was cleared while preparing source ${source}`);
    assert.strictEqual(await ev(`SelectionDragTestHooks.layerTransfer(${fromB?1:-1})`),true,
      `Iteration ${i}: compatible transfer was rejected`);
    await editorFrame();
    current=await ev('SelectionDragTestHooks.layerTransferState()');
    assert.strictEqual(current.active,target,`Iteration ${i}: wrong active layer`);
    assert.deepStrictEqual(current.selectionLayers,[target],
      `Iteration ${i}: selection did not survive a complete editor frame`);
    assert.deepStrictEqual(fromB?current.a22:current.b22,
      [{tileId:10,flips:0},{tileId:11,flips:1}],`Iteration ${i}: tile stack changed`);
  }
  pass('16 alternating layer transfers preserve selection and tile stacks after editor-frame processing');

  // Use a real atlas and one-cell auto-layer rules for the flip regressions.
  // The old transfer fixture intentionally has no atlas and cannot verify that
  // mirrored IntGrid cells regenerate the visuals used in the user's sample.
  currentCase='flip fixture setup';
  fs.copyFileSync(path.join(root,'extraFiles/samples/atlas/Cavernas_by_Adam_Saltsman.png'),path.join(tmp,'flip-atlas.png'));
  await ev(`SelectionDragTestHooks.setup(${JSON.stringify(path.join(tmp,'flip.ldtk'))},"flip-atlas.png")`);
  await until('SelectionDragTestHooks.ready()','Flip regression project did not open');
  await settleHistory();
  for(const kind of ['tiles','intgrid','mixed']){
    for(const axes of ['x','y','xy','xx','yy']){
      const label=`${kind} idle ${axes.toUpperCase()}`;
      currentCase=label;
      await ev(`SelectionDragTestHooks.prepareFlip(${JSON.stringify(kind)})`);
      const before=await ev('SelectionDragTestHooks.flipState()');
      assert.deepStrictEqual(before.autoTiles,before.ints.map(c=>({cx:c.cx,cy:c.cy,tileId:69+c.value,flips:0})),`${label}: fixture auto-layer rules did not run`);
      await ev(`SelectionDragTestHooks.flipCommands(${JSON.stringify(axes)})`);
      const after=await ev('SelectionDragTestHooks.flipState()');
      assert.deepStrictEqual(after,expectedFlipState(before,kind,axes),`${label}: wrong reflected cells, tile bits, stack order, sentinels, or auto-layer visuals`);
      for(const axis of axes){await ev('SelectionDragTestHooks.undo()');await settleHistory();}
      assert.deepStrictEqual(await ev('SelectionDragTestHooks.flipState()'),before,`${label}: Undo did not restore the complete grid state`);
      for(const axis of axes){await ev('SelectionDragTestHooks.redo()');await settleHistory();}
      assert.deepStrictEqual(await ev('SelectionDragTestHooks.flipState()'),after,`${label}: Redo did not restore the complete flipped state`);
      flipChecks++;
    }
  }
  pass('15 idle X/Y combinations preserve tile stacks, IntGrid auto-layer visuals, and exact Undo/Redo');

  for(const kind of ['tiles','intgrid','mixed'])for(const isCopy of [false,true]){
    for(const axes of ['x','y','xy','xx','yy','xyxy']){
      const label=`${kind} ${isCopy?'copy':'move'} ${axes.toUpperCase()}`;
      currentCase=label;
      await ev(`SelectionDragTestHooks.prepareFlip(${JSON.stringify(kind)})`);
      const before=await ev('SelectionDragTestHooks.flipState()');
      assert.deepStrictEqual(await ev(`SelectionDragTestHooks.startFlipDrag(${isCopy})`),{running:true,moving:true,isCopy},`${label}: real SelectionTool gesture did not start`);
      const whileDragging=await ev('SelectionDragTestHooks.flipState()');
      await ev(`SelectionDragTestHooks.flipCommands(${JSON.stringify(axes)})`);
      assert.deepStrictEqual(await ev('SelectionDragTestHooks.flipState()'),whileDragging,`${label}: preview flip mutated level data before mouse-up`);
      assert.deepStrictEqual(await ev('SelectionDragTestHooks.finishFlipDrag()'),{running:false,moving:false,flipX:false,flipY:false},`${label}: mouse-up left the tool or flip toggles active`);
      const after=await ev('SelectionDragTestHooks.flipState()');
      assert.deepStrictEqual(after,expectedFlipState(before,kind,axes,isCopy,8,5),`${label}: drop produced wrong reflected cells, tile bits, stack order, sentinels, or auto-layer visuals`);
      await ev('SelectionDragTestHooks.finishFlipDrag()');
      assert.deepStrictEqual(await ev('SelectionDragTestHooks.flipState()'),after,`${label}: repeated mouse-up replayed the drop`);
      await ev('SelectionDragTestHooks.undo()');await settleHistory();
      assert.deepStrictEqual(await ev('SelectionDragTestHooks.flipState()'),before,`${label}: one Undo did not restore both source and destination`);
      await ev('SelectionDragTestHooks.redo()');await settleHistory();
      assert.deepStrictEqual(await ev('SelectionDragTestHooks.flipState()'),after,`${label}: one Redo did not restore the reflected drop`);
      flipChecks++;
    }
  }
  pass('36 real SelectionTool X/Y drag/drop cases cover move/copy, both axes, cancelled flips, repeated mouse-up, and atomic Undo/Redo');

  currentCase='rotation fixture setup';
  const rotationFile=path.join(tmp,'rotation.ldtk');
  writeRotationAtlas(path.join(tmp,'rotation-atlas.png'));
  await ev(`SelectionDragTestHooks.setup(${JSON.stringify(rotationFile)},"rotation-atlas.png")`);
  await until('SelectionDragTestHooks.ready()','Rotation regression project did not open');
  await settleHistory();

  currentCase='unsaved rotation across configuration reload';
  await ev('SelectionDragTestHooks.prepareRotation("tiles")');
  await ev('SelectionDragTestHooks.saveRotationProject(false)');
  await until('SelectionDragTestHooks.rotationIoState().done','Initial rotation fixture save did not complete');
  assert.strictEqual((await ev('SelectionDragTestHooks.rotationIoState()')).error,null);
  await ev('SelectionDragTestHooks.rotationCommands("r")');
  const unsavedWithoutMetadata=await ev('SelectionDragTestHooks.rotationState()');
  await ev('SelectionDragTestHooks.reloadRotationConfig()');
  assert.deepStrictEqual(await ev('SelectionDragTestHooks.rotationState()'),unsavedWithoutMetadata,'Reloading a configuration without saved tile transforms discarded unsaved rotation');

  const rotateCases=[];
  for(const kind of ['tiles','intgrid','mixed','shapes'])for(const commands of ['r','l','rrrr','rl'])rotateCases.push({kind,commands,offset:false});
  for(const commands of ['r','l','rx','xr','ry','yr'])rotateCases.push({kind:'mixed',commands,offset:true});
  for(const {kind,commands,offset} of rotateCases){
    const label=`${kind} idle ${commands} offset=${offset}`;currentCase=label;
    await ev(`SelectionDragTestHooks.prepareRotation(${JSON.stringify(kind)},${offset})`);
    const before=await ev('SelectionDragTestHooks.rotationState()');
    const membership=await ev('SelectionDragTestHooks.selectionCounts()');
    await ev(`SelectionDragTestHooks.rotationCommands(${JSON.stringify(commands)})`);
    const after=await ev('SelectionDragTestHooks.rotationState()');
    assert.deepStrictEqual(withoutEntityIds(after),expectedRotationState(before,kind,commands),`${label}: wrong rotated cells, artwork, shape facing or surrounding data`);
    assert.deepStrictEqual(await ev('SelectionDragTestHooks.selectionCounts()'),membership,`${label}: selection membership was lost`);
    if(commands==='rrrr'||commands==='rl')assert.deepStrictEqual(after,before,`${label}: inverse turns did not restore exact state`);
    for(const command of commands){await ev('SelectionDragTestHooks.undo()');await settleHistory();}
    assert.deepStrictEqual(await ev('SelectionDragTestHooks.rotationState()'),before,`${label}: Undo lost original data or orientation`);
    for(const command of commands){await ev('SelectionDragTestHooks.redo()');await settleHistory();}
    assert.deepStrictEqual(await ev('SelectionDragTestHooks.rotationState()'),after,`${label}: Redo lost rotated data or orientation`);
    rotationChecks++;
  }
  pass('22 non-square quarter-turn cases cover both directions, inverse/four-turn restoration, X/Y order, layer offsets, shapes and exact Undo/Redo');

  for(const kind of ['tiles','intgrid','mixed','shapes'])for(const isCopy of [false,true])for(const commands of ['r','l','rx','xr','rrrr']){
    const label=`${kind} ${isCopy?'copy':'move'} ${commands}`;currentCase=label;
    await ev(`SelectionDragTestHooks.prepareRotation(${JSON.stringify(kind)},true)`);
    const before=await ev('SelectionDragTestHooks.rotationState()');
    const membership=await ev('SelectionDragTestHooks.selectionCounts()');
    assert.deepStrictEqual(await ev(`SelectionDragTestHooks.startRotationDrag(${isCopy})`),{running:true,moving:true,isCopy},`${label}: real gesture did not start`);
    const during=await ev('SelectionDragTestHooks.rotationState()');
    await ev(`SelectionDragTestHooks.rotationCommands(${JSON.stringify(commands)})`);
    assert.deepStrictEqual(await ev('SelectionDragTestHooks.rotationState()'),during,`${label}: ghost transform changed level data before mouse-up`);
    assert.deepStrictEqual(await ev('SelectionDragTestHooks.finishRotationDrag()'),{running:false,moving:false},`${label}: gesture remained active`);
    const after=await ev('SelectionDragTestHooks.rotationState()');
    assert.deepStrictEqual(withoutEntityIds(after),expectedRotationState(before,kind,commands,isCopy,8,5),`${label}: committed geometry differs from expected rotated drop`);
    assert.deepStrictEqual(await ev('SelectionDragTestHooks.selectionCounts()'),membership,`${label}: drop lost selected members`);
    await ev('SelectionDragTestHooks.finishRotationDrag()');
    assert.deepStrictEqual(await ev('SelectionDragTestHooks.rotationState()'),after,`${label}: repeated mouse-up replayed rotation`);
    await ev('SelectionDragTestHooks.undo()');await settleHistory();
    assert.deepStrictEqual(await ev('SelectionDragTestHooks.rotationState()'),before,`${label}: one Undo did not restore the whole gesture`);
    await ev('SelectionDragTestHooks.redo()');await settleHistory();
    assert.deepStrictEqual(await ev('SelectionDragTestHooks.rotationState()'),after,`${label}: one Redo did not restore the whole gesture`);
    rotationChecks++;
  }
  pass('40 native move/copy quarter-turn gestures preserve sparse holes, stacks, normal entities/points, shape geometry and one-step Undo/Redo');

  currentCase='rotation cancellation and boundaries';
  for(const isCopy of [false,true]){
    await ev('SelectionDragTestHooks.prepareRotation("mixed",true)');
    const before=await ev('SelectionDragTestHooks.rotationState()');
    await ev(`SelectionDragTestHooks.startRotationDrag(${isCopy})`);
    await ev('SelectionDragTestHooks.rotationCommands("rx")');
    await ev('SelectionDragTestHooks.cancelRotationDrag()');await editorFrame();
    assert.deepStrictEqual(await ev('SelectionDragTestHooks.rotationState()'),before,'Cancelling a rotated gesture changed source or destination');
  }
  await ev('SelectionDragTestHooks.prepareRotationBoundary()');
  const boundaryBefore=await ev('SelectionDragTestHooks.rotationState()');
  const boundaryMembers=await ev('SelectionDragTestHooks.selectionCounts()');
  await ev('SelectionDragTestHooks.rotationCommands("r")');
  assert.deepStrictEqual(await ev('SelectionDragTestHooks.rotationState()'),boundaryBefore,'Out-of-bounds rotation erased or partially moved cells');
  assert.deepStrictEqual(await ev('SelectionDragTestHooks.selectionCounts()'),boundaryMembers,'Rejected rotation changed the selection');
  assert.strictEqual(await ev('SelectionDragTestHooks.tryUndo()'),false,'Rejected rotation created a history transaction');
  await ev('SelectionDragTestHooks.prepareRotationMisaligned()');
  const misalignedBefore=await ev('SelectionDragTestHooks.rotationState()');
  await ev('SelectionDragTestHooks.rotationCommands("r")');
  assert.deepStrictEqual(await ev('SelectionDragTestHooks.rotationState()'),misalignedBefore,'Incompatible layer offset rounded cells or partially transformed data');
  assert.strictEqual(await ev('SelectionDragTestHooks.tryUndo()'),false,'Misaligned rotation created a history transaction');
  pass('Cancelled move/copy restores the exact source; out-of-bounds and misaligned-layer rotation reject atomically without history entries');

  currentCase='select-all inclusive bounds';
  await ev('SelectionDragTestHooks.prepareRotationSelectAll()');
  const selectAllBefore=await ev('SelectionDragTestHooks.rotationState()');
  await ev('SelectionDragTestHooks.rotationCommands("r")');
  const selectAllAfter=await ev('SelectionDragTestHooks.rotationState()');
  assert.deepStrictEqual(selectAllAfter.grid.tilesA,[
    {cx:13,cy:2,tiles:[{tileId:10,flips:5}]},
    {cx:12,cy:4,tiles:[{tileId:20,flips:4}]},
  ],'Select All plus empty-space selection used an off-by-one rectangle');
  await ev('SelectionDragTestHooks.rotationCommands("rrr")');
  assert.deepStrictEqual(await ev('SelectionDragTestHooks.rotationState()'),selectAllBefore,'Four turns of Select All did not restore the square level exactly');
  pass('Select All with empty-space selection uses inclusive bounds correctly and survives four turns');

  const nativeKey=async(keyCode,modifiers=[])=>{
    const names={shift:'Shift',alt:'Alt',control:'Control',meta:'Meta'};
    for(const modifier of modifiers)win.webContents.sendInputEvent({type:'keyDown',keyCode:names[modifier],modifiers});
    if(modifiers.length)await editorFrame();
    win.webContents.sendInputEvent({type:'keyDown',keyCode,modifiers});await editorFrame();
    win.webContents.sendInputEvent({type:'keyUp',keyCode,modifiers});
    for(const modifier of [...modifiers].reverse())win.webContents.sendInputEvent({type:'keyUp',keyCode:names[modifier]});
    await settleHistory();
  };
  currentCase='native rotation keyboard and toolbar';
  win.focus();win.webContents.focus();
  await ev('SelectionDragTestHooks.rotationNavigationKeys(false)');
  await ev('SelectionDragTestHooks.prepareRotation("tiles")');await settleHistory();
  await ev('document.activeElement && document.activeElement.blur()');
  let keyboardBefore=await ev('SelectionDragTestHooks.rotationState()');
  await nativeKey('z');
  assert.deepStrictEqual(withoutEntityIds(await ev('SelectionDragTestHooks.rotationState()')),expectedRotationState(keyboardBefore,'tiles','r'),'Native Z did not rotate clockwise');
  await nativeKey('z',['shift']);
  assert.deepStrictEqual(await ev('SelectionDragTestHooks.rotationState()'),keyboardBefore,'Native Shift+Z did not rotate counterclockwise');
  await nativeKey('z');
  await nativeKey('z',[process.platform==='darwin'?'meta':'control']);
  assert.deepStrictEqual(await ev('SelectionDragTestHooks.rotationState()'),keyboardBefore,'Ctrl/Cmd+Z no longer performs Undo');

  await ev('SelectionDragTestHooks.prepareRotation("tiles")');await editorFrame();
  keyboardBefore=await ev('SelectionDragTestHooks.rotationState()');
  await ev('(()=>{const input=document.createElement("input");input.id="rotation-typing-guard";document.body.appendChild(input);input.focus();return true;})()');
  await nativeKey('z');
  assert.deepStrictEqual(await ev('SelectionDragTestHooks.rotationState()'),keyboardBefore,'Typing Z into a form rotated the selection');
  await ev('document.getElementById("rotation-typing-guard").remove()');
  await ev('SelectionDragTestHooks.rotationNavigationKeys(true)');
  await nativeKey('z');
  assert.deepStrictEqual(await ev('SelectionDragTestHooks.rotationState()'),keyboardBefore,'ZQSD navigation Z was stolen by rotation');
  await nativeKey('r',['alt']);
  assert.deepStrictEqual(withoutEntityIds(await ev('SelectionDragTestHooks.rotationState()')),expectedRotationState(keyboardBefore,'tiles','r'),'Alt+R did not rotate in ZQSD mode');
  await nativeKey('r',['alt','shift']);
  assert.deepStrictEqual(await ev('SelectionDragTestHooks.rotationState()'),keyboardBefore,'Alt+Shift+R did not rotate counterclockwise in ZQSD mode');
  await ev('SelectionDragTestHooks.rotationNavigationKeys(false)');

  const toolbarClick=async selector=>{
    const target=await ev(`(()=>{const el=document.querySelector(${JSON.stringify(selector)});if(!el)throw Error("Missing rotation toolbar action");const r=el.getBoundingClientRect();return {x:Math.round(r.left+r.width/2),y:Math.round(r.top+r.height/2),width:r.width,height:r.height};})()`);
    assert(target.width>0&&target.height>0,'Rotation toolbar action is not visible');
    const point={x:target.x,y:target.y};
    win.webContents.sendInputEvent({type:'mouseMove',...point});await editorFrame();
    win.webContents.sendInputEvent({type:'mouseDown',...point,button:'left',clickCount:1});
    win.webContents.sendInputEvent({type:'mouseUp',...point,button:'left',clickCount:1});await settleHistory();
  };
  await toolbarClick('li.rotateSelectionClockwise');
  assert.deepStrictEqual(withoutEntityIds(await ev('SelectionDragTestHooks.rotationState()')),expectedRotationState(keyboardBefore,'tiles','r'),'Toolbar clockwise action did not rotate');
  await toolbarClick('li.rotateSelectionCounterClockwise');
  assert.deepStrictEqual(await ev('SelectionDragTestHooks.rotationState()'),keyboardBefore,'Toolbar counterclockwise action did not restore state');
  await ev('SelectionDragTestHooks.clearSelection()');await editorFrame();
  assert.strictEqual(await ev('document.querySelector("li.rotateSelectionClockwise").getAttribute("aria-disabled")'),'true','Empty selection did not disable the rotation toolbar');
  await nativeKey('z');
  assert.deepStrictEqual(await ev('SelectionDragTestHooks.rotationState()'),keyboardBefore,'Empty-selection rotation mutated data');
  pass('Real Z/Shift+Z and toolbar clicks rotate; Ctrl/Cmd+Z, input typing, ZQSD navigation and empty-selection guards remain correct');

  currentCase='native tile artwork pixels';
  win.webContents.sendInputEvent({type:'mouseMove',x:2,y:2});
  let referencePixels=null;
  for(const largeCell of [false,true])for(const initial of [0,1,2,3])for(const commands of ['', 'r']){
    await ev(`SelectionDragTestHooks.prepareRotationVisual(${initial},${largeCell})`);
    if(commands)await ev(`SelectionDragTestHooks.rotationCommands(${JSON.stringify(commands)})`);
    const samples=await ev('SelectionDragTestHooks.rotationVisualSamples()');await settleHistory();
    const screenshot=await win.webContents.capturePage(),size=screenshot.getSize(),pixels=screenshot.toBitmap();
    const cssWidth=await ev('window.innerWidth'),scale=size.width/cssWidth;
    const samplePixels=samples.map(p=>{
      const x=Math.floor(p.x*scale),y=Math.floor(p.y*scale);
      assert(x>=0&&x<size.width&&y>=0&&y<size.height,'Artwork sample fell outside the viewport');
      const at=(y*size.width+x)*4;return [...pixels.subarray(at,at+3)];
    });
    const orientation=commands?cwOrientation[initial]:initial;
    if(referencePixels===null){
      referencePixels=samplePixels;
      assert.strictEqual(new Set(referencePixels.map(p=>p.join(','))).size,4,'Asymmetric atlas quadrants are not visibly distinct');
    }
    for(let i=0;i<4;i++){
      let x=i%2,y=Math.floor(i/2);
      if(orientation&1)x=1-x;if(orientation&2)y=1-y;
      if(orientation&4)[x,y]=[y,x];
      const expected=referencePixels[y*2+x];
      assert(samplePixels[i].every((channel,n)=>Math.abs(channel-expected[n])<=6),`Artwork orientation ${orientation}, quadrant ${i}: ${samplePixels[i]} != ${expected}`);
    }
    if(!largeCell&&initial===0&&commands==='r')fs.writeFileSync(path.join(output,'rotation-artwork-clockwise.png'),screenshot.toPNG());
  }
  pass('Native screenshots verify all eight tile orientations on 16px and 32px cells, including asymmetric tile pivots');

  currentCase='rotation save and reopen';
  for(const external of [false,true]){
    await ev('SelectionDragTestHooks.prepareRotation("mixed",true)');
    await ev('SelectionDragTestHooks.rotationCommands("r")');
    const before=await ev('SelectionDragTestHooks.rotationState()');
    const cloneFlags=await ev('SelectionDragTestHooks.rotationCloneFlags()');
    assert(cloneFlags.runtime.some(f=>(f&4)!==0),'Project clone discarded quarter-turn orientation');
    assert(cloneFlags.native.every(f=>f>=0&&f<=3),'Cloned project leaked editor orientation bits into native JSON');
    const assertNativeFlags=value=>{
      if(!value||typeof value!=='object')return;
      if(Array.isArray(value.gridTiles))for(const tile of value.gridTiles)assert(tile.f>=0&&tile.f<=3,'Cached clone JSON leaked editor orientation bits');
      for(const child of Object.values(value))assertNativeFlags(child);
    };
    assertNativeFlags(JSON.parse(cloneFlags.json));
    await ev(`SelectionDragTestHooks.saveRotationProject(${external})`);
    await until('SelectionDragTestHooks.rotationIoState().done','ProjectSaver did not finish rotation fixture');
    assert.strictEqual((await ev('SelectionDragTestHooks.rotationIoState()')).error,null,'Saving rotation failed');
    const native=JSON.parse(fs.readFileSync(rotationFile,'utf8'));
    const levels=native.levels.concat((native.worlds||[]).flatMap(w=>w.levels));
    for(const metadata of levels){
      const level=metadata.externalRelPath?JSON.parse(fs.readFileSync(path.resolve(path.dirname(rotationFile),metadata.externalRelPath),'utf8')):metadata;
      for(const layer of level.layerInstances||[])for(const tile of [...layer.gridTiles,...layer.autoLayerTiles])
        assert(Number.isInteger(tile.f)&&tile.f>=0&&tile.f<=3,'Stock LDtk JSON contains an unsupported orientation flag');
    }
    const sidecar=JSON.parse(fs.readFileSync(rotationFile+'-fork.json','utf8'));
    assert(Object.values(sidecar.tileTransforms||{}).some(layer=>layer.cells.some(cell=>(cell.flips&4)!==0)),'Rotated tile orientation was not persisted in the companion file');
    await ev('SelectionDragTestHooks.rotationCommands("r")');
    const unsavedWithMetadata=await ev('SelectionDragTestHooks.rotationState()');
    assert.notDeepStrictEqual(unsavedWithMetadata,before,'Unsaved edit fixture did not rotate after saving');
    await ev('SelectionDragTestHooks.reloadRotationConfig()');
    assert.deepStrictEqual(await ev('SelectionDragTestHooks.rotationState()'),unsavedWithMetadata,'Configuration reload replaced unsaved orientation with the disk copy');
    await ev('SelectionDragTestHooks.reloadRotationProject()');
    await until('SelectionDragTestHooks.rotationIoState().done','ProjectLoader did not reopen rotation fixture');
    assert.strictEqual((await ev('SelectionDragTestHooks.rotationIoState()')).error,null,'Reopening rotation failed');
    await until('SelectionDragTestHooks.ready()','Reopened rotation editor is not ready');await settleHistory();
    assert.deepStrictEqual(await ev('SelectionDragTestHooks.rotationState()'),before,`${external?'External':'Embedded'} project lost rotation, stacks, offsets, entities or points on disk round-trip`);
  }
  pass('ProjectSaver/ProjectLoader retain rotated stacks for embedded/external levels; configuration reloads preserve unsaved edits and native JSON flags stay stock-compatible');

  fs.writeFileSync(path.join(output,'results.json'),JSON.stringify({passed,variantChecks:checks,flipChecks,rotationChecks,platform:process.platform,electron:process.versions.electron},null,2));
  console.log(`SUCCESS: ${checks} matrix variants + ${flipChecks} flip cases + ${rotationChecks} rotation cases + ${passed.length} grouped selection scenarios passed`);
  clearTimeout(timer);app.exit(0);
}
require('../assets/main.js');
