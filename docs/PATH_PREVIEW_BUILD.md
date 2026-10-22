# Build the CargoLine preview for manual testing

Open [the manual build workflow](https://github.com/RondeI33/ldtk/actions/workflows/test-windows.yml).
Branch **main** contains the manual installer-testing workflow. Select **main** in the Run workflow branch selector.

1. Click **Run workflow**.
2. In the branch selector, select **main** (not `master`).
3. Click the green **Run workflow** button.
4. Open the new run. After it succeeds, download the Windows x64, universal macOS or Linux x64
   installer from **Artifacts** at the bottom of the run page. Extract the downloaded ZIP first.

The `main` branch's workflow runs the path preview tests, point picking regressions and
auto-chain/sidecar regressions in the compiled editor on Linux and macOS Intel. The Linux gate
also runs the selection move/copy regressions. All installer jobs depend on those regressions
passing. It then builds the three platform packages and uploads
them as Actions artifacts, retained for 14 days.

The workflow is manual only. It has read-only repository permissions and packages with
`--publish never`; it does not create a release, update a tag or change the package version.

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
