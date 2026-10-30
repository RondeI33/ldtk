# LDTK-Smartive Unity Integration

Editor-only Unity package that replaces LDtk/Cammin asset icons and exports the active scene camera framing for LDtk's camera preview.

It does not replace or modify the LDtkUnity importer. It runs after imports and applies the Smartive icon to the imported main asset, so existing LDtkUnity workflows continue to work.

## Install with Unity Package Manager

Add this Git URL:

`https://github.com/RondeI33/ldtk.git?path=/unity/com.rondei33.ldtk-smartive-unity-icons#master`

After installation, existing LDtk assets are refreshed automatically. You can also run **Tools > LDTK-Smartive > Refresh LDtk asset icons**.

## Camera preview sync

1. Open **Tools > LDTK-Smartive > Camera preview sync**.
2. Select the `.ldtk` project asset used by the scene.
3. Leave **Camera (optional)** empty to select the active scene's unique enabled `MainCamera`, or its sole enabled game camera. Assign the gameplay camera explicitly if the scene has several candidates, or if its output camera lives in a persistent/additive scene or `DontDestroyOnLoad`.
4. The window reads **Pixels Per Unit** from the LDtkUnity importer. If unavailable, enable the override and enter the actual importer scale.
5. Choose **Export camera snapshot** for a one-time export, or enable **Automatic sync** and leave the window open.
6. Open the same project in LDTK-Smartive and enable its camera preview toolbar button.

The export is stored beside the project: `World.ldtk` produces `World.ldtk-camera.json`. It does not modify the scene, camera, importer, level data, or the existing fork settings. Automatic sync samples twice per second, writes changed values, and sends a heartbeat every five seconds. Closing the sync window or disabling automatic sync invalidates its previous live export. A manual snapshot remains available with its export timestamp.

The camera must be an enabled, unrotated orthographic game camera in a valid loaded scene, using a centered axis-aligned orthographic projection. Automatic selection stays scoped to the active scene; an explicit camera selection can use a persistent output camera from another loaded scene. The exported scene name/path identify the active gameplay scene. The exporter reads the current output projection, including centered size/aspect adjustments such as Pixel Perfect when they are present at sampling time. Perspective, stereo, rotated, skewed and off-center cameras produce an explicit unavailable status instead of an inaccurate rectangle. With Cinemachine or a camera controller, select its final Unity `Camera` output; dynamic lens changes are sampled from that component. This feature previews framing over LDtk content, not Unity lighting, post-processing, runtime prefabs, camera damping or room/zone constraints.

Full contract and verification guidance: [Unity camera preview](../../docs/UNITY_CAMERA_PREVIEW.md).
