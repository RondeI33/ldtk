# Drawable entity shapes: contract version 1

This contract is implemented by LDTK-Smartive. It describes editor authoring and
the native LDtk export that the separate Unity importer/runtime consumes. It does
not implement the saw, damage, or retracting-platform simulation in Unity.

## Designer workflow

1. Open the entity definition editor, find **Smartive authoring**, and enable
   **Drawable shape** for the desired entity type. The editor adds compatible
   native fields and reports any conflicting field definition before changing it.
2. Select an Entities layer and that entity type. In the palette's **Drawable
   shape** controls choose **Custom** and **Paint**, or choose **Preset** and one
   of the seven starting shapes. Drag on the level grid. Each complete stroke
   creates or edits one owner and one undo checkpoint.
3. Use **Erase** or right-click to remove cells. Use **Fill**, or hold Shift while
   painting, for a rectangle of cells. Select **New shape** to begin another owner.
   Escape cancels a held stroke and exits the drawing tool. Invalid disconnected
   candidates appear in red and are rejected on release.
4. Select an instance to edit its **Shape** controls. X, Y, thickness and rotation
   show a pending preview. **Apply preset** deliberately replaces its silhouette;
   **Resize X / Y** keeps custom topology. **Apply rows / columns** inserts or
   removes at the chosen zero-based row/column; positive counts duplicate after
   it and negative counts remove from it. **Cancel preview** discards the candidate.
5. Set **VisualProfile**, **ShapeFacing**, ordinary behavior fields and the native
   **Color** well in the same inspector. The advanced picker previews tint live.
   Escape, Enter and the surrounding mask retain the existing confirmation behavior.
6. Use **Save configuration**, then the existing **Templates** panel. Drag its
   **Place** button onto a same-type shape to apply settings while preserving its
   cells and IID. Hover text states the action. Drop on empty space for a new copy,
   or select **Draw configuration** to paint a new silhouette with those settings.
7. With the pointer over the idle level canvas, use **Ctrl+C / Ctrl+V** on
   Windows/Linux or **Cmd+C / Cmd+V** on macOS to copy a scene selection and open
   its placement preview. Click to place a new copy, or press Escape to cancel.
   Pasting always creates fresh owners, including over an existing shape; it does
   not apply saved settings to that shape. Copies can move between levels of the
   same project, with internal references remapped and point anchors translated.
   Text inputs keep normal clipboard behavior. Cross-project scene pasting is
   rejected to avoid reusing unrelated definition IDs; use template import for
   validated cross-project definition mapping.

## One shape, one entity

A painted object is one ordinary LDtk entity instance. Its IID, standard `px`,
`width`, `height`, and `__pivot` identify the occupied shape's bounding box.
The silhouette is a connected set of grid cells. Adjacent objects keep separate
IIDs even when their edges touch. Connectivity uses four edge neighbours.
Diagonal contact alone does not join two components. Holes and one-cell bridges
are supported.

The project's `<project>.ldtk-fork.json` stores the opt-in editor capability at
`entities[entityDefUid].drawableShape = { "enabled": true, "version": 1 }`.
It contains no runtime mask, damage, tint, or phase data. Runtime consumers do not
need this file. Native field identifiers below are reserved for this capability.
An incompatible existing field is reported before enabling changes the entity.
Existing `VisualProfile` enum values are retained when the built-in values are
added. An unknown project profile preserves its value and uses a solid preview
until a dedicated renderer is supplied.

## Native fields

| Field | Native type | Meaning |
| --- | --- | --- |
| `ShapeVersion` | Int | Contract version, currently `1`. |
| `ShapeMode` | Enum | `Rectangle`, `Preset`, or `Custom`. |
| `ShapeGridSize` | Int | Positive cell size in layer pixels. New shapes use the active entity layer's grid. |
| `ShapeCells` | Array<Int> | Flattened local occupied pairs `[x0,y0,x1,y1,...]`. |
| `ShapePreset` | Enum | `Rectangle`, `Strip`, `LCorner`, `UShape`, `Staircase`, `Diamond`, `Ring`, or `Custom`. |
| `ShapeThickness` | Int | Positive arm/frame thickness in grid cells for preset generation. |
| `ShapeQuarterTurns` | Int | Preset authoring orientation `0..3`, clockwise in LDtk's downward-Y coordinates. |
| `ShapeFacing` | Enum | Exposed damaging spike faces: `All`, `Up`, `Right`, `Down`, or `Left`. |
| `VisualProfile` | Enum | Built-ins: `SolidBarrier`, `Spikes`, `EnergyPool`. Existing project values remain valid. |
| `Color` | Color | Per-instance tint, native `#RRGGBB` serialization. |

