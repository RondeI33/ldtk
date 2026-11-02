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

This is a framing preview over LDtk's existing rendering. Unity-specific lighting, bloom, shaders, runtime prefabs, animation, camera shake, look-ahead, damping, and transitions are not simulated. Optional model compatibility is described below and must not be mistaken for verified game-camera parity. Importer PPU must match the level's world scale; additional scaling of imported level roots requires a corresponding PPU override.

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

## Level switching and explicit placement

Joshua placement is a four-state UI operation: **off**, **idle**, **placing**, or **placed**. The first time Camera Preview opens in a project, you can click the level to place Joshua as before. Clicking into a different level that does not already have an explicitly placed Joshua enters **idle**, not **placing**: the sprite and frame are hidden, the cursor remains the ordinary LDtk editor cursor, and regular painting/selection/erasing continues. To set a new point in that level, use the **Ustaw Joshuę** button. While placing, the same button says **Anuluj** and cancels without storing an incidental mouse position.

Existing placed points remain saved per level for the open editor project. Returning to a level restores its last committed Joshua position and frame without re-arming placement. If placement is underway when entering World View, it is cancelled; an earlier committed point, if any, is restored. Toggling the preview off/on does not silently re-arm placement either. Switching projects resets all editor-only placement state. All these operations leave the LDtk project file, Undo/Redo and editor layer state untouched.

## Joshua placement (1.0.36)

Use **Camera preview → click the level** to position Joshua. The blue outline shows the camera's visible frame at that player position, computed from the Unity camera snapshot. The click only anchors the editor marker; it does not create a game entity, modify the level JSON or enter undo history. The mouse-up that completes placement is consumed so an accidental stroke is not produced. Every subsequent click, drag, stroke, selection, shortcut, Undo and Redo goes to the regular LDtk tool.

**Siatka kamery** draws camera-sized guide cells while keeping the current Joshua position pinned. **Kadr Joshuy** shows only the camera outline. Neither mode dims the area outside the camera; the normal editor grid remains visible according to the regular Visuals setting. Use **Przestaw Joshuę** to explicitly choose a different point.

The last point and pinned state are retained for each level in the open project when you toggle the preview, switch levels or pass into World View through zooming. World View renders the frame and the included Joshua marker using the level's world offset; the marker stays visible at small zoom. Leaving World View restores editing without requiring new placement. Opening another LDtk project clears the previous project's stored points.

The preview uses a single fixed, nearest-neighbor Joshua marker bundled with LDtk. Sprite/prefab selection and manual PPU/pivot/offset calibration have been removed from this mode. The preview never replaces a sprite in the Unity project.

## Optional camera model: verification boundary

Top-level `schemaVersion:1` and `unityCameraModel.schemaVersion:1` are preserved; no second export format is created. Legacy snapshots without a model only describe lens dimensions, which the UI explicitly states. A recognized model is solved as a settled state, never as a runtime damping simulation. Level matching is by IID, not name or position. The existing adapter can interpret the level-local room/zone layout covered by repository regression vectors, Unity-unit camera offsets, pixel offsets, zoom/orthographic-size changes and clamping to explicit rooms; global zone focus positions subtract the level world origin. Highest-priority matching zones win, with stable array order for equal priority.

**The original custom Unity `preview.cjs` and its 53 `core-design.fixture.json` cases are not in this repository or available to this implementation. The repository's synthetic vectors are not those Unity-generated reference tests. Exact compatibility with that custom model is not established.** Unrecognized coordinate mappings or missing level IIDs are errors, not silent centered-camera fallbacks. The model status always says its Unity parity is unverified. The stock Unity package still exports the dimension-only snapshot above; it does not invent a custom game-camera model.

The source file is bounded to 4 MiB to accommodate model-sized snapshots. Reloading it recomputes the frame for the same pinned player point, without reloading the edited map. Malformed sources hide invalid frames, retain the player anchor and recover after a valid export.


## Unity camera model revision 2 (Dither Paradox handoff)

