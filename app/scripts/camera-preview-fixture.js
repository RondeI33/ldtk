(() => {
  const H = __ldtk, C = H.classes, E = H.enums;
  const fs = require('fs'), Coords = C['misc.Coords'];
  const F = window.cameraPreviewFixture = {};
  F.editor = () => {
    const e = H.App.ME.curPageProcess;
    if (e && e.project && !e.destroyed) H.Editor.ME = e;
    return H.Editor.ME;
  };
  F.level = () => F.editor().get_curLevel();
  F.preview = () => F.editor().cameraPreview;
  F.profile = values => ({
    schemaVersion: 1, source: 'unity', valid: true, orthographic: true,
    orthographicSize: 5.625, aspect: 16 / 9, pixelsPerUnit: 16,
    sceneName: '04_research', scenePath: 'Assets/Scenes/04_research.unity',
    cameraName: 'Main Camera', updatedAtUtc: new Date().toISOString(), live: false,
    ...values,
  });
  F.loadEditor = p => {
    H.App.ME.clearCurPage();
    C['dn.Process'].forceProcessGarbageCollection();
    H.App.ME.loadPage(() => new H.Editor(p), false);
    const e = F.editor();
    e.setWorldMode(false);
    e.selectLevel(p.worlds[0].levels[0]);
    if (p.defs.layers.length) e.selectLayerInstance(e.get_curLevel().getLayerInstance(F.terrain));
    e.camera.fit(true);
    H.EntityTool.PREV_CHAINABLE_EI = null;
    if (e.get_curLayerInstance()) e.get_curTool().selectValue(1);
    e.needSaving = false;
    return true;
  };
  F.setup = file => {
    H.App.ME.settings.v.openLastProject = false;
    H.App.ME.settings.v.zenMode = false;
    H.App.ME.settings.v.singleLayerMode = false;
    const p = H.Project.createEmpty(file);
    p.bgColor = 0x111b2a;
    const ld = p.defs.createLayerDef(E['ldtk.LayerType'].IntGrid, 'Terrain');
    ld.gridSize = 16;
    ld.intGridValues = [
      {value: 1, identifier: 'Metal', color: 0x607a91, tile: null, groupUid: 0},
      {value: 2, identifier: 'Light', color: 0x6fd5ce, tile: null, groupUid: 0},
    ];
    const entities = p.defs.createLayerDef(E['ldtk.LayerType'].Entities, 'Objects');
    entities.gridSize = 16;
    const untouched = p.defs.createLayerDef(E['ldtk.LayerType'].IntGrid, 'Untouched');
    untouched.gridSize = 16;
    untouched.intGridValues = [{value: 1, identifier: 'Keep', color: 0x39504a, tile: null, groupUid: 0}];
    const ed = p.defs.createEntityDef();
    ed.set_identifier('CameraTestObject'); ed.width = 32; ed.height = 48; ed.setPivot(0.5, 0.5); ed.color = 0xe6af63;
    const path = ed.createFieldDef(p, E['ldtk.FieldType'].F_Point, 'Path', true);
    path.editorDisplayMode = E['ldtk.FieldDisplayMode'].PointPath;
    path.editorAlwaysShow = true;
    const level = p.worlds[0].levels[0];
    level.set_identifier('CameraPreview'); level.pxWid = 960; level.pxHei = 576;
    const next = p.worlds[0].createLevel();
    next.set_identifier('SecondRoom'); next.pxWid = 640; next.pxHei = 384; next.worldX = 1024; next.worldY = 80;
    p.tidy();
    const li = level.getLayerInstance(ld.uid);
    for (let cy = 0; cy < 36; cy++) {
      for (let cx = 0; cx < 60; cx++) {
        const wall = cx < 2 || cx > 57 || cy < 2 || cy > 33;
        const platform = cy === 16 && cx >= 8 && cx <= 22 || cy === 25 && cx >= 32 && cx <= 46;
        const pillar = (cx === 8 || cx === 48) && cy > 18;
        if (wall || platform || pillar) li.setIntGrid(cx, cy, cy === 2 || platform ? 2 : 1, false);
      }
    }
    for (const pt of [[20, 9], [37, 19], [49, 8]]) li.setIntGrid(pt[0], pt[1], 2, false);
    level.getLayerInstance(untouched.uid).setIntGrid(40, 30, 1, false);
    const ei = level.getLayerInstance(entities.uid).createEntityInstance(ed);
    ei.x = 512; ei.y = 288; ei.tidy(p, ei._li);
    const fi = ei.getFieldInstance(path, true);
    fi.addArrayValue(); fi.parseValue(0, '40,20');
    p.tidy();
    // A project loaded from disk has null here; newly constructed Haxe instances
    // leave it undefined until their first history round trip. Seed the fixture
    // like a real loaded project so Undo can be compared byte for byte.
    for (const world of p.worlds) for (const room of world.levels)
      for (const layer of room.layerInstances) layer.setOverrideTileset(null);
    Object.assign(F, {file, terrain: ld.uid, objects: entities.uid, sentinel: untouched.uid,
      iid: ei.iid, entityDef: ed.uid, field: path.uid, firstLevel: level.uid, secondLevel: next.uid});
    fs.writeFileSync(file, JSON.stringify(p.toJson()));
    fs.writeFileSync(file + '-fork.json', JSON.stringify({format: 1, projectIid: p.iid, futureMetadata: {keep: [1, 2, 3]}, entities: {}}));
    p.forkConfig.load();
    F.loadEditor(p);
    const e = F.editor();
    li.setIntGrid(4, 4, 1, false);
    e.ge.emit(E.GlobalEvent.LayerInstanceChangedGlobally(li));
    e.ensureLevelTimeline(level).saveLayerState(li);
    e.needSaving = false;
    return {terrain: ld.uid, objects: entities.uid, iid: ei.iid};
  };
  F.write = (value, force = false) => {
    const target = F.preview().getSourcePath();
    const raw = typeof value === 'string' ? value : JSON.stringify(value);
    const temporary = target + '.tmp';
    fs.writeFileSync(temporary, raw);
    fs.renameSync(temporary, target);
    if (force) F.preview().refreshSource(true);
    return target;
  };
  F.removeSource = () => {
    const target = F.preview().getSourcePath();
    if (fs.existsSync(target)) fs.unlinkSync(target);
    return true;
  };
  F.screen = (x, y) => {
    const c = Coords.fromLevelCoords(x, y);
    return {x: Math.round(c.pageX), y: Math.round(c.pageY)};
  };
  F.setPoint = (x, y) => {
    const p = F.preview();
    p.setPinned(false);
    p.moveTo(Coords.fromLevelCoords(x, y));
    return true;
  };
  F.entity = () => F.editor().project.getEntityInstanceByIid(F.iid);
  F.selectEntity = () => {
    const e = F.editor(), ei = F.entity();
    e.selectLayerInstance(ei._li);
    e.selectionTool.select([E.GenericLevelElement.Entity(ei._li, ei)]);
    return true;
  };
  F.selectTerrain = () => {
    const e = F.editor();
    e.selectionTool.clear();
    e.selectLayerInstance(F.level().getLayerInstance(F.terrain));
    e.get_curTool().selectValue(1);
    return true;
  };
  F.history = () => Object.fromEntries(Object.entries(F.editor().levelTimelines.h).map(([key, value]) => [key, value.curStateIdx]));
  F.serial = () => ({json: JSON.stringify(F.editor().project.toJson()), history: F.history(), dirty: F.editor().needSaving});
  F.flags = () => ({
    zen: H.App.ME.settings.v.zenMode, single: H.App.ME.settings.v.singleLayerMode,
    details: H.App.ME.settings.v.showDetails, grid: H.App.ME.settings.v.grid,
    variables: F.editor().showVariablePreviews, auto: F.editor().levelRender.isAutoLayerRenderingEnabled(),
  });
  F.stats = () => {
    const e = F.editor(), p = F.preview(), camera = e.camera, layer = e.get_curLayerInstance();
    const result = {
      enabled: p.enabled, active: p.isActive(), placing: p.isPlacing(), pinned: p.pinned, gridMode: p.gridMode, guide: p.useGuideGrid,
      profile: p.profile, frame: p.frame, error: p.sourceError, renderError: p.renderError, stale: p.sourceStale,
      visible: p.root.visible, gridLines: p.drawnGridLines, point: {x: p.pointX, y: p.pointY},
      dirty: e.needSaving, history: F.history(), selection: e.selectionTool.any(),
      running: e.selectionTool.isRunning() || e.get_curTool().isRunning(),
      banner: !!document.querySelector('.smartiveDiskChange'),
      mode: e.worldMode, level: e.curLevelId, layer: layer && layer.layerDefUid,
      status: document.querySelector('.cameraSource').textContent,
       lockStatus: document.querySelector('.cameraLockStatus').textContent,
       sprite: (() => { const e=document.querySelector('.cameraJoshuaSprite'); const r=e.getBoundingClientRect(); return {src:e.getAttribute('src'),visible:getComputedStyle(e).display!=='none',pointerEvents:getComputedStyle(e).pointerEvents,x:r.x,y:r.y,width:r.width,height:r.height}; })(),
      sourcePath: p.getSourcePath(), label: {x: p.label.x, y: p.label.y, text: p.label.text},
      transform: {x: e.levelRender.root.x, y: e.levelRender.root.y, zoom: camera.get_adjustedZoom(), width: camera.get_width(), height: camera.get_height(),
        cameraX: camera.get_levelX(), cameraY: camera.get_levelY(), pixelRatio: camera.get_pixelRatio()},
      flags: F.flags(), toolbarPressed: document.querySelector('#editingOptions .cameraPreview').getAttribute('aria-pressed'),
    };
    if (layer) {
      result.guideInfo = {
        width: layer.get_def().guideGridWid, height: layer.get_def().guideGridHei,
        scale: layer.get_def().getScale(), offsetX: layer.get_pxTotalOffsetX(), offsetY: layer.get_pxTotalOffsetY(),
        parallaxX: camera.getParallaxOffsetX(layer), parallaxY: camera.getParallaxOffsetY(layer),
      };
    }
    return result;
  };
  F.configureGuide = enabled => {
    const e = F.editor(), li = F.level().getLayerInstance(F.terrain), ld = li.get_def();
    ld.guideGridWid = enabled ? 128 : 0; ld.guideGridHei = enabled ? 80 : 0;
    ld.pxOffsetX = enabled ? 8 : 0; ld.pxOffsetY = enabled ? -6 : 0;
    li.pxOffsetX = enabled ? 4 : 0; li.pxOffsetY = enabled ? 10 : 0;
    ld.parallaxFactorX = enabled ? 0.25 : 0; ld.parallaxFactorY = enabled ? 0.125 : 0;
    ld.parallaxScaling = true;
    e.ge.emit(E.GlobalEvent.LayerDefChanged(ld.uid, true));
    e.ge.emit(E.GlobalEvent.ViewportChanged(true));
    return true;
  };
  F.switchLevel = second => {
    const e = F.editor(), level = e.project.getLevelAnywhere(second ? F.secondLevel : F.firstLevel);
    e.selectLevel(level); e.camera.fit(true);
    return true;
  };
  F.emptyProject = file => {
    const p = H.Project.createEmpty(file);
    p.worlds[0].levels[0].pxWid = 960; p.worlds[0].levels[0].pxHei = 576;
    p.tidy();
    fs.writeFileSync(file, JSON.stringify(p.toJson()));
    F.loadEditor(p);
    return {layers: p.defs.layers.length, file: p.filePath.full};
  };
  F.command = name => {
    H.App.ME.executeAppCommand(E.AppCommand[name]);
    return true;
  };
  F.setFlags = values => {
    const e = F.editor();
    if ('single' in values) e.setSingleLayerMode(values.single);
    if ('details' in values) e.setShowDetails(values.details);
    if ('grid' in values) e.setGrid(values.grid);
    if ('variables' in values) e.setVariablePreviews(values.variables);
    if ('auto' in values) e.levelRender.setAutoLayerRendering(values.auto);
    if ('zen' in values) e.setZenMode(values.zen, false);
    return true;
  };
})();
