# Selection Templates

## Create
Select the source objects in the level with Alt/Option + Shift and drag. Open the compact **Templates** icon immediately after **Tilesets**, then click the save icon. The save icon updates while the panel is open; no right-click is needed. Templates is a native LDtk panel: clicking it directly swaps from Layers, Entities, Enums, Tilesets or another open panel without requiring a separate close step. Hovering the Templates icon shows the normal **Templates** toolbar tooltip.

The **Edit template** dialog opens a separate draft. Name it, then use the layer checkboxes to exclude walls or other layers before pressing **Save template**. Cancel discards the draft, not the source selection.

## Edit a saved template
Click **Edit** in the library. The same editor is available both before the first save and later. Click an entity or a connection in the preview, or drag over empty space to select a group. Shift-click extends selection. Press Delete or use the Delete button to remove selected draft elements.

Select an entity to edit numeric, text, Boolean, enum, point, and connection values in the inspector. The reset button clears a value to its LDtk default; array entries have individual remove buttons. Required fields are marked when empty. Tile-valued fields retain their tile selection and offer Reset; choosing a different tile for a tile-valued field is not part of this dialog.

Connection dropdowns refer to entities in this template. Removing an entity also clears connections to it. Excluded layers are remembered and can be included again by editing the saved template. The editor has its own Undo and Redo. These do not affect map history.

**Rename** also remains available directly in the library and uses LDtk's standard input dialog. Deleting a template uses LDtk's confirmation dialog. There are no browser prompt or confirm calls in template UI.

## Place
Click **Place**, then click the destination level. Before placement, the cursor shows a layered visual ghost using the template's real entity rendering and actual Tiles sprites rather than only bounding boxes. IntGrid cells use their authored colors and point/path handles are visible on top. Each placement creates independent entity IDs and rewires internal references to that copy. Excluded layers are omitted, including entity tile stamps targeting those layers. Required connections to excluded or deleted entities must be repaired before placement. Empty space does not erase destination cells; occupied grid cells are protected.

After a successful placement, stamp mode closes automatically and the newly placed template is selected using LDtk's normal multi-layer selection system. Entities, their point/path handles, and explicit Tiles/IntGrid cells are selected together, so you can immediately drag the placed template to fine-tune its position. Generated entity tile stamps are not selected separately because they already move with their owner.

Generated AutoLayer output is controlled by its IntGrid source. Excluding a generated layer also excludes its source rather than pretending generated output can be frozen independently.

A placement is one map Undo/Redo operation. Editing or renaming a template never updates already-placed copies. Templates remain in `<project>.ldtk-templates.json` next to the project; keep that sidecar when copying a project. Library writes use a temporary file and atomic replacement, and report failures instead of displaying a false success message.

## Regression test
Run `npm run test:templates` from `app` (on a Linux server, use `xvfb-run -a npm run test:templates`). The command compiles an instrumented renderer, exercises the real Electron UI and map controller with an isolated temporary project, and restores the production renderer before exiting. Test hooks are compiled only with `selection_template_tests`.
