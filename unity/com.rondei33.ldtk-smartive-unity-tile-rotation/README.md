# LDTK-Smartive per-tile rotations for Unity (LDtkUnity)

An optional Unity Editor package that restores **90° tile-art rotations per Tilemap cell** after Cammin/LDtkUnity imports a Smartive project. The native `.ldtk` JSON remains readable by previous editors and Unity importers. The extra transpose orientation is stored in `World.ldtk-fork.json`.

## Install

1. Install the Cammin **LDtkUnity** importer in your Unity project first (the source assembly names must be `LDtkUnity.Runtime` and `LDtkUnity.Editor`).
2. In Unity Package Manager > **Add package from git URL**, enter:

   `https://github.com/RondeI33/ldtk.git?path=/unity/com.rondei33.ldtk-smartive-unity-tile-rotation#master`

3. Keep `World.ldtk-fork.json` adjacent to `World.ldtk` **inside Unity's Assets directory** (or wherever you import the LDtk project under Assets); both must be copied/synced on every LDtk save.
4. Reimport the `.ldtk` asset (and any generated `.ldtkl` files for external levels) once. Future sidecar changes are tracked as an import dependency.

This package depends on Unity's Newtonsoft JSON package (`com.unity.nuget.newtonsoft-json`). It is separate from the existing Smartive Unity icon/camera integration so projects without LDtkUnity do not acquire a hard compile-time dependency.

## How it works

- Runs as an LDtkUnity `LDtkPostprocessor` **after each level import**.
- Matches the imported Tile layer using its IID, verifies dimensions, tileset UID and definition UID against native LDtk JSON.
- Validates each sidecar cell's `coordId`, `stackIndex`, tile ID and native 2-bit flip value. Stale or mismatched entries are skipped; no speculative transforms are applied.
- Maps LDtk's Y-down `(cx,cy)` to Unity's Y-up Tilemap cell `(cx,gridHeight - 1 - cy,stackIndex)`.
- Multiplies **only that cell's** existing imported transform matrix by the missing transpose operation. The original per-tile flip, scale, offset and other tiles are preserved. **No level, parent, Tilemap or sprite-sheet GameObject is rotated.**
- Works with embedded and external level JSON; external level imports resolve their owning `.ldtk` project by level IID and exact relative path.

## Compatibility and limitations

- Works on **manual Tiles layers**; LDtk's normal IntGrid/AutoLayer behavior is left unchanged.
- Tilemap rotation requires the companion fork metadata. Without the sidecar, the importer only sees original LDtk's X/Y flip bits and therefore cannot reproduce a 90° turn.
- Requires the source `.ldtk`/`.ldtkl` files and matching sidecar to be present in the Unity project; missing or stale entries are never guessed.
- The `.ldtk-fork.json` companion is not part of native LDtk JSON. The Unity integration has separate regression checks for orientation matrix and stacked coordinate contracts but **must also be exercised in an actual Unity project** before claiming pixel-for-pixel parity.
- If a separate system converts tilemap cells into prefabs at runtime, it must preserve each Tilemap cell's individual transform matrix; rotating the whole prefab or discarding Tilemap matrices defeats the fix.
