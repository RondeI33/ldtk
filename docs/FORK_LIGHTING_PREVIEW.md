# Fork lighting preview

This fork can preview Unity-style 2D lighting in the **currently active LDtk level** without adding fork-only data to the LDtk project format.

The preview intentionally reads ordinary LDtk **Entity definitions, Entity instances, and fields**. A project that uses these conventions remains a normal LDtk project and can still be opened, edited, saved, and exported with stock LDtk. Stock LDtk simply ignores the special meaning of the fields and renders the entities normally.

## Preview controls

The level editor exposes a compact lighting-preview panel with:

- `Unlit`
- `Lit`
- `Lit + Shadows`
- `Lighting preview`
- `Low-res preview`

Lighting work is limited to the active level. World mode and inactive levels do not run the light preview.

## Recommended light entity

Create a normal Entity definition such as `UnityLight2D` and add normal LDtk fields. The preview accepts the following preferred names (matching is case/punctuation insensitive and several aliases are also accepted):

- `LightType` — `Point`, `Freeform`, `Sprite`, or `Global`
- `Color`
- `Intensity`
- `OuterRadius`
- `InnerRadius`
- `Falloff`
- `InnerAngle`
- `OuterAngle`
- `RotationDeg`
- `ShadowsEnabled`
- `ShadowIntensity`
- `Enabled`
- `PreviewEnabled`

`OuterRadius` and `InnerRadius` are intended to contain the real Unity-unit values that the Unity importer will apply to `Light2D`. The editor preview converts them to LDtk pixels with the project convention described below.

For workflows that already store pixel radii, `OuterRadiusPx` / `RadiusPx` and `InnerRadiusPx` are also understood.

The Unity importer is free to add additional ordinary fields for exact URP properties (blend style, sorting-layer targeting, cookie references, volumetric parameters, freeform paths, etc.). Unknown fields remain valid LDtk data even when the fork preview does not visualize them yet.

## Unit conversion settings

Optionally create an ordinary Entity such as `LDtkLightSettings` or `LightPreviewSettings` with:

- `LDtkPixelsPerUnityUnit` — default preview fallback is `16`
- `PreviewAmbientDarkness` — optional authoring-only backdrop darkening from `0` to `0.8`

This keeps Unity radii exact in project data while allowing the LDtk preview to convert those units consistently.

## Shadow casters

Any normal Entity can be treated as a preview shadow caster when either:

- its identifier contains `ShadowCaster`, or
- it has a true field named `CastsLightShadow`, `CastsShadows`, `ShadowCaster`, or `CastShadows`.

The current editor preview uses the entity bounds as a cheap rectangular occluder. `Lit + Shadows` projects an approximate 2D shadow away from point lights. This is deliberately an authoring approximation; Unity/URP remains the final renderer.

## Rendering scope and performance

The preview is deliberately lightweight:

- active level only;
- camera culling for local lights;
- dirty-signature redraws instead of continuous full rebuilds;
- a 20 Hz maximum change check;
- reduced ring/segment counts in low-resolution mode;
- no project-wide lighting simulation.

## Stock LDtk compatibility

**Do not add custom top-level JSON members to `.ldtk` files for lighting.** Store the lighting contract in standard entity definitions and standard fields.

That makes the intended pipeline:

```text
stock-compatible .ldtk entity data
        |                    |
        |                    +--> stock LDtk: normal entities/fields
        |
        +--> this fork: lightweight lighting preview
        |
        +--> Unity importer: exact Light2D/ShadowCaster2D values
```

The fork preview is never the authoritative final renderer. The LDtk entity values are the authoring data; Unity is responsible for producing the exact runtime rendering result.
