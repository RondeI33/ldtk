'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const { createRequire, Module } = require('node:module');
const { setImmediate: nextTurn } = require('node:timers/promises');
const { createDmgDetachExec, isForcedDmgDetach, isBusyDetachError, RETRY_DELAYS_MS } = require('./package-macos.cjs');

const busy = message => new Error(message || 'hdiutil: detach failed - Resource busy');
const delays = [2000, 4000, 8000, 16000];

function recorder(exec) {
  const waits = [], warnings = [];
  return {
    run: createDmgDetachExec(exec, { sleep: async ms => { waits.push(ms); }, warn: text => warnings.push(text) }),
    waits, warnings,
  };
}

test('retry budget is the fixed, immutable 2/4/8/16-second sequence', () => {
  assert.deepEqual(RETRY_DELAYS_MS, delays);
  assert.equal(Object.isFrozen(RETRY_DELAYS_MS), true);
});

test('only exact forced hdiutil detaches of disk devices are eligible', () => {
  for (const command of ['hdiutil', '/usr/bin/hdiutil'])
    for (const device of ['/dev/disk0', '/dev/disk17', '/dev/disk4s2', '/dev/disk4s2s3'])
      assert.equal(isForcedDmgDetach(command, ['detach', '-force', device]), true, `${command}: ${device}`);

  for (const [command, args] of [
    ['other-command', ['detach', '-force', '/dev/disk4']],
    ['/tmp/hdiutil', ['detach', '-force', '/dev/disk4']],
    ['hdiutil', ['detach', '-quiet', '/dev/disk4']],
    ['hdiutil', ['detach', '/dev/disk4']],
    ['hdiutil', ['detach', '-force', '/dev/disk4', '-quiet']],
    ['hdiutil', ['detach', '/dev/disk4', '-force']],
    ['hdiutil', ['attach', '-force', '/dev/disk4']],
    ['hdiutil', ['create', '-force', '/dev/disk4']],
    ['hdiutil', ['detach', '-force', '/Volumes/Installer']],
    ['hdiutil', ['detach', '-force', '/dev/rdisk4']],
    ['hdiutil', ['detach', '-force', '/dev/disk']],
    ['hdiutil', ['detach', '-force', '/dev/disk4s']],
    ['hdiutil', ['detach', '-force', '/dev/disk4/other']],
    ['hdiutil', ['detach', '-force', '/dev/disk4;echo bad']],
    ['hdiutil', ['detach', '-force', null]],
    ['hdiutil', null], ['hdiutil', undefined], ['hdiutil', 'detach -force /dev/disk4'],
  ]) assert.equal(isForcedDmgDetach(command, args), false, `${command}: ${JSON.stringify(args)}`);
});

test('busy classification accepts actual hdiutil and builder-util diagnostics only', () => {
  for (const error of [
    busy(), new Error('HDIUTIL: DEVICE OR RESOURCE BUSY'),
    new Error('Exit code: 16. Command failed: hdiutil detach -force /dev/disk4'),
    new Error('exit CODE:\n 16'),
    Object.assign(new Error('Command failed'), { stderr: 'hdiutil: detach failed - Resource busy' }),
    Object.assign(new Error('Command failed'), { code: 16 }),
  ]) assert.equal(isBusyDetachError(error), true, String(error));

  for (const error of [
    null, undefined, new Error('Operation not permitted'), new Error('Permission denied'),
    Object.assign(new Error('Command failed'), { code: 'EACCES', stderr: 'Operation not permitted' }),
    new Error('Exit code: 160'), new Error('Exit code: 116'), new Error('failed at disk16'),
    new Error('Resource busyness'), new Error('Device not configured'),
  ]) assert.equal(isBusyDetachError(error), false, String(error));
});

