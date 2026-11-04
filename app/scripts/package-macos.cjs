'use strict';

const { createRequire } = require('node:module');

const RETRY_DELAYS_MS = Object.freeze([2000, 4000, 8000, 16000]);

function isForcedDmgDetach(command, args) {
  return (command === 'hdiutil' || command === '/usr/bin/hdiutil') &&
    Array.isArray(args) && args.length === 3 && args[0] === 'detach' &&
    args[1] === '-force' && /^\/dev\/disk\d+(?:s\d+)*$/.test(args[2]);
}

function isBusyDetachError(error) {
  // builder-util 23.x puts the exit status in the message, not error.code.
  const message = `${error?.message || ''}\n${error?.stderr || ''}`;
  return error?.code === 16 || /\bExit code:\s*16\b/i.test(message) ||
    /\bResource busy\b/i.test(message);
}

function createDmgDetachExec(exec, {
  sleep = ms => new Promise(resolve => setTimeout(resolve, ms)),
  warn = message => console.warn(message),
} = {}) {
  return function (...callArgs) {
    if (!isForcedDmgDetach(callArgs[0], callArgs[1]))
      return exec.apply(this, callArgs);

    const receiver = this;
    return (async () => {
      for (let attempt = 0; ; attempt++) {
        try {
          return await exec.apply(receiver, callArgs);
        } catch (error) {
          if (!isBusyDetachError(error) || attempt === RETRY_DELAYS_MS.length)
            throw error;
          const delay = RETRY_DELAYS_MS[attempt];
          warn(`[DMG] ${callArgs[1][2]} is still busy; retrying forced detach in ${delay / 1000}s (${attempt + 2}/${RETRY_DELAYS_MS.length + 1}).`);
          await sleep(delay);
        }
      }
    })();
  };
}

function runBuilder() {
  if (process.platform !== 'darwin')
    throw new Error('Universal macOS packaging requires macOS.');

  // Resolve from the actual dependency owners so nested npm installs work too.
  const builderRequire = createRequire(require.resolve('electron-builder/package.json'));
  const appBuilderRequire = createRequire(builderRequire.resolve('app-builder-lib'));
  const dmgRequire = createRequire(appBuilderRequire.resolve('dmg-builder'));
  const builderUtil = dmgRequire('builder-util');
  builderUtil.exec = createDmgDetachExec(builderUtil.exec);

  // Keep Electron Builder's own CLI, target selection and failure handling.
  const cli = builderRequire.resolve('./cli.js');
  process.argv[1] = cli;
  require(cli);
}

module.exports = { createDmgDetachExec, isForcedDmgDetach, isBusyDetachError, RETRY_DELAYS_MS };

if (require.main === module) {
  try {
    runBuilder();
  } catch (error) {
    console.error(error);
    process.exitCode = 1;
  }
}
