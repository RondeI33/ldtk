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