Behavior fields such as `Damage` are ordinary project-specific native fields.
There is no custom entity JSON member or alternate serialization path.
`fieldInstances[].__value` and `realEditorValues` are generated by the same native
field APIs. `ShapeCells` has no arbitrary small maximum array length. Generated
geometry is edited through drawing controls rather than thousands of numeric
field inputs; ordinary manual behavior fields remain available.
The contract's field identifiers and reserved enum values retain their exact
spelling under uppercase/lowercase project naming policies. Unrelated enum values
continue to follow the project's normal policy.

### Resolved cell invariant

Pairs are unique integers, normalized to their occupied bounding box's upper-left
corner. Minimum X and minimum Y are zero. Sort pairs by Y, then X. In Preset and
Custom modes the array must be nonempty and four-connected. The occupied maximum
coordinates plus one, multiplied by `ShapeGridSize`, equal standard `width` and
`height` exactly.

For example, this L has width and height 48 at grid 16:

```json
{ "ShapeCells": [0,0, 0,1, 0,2, 1,2, 2,2], "ShapeGridSize": 16 }
```

Rectangle mode derives a completely filled mask from standard bounds and may
store an empty `ShapeCells`. Selecting Rectangle deliberately replaces a custom
silhouette. Preset mode always exports the resolved mask. A runtime must not
regenerate it from `ShapePreset`, parameters, or the editor sidecar.

All exported cells are in their final orientation. Mirroring or rotating changes
cells and `ShapeFacing` together; it marks the instance Custom. Do not apply
`ShapeQuarterTurns` a second time in Unity. It is an authoring parameter for an
untouched preset, not an additional runtime transform.

### Position and layer offsets

Use standard LDtk coordinates. Given instance `px`, its bounding `width` and
`height`, and its pivot, the layer-local upper-left corner is:

```text
left = round(px[0] - width  * pivot[0])
top  = round(px[1] - height * pivot[1])
cellOriginInLevel = (left + cellX * grid, top + cellY * grid)
                  + (layer.__pxTotalOffsetX, layer.__pxTotalOffsetY)
cellOriginInWorld = cellOriginInLevel + (level.worldX, level.worldY)
```

Apply each offset once. LDtk Y points downward; convert axes only once when
entering Unity space. Moving an instance changes `px`, leaving local cells
unchanged. Painting left/up or removing an extreme row/column changes the bounds
and pivot position in the same commit, so surviving occupied cells retain their
world position. Versioned shapes ignore sidecar appearance width, height, and
pivot overrides; standard bounds remain the single source of extent.
The editor preserves LDtk's native pixel rounding. If an odd grid and fractional
pivot cannot represent a requested origin with an integer `px`, the complete edit
is rejected before changing fields or bounds; it never shifts surviving cells.

## Presets and resizing

Dimensions are in cells. For thickness `t >= 1`, these are the minimum unrotated
dimensions. Odd quarter-turn orientations swap the required dimensions.

| Preset | Minimum width × height | Geometry |
| --- | --- | --- |
| Rectangle | 1 × 1 | Filled rectangle; all exposed spike faces by default. |
| Strip | 1 × 1 | Filled base; defaults to Up when no single face was selected. |
| LCorner | `(t+1) × (t+1)` | Left arm and bottom arm before rotation. |
| UShape | `(2t+1) × (t+1)` | Left/right arms and bottom base; an open central recess. |
| Staircase | 2 × 2 | Filled steps widening toward the bottom, with edge-connected occupancy. |
| Diamond | 3 × 3 | Filled grid-rasterized diamond with edge-connected rows. |
| Ring | `(2t+1) × (2t+1)` | Rectangular frame with a genuinely empty centre. |

Both dimensions can change. A preset resize regenerates resolved cells using its
orientation and thickness. Invalid dimensions are rejected visibly; an invalid
Ring or U never silently becomes a filled rectangle. Manual cell edits set both
mode and preset to Custom. Appearance and tint changes do not regenerate cells.

Custom X/Y extension duplicates the selected grid column or row and shifts cells
beyond the insertion. Shrinking removes selected rows/columns. The candidate must
remain connected and retain its number of enclosed holes. An operation that
would disconnect the mask or open/close a hole is rejected. Cell size is never
stretched to accommodate a bounding-box resize.

## Editing, identity, and references

The editor keeps a stroke candidate separate from the live native fields. Mouse-up
validates and commits the complete candidate in one undo transaction. Cancellation
leaves the previous geometry and fields intact. Erasing the final cell deletes
the ordinary instance through its normal history mechanism. Fast brush movement
uses edge-connected interpolation.

