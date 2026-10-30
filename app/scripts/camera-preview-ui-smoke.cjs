'use strict';

const {app, Menu, clipboard} = require('electron');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'smartive-camera-preview-'));
const output = path.join(root, 'test-results/camera-preview');
fs.mkdirSync(output, {recursive: true});
process.chdir(root);
app.setPath('userData', tmp);
app.setAppPath(root);
process.env.LDTK_SMARTIVE_CONTROL_DIR = path.join(tmp, 'control');
app.commandLine.appendSwitch('no-sandbox');
if(process.env.SMARTIVE_CAMERA_DPR) app.commandLine.appendSwitch('force-device-scale-factor',process.env.SMARTIVE_CAMERA_DPR);
if (process.platform === 'linux') {
  app.commandLine.appendSwitch('use-gl', 'angle');
  app.commandLine.appendSwitch('use-angle', 'swiftshader');
}
const passed = [];
const retinaOnly=Number(process.env.SMARTIVE_CAMERA_DPR || 1)>1;
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
// Intel macOS CI took about 3.5 times as long as Linux for the same native gestures.
// Budget the whole suite accordingly; individual frame/polling deadlines stay strict.
const timer = setTimeout(() => {console.error('FAIL: camera preview regression timed out'); app.exit(1);}, process.platform === 'darwin' || retinaOnly ? 900000 : 420000);
let running = false;

app.on('browser-window-created', (_, win) => {
  win.webContents.on('did-finish-load', () => {
    if (!win.webContents.getURL().endsWith('/assets/app.html') || running) return;
    running = true;
    run(win).catch(async error => {
      console.error(error.stack || error);
      fs.writeFileSync(path.join(output, 'results.json'), JSON.stringify({status: 'failed', passed, error: String(error.stack || error)}, null, 2));
      try {fs.writeFileSync(path.join(output, 'failure.png'), (await win.webContents.capturePage()).toPNG());} catch (_) {}
      clearTimeout(timer); app.exit(1);
    });
  });
});