test('first-attempt success preserves receiver, argument identities, options and exact stdout', async () => {
  const receiver = { task: 'macOS packaging' };
  const args = Object.freeze(['detach', '-force', '/dev/disk8s1']);
  const options = Object.freeze({ cwd: '/tmp/Build with spaces', env: Object.freeze({ TEST: 'value' }) });
  const stdout = 'detached disk8s1\n\tunchanged output\n';
  let calls = 0;
  const retry = recorder(function (...received) {
    calls++;
    assert.equal(this, receiver);
    assert.deepEqual(received, ['hdiutil', args, options, false]);
    assert.equal(received[1], args); assert.equal(received[2], options);
    return Promise.resolve(stdout);
  });
  assert.equal(await retry.run.call(receiver, 'hdiutil', args, options, false), stdout);
  assert.equal(calls, 1); assert.deepEqual(retry.waits, []); assert.deepEqual(retry.warnings, []);
});

test('transient busy failures retry the same call and recover without changing stdout', async () => {
  const receiver = { id: 3 }, args = Object.freeze(['detach', '-force', '/dev/disk42']);
  const options = Object.freeze({ timeout: 5000 }), failures = [busy(), new Error('Exit code: 16')];
  const calls = [];
  const retry = recorder(async function (...received) {
    calls.push(received);
    assert.equal(this, receiver); assert.equal(received[1], args); assert.equal(received[2], options);
    if (calls.length <= failures.length) throw failures[calls.length - 1];
    return 'disk42 ejected\n';
  });
  assert.equal(await retry.run.call(receiver, '/usr/bin/hdiutil', args, options, false), 'disk42 ejected\n');
  assert.equal(calls.length, 3); assert.deepEqual(retry.waits, [2000, 4000]);
  assert.deepEqual(calls, Array.from({ length: 3 }, () => ['/usr/bin/hdiutil', args, options, false]));
  assert.equal(retry.warnings.length, 2);
  assert.match(retry.warnings[0], /disk42.*2s.*2\/5/);
  assert.match(retry.warnings[1], /disk42.*4s.*3\/5/);
});

test('the next detach attempt actually waits for its backoff promise', async () => {
  let calls = 0, release;
  const waits = [];
  const wrapper = createDmgDetachExec(async () => {
    if (++calls === 1) throw busy();
    return 'done';
  }, {
    sleep: ms => { waits.push(ms); return new Promise(resolve => { release = resolve; }); },
    warn: () => {},
  });
  const result = wrapper('hdiutil', ['detach', '-force', '/dev/disk4']);
  await nextTurn();
  assert.equal(calls, 1); assert.deepEqual(waits, [2000]);
  release();
  assert.equal(await result, 'done'); assert.equal(calls, 2);
});

test('exhaustion makes exactly five attempts and rethrows the final original error', async () => {
  const failures = Array.from({ length: 5 }, (_, i) => busy(`Resource busy on attempt ${i + 1}`));
  let calls = 0;
  const retry = recorder(async () => { throw failures[calls++]; });
  await assert.rejects(retry.run('hdiutil', ['detach', '-force', '/dev/disk9']), error => error === failures[4]);
  assert.equal(calls, 5); assert.deepEqual(retry.waits, delays); assert.equal(retry.warnings.length, 4);
  assert.match(retry.warnings[3], /16s.*5\/5/);
});

test('permission and unrelated errors fail immediately with their original identity', async t => {
  for (const error of [
    Object.assign(new Error('Operation not permitted'), { code: 'EPERM' }),
    new Error('Exit code: 1\nhdiutil: detach failed - Permission denied'),
    Object.assign(new Error('spawn hdiutil ENOENT'), { code: 'ENOENT' }),
    new Error('Exit code: 160'),
  ]) await t.test(error.message, async () => {
    let calls = 0;
    const retry = recorder(async () => { calls++; throw error; });
    await assert.rejects(retry.run('hdiutil', ['detach', '-force', '/dev/disk4']), found => found === error);
    assert.equal(calls, 1); assert.deepEqual(retry.waits, []); assert.deepEqual(retry.warnings, []);
  });
});

