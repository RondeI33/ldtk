# Unity camera preview in LDTK-Smartive

The camera toolbar toggle previews the portion of the LDtk level covered by the Unity scene's game camera. Camera dimensions come from an editor-only Unity exporter. The source camera and scene are shown with the last export time, so a saved snapshot can be distinguished from active synchronization.

## Unity setup

Install or update the existing Smartive integration package in Unity Package Manager:

```text
https://github.com/RondeI33/ldtk.git?path=/unity/com.rondei33.ldtk-smartive-unity-icons#master
```

Open **Tools > LDTK-Smartive > Camera preview sync** and select the source `.ldtk` project asset inside `Assets`. The `.ldtkl` external level and a level prefab are not the project asset.

Leave the optional Camera field empty for automatic selection from the active scene. A unique enabled game camera tagged `MainCamera` takes priority. Otherwise the sole enabled game camera is selected. Ambiguous scenes require an explicit camera selection. Automatic lookup does not silently substitute a camera from another scene.

For scene streaming, explicitly select the final output camera if it lives in a persistent scene, another additive loaded scene, or `DontDestroyOnLoad`. Explicit selection accepts an enabled game camera from any valid loaded scene, while still rejecting prefab assets, disabled cameras and temporary hidden cameras. `sceneName` and `scenePath` continue to identify the active gameplay scene; `cameraName` identifies the actual selected output camera.

**Pixels Per Unit** is read from the selected LDtkUnity project's importer. This is independent of the LDtk tile grid size. An explicit PPU override is available when the importer is unavailable or uses a different custom setting. No PPU value is guessed.

Use **Export camera snapshot** to update the profile once. Enable **Automatic sync** to refresh it while the window is open. Installation does not enable synchronization. The game camera's current values are sampled during editor updates, including while a game is already running; the tool never enters Play Mode. For Cinemachine or Corgi, use the actual output `Camera`, rather than a virtual camera's nominal lens.

When a camera controller changes its lens only during gameplay, its runtime lens is available only while the game is running. Outside Play Mode, the exporter reports the current edit-time camera state.

## Supported camera framing

The exported camera must be enabled, belong to a valid loaded scene, use the `Game` camera type and be orthographic. Automatic selection is restricted to the active scene; cross-scene output cameras require explicit selection. Its world rotation must be identity, within a small floating-point tolerance. The exporter reads the current output projection matrix and derives its effective half-height and half-width. Centered size/aspect adjustments from Pixel Perfect or another controller are supported when present in that sampled matrix. A full matrix comparison rejects stereo, off-center, skewed or perspective projections that an axis-aligned centered frame cannot accurately represent.

For a supported camera:

```text
orthographicSize = 1 / projection.m11
halfWidth = 1 / projection.m00
aspect = halfWidth / orthographicSize
heightPx = 2 * orthographicSize * pixelsPerUnit
widthPx  = heightPx * aspect
```

The exported `orthographicSize` and `aspect` are effective values from the current projection, which may differ from the nominal `Camera.orthographicSize` and `Camera.aspect` properties. No 16:9 ratio is assumed. Fractional pixel dimensions remain fractional, avoiding cumulative grid drift. Both pixel dimensions must be finite, positive and no larger than 10,000,000, matching LDtk's profile validation.

The exporter samples during `EditorApplication.update`; it reports the projection currently exposed by the camera at that time. A render-time adjustment that is applied and reverted entirely inside a rendering callback is not available between frames and must not be inferred from the edit-time lens. Inspect the resulting profile when using a custom camera pipeline with such temporary adjustments.

This is a framing preview over LDtk's existing rendering. Unity-specific lighting, bloom, shaders, runtime prefabs, animation, camera shake, look-ahead, damping, and room/zone restrictions are not simulated. Importer PPU must match the level's world scale; additional scaling of imported level roots requires a corresponding PPU override.

## File contract

The project `World.ldtk` has the profile `World.ldtk-camera.json` in the same directory. The stock `.ldtk` schema and `<project>.ldtk-fork.json` remain independent. Profile updates do not reload the level or discard unsaved edits.

Example values below are illustrative and are not defaults:

```json
{
  "schemaVersion": 1,
  "source": "unity",
  "valid": true,
  "orthographic": true,
  "orthographicSize": 5.625,
  "aspect": 1.7777778,
  "pixelsPerUnit": 16,
  "sceneName": "04_research",
  "scenePath": "Assets/Scenes/04_research.unity",
  "cameraName": "Main Camera",
  "updatedAtUtc": "2026-10-30T10:00:00.0000000Z",
  "live": true,
  "error": ""
}
```

`valid:false` means the current source is unavailable or unsupported; `error` explains why. A missing camera, closed scene, invalid PPU or unsupported projection replaces the previous live profile with this invalid status. Closing the window, disabling automatic sync, moving the selected project, or closing Unity also invalidates the previous live destination when it can still be written. Manual snapshots have `live:false` and remain readable after the export window closes.

Automatic sync samples at most once every 0.5 seconds. Unchanged semantic values are written only for a heartbeat every 5 seconds; `updatedAtUtc` is the successful export time. LDtk can identify a stale live profile using that timestamp if Unity stops unexpectedly. Writes use a temporary file followed by an atomic replacement, never a delete-then-rewrite of the current valid JSON. A write failure leaves the previous file intact and is reported in the Unity window.

## Verification

The package includes Edit Mode tests in `Tests/Editor`. To make package tests visible in a Unity test project, include `com.rondei33.ldtk-smartive-unity-icons` in the manifest's `testables` array, then run **Window > General > Test Runner > EditMode**. The test assembly is editor-only and requires `UNITY_INCLUDE_TESTS`; normal player builds contain neither integration nor tests.

Tests cover exact path construction, complete atomic replacement, automatic camera selection and ambiguity, inactive-camera rejection, explicit cross-scene selection without automatic cross-scene inference, orthographic geometry, centered final-projection adjustments, rejected rotation/shear/off-center/perspective matrices, invalid PPU, pixel-dimension limits, and preservation of camera settings during capture. They create temporary test scenes and restore the previous active scene.

For end-to-end validation, change the actual camera's orthographic size or Game view aspect and check that the LDtk dimensions change; switch scenes and check source identification; close or disable the camera and verify that LDtk reports the invalid state. Confirm that toggling or moving the preview leaves the level's dirty state and undo history unchanged.

## API references

- [Unity Camera.orthographicSize](https://docs.unity3d.com/6000.0/Documentation/ScriptReference/Camera-orthographicSize.html)
- [Unity Camera.aspect](https://docs.unity3d.com/6000.0/Documentation/ScriptReference/Camera-aspect.html)
- [Unity Camera.projectionMatrix](https://docs.unity3d.com/6000.0/Documentation/ScriptReference/Camera-projectionMatrix.html)
- [LDtkUnity importer Pixels Per Unit](https://cammin.github.io/LDtkToUnity/documentation/Importer/topic_Section_Main.html)
- [LDtkUnity importer serialized PPU source](https://github.com/Cammin/LDtkToUnity/blob/master/Assets/LDtkUnity/Editor/ScriptedImporter/LDtkProjectImporter.cs)