async function run(win) {
  const ev = async code => {
    const result = await win.webContents.executeJavaScript(`(()=>{try{return {ok:true,value:(${code})}}catch(e){return {ok:false,error:String(e&&e.stack||e)}}})()`, true);
    if (!result || !result.ok) throw Error(code + '\n' + String(result && result.error));
    return result.value;
  };
  const until = async (code, message) => {
    for (let i = 0; i < 220; i++) {
      const value = await ev(code);
      if (value) return value;
      await delay(40);
    }
    throw Error(message);
  };
  await until('!!(globalThis.__ldtk && __ldtk.App.ME && document.querySelector("#page"))', 'Editor bootstrap unavailable');
  await delay(750);
  win.setSize(1600, 1000); win.show(); win.focus(); win.webContents.focus();
  win.webContents.setBackgroundThrottling(false); Menu.setApplicationMenu(null);
  await win.webContents.executeJavaScript(fs.readFileSync(path.join(__dirname, 'camera-preview-fixture.js'), 'utf8'), true);
  await ev(`(()=>{window.cameraMouseDelivery={sequence:0,x:null,y:null};document.addEventListener('mousemove',event=>{
    cameraMouseDelivery={sequence:cameraMouseDelivery.sequence+1,x:event.clientX,y:event.clientY};
  },true);return true})()`);
  const call = (name, ...args) => ev(`cameraPreviewFixture.${name}(${args.map(value => JSON.stringify(value)).join(',')})`);
  const state = () => call('stats');
  const frame = (count = 1) => win.webContents.executeJavaScript(`new Promise((resolve,reject)=>{
    const P=__ldtk.classes['dn.Process']; let remaining=${count};
    const next=()=>{
      const timeout=setTimeout(()=>reject(Error('Editor frame did not complete')),${retinaOnly ? 30000 : 8000});
      P.callAtTheBeginningOfNextFrame(()=>P.callAtTheEndOfCurrentFrame(()=>{
        clearTimeout(timeout); if(--remaining>0)next(); else resolve(true);
      }));
    }; next();
  })`, true);
  // Keep both real editor frames without another main/renderer IPC round trip.
  const settled = async () => {await frame(2); return state();};
  const pass = async message => {
    assert.equal(await ev('__ldtk.App.ME.curPageProcess.__class__.__name__'), 'page.Editor', 'Application entered a crash page');
    passed.push(message); console.log('PASS: ' + message);
  };
  const screenshot = async name => {
    await settled();
    fs.writeFileSync(path.join(output, name + '.png'), (await win.webContents.capturePage()).toPNG());
  };
  const near = (a, b, message, tolerance = 0.00001) => assert.ok(Number.isFinite(a) && Math.abs(a - b) <= tolerance, `${message}: ${a} != ${b}`);
  const primaryModifier = process.platform === 'darwin' ? 'meta' : 'control';
  const modifierKey = {control: 'Control', alt: 'Alt', shift: 'Shift', meta: 'Meta'};
  const withModifiers = async (modifiers, action) => {
    for (const modifier of modifiers) {
      win.webContents.sendInputEvent({type: 'keyDown', keyCode: modifierKey[modifier], modifiers});
    }
    if (modifiers.length) await frame();
    for (const modifier of modifiers) {
      const expression = modifier === 'meta' ? '__ldtk.App.ME.isCtrlCmdDown()'
        : `__ldtk.App.ME.isKeyDown(${({control: 17, alt: 18, shift: 16})[modifier]})`;
      assert.equal(await ev(expression), true, 'Native modifier is not held: ' + modifier);
    }
    try {return await action();}
    finally {
      for (const modifier of [...modifiers].reverse()) {
        win.webContents.sendInputEvent({type: 'keyUp', keyCode: modifierKey[modifier]});
      }
      if (modifiers.length) await frame();
    }
  };
  const nativeMove = async (p, modifiers = [], waitForFrame = true) => {
    const sequence = await ev('cameraMouseDelivery.sequence');
    win.webContents.sendInputEvent({type: 'mouseMove', ...p, modifiers});
    await until(`cameraMouseDelivery.sequence>${sequence} && cameraMouseDelivery.x===${p.x} && cameraMouseDelivery.y===${p.y}`, 'Native mouse movement was not delivered');
    if (waitForFrame) await frame();
  };
  const move = async (x, y) => {
    const p = await call('screen', x, y);
    assert.equal(await ev(`document.elementFromPoint(${p.x},${p.y})?.id`), 'webgl', 'Map target is covered by UI');
    // Both native moves must arrive; only the final point needs a rendered frame.
    await nativeMove({x: p.x + 1, y: p.y}, [], false); await nativeMove(p);
    return p;
  };
  const click = async (p, button = 'left', modifiers = []) => {
    await withModifiers(modifiers, async () => {
      // The next barrier processes this delivered move and the down together.
      await nativeMove(p, modifiers, false);
      win.webContents.sendInputEvent({type: 'mouseDown', ...p, button, clickCount: 1, modifiers}); await frame();
      win.webContents.sendInputEvent({type: 'mouseUp', ...p, button, clickCount: 1, modifiers}); await settled();
    });
  };
  const clickSelector = async selector => {
    let p;
    try {
      p = await until(`(()=>{const el=document.querySelector(${JSON.stringify(selector)});if(!el)return null;el.scrollIntoView({block:'nearest'});const r=el.getBoundingClientRect(),x=Math.round(r.left+r.width/2),y=Math.round(r.top+r.height/2);return r.width>0&&r.height>0&&el.contains(document.elementFromPoint(x,y))?{x,y}:null})()`, 'Control unavailable: ' + selector);
    } catch (error) {
      const details = await ev(`(()=>{const e=document.querySelector(${JSON.stringify(selector)}),panel=document.querySelector('#cameraPreviewControls');if(!e)return null;const r=e.getBoundingClientRect(),style=getComputedStyle(e),ps=getComputedStyle(panel);return {rect:r.toJSON(),display:style.display,pointerEvents:style.pointerEvents,panel:{rect:panel.getBoundingClientRect().toJSON(),position:ps.position,width:ps.width},bodyClass:document.body.className,cover:document.elementFromPoint(r.x+r.width/2,r.y+r.height/2)?.outerHTML.slice(0,300)}})()`);
      throw Error(error.message + '\n' + JSON.stringify(details));
    }
    await click(p);
  };
  const key = async (keyCode, modifiers = []) => {
    await withModifiers(modifiers, async () => {
      win.webContents.sendInputEvent({type: 'keyDown', keyCode, modifiers}); await frame();
      win.webContents.sendInputEvent({type: 'keyUp', keyCode, modifiers}); await settled();
    });
  };
  const drag = async (from, to, button = 'left', modifiers = []) => {
    await withModifiers(modifiers, async () => {
      await nativeMove(from, modifiers, false);
      win.webContents.sendInputEvent({type: 'mouseDown', ...from, button, clickCount: 1, modifiers}); await frame();
      await nativeMove(to, modifiers);
      win.webContents.sendInputEvent({type: 'mouseUp', ...to, button, clickCount: 1, modifiers}); await settled();
    });
  };
  const writeProfile = async values => {
    const profile = await call('profile', values || {});
    await call('write', profile);
    return profile;
  };
  const unchanged = async before => {
    assert.deepEqual(await call('serial'), before, 'Camera inspection changed project JSON, undo history, or dirty state');
    assert.equal((await state()).banner, false, 'Camera telemetry triggered a project-reload banner');
  };


  await call('setup', path.join(tmp, 'camera-preview.ldtk'));
  await delay(400); await ev('__ldtk.classes["ui.Modal"].closeAll()'); await settled();
  const initial = await call('serial');
  const initialFlags = await call('flags');
  assert.equal(initial.dirty, false);

  if(retinaOnly) {
    // Exercise real DPR=2 rendering on a smaller viewport. The normal suite
    // covers all native tools; this avoids quadrupling SwiftShader pixel work.
    win.setSize(1000,760);await delay(150);await ev('cameraPreviewFixture.editor().camera.fit(true)');await settled();
    await clickSelector('#editingOptions li.cameraPreview');await writeProfile();
    await until('cameraPreviewFixture.stats().profile?.width === 320','Retina profile not loaded');
    await call('setPoint',480,430);await ev('cameraPreviewFixture.preview().setPinned(true)');
    let s=await settled();const point=s.point,rect=s.frame;
    assert.equal(s.transform.pixelRatio,2);assert.equal(s.sprite.pointerEvents,'none');
    const verify=async()=>{
      const p=await state(),bounds=await ev('document.querySelector("#webgl").getBoundingClientRect().toJSON()');
      const scale=p.transform.zoom/p.transform.pixelRatio;
      near(p.sprite.width,32*scale,'Retina native sprite width',.03);
      near(p.sprite.height,44*scale,'Retina native sprite height',.03);
      near(p.sprite.x,bounds.left+(p.transform.x+p.point.x*p.transform.zoom)/2-p.sprite.width*.5,'Retina anchored X',.03);
      near(p.sprite.y,bounds.top+(p.transform.y+p.point.y*p.transform.zoom)/2-p.sprite.height,'Retina anchored Y',.03);
      assert.deepEqual(p.point,point);assert.deepEqual(p.frame,rect);
    };
    await verify();await unchanged(initial);await pass('Retina DPR=2 sprite size/pivot and player root match real canvas coordinates');
    await drag(await call('screen',480,430),await call('screen',530,440),'middle');await settled();
    await verify();await pass('Native Retina panning keeps the camera and player world anchor');
    await ev('cameraPreviewFixture.editor().camera.setZoom(1.25)');await settled();
    await verify();await unchanged(initial);await pass('Retina zoom reprojects the overlay without map/history mutation');
    await screenshot('retina-success');
    fs.writeFileSync(path.join(output,'results.json'),JSON.stringify({status:'passed',passed,devicePixelRatio:2,platform:process.platform,electron:process.versions.electron},null,2));
    console.log('SUCCESS: '+passed.length+' Retina camera-preview scenarios passed');clearTimeout(timer);app.exit(0);return;
  }

  await clickSelector('#editingOptions li.cameraPreview');
  let s = await state();
  assert.equal(s.enabled, true); assert.equal(s.placing, true);
  assert.equal(s.profile, null); assert.match(s.status, /Waiting for Unity/);
  await unchanged(initial); await pass('Preview toggle enters Joshua placement without modifying the level');

  await writeProfile();
  await until('cameraPreviewFixture.stats().profile?.width === 320', 'Camera snapshot not detected');
  await move(451,263); s=await settled();
  assert.equal(s.gridMode, false);
  near(s.frame.centerX,s.point.x,'Camera fallback is at Joshua X');
  near(s.frame.centerY,s.point.y,'Camera fallback is at Joshua Y');
  assert.match(s.status,/tylko wymiary/);
  assert.ok(s.sprite.visible && s.sprite.src.includes('joshua-idle-preview.png'));
  assert.equal(s.sprite.pointerEvents,'none');
  await unchanged(initial); await pass('Joshua graphic follows the cursor, legacy snapshots declare dimensions-only');
  await screenshot('joshua-placement');

  const modeRects=await ev(`(()=>[...document.querySelectorAll('.cameraModes button')].map(e=>{const r=e.getBoundingClientRect();return {left:r.left,right:r.right,top:r.top,bottom:r.bottom}}))()`);
  assert.ok(modeRects[0].right<=modeRects[1].left && modeRects[2].top>=modeRects[0].bottom,'Mode buttons overlap');
  await drag(await call('screen',451,263),await call('screen',575,300));
  assert.equal((await state()).pinned,true); await unchanged(initial);
  await clickSelector('#cameraPreviewControls .cameraPin');
  await pass('Holding and dragging the placement click never paints or enters map history');
  const placement = await move(451,263);
  await click(placement); s=await settled();
  assert.equal(s.pinned,true); assert.equal(s.placing,false);
  assert.match(s.lockStatus,/Zablokowany/);
  await unchanged(initial);
  const fixedPoint=s.point, fixedFrame=s.frame;
  await move(575,360); s=await settled();
  assert.deepEqual(s.point,fixedPoint); assert.deepEqual(s.frame,fixedFrame);
  await click(await call('screen',575,360)); s=await settled();
  assert.equal(s.pinned,true); assert.deepEqual(s.point,fixedPoint);
  assert.notEqual((await call('serial')).json,initial.json,'A click after locking must reach the editor');
  await pass('Placement never modifies the level; after locking, the very next click reaches the editing tool');

  const toolAtLock=await ev('cameraPreviewFixture.editor().get_curTool().__class__.__name__');
  await call('selectTerrain'); await settled();
  const paintBefore=await call('serial');
  await drag(await call('screen',320,160),await call('screen',448,160));
  const painted=await call('serial');
  assert.deepEqual(await ev('Array.from({length:9},(_,i)=>cameraPreviewFixture.editor().get_curLayerInstance().getIntGrid(20+i,10))'),Array(9).fill(1),'Continuous stroke has holes');
  assert.notEqual(painted.json,paintBefore.json,'Real continuous paint did not affect the level');
  assert.deepEqual((await state()).frame,fixedFrame);
  assert.deepEqual((await state()).point,fixedPoint);
  assert.equal(await ev('cameraPreviewFixture.editor().get_curTool().__class__.__name__'),toolAtLock);
  await pass('Locked overlay preserves drawing tool, real continuous painting, player and frame');
  await screenshot('joshua-locked-paint');

  await key('z',[primaryModifier]);
  assert.equal((await call('serial')).json,paintBefore.json,'Undo did not restore the tile stroke');
  await key('y',[primaryModifier]);
  assert.equal((await call('serial')).json,painted.json,'Redo did not restore the tile stroke');
  await pass('Native undo and redo remain functional while Joshua is locked');

  await drag(await call('screen',320,160),await call('screen',448,160),'right');
  assert.notEqual((await call('serial')).json,painted.json,'Eraser did not change the painted tiles');
  await key('z',[primaryModifier]);
  assert.equal((await call('serial')).json,painted.json,'Undo did not restore erased tiles');
  await pass('Right-drag eraser and its Undo run through the normal tools');

  // Include the freshly painted cells. An empty-area Alt drag has no selection when empty-space selection is off.
  await drag(await call('screen',310,152),await call('screen',465,180),'left',['alt','shift']);
  assert.equal((await state()).selection,true,'Alt+Shift-drag selection did not create a selection');
  assert.deepEqual((await state()).point,fixedPoint);
  await call('selectTerrain');
  await pass('Alt+Shift-drag selection still works with the locked overlay');

  const oldSprite=await state();
  await ev(`(()=>{const e=document.querySelector(".cameraSpritePpu");e.value="32";e.dispatchEvent(new Event("input",{bubbles:true}));return true})()`);
  s=await settled();
  assert.ok(s.sprite.width<oldSprite.sprite.width,'Sprite PPU did not change visual scale');
  assert.equal(s.sprite.pointerEvents,'none');
  await ev(`(()=>{const e=document.querySelector(".cameraSpritePpu");e.value="16";e.dispatchEvent(new Event("input",{bubbles:true}));return true})()`);
  await settled(); await pass('Sprite PPU controls visual scale without changing project data');

  const beforeSpriteImport=await call('serial');
  const spriteFile=path.join(tmp,'JoshuaIdle.png');
  await call('makeSpriteFixture',spriteFile);
  await call('setAssetFile','.cameraSpriteFile',spriteFile);
  await until('cameraPreviewFixture.preview().spritePixelsPerUnit === 32 && document.querySelector(".cameraJoshuaSprite").complete','Meta sprite did not load');
  s=await settled();
  assert.match(s.spriteStatus,/PPU i pivot z .meta/);
  assert.deepEqual(await call('spritePixel'),[0,255,0,255],'Unity bottom-left rect was cropped from the wrong row');
  near(await ev('cameraPreviewFixture.preview().spritePivotX'),.25,'Imported pivot X');
  near(await ev('cameraPreviewFixture.preview().spritePivotY'),.125,'Imported pivot Y');
  const pref=path.join(tmp,'Joshua.prefab');
  fs.writeFileSync(pref,`--- !u!4 &1
Transform:
  m_GameObject: {fileID: 10}
  m_Father: {fileID: 0}
  m_LocalPosition: {x: 400, y: -700, z: 0}
  m_LocalRotation: {x: 0, y: 0, z: 0, w: 1}
  m_LocalScale: {x: 1, y: 1, z: 1}
--- !u!4 &2
Transform:
  m_GameObject: {fileID: 11}
  m_Father: {fileID: 1}
  m_LocalPosition: {x: 0.5, y: 1, z: 0}
  m_LocalRotation: {x: 0, y: 0, z: 0, w: 1}
  m_LocalScale: {x: 1, y: 1, z: 1}
--- !u!212 &3
SpriteRenderer:
  m_GameObject: {fileID: 11}
  m_Sprite: {fileID: 9223372036854775701, guid: 1234567890abcdef1234567890abcdef, type: 3}
`);
  await call('setAssetFile','.cameraPrefabFile',pref);
  await until('document.querySelector(".cameraSpriteStatus").dataset.verified === "true"','Prefab transform was not applied');
  s=await settled();
  const sr=s.transform.zoom/s.transform.pixelRatio;
  const canvasRect=await ev('document.querySelector("#webgl").getBoundingClientRect().toJSON()');
  near(s.sprite.width,16*sr,'Meta PPU preserves sprite width at device pixel ratio',.02);
  near(s.sprite.x,canvasRect.left+(s.transform.x+(s.point.x+8)*s.transform.zoom)/s.transform.pixelRatio-s.sprite.width*.25,'Sprite pivot and root offset X',.02);
  near(s.sprite.y,canvasRect.top+(s.transform.y+(s.point.y-16)*s.transform.zoom)/s.transform.pixelRatio-s.sprite.height*.875,'Sprite pivot and Unity-up offset Y',.02);
  await unchanged(beforeSpriteImport);
  await call('setAssetFile','.cameraSpriteFile',path.join(root,'assets/img/joshua-idle-preview.png'));
  await until('cameraPreviewFixture.preview().spritePixelsPerUnit === 16','Fallback sprite did not recover');
  await pass('Native renderer imports exact meta crop, PPU, pivot and prefab offset without mutating level/history');

  await call('selectObjects'); await settled();
  const beforeEntity=await call('serial');
  await click(await move(700,400));
  assert.notEqual((await call('serial')).json,beforeEntity.json,'Locked preview blocks entity placement');
  assert.deepEqual((await state()).point,fixedPoint);
  await key('z',[primaryModifier]); assert.equal((await call('serial')).json,beforeEntity.json);
  await call('selectTerrain');await settled();
  await pass('Locked preview permits native entity placement and Undo');

  const previousTransform=await state();
  await drag(await call('screen',480,288),await call('screen',540,320),'middle');
  s=await state(); assert.deepEqual(s.point,fixedPoint); assert.deepEqual(s.frame,fixedFrame);
  assert.notEqual(s.transform.x,previousTransform.transform.x);
  const oldSpriteX=s.sprite.x;
  await ev('cameraPreviewFixture.editor().camera.setZoom(1.5)');
  await settled(); s=await state();
  assert.deepEqual(s.frame,fixedFrame); assert.deepEqual(s.point,fixedPoint);
  assert.notEqual(s.transform.zoom,previousTransform.transform.zoom);
  assert.notEqual(s.sprite.x,oldSpriteX);
  await ev('cameraPreviewFixture.editor().camera.fit(true)');
  await pass('Pan and zoom reproject sprite and frame without moving Joshua in the world');

  const currentIid=await ev('cameraPreviewFixture.level().iid');
  const model={schemaVersion:1,levels:[{iid:currentIid,camera:{offset:{x:1,y:-0.25}},
    rooms:[{x:0,y:0,width:960,height:576}],zones:[{x:400,y:230,width:300,height:260,zoom:2}]}]};
  await writeProfile({unityCameraModel:model});
  await until('cameraPreviewFixture.stats().profile?.unityCameraModel', 'Unity camera model not loaded');
  s=await settled(); assert.deepEqual(s.point,fixedPoint);
  assert.notDeepEqual(s.frame,fixedFrame);
  assert.match(s.status,/stan ustalony/);
  await pass('Unity JSON model recalculates the locked frame without moving Joshua');
  await writeProfile({unityCameraModel:{...model,levels:[{...model.levels[0],zones:[]} ]}});
  await until('cameraPreviewFixture.stats().frame?.width === 320','Camera model zone update not recognized');
  assert.deepEqual((await state()).point,fixedPoint);
  await pass('Updating zone/zoom source reuses the same pinned world position');

  await clickSelector('#cameraPreviewControls .cameraPin');
  s=await state(); assert.equal(s.pinned,false); assert.equal(s.placing,true);
  await move(215,225); await click(await call('screen',215,225)); s=await settled();
  assert.equal(s.pinned,true); assert.notDeepEqual(s.point,fixedPoint);
  const relocated=s.point;
  await drag(await call('screen',350,210),await call('screen',430,210));
  assert.deepEqual((await state()).point,relocated);
  await pass('Przestaw Joshuę re-enables placement, then new locked point allows more painting');

  const level0=await call('serial');
  await clickSelector('#cameraPreviewControls .cameraGrid');
  assert.equal((await state()).placing,true);
  await clickSelector('#cameraPreviewControls .cameraFree');
  s=await state(); assert.equal(s.placing,true); assert.equal(s.gridMode,false);
  await unchanged(level0);
  await pass('Optional grid mode and Joshua mode never mutate level history');

  await call('switchLevel',true);
  s=await settled(); assert.equal(s.pinned,false);
  near(s.point.x,320,'Second level X resets'); near(s.point.y,192,'Second level Y resets');
  assert.equal(s.frame,null); assert.match(s.status,/IID/,'Missing level model must not pretend to have a valid frame');
  await call('switchLevel',false); await settled();
  await pass('Changing levels prevents a previously pinned Joshua from leaking across rooms');

  await call('write','{');
  await until('cameraPreviewFixture.stats().profile === null','Malformed JSON not rejected');
  s=await settled(); assert.match(s.status,/JSON/);
  await writeProfile(); await until('cameraPreviewFixture.stats().profile?.width === 320','Snapshot did not recover');
  await pass('Invalid Unity source is diagnosed and recovers while the editor stays open');
  const beforeSourceLimits=await call('serial'),pointBeforeLimits=(await state()).point;
  await call('write',JSON.stringify({...await call('profile'),cameraName:'Large source',padding:'x'.repeat(66000)}),true);
  assert.equal((await state()).profile?.cameraName,'Large source','Valid source above 64 KB was rejected');
  await call('write',' '.repeat(4*1024*1024+1),true);
  assert.equal((await state()).profile,null);assert.match((await state()).status,/4 MiB/);
  assert.deepEqual((await state()).point,pointBeforeLimits);
  await call('write',await call('profile'),true);await settled();await unchanged(beforeSourceLimits);
  await pass('Model-sized snapshots load, oversized sources fail safely and recover without changing the player');

  await clickSelector('#cameraPreviewControls .cameraSetup');
  await until('!!document.querySelector(".cameraPreviewSetup .cameraFilePath")','Setup dialog unavailable');
  await key('Escape'); await until('!__ldtk.classes["ui.Modal"].hasAnyOpen()','Setup dialog did not close');
  await clickSelector('#cameraPreviewControls .cameraClose');
  assert.equal((await state()).enabled,false);
  assert.deepEqual(await call('flags'),initialFlags);
  await pass('Closing the preview restores the editor without changing display preferences');

  await clickSelector('#editingOptions li.cameraPreview');
  await call('emptyProject',path.join(tmp,'empty-camera-level.ldtk'));
  await delay(300); await ev('__ldtk.classes["ui.Modal"].closeAll()'); await settled();
  s=await state(); assert.equal(s.enabled,false); assert.equal(s.pinned,false);
  assert.equal(s.profile,null);
  await pass('Changing project clears the old sprite position and Unity source');

  await screenshot('success');
  fs.writeFileSync(path.join(output, 'results.json'), JSON.stringify({status: 'passed', passed, platform: process.platform, electron: process.versions.electron}, null, 2));
  console.log('SUCCESS: ' + passed.length + ' camera-preview scenarios passed');
  clearTimeout(timer); app.exit(0);
}

require('../assets/main.js');