test('a non-busy failure during retries stops immediately instead of consuming the budget', async () => {
  let calls = 0;
  const denied = new Error('Operation not permitted');
  const retry = recorder(async () => { throw ++calls === 1 ? busy() : denied; });
  await assert.rejects(retry.run('hdiutil', ['detach', '-force', '/dev/disk4']), error => error === denied);
  assert.equal(calls, 2); assert.deepEqual(retry.waits, [2000]); assert.equal(retry.warnings.length, 1);
});

test('normal detach, attach, create and other commands pass through even on busy errors', async t => {
  for (const [command, args] of [
    ['hdiutil', ['detach', '-quiet', '/dev/disk4']],
    ['hdiutil', ['detach', '/dev/disk4']],
    ['hdiutil', ['attach', '-noverify', '/tmp/test.dmg']],
    ['hdiutil', ['create', '-srcfolder', '/tmp/app', '/tmp/test.dmg']],
    ['diskutil', ['detach', '-force', '/dev/disk4']],
  ]) await t.test(`${command} ${args[0]}`, async () => {
    const receiver = {}, options = {}, error = busy(), original = Promise.reject(error);
    let calls = 0;
    const retry = recorder(function (...received) {
      calls++; assert.equal(this, receiver);
      assert.deepEqual(received, [command, args, options, false]);
      assert.equal(received[1], args); assert.equal(received[2], options);
      return original;
    });
    const result = retry.run.call(receiver, command, args, options, false);
    assert.equal(result, original, 'Unrelated commands must retain the original promise');
    await assert.rejects(result, found => found === error);
    assert.equal(calls, 1); assert.deepEqual(retry.waits, []); assert.deepEqual(retry.warnings, []);
  });
});

test('synchronous pass-through return values and exceptions keep their behavior', () => {
  const stdout = { output: 'unchanged' }, error = busy();
  assert.equal(recorder(() => stdout).run('hdiutil', ['create', '/tmp/test.dmg']), stdout);
  assert.throws(() => recorder(() => { throw error; }).run('other', []), found => found === error);
});

async function withInstalledDmgUtility(exec, action) {
  const builderRequire = createRequire(require.resolve('electron-builder/package.json'));
  const appBuilderRequire = createRequire(builderRequire.resolve('app-builder-lib'));
  const dmgRequire = createRequire(appBuilderRequire.resolve('dmg-builder'));
  const builderUtil = dmgRequire('builder-util');
  // Load before replacing exec: attachAndExecute closes over its internal detach,
  // so mocking only the exported detach function would not test real cleanup.
  const targetPath = dmgRequire.resolve('./dmg'), utilityPath = dmgRequire.resolve('./dmgUtil');
  const originalTarget = require.cache[targetPath], originalUtility = require.cache[utilityPath];
  const isolateTarget = process.platform !== 'darwin' && !originalTarget;
  if (isolateTarget) {
    // Linux omits the Darwin-only dmg-license dependency of this unused export.
    // Keep the installed utility/cleanup code intact; macOS loads every real module.
    const target = new Module(targetPath);
    target.loaded = true;
    Object.defineProperty(target.exports, 'DmgTarget', { get() { throw new Error('Packaging target is not part of the attach/cleanup test'); } });
    require.cache[targetPath] = target;
  }
  let dmgUtil;
  try {
    dmgUtil = dmgRequire('./dmgUtil');
  } finally {
    if (isolateTarget) delete require.cache[targetPath];
  }
  const originalExec = Object.getOwnPropertyDescriptor(builderUtil, 'exec');
  const originalTimeout = global.setTimeout, cleanupWaits = [], retry = recorder(exec);
  builderUtil.exec = retry.run;
  global.setTimeout = function (callback, ms, ...args) {
    if (ms === 1000) {
      cleanupWaits.push(ms);
      return originalTimeout.call(this, callback, 0, ...args);
    }
    return originalTimeout.call(this, callback, ms, ...args);
  };
  try {
    return await action({ dmgUtil, builderUtil, cleanupWaits, ...retry });
  } finally {
    Object.defineProperty(builderUtil, 'exec', originalExec);
    global.setTimeout = originalTimeout;
    if (isolateTarget) {
      if (originalUtility) require.cache[utilityPath] = originalUtility;
      else delete require.cache[utilityPath];
    }
  }
}

