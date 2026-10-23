'use strict';
const assert = require('node:assert/strict');
const path = require('node:path');

// Real Electron DOM/layout regression: the drawable toolbar must never own the
// list's flex space, and entity entries must remain scrollable and selectable.
module.exports = async ({win,ev,call,frame,until,pass,tmp}) => {
  await call('setup', path.join(tmp, 'palette-overflow.ldtk'));
  await until('!!document.querySelector("#mainPaletteWrapper .palette.entities .drawableShapePalette")', 'drawable entity palette');

  // A long palette catches cases where an unscrollable 24px row hides entities.
  const count = await ev(`(()=>{
    const e=shapeFixture.editor(),p=e.project;
    for(let i=0;i<36;i++){
      const ed=p.defs.createEntityDef();
      ed.set_identifier('PaletteScrollTest'+String(i).padStart(2,'0'));
      ed.width=ed.height=16;
    }
    e.get_curTool().palette.render();
    return document.querySelectorAll('#mainPaletteWrapper .palette.entities > ul.niceList li.entity').length;
  })()`);
  assert(count >= 39, 'Expected populated entity palette for scroll regression');

  const measure = () => ev(`(()=>{
    const root=document.querySelector('#mainPaletteWrapper .palette.entities'),
          bar=root.querySelector(':scope > .bar'),
          shape=root.querySelector(':scope > .drawableShapePalette'),
          list=root.querySelector(':scope > ul.niceList'),
          panel=document.querySelector('#mainPanel');
    const b=el=>{const r=el.getBoundingClientRect();return {top:r.top,bottom:r.bottom,height:r.height};};
    return {shapeVisible:!!shape,shapeActive:root.classList.contains('withDrawableShape'),
      bar:b(bar),shape:shape?b(shape):null,list:b(list),panel:b(panel),
      listClient:list.clientHeight,listScroll:list.scrollHeight,
      rowSizes:getComputedStyle(root).gridTemplateRows};
  })()`);
  const check = async (label,minHeight) => {
    await frame();
    const m=await measure();
    assert.equal(m.shapeVisible,true, label+': toolbar absent');
    assert.equal(m.shapeActive,true,label+': three-row layout class missing');
    assert(m.shape.top >= m.bar.bottom-2,label+': toolbar overlaps search');
    assert(m.list.top >= m.shape.bottom-3,label+': entity list overlaps shape toolbar');
    assert(m.list.bottom <= m.panel.bottom+2,label+': entity list clipped beneath panel');
    assert(m.listClient >= minHeight,label+': list has insufficient usable height: '+JSON.stringify(m));
    assert(m.listScroll > m.listClient+80,label+': long entity list should scroll: '+JSON.stringify(m));
    const scrolled = await ev(`(()=>{const list=document.querySelector('#mainPaletteWrapper .palette.entities > ul.niceList');
      list.scrollTop=list.scrollHeight;return list.scrollTop;})()`);
    assert(scrolled>80,label+': unable to scroll to bottom of entity list');
    await pass(label);
  };

  // Use a small editor window close to the screenshot's logical dimensions.
  win.setSize(1100,700);
  await frame(); await check('Drawable shape does not cover scrollable entity list at 700px window height',80);
  win.setSize(1100,900);
  await frame(); await check('Drawable shape leaves entity list scrollable after window resize',150);

  // Select a non-drawable entity from the list; verify the toolbar disappears
  // and the palette returns to its normal layout. Then reselect the shape.
  const ordinaryUid=await ev('shapeFixture.defs.ordinary');
  const hazardUid=await ev('shapeFixture.defs.hazard');
  const select = uid => ev(`(()=>{
    const entry=document.querySelector('#mainPaletteWrapper .palette.entities [data-def-uid="'+${JSON.stringify(uid)}+'"]')
        || document.querySelector('#mainPaletteWrapper .palette.entities [data-defUid="'+${JSON.stringify(uid)}+'"]');
    if(!entry)throw Error('Entity entry missing for '+${JSON.stringify(uid)});
    entry.scrollIntoView({block:'nearest'});
    entry.dispatchEvent(new MouseEvent('mousedown',{bubbles:true,button:0}));
    return true;
  })()`);
  await select(ordinaryUid);
  await frame();
  assert.equal(await ev('shapeFixture.editor().get_curTool().getSelectedValue()'),ordinaryUid);
  assert.equal(await ev('!!document.querySelector("#mainPaletteWrapper .palette.entities .drawableShapePalette")'),false);
  await pass('Selecting an ordinary entity removes drawable shape controls and retains its palette list');

  await select(hazardUid);
  await frame();
  assert.equal(await ev('shapeFixture.editor().get_curTool().getSelectedValue()'),hazardUid);
  assert.equal(await ev('!!document.querySelector("#mainPaletteWrapper .palette.entities.withDrawableShape .drawableShapePalette")'),true);
  await check('Switching back to drawable entity restores layout and scrolling',150);
  win.setSize(1400,900);
};
