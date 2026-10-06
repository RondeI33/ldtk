# Ordinary selection regression checks

Scope: ordinary editor selection, movement and duplication. Template placement semantics are unchanged.

## Run

Install the Haxe and app dependencies as in the normal project setup. From `app`, run `npm run test:selection`. On headless Linux, run `xvfb-run -a -s '-screen 0 1600x1000x24' npm run test:selection`.

The runner compiles test-only Haxe hooks into the real Electron renderer, runs both selection scripts and restores the production renderer afterwards. A failed compile or test returns a nonzero status. `--input-only` exists for the negative baseline reproduction; it is not the release gate.

## Coverage

- Existing 450 copy/move variants, Undo/Redo and cancelled-move restoration.
- 1,250 additional sparse-overlay cases: both movement modes, all directions, zero displacement, overlapping source/destination and different grab/release positions within cells.
- 512 mixed 16px/32px grid cases.
- Eight transfers through the actual SelectionTool start/move/release handlers, checking first-event ghost visibility, logical position and whole-grid state.
- 100 consecutive transfers in 50 round trips, with exact grid comparison after each round trip.
- Four rectangle/modifier combinations, empty dragging, and eight offset-layer boundary checks.

This is 2,320 transfer variants plus the grouped input/history checks. These are parameterized regression cases, not 2,320 independent hand-written tests. The new grid oracle snapshots every occupied cell before the operation, applies an independent sparse overlay and compares all grid layers afterwards. Empty cells never occur in the payload, so any hole erasing a destination or any unrelated-cell mutation fails the comparison.

Input checks call the real handlers with synthetic coordinates and modifier state; they are not a replacement for native mouse/keyboard testing on macOS and Windows. The matrix validates tile/IntGrid data and ghost coordinates, not pixel-perfect sprite rendering, imported user projects, every parallax/zoom configuration or all cross-level combinations.

## Bugs guarded

Rectangle selection must not enter move mode or temporarily cut the existing selection. Empty dragging must remain a no-op. Layer-relative rectangle coordinates use floor, not truncation toward zero, so a rectangle just outside an offset layer cannot include its first row or column.

The feature-branch workflow temporarily checks out only the pre-fix SelectionTool source at `7c359761feff184a09d467c458b5a4dd92b28907`. The new input test must fail specifically with `MARQUEE_STARTED_MOVE`; compilation/environment errors do not count as reproducing the bug. The fixed source is restored before the complete suite runs.

## Packaging gate

The candidate matrix depends on the regression job, which includes selection, existing template compatibility and PSD import tests. A failure skips candidate packaging. Candidate builds use `--publish never` and do not replace an existing stable release.

The normal release workflow's Windows, macOS and Linux jobs depend on both selection-runtime and template-runtime, rather than running alongside them. The duplicate legacy macOS publishing workflow is manual-only and depends on the same reusable regression gate.

Test evidence is stored under `app/test-results/selection` and uploaded by Actions, including the expected negative-baseline failure and successful result summaries. A successful Linux runtime check does not by itself certify native behavior on every platform.