test('installed attachAndExecute cleanup reaches the wrapper and recovers without losing the task result', async () => {
  const calls = [], result = { artifact: 'installer.dmg' }, originalTimeout = global.setTimeout;
  let forced = 0, taskCalls = 0;
  await withInstalledDmgUtility(async function (command, args) {
    calls.push({ receiver: this, command, args });
    if (args[0] === 'attach') return '/dev/disk42\tApple_partition_scheme\n/dev/disk42s1\tApple_HFS\t/Volumes/Installer';
    if (args[1] === '-quiet' || ++forced <= 2) throw busy();
    return 'disk42 ejected';
  }, async ({ dmgUtil, builderUtil, cleanupWaits, waits, warnings }) => {
    assert.equal(await dmgUtil.attachAndExecute('/tmp/My Installer.dmg', true, async () => { taskCalls++; return result; }), result);
    assert.equal(taskCalls, 1); assert.equal(forced, 3);
    assert.deepEqual(cleanupWaits, [1000]); assert.deepEqual(waits, [2000, 4000]); assert.equal(warnings.length, 2);
    assert.deepEqual(calls.map(({ command, args }) => [command, args]), [
      ['hdiutil', ['attach', '-noverify', '-noautoopen', '-readwrite', '/tmp/My Installer.dmg']],
      ['hdiutil', ['detach', '-quiet', '/dev/disk42']],
      ...Array.from({ length: 3 }, () => ['hdiutil', ['detach', '-force', '/dev/disk42']]),
    ]);
    for (const call of calls) assert.equal(call.receiver, builderUtil);
  });
  assert.equal(global.setTimeout, originalTimeout);
});

test('installed cleanup also retries after a failing task and preserves the task error', async () => {
  const taskError = new Error('DMG customization failed');
  let forced = 0;
  await withInstalledDmgUtility(async (command, args) => {
    if (args[0] === 'attach') {
      assert.deepEqual(args, ['attach', '-noverify', '-noautoopen', '/tmp/test.dmg']);
      return '/dev/disk7\tApple_HFS\t/Volumes/Installer';
    }
    if (args[1] === '-quiet' || ++forced === 1) throw busy();
    return '';
  }, async ({ dmgUtil, waits, cleanupWaits }) => {
    await assert.rejects(dmgUtil.attachAndExecute('/tmp/test.dmg', false, async () => { throw taskError; }), error => error === taskError);
    assert.equal(forced, 2); assert.deepEqual(waits, [2000]); assert.deepEqual(cleanupWaits, [1000]);
  });
});

test('installed cleanup exhausts the same bounded budget and propagates the final detach error', async () => {
  const errors = Array.from({ length: 5 }, (_, i) => busy(`Resource busy: forced cleanup ${i + 1}`));
  let forced = 0;
  await withInstalledDmgUtility(async (command, args) => {
    if (args[0] === 'attach') return '/dev/disk8\tApple_HFS\t/Volumes/Installer';
    if (args[1] === '-quiet') throw busy();
    throw errors[forced++];
  }, async ({ dmgUtil, waits, cleanupWaits, warnings }) => {
    await assert.rejects(dmgUtil.attachAndExecute('/tmp/test.dmg', false, async () => 'built'), error => error === errors[4]);
    assert.equal(forced, 5); assert.deepEqual(waits, delays); assert.deepEqual(cleanupWaits, [1000]);
    assert.equal(warnings.length, 4);
  });
});