Hit testing follows occupied cells and their exposed outline, including concave
and hole boundaries. Empty areas inside a large bounding rectangle do not select
that object. Canvas previews, selection ghosts and template images draw the same
resolved geometry. Graphics remain owned by the entity; versioned shapes do not
execute destructive sidecar tile stamps on manually painted tile layers.

Duplicate and clipboard/template placement retain native field payloads while
allocating new IIDs through the existing editor mechanisms. Moves, including
cross-level ownership transfer, preserve the original IID. Applying a saved
configuration is restricted to the same entity type: compatible behavior and
appearance values copy onto the existing owner, preserving its geometry, bounds,
IID, point anchors, and entity-reference fields. The editor does not silently convert types or
create another overlapping owner when applying settings.

With the cursor over the canvas, Ctrl/Cmd+C copies the scene selection and
Ctrl/Cmd+V starts a placement preview. Click to place or Escape to cancel. Clipboard
paste always creates copies, including when the cursor overlaps another shape.
Copies can be placed in another level of the same project; references between
copied entities remap to their new IIDs, and point anchors follow their owners.
The shortcuts keep their normal text-editing behavior inside input fields.
Malformed versioned geometry in a template or clipboard selection is rejected
before any part of that selection is attached to a level.

## Visual meaning

SolidBarrier draws occupied body cells and exposed edges. Spikes adds teeth only
to selected exposed faces; internal shared edges have no teeth. One-sided spikes
describe a damaging face and do not imply one-way platform physics. EnergyPool
fills only occupied cells and draws horizontal surface spans on upward-facing
edges. It does not rotate a liquid surface into a wall or fill a Ring's empty
centre. Repeated body artwork and procedural fallback decorations keep their
pixel density when dimensions change.

`Color` is independent for each instance and independent of the entity definition's
editor color. The native advanced picker retains the existing confirmation
behavior while providing a hue wheel and saturation/value square, synchronized
with hex/RGB inputs and the color well. It does not encode timing groups.

## Timed-platform handoff

The example `TimedPlatform` definition includes these ordinary Float fields:

| Field | Unit and meaning |
| --- | --- |
| `HiddenDuration` | Seconds spent fully hidden. |
| `ExtendDuration` | Seconds extending into view. |
| `VisibleDuration` | Seconds fully visible. |
| `RetractDuration` | Seconds retracting. |
| `PhaseOffsetSeconds` | Seconds added to cycle time; positive advances, negative delays. |
| `Color` | Native per-instance tint, with no phase/group meaning. |

The Unity task defines interpolation, collision, and zero-duration handling.
Its phase convention must use positive offset as an advance, for example
`phase = positiveModulo(elapsedSeconds + PhaseOffsetSeconds, cycleDuration)`.
Timing is independent for each placed object. There is no automatic red/blue
alternation.

## Invalid and legacy data

An ordinary legacy entity without explicit shape metadata retains its rectangular
interpretation. Merely enabling the capability does not rewrite its instances.
Any explicit shape mode/grid/preset or nonempty cells opts into validation, even
if stock LDtk compacted ShapeVersion back to its default.

Unsupported versions, odd coordinate arrays, duplicate or unsorted pairs,
unnormalized coordinates, disconnected masks, empty Preset/Custom masks, mismatched
bounds, and disagreement between public and native editor values produce a visible
validation error. They never silently become their damaging bounding rectangle.
An importer should reject/report these cases before building physics or hazards.

## Example and verification

The sample project is `tests/drawable-shapes/fixtures/drawable-shapes.ldtk`, with
standard external levels in the neighbouring `drawable-shapes/` directory and
its editor capability sidecar beside it. The representative Unity handoff is
`tests/drawable-shapes/fixtures/drawable-shapes-v1-export.json`.
The sample includes nonzero level origins and nonzero layer offsets deliberately.

Run focused verification from the repository root:

```sh
haxe tests/drawable-shapes.hxml
cd app
npm run test:drawable-shapes
```

On a headless Linux host, run the Electron test with `xvfb-run -a`. The suite uses
the freshly compiled production classes, verifies native save/reopen and actual
editor interactions, writes screenshots/results to `app/test-results/drawable-shapes`,
and restores the distributable renderer after temporary test instrumentation.

To regenerate the checked-in example using native production serializers, set
`LDTK_DRAWABLE_EXPORT_DIR` to the absolute fixtures directory while running that
same suite. Existing release preflight also covers templates, selection,
entity-history/chain/multi behavior, point editing, and path previews.

Native format references: [LDtk entity fields](https://ldtk.io/docs/game-dev/json-overview/entity-fields/)
and [LDtk JSON specification](https://ldtk.io/json/).
