'use strict';

// Load and save real project files with immutable earlier editor sources. A
// successful compilation or a copy of the current parser is not this test.
const {spawnSync} = require('node:child_process');
const fs = require('node:fs'), os = require('node:os'), path = require('node:path');
const appDir = path.resolve(__dirname, '..'), repo = path.resolve(appDir, '..');
const output = path.join(appDir, 'test-results/project-compatibility');
const work = fs.mkdtempSync(path.join(os.tmpdir(), 'ldtk-project-compat-'));
const renderer = path.join(appDir, 'assets/js/renderer.js');
const baselines = [
  {id: 'smartive-1.0.37', sha: 'bb14476a0320f2fe7ffc83cddbbaf215acd21fa4', remote: 'https://github.com/RondeI33/ldtk.git'},
  {id: 'smartive-1.0.31', sha: '19d0601a8b874d9414bd0f2eef398778ec5efee5', remote: 'https://github.com/RondeI33/ldtk.git'},
  {id: 'stock-1.5.3', sha: '72c75f1abfdc28f58522b858c6a69fe4af6a9522', remote: 'https://github.com/deepnight/ldtk.git'},
];
// Stock 1.5.3 predates API changes in GetText, Modal and Heaps. Compile its
// untouched source against matching, pinned pre-release library revisions.
// A private HAXELIB_PATH prevents this test from changing the main toolchain.
const stockDependencies = [
  {id: 'deepnightLibs', sha: 'b83b9e5d5c0911ec1dc9e5807e2dd0e9199c81bc', remote: 'https://github.com/deepnight/deepnightLibs.git'},
  {id: 'castle', sha: 'e0dea2643ce30ed46ae8d55a2cc90f5af74b29c9', remote: 'https://github.com/deepnight/castle.git'},
  {id: 'heaps', sha: '1bc807195d58b75eb002ca21331c180e5e161b2d', remote: 'https://github.com/deepnight/heaps.git'},
  {id: 'hxnodejs', sha: '504066dc1ba5ad543afa5f6c3ea019f06136a82b', remote: 'https://github.com/HaxeFoundation/hxnodejs.git'},
  {id: 'electron', sha: 'e4779eeed993e232f16a477203bfa9f35662b8fd', remote: 'https://github.com/deepnight/hxelectron.git'},
  {id: 'ldtk-haxe-api', sha: '9859b4a837af0a9b0d7b7450ca3096baa417dbbe', remote: 'https://github.com/deepnight/ldtk-haxe-api.git'},
  {id: 'heaps-aseprite', sha: 'dbc81f70de7ebff4c3c02f747a6951d91af360fb', remote: 'https://github.com/AustinEast/heaps-aseprite.git'},
];
let original = null, status = 1;
const completed = [];
function run(command, args, cwd = repo, extraEnv = {}) {
  const result = spawnSync(command, args, {cwd, stdio: 'inherit', env: {...process.env, ...extraEnv}});
  if (result.error) throw result.error;
  if (result.status !== 0) throw Error(`${path.basename(command)} ${args.join(' ')} failed (exit ${result.status})`);
}
function libraryRoot(name) {
  const result = spawnSync('haxelib', ['libpath', name], {cwd: repo, encoding: 'utf8', env: process.env});
  if (result.error) throw result.error;
  const dir = result.stdout.trim();
  if (result.status !== 0 || !fs.statSync(dir).isDirectory()) throw Error(`Cannot locate installed Haxe library ${name}: ${result.stderr || result.stdout}`);
  return dir;
}
function archiveSource(source, destination, installed = repo) {
  let objectStore = installed;
  const hasObject = spawnSync('git', ['cat-file', '-e', source.sha + '^{commit}'], {cwd: objectStore, stdio: 'ignore'}).status === 0;
  if (!hasObject) {
    // Avoid mutating installed dependency working trees or changing their refs.
    objectStore = path.join(work, 'objects-' + source.id + '.git');
    run('git', ['init', '--bare', objectStore]);
    run('git', ['fetch', '--no-tags', '--depth=1', source.remote, source.sha], objectStore);
  }
  fs.mkdirSync(destination, {recursive: true});
  const archive = destination + '.tar';
  run('git', ['archive', '--format=tar', '--output=' + archive, source.sha], objectStore);
  run('tar', ['-xf', archive, '-C', destination]);
  fs.rmSync(archive);
}
function stockToolchain() {
  const registry = path.join(work, 'stock-haxelib');
  const register = (name, directory) => {
    const entry = path.join(registry, name);
    fs.mkdirSync(entry, {recursive: true});
    fs.writeFileSync(path.join(entry, '.dev'), directory);
  };
  for (const source of stockDependencies) {
    const destination = path.join(work, 'stock-dependencies', source.id);
    archiveSource(source, destination, libraryRoot(source.id));
    register(source.id, destination);
  }
  for (const name of ['ase', 'format', 'uuid']) register(name, libraryRoot(name));
  return {HAXELIB_PATH: registry};
}
function expose(file) {
  const code = fs.readFileSync(file, 'utf8');
  const marker = '\tBoot.main();';
  if (code.split(marker).length !== 2) throw Error(`Cannot locate unique renderer bootstrap in ${file}`);
  const hook = '\tglobalThis.__ldtk = {classes:$hxClasses,enums:$hxEnums,App:$hxClasses["App"],Editor:$hxClasses["page.Editor"],Project:$hxClasses["data.Project"]};\n';
  fs.writeFileSync(file, code.replace(marker, hook + marker));
  return code;
}
function native(app, dataDir, phase, reader) {
  run(require('electron'), ['--no-sandbox', path.join(__dirname, 'project-compatibility-smoke.cjs')], app, {
    LDTK_COMPAT_APP_DIR: app, LDTK_COMPAT_DATA_DIR: dataDir,
    LDTK_COMPAT_PHASE: phase, LDTK_COMPAT_READER: reader,
    LDTK_COMPAT_REPORT_DIR: output,
    LDTK_SMARTIVE_CONTROL_DIR: path.join(work, 'control-' + reader + '-' + phase),
  });
  completed.push(`${reader}/${phase}`);
}
try {
  fs.mkdirSync(output, {recursive: true});
  run('haxe', ['main.hxml']); run('haxe', ['renderer.hxml']);
  original = expose(renderer);
  const seed = path.join(work, 'projects');
  native(appDir, seed, 'write', 'current');
  for (const baseline of baselines) {
    const checkout = path.join(work, baseline.id);
    archiveSource(baseline, checkout);
    const oldApp = path.join(checkout, 'app');
    fs.symlinkSync(path.join(appDir, 'node_modules'), path.join(oldApp, 'node_modules'), process.platform === 'win32' ? 'junction' : 'dir');
    const toolchain = baseline.id === 'stock-1.5.3' ? stockToolchain() : {};
    run('haxe', ['main.hxml'], checkout, toolchain); run('haxe', ['renderer.hxml'], checkout, toolchain);
    expose(path.join(oldApp, 'assets/js/renderer.js'));
    const dataDir = path.join(work, 'data-' + baseline.id);
    fs.cpSync(seed, dataDir, {recursive: true});
    native(oldApp, dataDir, 'legacy', baseline.id);
    native(appDir, dataDir, 'verify', baseline.id);
  }
  status = 0;
  console.log('SUCCESS: 28 native compatibility cases passed across Smartive 1.0.37, 1.0.31 and stock LDtk 1.5.3');
} catch (error) {
  console.error(error.stack || error);
} finally {
  if (original !== null) fs.writeFileSync(renderer, original);
  fs.mkdirSync(output, {recursive: true});
  fs.writeFileSync(path.join(output, 'summary.json'), JSON.stringify({success: status === 0, platform: process.platform, baselines, stockDependencies, completed}, null, 2));
  fs.rmSync(work, {recursive: true, force: true});
}
process.exit(status);
