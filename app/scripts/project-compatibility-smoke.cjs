'use strict';

const {app} = require('electron');
const fs = require('node:fs'), os = require('node:os'), path = require('node:path');
const assert = require('node:assert/strict');
const {isDeepStrictEqual} = require('node:util');
const root = process.env.LDTK_COMPAT_APP_DIR;
const dataDir = process.env.LDTK_COMPAT_DATA_DIR;
const phase = process.env.LDTK_COMPAT_PHASE;
const reader = process.env.LDTK_COMPAT_READER || 'current';
const output = process.env.LDTK_COMPAT_REPORT_DIR;
if (!root || !dataDir || !output || !['write', 'legacy', 'verify'].includes(phase)) throw Error('Missing compatibility test configuration');
fs.mkdirSync(dataDir, {recursive: true}); fs.mkdirSync(output, {recursive: true});
process.chdir(root);
app.setPath('userData', fs.mkdtempSync(path.join(os.tmpdir(), 'ldtk-compat-user-')));
if (app.setAppPath) app.setAppPath(root); else app.getAppPath = () => root;
app.commandLine.appendSwitch('no-sandbox');
if (process.platform === 'linux') {
  app.commandLine.appendSwitch('use-gl', 'angle');
  app.commandLine.appendSwitch('use-angle', 'swiftshader');
}
let running = false;
const passed = [], delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const timer = setTimeout(() => { console.error(`FAIL: ${reader}/${phase} compatibility smoke timed out`); app.exit(1); }, 180000);
app.on('browser-window-created', (_, win) => {
  win.webContents.on('did-finish-load', () => {
    if (!win.webContents.getURL().endsWith('/assets/app.html') || running) return;
    running = true;
    test(win).catch(async error => {
      console.error(error.stack || error);
      try { fs.writeFileSync(path.join(output, `${reader}-${phase}-failure.png`), (await win.webContents.capturePage()).toPNG()); } catch (_) {}
      fs.writeFileSync(path.join(output, `${reader}-${phase}.json`), JSON.stringify({status: 'failed', passed, error: String(error.stack || error)}, null, 2));
      clearTimeout(timer); app.exit(1);
    });
  });
});
function canonical(json) {
  const out = JSON.parse(JSON.stringify(json));
  // External levels carry their own application header inside the cached JSON.
  // App/build versions may differ; the LDtk schema and all project data may not.
  const dropHeaders = value => {
    if (!value || typeof value !== 'object') return;
    delete value.__header__;
    for (const child of Object.values(value)) dropHeaders(child);
  };
  dropHeaders(out); delete out.appBuildId;
  if (Array.isArray(out.flags)) out.flags.sort();
  return out;
}
function compareJson(actual, expected, label) {
  if (isDeepStrictEqual(actual, expected)) return;
  const name = `${reader}-${phase}-${label}`;
  fs.writeFileSync(path.join(output, name + '-actual.json'), JSON.stringify(actual, null, 2));
  fs.writeFileSync(path.join(output, name + '-expected.json'), JSON.stringify(expected, null, 2));
  const differences = [];
  const short = value => JSON.stringify(value)?.slice(0, 160);
  const visit = (a, b, key) => {
    if (differences.length >= 12 || isDeepStrictEqual(a, b)) return;
    if (a && b && typeof a === 'object' && typeof b === 'object' && Array.isArray(a) === Array.isArray(b)) {
      if (Array.isArray(a) && a.length !== b.length) differences.push(`${key}.length: ${a.length} != ${b.length}`);
      for (const child of new Set([...Object.keys(a), ...Object.keys(b)])) visit(a[child], b[child], `${key}.${child}`);
    } else differences.push(`${key}: actual ${short(a)}; expected ${short(b)}`);
  };
  visit(actual, expected, '$');
  throw Error(`${reader}/${phase}/${label} changed project data:\n${differences.join('\n')}\nFull expected/actual JSON saved in the compatibility artifact.`);
}
function checkFiles(file) {
  const json = JSON.parse(fs.readFileSync(file, 'utf8'));
  assert.equal(json.jsonVersion, '1.5.3', 'Smartive application version leaked into jsonVersion');
  assert.equal(json.__header__.app, 'LDtk');
  assert.equal(json.__header__.fileType, 'LDtk Project JSON');
  const levels = json.worlds.length ? json.worlds.flatMap(w => w.levels) : json.levels;
  const documents = [json];
  for (const level of levels) {
    if (json.externalLevels) {
      assert.equal(level.layerInstances, null);
      assert.equal(typeof level.externalRelPath, 'string');
      documents.push(JSON.parse(fs.readFileSync(path.resolve(path.dirname(file), level.externalRelPath), 'utf8')));
    } else assert(Array.isArray(level.layerInstances));
  }
  for (const document of documents) {
    const serialized = JSON.stringify(document);
    for (const key of ['contentShift', 'cameraPreview', 'autoChainBackRefs', 'futureMetadata', 'decorAnchor'])
      assert(!serialized.includes('"' + key + '"'), `Fork-only ${key} leaked into LDtk JSON`);
  }
}
async function test(win) {
  const ev = async code => {
    const result = await win.webContents.executeJavaScript('(()=>{try{return {ok:true,value:(' + code + ')};}catch(e){return {ok:false,error:String(e&&e.stack||e)};}})()', true);
    if (!result || !result.ok) throw Error(`Renderer error (${reader}/${phase}): ${result && result.error}\n${code}`);
    return result.value;
  };
  const until = async (code, message) => {
    for (let i = 0; i < 400; i++) { const result = await ev(code); if (result) return result; await delay(40); }
    throw Error(message);
  };
  const pass = message => { passed.push(message); console.log(`PASS: ${reader}/${phase}: ${message}`); };
  await until('!!(globalThis.__ldtk && __ldtk.App.ME && document.querySelector("#page"))', 'Editor bootstrap unavailable');
  win.setSize(1280, 900); win.show(); win.focus(); win.webContents.setBackgroundThrottling(false);
  await delay(500);
  await win.webContents.executeJavaScript(fs.readFileSync(path.join(__dirname, 'project-compatibility-fixture.js'), 'utf8'), true);
  const call = (name, ...args) => ev(`projectCompatibilityFixture.${name}(${args.map(arg => JSON.stringify(arg)).join(',')})`);
  const save = async () => {
    await call('beginSave'); await until('projectCompatibilityFixture.saveDone', 'Real ProjectSaver did not finish');
    assert.equal(await ev('projectCompatibilityFixture.saveError'), null);
    await delay(60);
  };
  const open = async file => {
    await call('beginOpen', file); await until('projectCompatibilityFixture.loadDone', 'Real ProjectLoader did not finish');
    assert.equal(await ev('projectCompatibilityFixture.loadError'), null);
    await delay(60);
  };
  const variants = [
    {id: 'embedded', external: false, multiWorld: false},
    {id: 'external', external: true, multiWorld: false},
    {id: 'multiworld', external: false, multiWorld: true},
    {id: 'multiworld-external', external: true, multiWorld: true},
  ];
  for (const variant of variants) {
    const file = path.join(dataDir, variant.id + '.ldtk');
    const manifestFile = path.join(dataDir, variant.id + '.expected.json');
    if (phase === 'write') {
      const ids = await call('create', file, variant.external, variant.multiWorld);
      await save(); checkFiles(file);
      const sidecar = JSON.parse(fs.readFileSync(file + '-fork.json', 'utf8'));
      assert.deepEqual(sidecar.levels[ids.levels[0]].decorAnchor, {x: 19.5, y: -21.25});
      assert.equal(sidecar.levels[ids.levels[0]].contentShift.futureUnits, 'pixels');
      assert.deepEqual(sidecar.levels[ids.levels[1]], {decorAnchor: {x: 3, y: 4}});
      assert.deepEqual(sidecar.cameraPreview, {origin: 'Joshua', keep: {offset: [13.5, -7.25]}});
      const snapshot = canonical(await call('snapshot'));
      const expected = {ids, snapshot, sidecar, shifts: await call('shifts')};
      fs.writeFileSync(manifestFile, JSON.stringify(expected, null, 2));
      await call('zeroShifts');
      const zero = JSON.parse(fs.readFileSync(file + '-fork.json', 'utf8'));
      assert.deepEqual(zero.levels[ids.levels[0]], {contentShift: {futureUnits: 'pixels'}, decorAnchor: {x: 19.5, y: -21.25}});
      assert.deepEqual(zero.levels[ids.levels[1]], sidecar.levels[ids.levels[1]]);
      await call('restoreSidecar', sidecar); await save();
      const before = fs.readFileSync(file + '-fork.json', 'utf8');
      const mtime = fs.statSync(file + '-fork.json').mtimeMs;
      await delay(40); await save();
      assert.equal(fs.readFileSync(file + '-fork.json', 'utf8'), before);
      assert.equal(fs.statSync(file + '-fork.json').mtimeMs, mtime, 'Unchanged sidecar was rewritten');
      pass(`${variant.id}: real save keeps stock 1.5.3 schema and preserves unknown per-level metadata, including after clearing offsets`);
    } else {
      const expected = JSON.parse(fs.readFileSync(manifestFile, 'utf8'));
      checkFiles(file); await open(file);
      compareJson(canonical(await call('snapshot')), expected.snapshot, variant.id + '-open');
      if (phase === 'verify') assert.deepEqual(await call('shifts'), expected.shifts, 'Fork offsets did not survive the older editor');
      await save(); checkFiles(file);
      compareJson(JSON.parse(fs.readFileSync(file + '-fork.json', 'utf8')), expected.sidecar, variant.id + '-sidecar');
      compareJson(canonical(await call('snapshot')), expected.snapshot, variant.id + '-save');
      pass(`${variant.id}: actual ProjectLoader + ProjectSaver preserve definitions, fields, UIDs, references, terrain and sidecar`);
    }
  }
  fs.writeFileSync(path.join(output, `${reader}-${phase}.json`), JSON.stringify({status: 'passed', reader, phase, passed, platform: process.platform, electron: process.versions.electron}, null, 2));
  console.log(`SUCCESS: ${reader}/${phase}: ${passed.length} compatibility cases passed`);
  clearTimeout(timer); app.exit(0);
}
require(path.join(root, 'assets/main.js'));
