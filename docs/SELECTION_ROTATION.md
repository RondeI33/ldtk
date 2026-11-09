# Selection rotation

Select contents in the level with **Alt+click** or **Alt+Shift+drag**, then use:

| Action | Default shortcut | Alternative on every navigation layout |
| --- | --- | --- |
| Rotate 90° clockwise | Z, with WASD or arrow navigation | Alt+R |
| Rotate 90° counterclockwise | Shift+Z | Alt+Shift+R |
| Mirror horizontally | X | Shift+H |
| Mirror vertically | Y | Shift+V |

The two curved-arrow buttons in the **Editing** sidebar perform the same rotation commands. Their tooltips show the shortcut for the active navigation layout. They are unavailable when there is no supported level selection. Both buttons support keyboard focus and activation with Enter or Space. The Help panel lists the rotation shortcuts.

In the ZQSD navigation layout, **Z** remains the upward movement key. Use the alternative clockwise shortcut or the sidebar button. Rotation does not replace Ctrl/Cmd+Z for Undo, the existing X/Y mirrors, or the R shortcut for tile randomization.

## Placement and editing

Rotation operates in the level's 2D plane. A quarter turn swaps the selection's width and height while keeping its top-left corner fixed. This keeps rectangular selections aligned to their grid even when one side has an odd number of cells and the other an even number.

Manual tile artwork rotates with its grid position. IntGrid values change positions and the normal auto-layer rules regenerate their visuals. Drawable shapes rotate their geometry, dimensions and facing. Ordinary entities and their point fields keep their existing orientation and positions during a direct rotation, matching the scope of the X/Y selection mirrors; they still move normally when the selection is dragged.

Empty gaps in a sparse selection do not erase unrelated content underneath them.

The commands also work while dragging a supported selection: the preview shows the turn before dropping it, and the completed gesture remains a single Undo operation. Transformed IntGrid cells use their authored colors in this preview; their auto-layer artwork regenerates from the rules when placed. This avoids showing rotated auto-tile graphics that the rules would not produce.

A direct rotation that would put selected content outside a layer or off its grid is rejected as a whole, with a message explaining why.

Rotation is available during level editing. Text fields, modal dialogs, world view, camera-placement mode and other active placement tools retain their own input behavior.

## File compatibility

The standard `.ldtk` and external `.ldtkl` files retain LDtk's native tile flip values. Smartive saves the additional diagonal tile orientation needed for quarter turns in the existing `<project>.ldtk-fork.json` file. Keep this companion file with the project when moving or sharing it.

Older LDtk editors and importers can still read the native project. Readers that do not use Smartive's orientation metadata see the saved cell positions and native X/Y flips, but do not reproduce the additional quarter-turn orientation. A game importer needs to read that metadata to reproduce those manual tile rotations.
