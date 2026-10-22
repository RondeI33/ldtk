# Build and publish the CargoLine preview from master

Open [the manual release build workflow](https://github.com/RondeI33/ldtk/actions/workflows/test-windows.yml).

1. Click **Run workflow** and select **master**.
2. Start the workflow. It invokes the repository's **existing** Smartive release workflow.
3. The release pipeline first checks the package version and changelog, then runs real
   Electron/Haxe regression tests on Linux and macOS Intel, including CargoLine preview,
   point picking, entity history, auto-chain, entity multi-edit, selection and templates.
4. Only if all tests and platform packages succeed, it publishes the versioned
   [GitHub release](https://github.com/RondeI33/ldtk/releases) with Windows x64,
   universal macOS and Linux x64 downloads and Windows update metadata.
5. The existing **Notify Slack about new release** step posts its release message
   and notes to the already-configured `SLACK_WEBHOOK_URL` secret. Missing or failing
   notifications are reported as workflow failures instead of silently succeeding.

This workflow is **manual only**, not triggered by commits. It uses the existing release
pipeline rather than duplicating its publishing or Slack logic. If the current version
already has a published release, the pipeline skips publication; update
`app/package.json` and `docs/SMARTIVE_CHANGELOG.md` to the next version first.
The new version for these features is **1.0.30**.

## Ctrl+Shift entity rectangle erase

On an **Entities** layer, hold **Ctrl+Shift** (physical Control on macOS) and
left-drag to erase entities whose pivot cells are inside the drawn rectangle
on the **active layer only**. Ctrl+Shift+left-click removes the entity or field
point under the cursor. Existing entity selections and resize handles do not steal this gesture;
an explicitly active Point picker retains priority. The removal is a single
Undo/Redo step; nothing on other layers is erased. This does not introduce a new configurable shortcut or
change the existing modifier behavior on Tiles/IntGrid layers.

The existing `npm run test:points` regression suite also checks native
Ctrl+Shift click/drag, the active-layer boundary, empty rectangles, single-step
Undo/Redo and ordinary non-modified entity clicks. The manual workflow runs
these tests before allowing installer packaging.
