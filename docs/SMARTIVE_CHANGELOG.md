# 1.0.12

## Flip scene selections while dragging

- `X` and `Y` can now be used while a scene selection is actively being held and dragged.
- Pressing a flip command updates the live multi-layer ghost immediately without mutating the level underneath the cursor.
- Releasing the mouse first moves/copies the selection and then commits the same queued horizontal/vertical flips to the dropped selection.
- Copy-drag + flip transforms only the new copy; the original selection remains unchanged.
- Move/copy plus any live X/Y flips are stored as one Undo/Redo history operation.
- Pressing the same axis again while still dragging toggles that temporary flip back off.
- Existing `C_FlipX` / `C_FlipY` commands are reused, so default and user-customized shortcut mappings are unchanged.
- Retains the 1.0.11 multi-layer ghost sorting, overlay suppression, and inactive-atlas loading fixes.

### Builds

- Windows x64 installer.
- Universal macOS DMG.
- Linux x64 AppImage.

# 1.0.11

## Multi-layer selection ghost sorting fix

- Reworked the scene selection ghost to use an internal `h2d.Layers` stack with the same layer depth values as the real level renderer.
- Multi-layer preview no longer depends on selection iteration order, so stacked tile/auto-layer content keeps the same visual order as the scene.
- The normal selection overlay is now suppressed for the entire drag lifecycle, preventing its filled selection rectangles from reappearing in `postUpdate()` and covering the real ghost.
- Non-active selected layer atlases are explicitly loaded before ghost construction, preventing inactive layers from falling back to a solid gray placeholder just because their texture had not been touched by the active tool yet.
- IntGrid/AutoLayer fallback graphics are attached to their own sorted layer roots instead of being painted globally over the full ghost.
- Retains the existing multi-layer flip behavior for **Tiles + IntGrid** and keeps all existing/custom `C_FlipX` / `C_FlipY` shortcut mappings unchanged.

### Builds

- Windows x64 installer.
- Universal macOS DMG.
- Linux x64 AppImage.

# 1.0.10

## Linked AutoLayer selection preview

- Completed multi-layer drag preview for projects where an **IntGrid** layer drives one or more separate **AutoLayer** layers.
- Dragging a selection now renders the linked AutoLayer tiles from their existing auto-tile cache instead of showing only the IntGrid cell-color/gray rectangle.
- Linked AutoLayer preview respects normal layer visibility and uses the same `LayerRender` auto-tile rendering helper as the scene.
- Retains the 1.0.9 multi-layer flip behavior: selected manual **Tiles** and **IntGrid** cells are mirrored together around one shared selection axis.
- Existing `C_FlipX` / `C_FlipY` commands and all user-customized shortcut mappings remain unchanged.

### Builds

- Windows x64 installer.
- Universal macOS DMG.
- Linux x64 AppImage.

# 1.0.9

## Full multi-layer scene flip and visual drag preview

- Scene-selection X/Y flip now transforms both manual **Tiles** cells and selected **IntGrid** cells, so chunks spanning tile layers and auto-layer source layers flip as one selection.
- IntGrid values are mirrored spatially and their auto-layer output is regenerated through the normal LDtk layer invalidation path.
- Manual tile cells continue to toggle their native horizontal/vertical flip bits while moving to their mirrored positions.
- Drag preview for IntGrid-backed auto-layers now renders the actual cached auto-tiles instead of the old solid cell-color/gray rectangle.
- Manual tile drag preview now uses the same `LayerRender` tile rendering helper as the scene for consistent pivots, flips, and layer scaling.
- The existing immediate drag-preview fix from 1.0.8 remains in place.
- Existing `C_FlipX` and `C_FlipY` commands are reused; shortcut mappings and user customizations are not changed.

### Builds

- Windows x64 installer.
- Universal macOS DMG.
- Linux x64 AppImage.

# 1.0.8

## Multi-layer selection flip and drag preview fixes

- Fixed scene-selection flipping so all selected tile layers are mirrored around one shared level-space axis instead of each layer using its own bounds.
- Preserved the authored selection rectangle as the flip axis when empty-space selection is enabled, keeping multi-layer arrangements aligned.
- Restored immediate drag ghost/preview rendering: the preview now appears on the same mouse-move event that crosses the movement threshold.
- Kept the existing selection, movement, copy, Undo/Redo, and tile-stack behavior intact.
- Existing `C_FlipX` and `C_FlipY` commands and user-customized shortcut mappings remain unchanged.

