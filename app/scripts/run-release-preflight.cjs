'use strict';

// Use the same compiled-editor regressions that gate the release. This command
// deliberately does not invoke electron-builder, create tags or publish files.
const {spawnSync} = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const appDir = path.resolve(__dirname, '..');
const repo = path.resolve(appDir, '..');
const resultDir = path.join(appDir, 'test-results', 'release-preflight');
const results = [];

function run(label, command, args, cwd = repo) {
  console.log(`\nPREFLIGHT: ${label}`);
  const started = Date.now();
  const result = spawnSync(command, args, {cwd, stdio: 'inherit', env: process.env});
  const status = result.status == null ? 1 : result.status;
  results.push({name: label, status, durationSeconds: (Date.now() - started) / 1000});
  if (result.error) throw result.error;
  if (status !== 0) throw new Error(`${label} failed (exit ${status}); packaging remains blocked`);
}

function validateReleaseMetadata() {
  const pkg = JSON.parse(fs.readFileSync(path.join(appDir, 'package.json'), 'utf8'));
  const match = /^(\d+)\.(\d+)\.(\d+)$/.exec(pkg.version);
  if (!match || +match[1] < 1 || !match.slice(1).map(Number).every(Number.isSafeInteger))
    throw new Error(`Smartive version must be stable SemVer >= 1.0.0, got ${pkg.version}`);
  const lines = fs.readFileSync(path.join(repo, 'docs', 'SMARTIVE_CHANGELOG.md'), 'utf8').split(/\r?\n/);
  const heading = lines.indexOf(`# ${pkg.version}`);
  if (heading < 0) throw new Error(`Changelog is missing '# ${pkg.version}'`);
  const notes = [];
  for (let i = heading + 1; i < lines.length && !/^# /.test(lines[i]); ++i) notes.push(lines[i]);
  if (!notes.join('\n').trim() || /TODO/i.test(notes.join('\n')))
    throw new Error(`Changelog section ${pkg.version} is empty or still contains TODO text`);
  const lockPath = path.join(appDir, 'package-lock.json');
  if (fs.existsSync(lockPath)) {
    const lock = JSON.parse(fs.readFileSync(lockPath, 'utf8'));
    if (lock.version !== pkg.version || lock.packages?.['']?.version !== pkg.version)
      throw new Error('Local package-lock version does not match package.json; use version:set/patch/minor');
  }
  console.log(`Release ${pkg.version}; LDtk JSON ${fs.readFileSync(path.join(repo, 'docs', 'version.txt'), 'utf8').trim()}`);
  return pkg.version;
}

let version = null;
let status = 1;
try {
  version = validateReleaseMetadata();
  const suites = ['path-preview', 'point', 'entity-history', 'entity-chain', 'entity-multi', 'drawable-shapes'];
  // The release runs selection/template integration on Linux and the entity
  // suites on both Linux and macOS Intel. Match that matrix here.
  if (process.platform === 'linux') suites.push('template', 'selection');
  for (const suite of suites) {
    const runner = suite === 'drawable-shapes' ? 'drawable-shape' : suite;
    run(`${suite} regressions`, process.execPath, [path.join(__dirname, `run-${runner}-tests.cjs`)], appDir);
  }
  run('PSD import runtime smoke', require('electron'), ['--no-sandbox', 'scripts/psd-import-smoke.cjs'], appDir);
  const jsonVersionPath = path.join(repo, 'docs', 'version.txt');
  const jsonVersion = fs.readFileSync(jsonVersionPath, 'utf8').trim();
  run('JSON documentation and schema generation', 'haxe', ['doc.hxml']);
  if (fs.readFileSync(jsonVersionPath, 'utf8').trim() !== jsonVersion)
    throw new Error('Documentation generation changed the LDtk JSON compatibility version');
  for (const schema of ['JSON_SCHEMA.json', 'MINIMAL_JSON_SCHEMA.json'])
    if (JSON.parse(fs.readFileSync(path.join(repo, 'docs', schema), 'utf8')).version !== jsonVersion)
      throw new Error(`${schema} version differs from the canonical LDtk JSON version`);
  run('Production main compilation', 'haxe', ['main.hxml']);
  run('Production renderer compilation', 'haxe', ['renderer.hxml']);
  status = 0;
  console.log(`\nSUCCESS: ${results.length} release preflight stages passed. No package or release was created.`);
} catch (error) {
  console.error(error.stack || error);
} finally {
  fs.mkdirSync(resultDir, {recursive: true});
  fs.writeFileSync(path.join(resultDir, 'summary.json'), JSON.stringify({version, platform: process.platform, success: status === 0, stages: results}, null, 2) + '\n');
}
process.exit(status);
