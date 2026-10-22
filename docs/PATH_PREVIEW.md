# Path preview

`pathPreview` draws a train of axis-aligned blocks along an entity's point path.
It is an editor preview: it does not create entities, paint tiles, change entity
or field JSON, or change the LDtk JSON version. Any entity definition can use it;
neither the entity name nor its UIDs are hard-coded.

## Configuration

Add `pathPreview` to the corresponding entity entry in `<project>.ldtk-fork.json`.
The sidecar retains this object and other unknown properties when the editor saves.
Field bindings use an existing `fieldUid` first, then `fieldIdentifier` if that UID
is absent from the entity definition. Identifier-only bindings are also supported.

```json
{
  "entities": {
    "4008": {
      "identifier": "CargoLine",
      "pathPreview": {
        "path": { "fieldUid": 4009, "fieldIdentifier": "Path" },
        "mode": {
          "fieldUid": 4010,
          "fieldIdentifier": "Mode",
          "loopValue": "Loop",
          "teleportValue": "Teleport",
          "pingPongValue": "PingPong"
        },
        "blockCount": { "fieldUid": 4011, "fieldIdentifier": "BlockCount" },
        "blockWidth": { "fieldUid": 4012, "fieldIdentifier": "BlockWidth" },
        "blockHeight": { "fieldUid": 4013, "fieldIdentifier": "BlockHeight" },
        "gap": { "fieldUid": 4014, "fieldIdentifier": "Gap" },
        "evenSpacing": { "fieldUid": 4015, "fieldIdentifier": "EvenSpacing" },
        "startOffset": { "fieldUid": 4017, "fieldIdentifier": "StartOffset" },
        "unitPx": 16,
        "blockColor": "#E8A33D",
        "overlapColor": "#FF3030"
      }
    }
  }
}
```

This example uses the supplied `00_prototype.ldtk` definition. The task's original
sample used UID **4016** for `startOffset`; its own UID table assigns that UID to
`Speed`. The correct `StartOffset` UID is **4017** in `00_prototype.ldtk`, **3883** in
`00_template.ldtk`, and **3914** in `02_LogisticWest.ldtk`. A valid UID deliberately
takes precedence over a conflicting identifier, including in that original sample.

The Path binding must resolve to `Array<Point>`. Coordinates start at the entity's
pivot; each Path value is converted from its layer grid cell to the cell center.
Dimensions, gaps and offsets are in `unitPx` cells. `unitPx` defaults to the layer
grid size. Keep the Path field in `PointPath` display mode to retain stock arrows
and editable point handles.

## Display

Blocks have a 35% fill, a solid outline, and an index when at least two cells wide.
Gap dimensions follow the polyline. Regular intervals show `pitch - extent`; when
wrapping moves the seam into the middle of the displayed path, its mark shows the
actual seam spacing rather than incorrectly repeating the regular gap. Overlapping
trains turn red and show the measured pitch or seam warning near their origin.

Loop adds the missing closing path segment. Teleport adds a dashed return line,
a re-entry marker and the seam gap. PingPong shows an outline-only train at the far
end of its travel, or `does not fit` when the train cannot travel. Blocks remain
axis-aligned on vertical and diagonal path segments.

Edits to fields, entity positions, Path points and undo/redo rebuild the preview.
During selection drags, a temporary drawing uses the same snapped delta as the
eventual drop; it does not write preview values into the project. Hidden layers
also hide their previews. Stock point handles and selection controls remain above
the preview and keep their existing mouse behavior.

## Verification and manual builds

`haxe tests/path-preview.hxml` runs the eight supplied game vectors, including the
nonzero travelled-distance samples and epsilon/degenerate cases. From `app`,
`npm run test:path-preview` additionally compiles and launches the actual editor
for rendering, editing, history and sidecar persistence regressions.

See [PATH_PREVIEW_BUILD.md](PATH_PREVIEW_BUILD.md) for the manual Actions build.
The build uploads installers as workflow artifacts without publishing a release.