### Builds

- Windows x64 installer.
- Universal macOS DMG.
- Linux x64 AppImage.

# 1.0.7

## Flip copied scene selections

- Tile groups selected directly in the level scene can now use the existing horizontal and vertical flip commands, matching the workflow available for tiles picked from a tileset.
- Scene-selection flips mirror the selected tile layout in place and toggle the corresponding per-tile flip bits, so copied arrangements keep the expected visual orientation.
- Tile stacks are preserved and the flipped selection remains selected after the operation.
- Selection flips are recorded in the normal level history, so Undo/Redo continues to work.
- Existing `C_FlipX` and `C_FlipY` commands are reused without changing their bindings, preserving user-customized shortcuts.
- When no flippable scene selection is active, the existing tileset/spritesheet flip behavior is unchanged.

### Builds

- Windows x64 installer.
- Universal macOS DMG.
- Linux x64 AppImage.

# 1.0.6

## Neighbour-driven entity appearance

- Added structured **Auto orientation from IntGrid neighbours** controls for existing appearance rules; no raw sidecar JSON is required.
- Appearance rules can now resolve from **Floor**, **Ceiling**, **Left wall**, **Right wall**, **Background wall**, or **Air**.
- Added deterministic priority when multiple surfaces are valid: **Floor → Ceiling → Left → Right → Background → Air**.
- Neighbour checks can target a chosen IntGrid layer and either any non-empty value or one specific IntGrid value.
- The winning rule writes its normal field/value condition into the entity instance, so exported `.ldtk` data and Unity importers can read the resolved orientation without understanding Smartive-only metadata.
- Entity position is never snapped or moved by this system. Moving an entity away from a surface leaves it where it was placed and allows an optional **Air** rule to become active.
- Neighbour probes use the authored entity rectangle rather than appearance-overridden size/pivot values, preventing sprite variants from feeding back into their own attachment detection.
- Resolution is limited to the active level and uses cached per-entity results; appearance layers are invalidated only when the resolved rule changes.
- Existing field-driven appearance rules remain compatible and continue to use the same Smartive sidecar format.

### Builds

- Windows x64 installer.
- Universal macOS DMG.
- Linux x64 AppImage.

# 1.0.5

## Reload project from disk

- Added a per-process HTTP control server bound only to `127.0.0.1` on an ephemeral port, with a random 32-byte token and per-PID control file under `~/.ldtk-smartive/control/`.
- Added the `GET /status` and `POST /reload` contract used by `ldtk-mcp`. Dirty projects still return `refused: "unsavedChanges"`; an MCP `force:true` request can no longer silently discard editor state and instead triggers the in-editor **Save and reload / Discard and reload / Cancel** dialog.
- Added atomic project reload using the normal project loader, including external `.ldtkl` levels and the Smartive `.ldtk-fork.json` sidecar.
- Added strict reload validation so a missing or malformed external level/sidecar aborts the reload without replacing the project currently open in the editor.
- Reload preserves the selected world/level, layer, world depth, camera position/zoom, world-view mode, and existing layer-tool/palette state when those objects still exist.
- Reload clears stale level undo/redo timelines by going through the normal project-selection initialization path.
- Added **File > Reload project from disk** with `Ctrl/Cmd + Shift + R`; `Ctrl/Cmd + R` remains the Electron window reload shortcut.
- Added a three-way unsaved-changes dialog: **Save and reload / Discard and reload / Cancel**, with Cancel focused by default.
- Added debounced project-file watching for `.ldtk`, external `.ldtkl`, and `.ldtk-fork.json`, with own-save suppression and a non-invasive Reload/Ignore warning banner.
- Added `LDTK_SMARTIVE_CONTROL_DIR` support for isolated control-server tests.

### Builds

- Windows x64 installer.
- Universal macOS DMG.
- Linux x64 AppImage.

# 1.0.4

## Smartive Unity asset icons

