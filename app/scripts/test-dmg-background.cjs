'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const appDir = path.resolve(__dirname, '..');
const config = require(path.join(appDir, 'electron-builder.json'));

function verifyPng(file, width, height) {
  const bytes = fs.readFileSync(path.join(appDir, file));
  assert.equal(bytes.subarray(0, 8).toString('hex'), '89504e470d0a1a0a', `${file}: invalid PNG signature`);
  assert.equal(bytes.subarray(12, 16).toString('ascii'), 'IHDR', `${file}: missing IHDR`);
  assert.equal(bytes.readUInt32BE(16), width, `${file}: unexpected width`);
  assert.equal(bytes.readUInt32BE(20), height, `${file}: unexpected height`);
  assert.ok(bytes.length > 50_000, `${file}: the installer background appears to be missing artwork`);
}

const { dmg } = config;
assert.ok(dmg, 'DMG configuration must exist');
assert.equal(dmg.background, 'buildAssets/dmg-background.png');
assert.deepEqual(dmg.window, { width: 800, height: 450 });
verifyPng(dmg.background, dmg.window.width, dmg.window.height);
verifyPng('buildAssets/dmg-background@2x.png', 1600, 900);
assert.ok(Array.isArray(dmg.contents));
assert.equal(dmg.contents.length, 2, 'The DMG should contain only the app and /Applications link');
const appIcon = dmg.contents.find(item => item.type === 'file');
const applicationsLink = dmg.contents.find(item => item.type === 'link' && item.path === '/Applications');
assert.ok(appIcon, 'Missing LDtk app icon');
assert.ok(applicationsLink, 'Missing drag-to-Applications shortcut');
assert.equal(dmg.iconSize, 100);
for (const item of dmg.contents) {
  assert.ok(item.x > dmg.iconSize / 2 && item.x < dmg.window.width - dmg.iconSize / 2, 'Icon outside DMG horizontal bounds');
  assert.ok(item.y > dmg.iconSize / 2 && item.y < dmg.window.height - dmg.iconSize / 2, 'Icon outside DMG vertical bounds');
}
assert.ok(appIcon.x + dmg.iconSize < applicationsLink.x, 'DMG icons overlap');
assert.ok(appIcon.y < 330 && applicationsLink.y < 330, 'DMG icons cover the artwork title');

console.log('DMG background images and Finder icon layout: OK');