The optional camera model in the existing \`World.ldtk-camera.json\` sidecar now accepts
\`unityCameraModel: { schemaVersion: 1, modelRevision: 2, ... }\`. The editor does not
write or change the LDtk level. The Unity exporter is responsible for all camera
configuration; LDtk only reads it, evaluates hypothetical settled camera framing
and draws the resulting rectangle.

### Inputs and camera modes

When a revision-2 model is present, Camera Preview shows:

- **Facing**: Left (-1), Neutral (0), Right (+1). In CameraFromScratch
  rooms with \`neutralFacing: false\`, Neutral behaves as Right.
- **Motion**: Grounded, Rising, Apex, Falling, Clinging. The legacy pipeline
  has different held-state vertical offsets; the CameraFromScratch rig uses
  its own exported framing profile.
- **Look**: None / Ledge peek. Available only when exported rooms contain
  a positive \`look.ledgePeek\`.
- **Camera**: Default or an explicitly exported option. \`CM_TallRoom\` can
  appear here even though its original trigger is not functional in gameplay
  (\`activation: "none"\`): this is an explicit *preview-only* selection.
- **Overlapping zone**: Automatic or a specific exported zone ID. A tie of
  overlapping non-pan zones raises a diagnostic rather than silently picking
  an incorrect camera.

The model uses Unity world units with Y up and its own room assignments,
framing, zoom steps, focus/pan/ledge behaviors, confiner and pixel snapping.
The renderer maps the resulting frame back into LDtk level-local pixels with
Y down, including each level's \`unityTopLeft\` and \`pixelsPerUnit\`. This
receiver does not modify Unity scene camera settings or persist the hypothetical
Joshua position as a game spawn.

### Reference-case verification and offline behavior

The snapshot's \`unityCameraModel.referenceCases[]\` contains authoritative
\`{ levelIid, localPoint, state, expected, error }\` examples exported from
Unity's C# \`SmartiveCameraGeometry.Evaluate\`. Each case is evaluated when the
model changes. Position and size must agree within **0.02 LDtk pixels**.
The status reports **Local (verified)** only after **all** reference cases pass.
Any mismatch is reported as **Unity camera model drift** and local revision-2
camera simulation is blocked rather than falsely presented as accurate.

If reference cases are entirely missing, the local solver can still produce
frames but labels them **Local (unverified)**. A failing reference set forces
a dimension-only fallback if there is no authoritative Unity query response.
The old version-1 snapshot/model path remains available.

The included synthetic regression cases cover the documented 000_CoreDesign
example: grounded/left/right/apex/falling, selected CM_TallRoom and both
confiner edges, plus zoom and simulated Unity sidecar replies. They do **not**
establish full parity with the original C# solver: the exporter source file
\`Tools/LDtkCameraSync/preview.cjs\` and the full 90+37 Unity fixtures must
be supplied and compared to confirm that parity.

### Live, authoritative Unity query protocol

With Unity's **Tools → LDTK-Smartive → Camera preview sync** window open and
automatic sync enabled, LDtk writes requests using an atomic rename:

- \`World.ldtk-camera-query.json\` — request
- \`World.ldtk-camera-answer.json\` — response from Unity

The request includes \`schemaVersion:1\`, a unique \`requestId\`, level
\`levelIid\`, a \`localPoint: {x,y}\` in LDtk local pixels and a
\`state: {direction,motion,look,cameraId,zoneId}\`. A response is accepted
only when source, request ID, level IID, player point, state and (if present)
\`snapshotUpdatedAtUtc\` match. Old answers and malformed responses cannot
move the frame, and missing answers never block painting in LDtk.

The preferred source order is:

1. **Unity (exact settled)** — a matching current answer.
2. **Local (verified)** — the embedded evaluator passes every reference case.
3. **Local (unverified)** — no reference cases were exported.
4. **Dimension-only fallback** — the Unity model is invalid/drifted, and no
   matching authoritative answer is available.

A query/answer frame is a **settled Edit Mode prediction**, not a literal
pixel-for-pixel Play Mode screenshot. Damping, blend transitions, landing
bumps, moving focus targets, camera shake and other runtime-only mechanics
remain out of scope unless Unity exports a separate supported rendered frame.
The older version-1 \`.ldtk-camera.json\` source remains readable and does
not depend on any sidecar query support.

### Verification command

From \`app\`, run \`npm run test:camera-preview\`: this includes
\`camera-model-revision2.test.cjs\`, Haxe geometry vectors and native
Electron UI interactions. Run \`npm run test:release-preflight\` and the
Linux/macOS CI gates before merging or releasing.


## Regression commands

`cd app && npm run test:camera-preview` compiles the production editor and drives native Electron mouse and keyboard input, including continuous strokes, erase, selection, entity placement, Undo/Redo, placement-drag safety, grid editing, World View, preview toggle state, pan/zoom and source reload. The old standalone sprite-parser unit tests remain in the repository but are not used by the Camera Preview UI. On Linux run it through `xvfb-run -a`; `SMARTIVE_CAMERA_DPR=2` exercises Retina-scale transforms. Run `npm run test:release-preflight` for the complete editor suite before packaging.
