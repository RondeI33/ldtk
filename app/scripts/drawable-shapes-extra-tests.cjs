'use strict';

const assert = require('node:assert/strict');
const path = require('node:path');

// Native gestures exercise layer/level coordinate conversion and transaction
// ownership. Fixture APIs only arrange the map and observe persisted state.
module.exports = async function ({win, ev, call, delay, pass, frame, until, tmp}) {
  const C = '__ldtk.classes';
  const ED = 'shapeFixture.editor()';
  const state = () => call('state');
  const processFrame = () => win.webContents.executeJavaScript(`new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(Error('Editor frame did not finish')), 10000);
    const P = __ldtk.classes['dn.Process'];
    P.callAtTheBeginningOfNextFrame(() => P.callAtTheEndOfCurrentFrame(() => { clearTimeout(timer); resolve(true); }));
  })`, true);

  win.show(); win.focus(); win.webContents.focus();
  await ev(`(() => {
    window.shapeExtraMouse = {sequence: 0};
    document.addEventListener('mousemove', e => {
      shapeExtraMouse = {sequence: shapeExtraMouse.sequence + 1, x: e.clientX, y: e.clientY};
    }, true);
    return true;
  })()`);

  const nativeMove = async p => {
    const sequence = await ev('shapeExtraMouse.sequence');
    win.webContents.sendInputEvent({type: 'mouseMove', ...p});
    await until(`shapeExtraMouse.sequence > ${sequence} && shapeExtraMouse.x === ${p.x} && shapeExtraMouse.y === ${p.y}`, 'resize mouse delivery');
    await processFrame();
  };
  const move = async (x, y) => {
    const p = await call('screen', x, y);
    assert.equal(await ev(`document.elementFromPoint(${p.x}, ${p.y})?.id`), 'webgl', 'Gesture is covered by editor UI');
    await nativeMove({x: p.x + 1, y: p.y});
    await nativeMove(p);
    return p;
  };
  const down = async p => {
    win.webContents.sendInputEvent({type: 'mouseDown', ...p, button: 'left', clickCount: 1});
    await processFrame();
  };
  const up = async p => {
    win.webContents.sendInputEvent({type: 'mouseUp', ...p, button: 'left', clickCount: 1});
    await processFrame(); await processFrame();
  };
  const escape = async () => {
    win.webContents.sendInputEvent({type: 'keyDown', keyCode: 'Escape'});
    win.webContents.sendInputEvent({type: 'keyUp', keyCode: 'Escape'});
    await processFrame(); await processFrame();
  };
  let sequence = 0;
  const setup = async (scaled = false) => {
    await call('setup', path.join(tmp, 'extra-' + (++sequence) + '.ldtk'), {offsets: true});
    await processFrame(); await processFrame();
    await ev(`${C}['ui.Modal'].closeAll()`);
    if (scaled) await ev(`(() => {
      const e = ${ED}, li = e.get_curLayerInstance(), ld = li.get_def();
      ld.parallaxScaling = true; ld.parallaxFactorX = 0.5; ld.parallaxFactorY = 0.5;
      e.levelRender.invalidateLayer(li); e.selectionTool.invalidateRender(); return true;
    })()`);
    await processFrame();
  };
  const select = async index => {
    await call('select', index); await processFrame(); await processFrame();
    await until(`!!${ED}.resizeTool`, 'native resize handles');
  };
  const handle = (index, side) => ev(`(() => {
    const ei = shapeFixture.entity(${index}), li = ei._li, scale = li.get_def().getScale();
    const x = li.get_pxParallaxX() + ei.get_left() * scale;
    const y = li.get_pxParallaxY() + ei.get_top() * scale;
    return ${JSON.stringify(side)} === 'right'
      ? {x: x + ei.get_width() * scale + 5, y: y + ei.get_height() * scale / 2, scale}
      : {x: x + ei.get_width() * scale / 2, y: y + ei.get_height() * scale + 5, scale};
  })()`);
  const beginResize = async (index, side, amount) => {
    const h = await handle(index, side);
    let p = await move(h.x, h.y); await down(p);
    await until(`!!${ED}.resizeTool && ${ED}.resizeTool.isRunning()`, 'resize drag start');
    p = await move(h.x + (side === 'right' ? amount * h.scale : 0), h.y + (side === 'bottom' ? amount * h.scale : 0));
    return p;
  };
  const noSuppression = () => ev(`Object.keys(${C}['display.EntityRender'].suppressedShapes.h).length === 0`);

  // Both instance offsets and parallax scaling must be accounted for by the
  // handle, pointer conversion, preview and committed native bounds.
  await setup(true); await select(0);
  let before = await state();
  let p = await beginResize(0, 'right', 32);
  assert.deepEqual((await state()).entities, before.entities, 'Held resize wrote through its preview');
  assert.equal((await state()).history, before.history);
  assert.equal(await ev(`${ED}.resizeTool.shapeError`), null);
  await up(p);
  let after = await state(), resized = after.entities[0];
  assert.equal(resized.iid, before.entities[0].iid);
  assert.equal(resized.left, 64); assert.equal(resized.top, 64);
  assert.equal(resized.width, 80); assert.equal(resized.height, 48);
  assert.deepEqual(resized.shape.cells, [0,0,0,1,0,2,1,2,2,2,3,2,4,2]);
  assert.equal(after.history, before.history + 1);
  assert.equal(after.entities.length, before.entities.length);
  assert.deepEqual(after.entities.slice(1), before.entities.slice(1));
  assert.equal(await noSuppression(), true);
  const committed = after.entities;
  assert.equal(await call('undo'), true); await processFrame(); await processFrame();
  assert.deepEqual((await state()).entities, before.entities);
  assert.equal(await call('redo'), true); await processFrame(); await processFrame();
  assert.deepEqual((await state()).entities, committed);
  await pass('Native resize handles respect layer offsets and scaling, preserve the mask and IID, and commit one reversible transaction');

  await select(0); before = await state(); p = await beginResize(0, 'bottom', 32);
  assert.deepEqual((await state()).entities, before.entities);
  await escape(); await up(p);
  after = await state();
  assert.deepEqual(after.entities, before.entities); assert.equal(after.history, before.history);
  assert.equal(await noSuppression(), true);
  await pass('Escape during a native shape resize restores the original drawing, native fields and history');

  // Switching context while the mouse is held must not save a source candidate
  // into the destination level's timeline or leave the source hidden.
  await select(0); before = await state();
  const sourceHistory = await ev(`${ED}.levelTimelines.h[shapeFixture.levels[0]].curStateIdx`);
  p = await beginResize(0, 'right', 32);
  await ev(`${ED}.selectLevel(shapeFixture.level(1))`); await processFrame(); await processFrame();
  await up(p); after = await state();
  assert.equal(await ev(`${ED}.curLevelId`), await ev('shapeFixture.levels[1]'));
  assert.deepEqual(after.entities, before.entities);
  assert.equal(await ev(`${ED}.levelTimelines.h[shapeFixture.levels[0]].curStateIdx`), sourceHistory);
  assert.equal(await ev(`${ED}.levelTimelines.h[shapeFixture.levels[1]].curStateIdx`), 0);
  assert.equal(await noSuppression(), true);
  await pass('Changing levels during a held resize cancels the preview without mutating either level or its undo timeline');

  await setup();
  await ev(`(() => { const S = ${C}['data.DrawableShape'], ei = shapeFixture.entity(1); S.set(ei, 'ShapeMode', 'Custom'); S.set(ei, 'ShapePreset', 'Custom'); return true; })()`);
  await select(1); before = await state(); p = await beginResize(1, 'right', -80);
  assert.match(await ev(`${ED}.resizeTool.shapeError`), /hole|topolog|connect/i);
  assert.deepEqual((await state()).entities, before.entities);
  await up(p); after = await state();
  assert.deepEqual(after.entities, before.entities); assert.equal(after.history, before.history);
  assert.equal(await noSuppression(), true);
  await pass('A native custom-ring resize that would collapse its hole is rejected atomically');

  await setup(); await select(0);
  await ev(`(() => {
    const e = ${ED}; window.offsetShapeTemplate = e.selectionTool.group.toSelectionTemplate('Offset shape');
    e.setSpecialTool(new ${C}['tool.SelectionTemplateTool'](offsetShapeTemplate)); return true;
  })()`);
  await processFrame(); before = await state();
  p = await move(440, 328);
  const deliveredOrigin = await ev(`(() => {
    const c = new ${C}['misc.Coords'](${p.x}, ${p.y}); return {x: c.get_levelX(), y: c.get_levelY()};
  })()`);
  assert.equal(await ev(`${ED}.specialTool.debugGhostStats().appliesSettings`), false);
  await down(p); await up(p); after = await state();
  const placed = after.entities.find(e => !before.entities.some(old => old.iid === e.iid));
  assert(placed, 'Template did not create a fresh shape');
  assert.equal(after.entities.length, before.entities.length + 1);
  assert.deepEqual(placed.shape, before.entities[0].shape);
  assert.equal(placed.left + 8, deliveredOrigin.x); assert.equal(placed.top + 24, deliveredOrigin.y);
  assert.equal(after.history, before.history + 1);
  assert.deepEqual(after.entities.filter(e => e.iid !== placed.iid), before.entities);
  assert.equal(await call('undo'), true); await processFrame(); await processFrame();
  assert.deepEqual((await state()).entities, before.entities);
  await pass('A captured shape template places its visible origin at the native cursor with nonzero layer offsets and undoes as one entity');

  // Send HTML5 events through the actual draggable Place button and the canvas
  // document listeners, including a shared browser DataTransfer object.
  await setup(); await select(0);
  await ev(`(() => {
    const e = ${ED}, S = ${C}['data.DrawableShape'], source = shapeFixture.entity(0);
    ${C}['ui.DrawableShapeEditor'].commit(source, () => {
      S.set(source, 'Damage', 91); S.set(source, 'Color', '#22BBCC'); return null;
    });
    const tpl = e.selectionTool.group.toSelectionTemplate('Dragged hazard configuration');
    if (!${C}['data.SelectionTemplates'].put(e.project, tpl)) throw Error('Could not save fixture configuration');
    new ${C}['ui.modal.panel.SelectionTemplatesPanel'](); return true;
  })()`);
  await processFrame(); await processFrame();
  await until('!!document.querySelector(".selectionTemplatesBody button[draggable=true]")', 'draggable saved configuration');
  const targetPoint = await call('screen', 272, 96); // Ring's first occupied cell plus its layer offsets.
  before = await state();
  const draggedId = await ev(`(() => {
    const button = document.querySelector('.selectionTemplatesBody button[draggable=true]');
    window.shapeDragButton = button; window.shapeDragTransfer = new DataTransfer();
    const r = button.getBoundingClientRect();
    button.dispatchEvent(new DragEvent('dragstart', {bubbles: true, cancelable: true, dataTransfer: shapeDragTransfer, clientX: r.left + r.width/2, clientY: r.top + r.height/2}));
    document.querySelector('#webgl').dispatchEvent(new DragEvent('dragover', {bubbles: true, cancelable: true, dataTransfer: shapeDragTransfer, clientX: ${targetPoint.x}, clientY: ${targetPoint.y}}));
    return shapeDragTransfer.getData('application/x-ldtk-selection-template');
  })()`);
  assert(draggedId, 'Place button did not attach its saved-template drag type');
  await processFrame();
  assert.equal(await ev(`${ED}.specialTool.debugGhostStats().appliesSettings`), true);
  assert.deepEqual((await state()).entities, before.entities, 'HTML drag hover committed settings prematurely');
  await ev(`(() => {
    document.querySelector('#webgl').dispatchEvent(new DragEvent('drop', {bubbles: true, cancelable: true, dataTransfer: shapeDragTransfer, clientX: ${targetPoint.x}, clientY: ${targetPoint.y}}));
    shapeDragButton.dispatchEvent(new DragEvent('dragend', {bubbles: true, dataTransfer: shapeDragTransfer}));
    return true;
  })()`);
  await processFrame(); await processFrame(); after = await state();
  assert.equal(after.entities.length, before.entities.length);
  assert.equal(after.entities[1].iid, before.entities[1].iid);
  assert.deepEqual(after.entities[1].shape.cells, before.entities[1].shape.cells);
  assert.equal(after.entities[1].left, before.entities[1].left);
  assert.equal(after.entities[1].top, before.entities[1].top);
  assert.equal(after.entities[1].fields.Damage, 91); assert.equal(after.entities[1].fields.Color, '#22BBCC');
  assert.equal(after.history, before.history + 1);
  assert.deepEqual(after.entities.filter((_, i) => i !== 1), before.entities.filter((_, i) => i !== 1));
  assert.equal(await call('undo'), true); await processFrame(); await processFrame();
  assert.deepEqual((await state()).entities, before.entities);
  await pass('HTML5 Place-button drag, hover and drop apply saved settings once through real UI handlers while preserving target geometry and ownership');

  await setup();
  const activateBrush = () => ev(`(() => {
    const ei = shapeFixture.entity(0); ${C}['ui.DrawableShapeEditor'].activate(ei.get_def(), ei, 'Paint'); return true;
  })()`);
  await activateBrush(); await processFrame(); before = await state();
  p = await move(80, 96); await down(p); p = await move(0, 96);
  assert.match(await ev(`${ED}.specialTool.candidateError`), /outside.*level/i);
  await up(p); after = await state();
  assert.deepEqual(after.entities, before.entities); assert.equal(after.history, before.history);
  await ev('shapeFixture.entity(0).get_def().allowOutOfBounds = true');
  await activateBrush(); await processFrame();
  p = await move(80, 96); await down(p); p = await move(0, 96); await up(p); after = await state();
  assert.equal(after.entities[0].iid, before.entities[0].iid);
  assert.equal(after.entities[0].left + 8, -8);
  assert.equal(after.entities[0].top, before.entities[0].top);
  assert.equal(after.entities[0].shape.error, null);
  assert.deepEqual(after.entities.slice(1), before.entities.slice(1));
  assert.equal(after.history, before.history + 1);
  await pass('Brush bounds use exported layer offsets: out-of-level cells reject the complete stroke unless the native entity definition permits them');
};
