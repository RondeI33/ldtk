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
if (process.platform === 'linux') {
  app.commandLine.appendSwitch('use-gl', 'angle');
  app.commandLine.appendSwitch('use-angle', 'swiftshader');
}
const passed = [];
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
// Intel macOS CI took about 3.5 times as long as Linux for the same native gestures.
// Budget the whole suite accordingly; individual frame/polling deadlines stay strict.
const timer = setTimeout(() => {console.error('FAIL: camera preview regression timed out'); app.exit(1);}, process.platform === 'darwin' ? 900000 : 420000);
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
      const timeout=setTimeout(()=>reject(Error('Editor frame did not complete')),8000);
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
  assert.equal(initial.dirty, false);
  const initialFlags = await call('flags');
  assert.equal((await state()).enabled, false);
  await clickSelector('#editingOptions li.cameraPreview');
  let s = await state();
  assert.equal(s.enabled, true); assert.equal(s.profile, null); assert.equal(s.visible, false);
  assert.match(s.status, /Waiting for Unity/); assert.equal(s.toolbarPressed, 'true');
  await unchanged(initial); await pass('Native toolbar toggle opens a clear missing-source state without changing the project');

  await writeProfile();
  await until('cameraPreviewFixture.stats().profile?.sceneName === "04_research"', 'Camera file was not detected automatically');
  await move(450, 260); s = await settled();
  assert.equal(s.profile.width, 320); assert.equal(s.profile.height, 180);
  assert.equal(s.visible, true);
  assert.equal(s.gridMode, false);
  near(s.frame.centerX, s.point.x, 'Joshua placement X');
  near(s.frame.centerY, s.point.y, 'Joshua placement Y');
  assert.equal(s.gridLines, 0);
  await unchanged(initial); await pass('Unity snapshot opens Joshua placement with exact player-point framing'); await screenshot('joshua-place');

  await click(await move(451, 263)); s = await state();
  assert.equal(s.pinned, true); const pinned = s.frame;
  await move(590, 330); assert.deepEqual((await settled()).frame, pinned);
  await call('selectTerrain');
  await drag(await call('screen', 448, 192), await call('screen', 528, 224), 'left');
  assert.deepEqual((await settled()).frame, pinned, 'Painting must never move Joshua');
  assert.notDeepEqual(await call('serial'), initial, 'A locked preview must allow painting');
  await key('z', [primaryModifier]);
  await unchanged(initial);
  await clickSelector('#cameraPreviewControls .cameraPin');
  assert.equal((await state()).pinned, false);
  await move(605, 342); s = await settled(); assert.notDeepEqual(s.frame, pinned);
  await unchanged(initial); await pass('Pinned Joshua enables tile painting and undo, while Reposition restores placement'); await screenshot('joshua-locked');

  for (const action of [
    {button: 'left', modifiers: []}, {button: 'right', modifiers: []},
    {button: 'left', modifiers: ['alt']}, {button: 'left', modifiers: ['alt', 'shift']},
    {button: 'left', modifiers: ['control', 'shift']},
  ]) {
    await ev('cameraPreviewFixture.preview().setPinned(false)');
    await drag(await call('screen', 320, 144), await call('screen', 400, 224), action.button, action.modifiers);
    await unchanged(initial);
    assert.equal((await state()).running, false); assert.equal((await state()).selection, false);
  }
  await pass('Native paint, erase, selection and rectangle gestures are intercepted while inspecting the camera');

  await ev('cameraPreviewFixture.preview().setPinned(false)');
  await call('selectEntity'); await settled();
  const keyboardBefore = await call('serial');
  clipboard.writeText('Camera preview clipboard sentinel');
  await click(await move(512, 288));
  assert.equal(await ev('__ldtk.App.ME.hasInputFocus() || __ldtk.classes["ui.Modal"].hasAnyOpen()'), false, 'Keyboard test must target an unlocked level canvas');
  for (const [code, modifiers] of [['Delete', []], ['Right', []], ['Up', ['control', 'alt']], ['z', [primaryModifier]], ['y', [primaryModifier]], ['x', []], ['y', []], ['v', [primaryModifier]], ['c', [primaryModifier]]]) {
    await key(code, modifiers); await unchanged(keyboardBefore);
    assert.equal(await ev('__ldtk.classes["ui.Modal"].hasAnyOpen()'), false, 'An intended editing shortcut opened a panel instead');
  }
  assert.equal(clipboard.readText(), 'Camera preview clipboard sentinel');
  await ev('cameraPreviewFixture.editor().selectionTool.clear()');
  await call('selectTerrain'); await settled();
  await pass('Native Delete, movement, layer transfer, Undo/Redo, flip and clipboard shortcuts cannot modify the inspected level');

  await ev('cameraPreviewFixture.preview().setPinned(false)');
  await move(480, 288); await click(await call('screen', 480, 288));
  s = await state(); const beforePan = s;
  await drag(await call('screen', 480, 288), await call('screen', 540, 320), 'middle');
  s = await state();
  assert.deepEqual(s.frame, beforePan.frame); assert.notEqual(s.transform.x, beforePan.transform.x);
  assert.equal(s.pinned, true);
  const panLabel = s.label;
  await ev('cameraPreviewFixture.editor().camera.setZoom(1.5)'); await settled(); s = await state();
  assert.deepEqual(s.frame, beforePan.frame); assert.notEqual(s.transform.zoom, beforePan.transform.zoom);
  assert.notDeepEqual(s.label, panLabel); assert.ok(s.label.x >= 0 && s.label.y >= 0);
  await unchanged(initial); await pass('Native middle-button pan and zoom retain a pinned world frame and realign its overlay');
  await ev('cameraPreviewFixture.editor().camera.fit(true)'); await settled();

  await call('configureGuide', true); await settled();
  const guideBefore = await call('serial');
  await clickSelector('#cameraPreviewControls .cameraGrid');
  await clickSelector('#cameraPreviewControls .cameraGuideGrid');
  await ev('cameraPreviewFixture.preview().setPinned(false)'); await move(451, 263); s = await settled();
  assert.equal(s.guide, true);
  const g = s.guideInfo, stepX = g.width * g.scale, stepY = g.height * g.scale;
  const originX = g.offsetX * g.scale + g.parallaxX, originY = g.offsetY * g.scale + g.parallaxY;
  const column = Math.floor((s.point.x - originX) / stepX), row = Math.floor((s.point.y - originY) / stepY);
  near(s.frame.centerX, originX + (column + .5) * stepX, 'Scaled/offset guide center X');
  near(s.frame.centerY, originY + (row + .5) * stepY, 'Scaled/offset guide center Y');
  assert.equal(s.frame.width, 320); assert.equal(s.frame.height, 180);
  await unchanged(guideBefore); await pass('Layer-guide mode honors independent guide steps, offsets, scale and parallax while preserving the Unity viewport size');
  await screenshot('guide-grid');
  await call('configureGuide', false); await settled();
  await clickSelector('#cameraPreviewControls .cameraGuideGrid');
  const sourceBefore = await call('serial');

  for (const [payload, pattern] of [
    ['{', /JSON/],
    [JSON.stringify({schemaVersion: 42, source: 'unity', valid: true}), /version/],
    [JSON.stringify(await call('profile', {orthographic: false})), /orthographic/],
    [JSON.stringify(await call('profile', {valid: false, error: 'Active scene has no camera.'})), /Active scene/],
    [' '.repeat(66000), /64 KB/],
  ]) {
    await call('write', payload);
    await until('cameraPreviewFixture.stats().profile === null', 'Invalid snapshot was not rejected');
    await delay(550); s = await settled();
    assert.equal(s.visible, false); assert.match(s.status, pattern);
    await unchanged(sourceBefore);
    await writeProfile();
    await until('cameraPreviewFixture.stats().profile?.width === 320', 'Valid snapshot did not recover');
  }
  await pass('Malformed, unsupported, perspective, invalidated and oversized snapshots fail clearly and recover automatically');

  await call('removeSource');
  await until('cameraPreviewFixture.stats().profile === null', 'Removed source was not detected');
  assert.equal((await settled()).visible, false);
  await writeProfile({sceneName: '05_hangar', cameraName: 'HangarCamera', orthographicSize: 6, aspect: 2, live: true});
  await until('cameraPreviewFixture.stats().profile?.sceneName === "05_hangar"', 'New scene snapshot was not detected');
  s = await settled(); assert.equal(s.profile.width, 384); assert.equal(s.profile.height, 192); assert.equal(s.stale, false);
  assert.match(s.status, /Unity camera synced/); assert.match(s.status, /HangarCamera/);
  await unchanged(sourceBefore); await pass('Removing telemetry hides stale geometry; a new live scene atomically updates source and projection without reloading the project');

  await writeProfile({live: true, updatedAtUtc: new Date(Date.now() - 20000).toISOString()});
  await until('cameraPreviewFixture.stats().stale', 'Stale live source was not identified');
  s = await settled(); assert.match(s.status, /Sync paused/); assert.equal(s.visible, true);
  await writeProfile({live: false, updatedAtUtc: '2020-01-01T00:00:00Z'});
  await until('!cameraPreviewFixture.stats().stale && cameraPreviewFixture.stats().profile?.live === false', 'Manual snapshot was treated as stale');
  assert.match((await state()).status, /Unity camera snapshot/);
  await unchanged(sourceBefore); await pass('Stale live snapshots are labeled paused, while deliberate manual snapshots remain valid');

  await call('setFlags', {single: true, details: false, grid: false, variables: false, auto: false}); await settled();
  const customFlags = await call('flags');
  await clickSelector('#cameraPreviewControls .cameraClose');
  assert.equal((await state()).enabled, false); assert.deepEqual(await call('flags'), customFlags);
  await clickSelector('#editingOptions li.cameraPreview');
  assert.deepEqual(await call('flags'), customFlags);
  await call('setFlags', {single: false, details: true, grid: true, variables: true, auto: true}); await settled();
  await pass('Preview toggles preserve Single Layer, details, layer grid, variable previews and auto-layer settings');

  await ev('cameraPreviewFixture.preview().setPinned(true)'); await call('switchLevel', true); s = await settled();
  assert.equal(s.pinned, false); near(s.point.x, 320, 'New level center X'); near(s.point.y, 192, 'New level center Y');
  assert.equal(s.profile.width, 320);
  await call('switchLevel', false); await settled();
  await ev('cameraPreviewFixture.editor().setWorldMode(true)'); s = await settled();
  assert.equal(s.enabled, true); assert.equal(s.active, false); assert.equal(s.visible, false); assert.match(s.status, /paused in World/);
  await ev('cameraPreviewFixture.editor().setWorldMode(false)'); await ev('__ldtk.classes["ui.Modal"].closeAll()'); await ev('cameraPreviewFixture.editor().camera.fit(true)');
  s = await settled(); assert.equal(s.visible, true); assert.equal(s.pinned, false);
  await pass('Changing levels resets the pinned point; World view suspends the overlay and returning restores it');

  await clickSelector('#cameraPreviewControls .cameraSetup');
  await until('!!document.querySelector(".cameraPreviewSetup .cameraFilePath")', 'Camera setup dialog did not open');
  assert.equal(await ev('document.querySelector(".cameraFilePath").textContent'), (await state()).sourcePath);
  await screenshot('camera-settings');
  await key('Escape'); await until('!__ldtk.classes["ui.Modal"].hasAnyOpen()', 'Escape did not close setup dialog');
  assert.equal((await state()).enabled, true);
  await call('setFlags', {zen: true}); await settled();
  assert.equal((await state()).enabled, true); assert.equal((await state()).visible, true);
  await screenshot('zen-camera-preview');
  win.setSize(1000, 720); await delay(250); await settled();
  const bounds = await ev(`(()=>{const r=document.querySelector('#cameraPreviewControls').getBoundingClientRect();return {left:r.left,top:r.top,right:r.right,bottom:r.bottom,w:innerWidth,h:innerHeight}})()`);
  assert.ok(bounds.left >= 0 && bounds.top >= 0 && bounds.right <= bounds.w + 1 && bounds.bottom <= bounds.h + 1, 'Preview controls do not fit in a smaller window');
  await screenshot('small-window-zen');
  await move(480, 288); await key('Escape'); s = await state();
  assert.equal(s.enabled, false); assert.equal(s.flags.zen, true);
  await call('setFlags', {zen: false}); win.setSize(1600, 1000); await delay(200); await ev('cameraPreviewFixture.editor().camera.fit(true)'); await settled();
  await pass('Setup path is accurate, modal Escape keeps preview open, and preview remains usable in Zen and a smaller window');

  await call('selectTerrain'); await settled();
  const editableBefore = await call('serial');
  await click(await move(400, 192));
  const painted = await call('serial');
  assert.notEqual(painted.json, editableBefore.json, 'Normal painting did not resume after preview closed');
  await key('z', [primaryModifier]);
  const undone = await call('serial');
  if (undone.json !== editableBefore.json) {
    fs.writeFileSync(path.join(output, 'undo-before.json'), JSON.stringify(editableBefore, null, 2));
    fs.writeFileSync(path.join(output, 'undo-painted.json'), JSON.stringify(painted, null, 2));
    fs.writeFileSync(path.join(output, 'undo-after.json'), JSON.stringify(undone, null, 2));
  }
  assert.deepEqual(undone, editableBefore, 'Undo after preview did not restore the paint and its history');
  assert.deepEqual(await call('flags'), initialFlags);
  await pass('Closing preview restores native painting and its ordinary Undo behavior');

  await clickSelector('#editingOptions li.cameraPreview');
  await ev('cameraPreviewFixture.preview().setPinned(true)');
  const empty = await call('emptyProject', path.join(tmp, 'empty-camera-level.ldtk'));
  await delay(250); await ev('__ldtk.classes["ui.Modal"].closeAll()'); await settled();
  assert.equal(empty.layers, 0); s = await state();
  assert.equal(s.enabled, false); assert.equal(s.profile, null); assert.equal(s.pinned, false); assert.equal(s.guide, false);
  assert.notEqual(s.sourcePath, path.join(tmp, 'camera-preview.ldtk-camera.json'));
  await clickSelector('#editingOptions li.cameraPreview'); await writeProfile();
  await until('cameraPreviewFixture.stats().profile?.width === 320', 'Empty-layer project did not load camera');
  await move(480, 288); s = await settled(); assert.equal(s.visible, true); assert.equal(s.layer, null);
  const emptyBefore = await call('serial');
  await clickSelector('#cameraPreviewControls .cameraGuideGrid'); await move(480, 288); await settled();
  await unchanged(emptyBefore); await pass('Opening another project clears source and interaction state; zero-layer levels support preview and safe guide fallback');

  await writeProfile({orthographicSize: 5000000, aspect: 1, pixelsPerUnit: 1});
  await until('cameraPreviewFixture.stats().profile?.height === 10000000', 'Large camera profile did not load');
  s = await settled(); assert.ok(s.gridLines <= 400); assert.equal(s.visible, true);
  await writeProfile({orthographicSize: 0.000001, aspect: 1, pixelsPerUnit: 1});
  await until('cameraPreviewFixture.stats().profile?.height < 0.001', 'Tiny camera profile did not load');
  s = await settled(); assert.equal(s.gridLines, 0); assert.equal(s.visible, true);
  await unchanged(emptyBefore); await pass('Huge camera bounds and tiny cell spacing keep grid rendering bounded without changing level data');

  await call('write', JSON.stringify(await call('profile', {orthographicSize: 1e-320, aspect: 1, pixelsPerUnit: 1})));
  await until('cameraPreviewFixture.stats().profile?.orthographicSize < 1e-300 && !!cameraPreviewFixture.stats().renderError', 'Extreme projection did not reach the safe rendering error state');
  s = await settled(); assert.equal(s.visible, false); assert.match(s.status, /cannot be displayed/i);
  assert.equal(await ev('__ldtk.App.ME.curPageProcess.__class__.__name__'), 'page.Editor');
  await writeProfile(); await until('cameraPreviewFixture.stats().profile?.height === 180', 'Extreme numeric snapshot did not recover');
  await unchanged(emptyBefore); await pass('An extreme finite projection cannot crash the editor and recovers on the next valid snapshot');

  await screenshot('success');
  fs.writeFileSync(path.join(output, 'results.json'), JSON.stringify({status: 'passed', passed, platform: process.platform, electron: process.versions.electron}, null, 2));
  console.log('SUCCESS: ' + passed.length + ' camera-preview scenarios passed');
  clearTimeout(timer); app.exit(0);
}

require('../assets/main.js');