- Added an editor-only Unity package in this repository that applies the LDTK-Smartive logo to `.ldtk`, `.ldtkl`, and `.ldtka` assets in the Unity Project window.
- The integration runs after asset imports so it replaces the old LDtkUnity/Cammin project-file artwork without replacing or modifying the importer itself.
- Existing LDtk assets are refreshed automatically when the Unity editor package loads.
- Added a manual **Tools > LDTK-Smartive > Refresh LDtk asset icons** command.
- Added a Unity Package Manager Git install path and package documentation to the repository README.
- Replaced the old desktop `.ldtk` project and `.ldtkl` level file-association artwork with the same Smartive application logo on Windows and macOS.
- The Unity icon package uses the same Smartive logo as the desktop builds.
- LDtk project JSON compatibility remains `1.5.3`; Smartive application/release versioning remains independent.

### Builds

- Windows x64 installer.
- Universal macOS DMG.
- Linux x64 AppImage.
- LDTK-Smartive Unity icon integration package.

# 1.0.3

## Restore LDtk JSON compatibility

- Fixed the regression where the Smartive application version `1.0.2` could be written into LDtk project `jsonVersion`.
- Smartive release version and LDtk JSON compatibility version are now guarded as separate version tracks.
- `.ldtk` and `.ldtkl` compatibility stays on LDtk JSON version `1.5.3` while the application release moves to `1.0.3`.
- Added a lower-bound guard so a Smartive `1.0.x` value cannot silently become the LDtk project schema version again.
- Opening and saving a project with a poisoned Smartive-era `jsonVersion` restores the canonical LDtk compatibility version through the existing project load normalization.
- Restores compatibility with LDtkUnity and other importers requiring LDtk JSON `1.5.x`.

### Builds

- Windows x64 installer.
- Universal macOS DMG.
- Linux x64 AppImage.

# 1.0.2

## Smartive branding

- Replaced the upstream LDtk logo in the repository README with the supplied LDTK-Smartive artwork.
- Replaced the in-app application icon with the Smartive logo.
- Replaced the Windows executable, installer, and uninstaller icons with the Smartive logo.
- Replaced the macOS application icon with the Smartive logo.
- Added an explicit Smartive PNG icon for Linux AppImage builds.
- Updated Electron Builder configuration so Windows, macOS, and Linux packages consistently use the fork branding.
- Fixed the stale macOS test-package workflow so it recognizes current LDTK-Smartive DMG filenames.

### Builds

- Windows x64 installer.
- Universal macOS DMG.
- Linux x64 AppImage.

# 1.0.1

## Intuitive fork authoring UI

- Replaced the normal raw-JSON workflow for fork-only entity appearance overrides with structured editor controls.
- Added visual replacement tile/sprite picking with field/value conditions, optional width/height overrides, pivot controls, and color overrides.
- Added structured tile-stamp authoring with target tile-layer selection, field/value conditions, visual tile pickers, grid offsets, and flip controls.
- Added structured conditional field-visibility rules with typed trigger values.
- Added structured conditional enum filtering with selectable allowed enum values.
- Kept the existing Auto Children editor unchanged.
- Kept `<project>.ldtk-fork.json` fully compatible with existing projects and retained the raw JSON editor as an Advanced JSON fallback.

### Builds

- Windows x64 installer.
- Universal macOS DMG.
- Linux x64 AppImage.

# 1.0.0

## First LDTK-Smartive release

### Smartive versioning

- Started an independent LDTK-Smartive release line at `1.0.0`.
- The application, installers, release titles, and update metadata now use the Smartive version.
- Kept the LDtk project JSON compatibility version independent at `1.5.3`, so opening and saving existing LDtk projects does not trigger false migrations or downgrade their format version.
- Added stable SemVer release tags in the form `v1.0.0`, `v1.0.1`, `v1.1.0`, and so on.
- Added Windows update metadata so installed Windows builds can detect and install later Smartive releases.
- macOS and Linux builds check the Smartive GitHub releases page for later versions.

### Fork features included

- Auto-place configured child entities when a parent entity is created.
- Apply configured child offsets and automatically populate compatible parent `EntityRef` fields.
- Import `.aseprite` tilesets with a layer picker so gameplay art can be selected without normal-map, emission, or other auxiliary layers.
- Include the cumulative editor-preview, animated-tile, atlas-composer, and authoring-tool changes currently present in the fork branch.

### Builds

- Windows x64 installer.
- Universal macOS DMG.
- Linux x64 AppImage.
