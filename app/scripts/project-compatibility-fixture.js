(() => {
  'use strict';
  const H = globalThis.__ldtk, C = H.classes, E = H.enums;
  const fs = require('node:fs');
  const F = window.projectCompatibilityFixture = {};
  F.editor = () => {
    const e = H.App.ME.curPageProcess;
    if (e && e.project && !e.destroyed) H.Editor.ME = e;
    return H.Editor.ME;
  };
  F.install = p => {
    H.App.ME.clearCurPage();
    const processClass = C['dn.Process'];
    if (typeof processClass.forceProcessGarbageCollection === 'function') processClass.forceProcessGarbageCollection();
    else processClass._garbageCollector(processClass.ROOTS); // Same cleanup API before the public wrapper existed.
    H.App.ME.loadPage(() => new H.Editor(p), false);
    const e = F.editor();
    e.setWorldMode(false);
    e.selectLevel(p.worlds[0].levels[0]);
    e.selectLayerInstance(e.get_curLevel().getLayerInstance(p.defs.layers[0].uid));
    e.camera.fit(true);
    e.needSaving = false;
  };
  F.create = (file, external, multiWorld) => {
    H.App.ME.settings.v.openLastProject = false;
    const p = H.Project.createEmpty(file), FT = E['ldtk.FieldType'];
    p.externalLevels = external;
    p.minifyJson = multiWorld;
    p.setFlag(E['ldtk.ProjectFlag'].IgnoreBackupSuggest, true);
    p.setFlag(E['ldtk.ProjectFlag'].UseMultilinesType, true);
    const objects = p.defs.createLayerDef(E['ldtk.LayerType'].Entities, 'Objects');
    const terrain = p.defs.createLayerDef(E['ldtk.LayerType'].IntGrid, 'Terrain');
    objects.gridSize = terrain.gridSize = 16;
    terrain.intGridValues = [{value: 1, identifier: 'Solid', color: 0x5b7999, tile: null, groupUid: 0}];
    const mode = p.defs.createEnumDef();
    mode.set_identifier('Mode');
    mode.values = [{id: 'Idle', color: 0, tileRect: null}, {id: 'Run', color: 0, tileRect: null}];
    const ed = p.defs.createEntityDef();
    ed.set_identifier('Joshua'); ed.width = 32; ed.height = 48; ed.setPivot(0.5, 1);
    const fields = [
      ['Health', FT.F_Int, false, '5'],
      ['Speed', FT.F_Float, false, '3.125'],
      ['Enabled', FT.F_Bool, false, 'true'],
      ['Label', FT.F_String, false, 'żółć / camera'],
      ['Description', FT.F_Text, false, 'First line\nDrugi wiersz'],
      ['Tint', FT.F_Color, false, '#45BBDD'],
      ['Anchor', FT.F_Point, false, '7,9'],
      ['Path', FT.F_Point, true, ['2,3', '9,6', '12,8']],
      ['Weights', FT.F_Int, true, ['1', '3', '5']],
      ['TexturePath', FT.F_Path, false, 'textures/example.png'],
      ['Mode', FT.F_Enum(mode.uid), false, 'Run'],
      ['From', FT.F_EntityRef, false, null],
      ['To', FT.F_EntityRef, false, null],
    ].map(([name, type, array, value]) => {
      const fd = ed.createFieldDef(p, type, name, array);
      fd.autoChainRef = name === 'To';
      fd.allowOutOfLevelRef = true;
      return {fd, value};
    });
    const first = p.worlds[0].levels[0];
    first.set_identifier('Room_A'); first.worldX = -320; first.worldY = 224;
    let second;
    if (multiWorld) {
      p.setFlag(E['ldtk.ProjectFlag'].MultiWorlds, true);
      second = p.createWorld(true).levels[0];
    } else second = p.worlds[0].createLevel();
    second.set_identifier('Room_B'); second.worldX = 480; second.worldY = -96;
    for (const l of [first, second]) { l.pxWid = 640; l.pxHei = 384; }
    p.tidy();
    const instances = [first, second].map((l, index) => {
      l.getLayerInstance(terrain.uid).setIntGrid(4 + index, 5, 1, false);
      const li = l.getLayerInstance(objects.uid), ei = li.createEntityInstance(ed);
      ei.x = 128 + index * 64; ei.y = 160; ei.tidy(p, li);
      for (const {fd, value} of fields) {
        const fi = ei.getFieldInstance(fd, true);
        if (fd.isArray) {
          for (const [i, item] of value.entries()) { fi.addArrayValue(); fi.parseValue(i, item); }
        } else if (value !== null) fi.parseValue(0, value);
      }
      return ei;
    });
    instances[0].getFieldInstance(ed.getFieldDef('To'), true).setEntityRefTo(0, instances[0], instances[1]);
    instances[1].getFieldInstance(ed.getFieldDef('From'), true).setEntityRefTo(0, instances[1], instances[0]);
    p.tidy();
    // Fork data is entirely in a sidecar, including metadata owned by other tools.
    const sidecar = {
      format: 1, projectIid: p.iid,
      cameraPreview: {origin: 'Joshua', keep: {offset: [13.5, -7.25]}},
      futureMetadata: {keep: ['unrecognized', 42]},
      entities: {[ed.uid]: {identifier: ed.identifier, autoChainBackRefs: [{chainField: 'To', backField: 'From'}], futureEntity: {keep: true}}},
      levels: {
        [first.iid]: {contentShift: {x: -8, y: 32, futureUnits: 'pixels'}, decorAnchor: {x: 19.5, y: -21.25}},
        [second.iid]: {decorAnchor: {x: 3, y: 4}},
      },
    };
    fs.writeFileSync(file + '-fork.json', JSON.stringify(sidecar, null, 2));
    p.forkConfig.load();
    for (const world of p.worlds) for (const room of world.levels)
      for (const layer of room.layerInstances) layer.setOverrideTileset(null);
    F.install(p);
    return {iid: p.iid, levels: [first.iid, second.iid], entity: ed.uid};
  };
  F.beginSave = () => {
    F.saveDone = false; F.saveError = null;
    const e = F.editor();
    for (const w of e.project.worlds) for (const l of w.levels) l.invalidateJsonCache();
    new C['ui.ProjectSaver'](e, e.project, success => {
      F.saveError = success ? null : 'ProjectSaver returned false'; F.saveDone = true;
    });
    return true;
  };
  F.beginOpen = file => {
    F.loadDone = false; F.loadError = null;
    new C['ui.ProjectLoader'](file, p => {
      try { p.tidy(); F.install(p); F.loadDone = true; }
      catch (error) { F.loadError = String(error && error.stack || error); F.loadDone = true; }
    }, error => { F.loadError = String(error); F.loadDone = true; }, true);
    return true;
  };
  F.snapshot = () => {
    const p = F.editor().project;
    for (const w of p.worlds) for (const l of w.levels) { l.invalidateJsonCache(); l.rebuildCache(); }
    return JSON.parse(C['ui.ProjectSaver'].prepareProjectSavingData(p, true).projectJsonStr);
  };
  F.shifts = () => F.editor().project.worlds.flatMap(w => w.levels.map(l => ({iid: l.iid, shift: [l.contentShiftX, l.contentShiftY]})));
  F.zeroShifts = () => {
    const p = F.editor().project;
    for (const w of p.worlds) for (const l of w.levels) { l.contentShiftX = 0; l.contentShiftY = 0; }
    p.forkConfig.save();
    return true;
  };
  F.restoreSidecar = sidecar => {
    const p = F.editor().project;
    fs.writeFileSync(p.forkConfig.getPath(), JSON.stringify(sidecar, null, 2));
    p.forkConfig.load();
    return true;
  };
  return true;
})()
