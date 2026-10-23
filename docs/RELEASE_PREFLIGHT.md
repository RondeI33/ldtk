# Release preflight

Run the release checks before starting installer packaging. The aggregate command
validates the version/changelog, runs the actual Haxe-compiled Electron editor
regressions, checks PSD import, generates the JSON documentation/schema, and ends
with a clean production compilation. It does not build installers or publish a
release.

## Setup

Use Haxe **4.3.3**, Node **20**, and the dependencies in `setup.hxml`, matching the
release workflow:

```sh
haxe setup.hxml
cd app
npm install --no-audit --no-fund
```

Linux also needs Xvfb, Xauth and the normal Electron system libraries. Run:

```sh
xvfb-run -a -s "-screen 0 1600x1100x24" node scripts/run-release-preflight.cjs
```

On macOS Intel, run:

```sh
node scripts/run-release-preflight.cjs
```

The release uses macOS Intel for GUI regression tests because Electron 24 cannot
initialize the required WebGL context on the headless macOS ARM64 runner. The
macOS installer remains universal (Intel and Apple Silicon).

## Checks and results

The aggregate runs path previews, point picking, entity history, automatic chain
references, multi-entity editing, drawable shape geometry/editor/color regression,
and PSD import. Linux additionally runs template and selection integration,
matching the release matrix. It then runs `haxe doc.hxml`, `haxe main.hxml`, and
`haxe renderer.hxml`. Each suite exits nonzero on failure. Results and screenshots
remain under `app/test-results`; the aggregate writes
`app/test-results/release-preflight/summary.json` with each stage's result.

Run suites sequentially in a checkout: their temporary instrumentation modifies
the generated `app/assets/js/renderer.js` and restores it on exit. Concurrent test
runners using that same output file can corrupt one another's test runtime.

`Drawable shapes release preflight` runs the same aggregate on Linux and macOS
Intel when `feature/drawable-shapes-v1` is pushed. It can also run from the Actions
tab or a qualifying pull request. That workflow has read-only repository
permissions and contains no packaging, tag creation, release or notification step.

## Publish after green checks

Use a new version in `app/package.json` and a complete matching section in
`docs/SMARTIVE_CHANGELOG.md`. The existing version script updates both the package
and any local lockfile:

```sh
npm run version:patch
```

Replace its changelog placeholder with the actual changes, run preflight, and
push the intended release commit. Confirm the preflight is green for that same
commit on both operating systems, then dispatch **LDTK-Smartive manual release
build** (or the reusable **LDTK-Smartive release** workflow). Keep
`force_rebuild=false` for a new version. The release repeats its regression gates
before packaging Windows x64, universal macOS and Linux x64, and only publishes
after all jobs succeed.

For the drawable-shapes handoff, the dedicated `release/drawable-shapes-v1`
branch is also a release trigger. Create or advance it to the **same commit**
that passed the feature-branch preflight only after checking both platform jobs.
Its small wrapper invokes the existing gated release workflow with
`force_rebuild=false` and `notify_slack=false`. Every checkout and the final tag
use the triggering commit; the feature branch remains available. A push to the
feature branch does not trigger that release wrapper.

Slack release announcements require the explicit `notify_slack` input; its default
is false. A failed preflight should be fixed and rerun before dispatching release.
Do not disable a failing check or repeatedly start installer jobs to diagnose an
editor regression.
